import Foundation

// T045: read-only viewer-mode queries (plan §5, D-M2-002, D-009, M2-FR-030..035).
//
// UI binding: the viewer root calls `ArchiveViewerUseCases.load()` once and keeps the returned
// `ArchiveViewerContent` in memory; every filter, search, trend and record is a pure function of
// that value (no index, no cache, no write). The only thing this type can write is the local
// display-settings file, which is not archive content (M2-FR-032). It holds no Coach use case,
// repository or store handle (plan §5).

public enum ArchiveViewerError: Error, Equatable, Sendable {
    /// No archive is installed.
    case noArchive
    /// A pointer exists but its snapshot cannot be used (unreadable, invalid or from a newer
    /// build). Nothing is deleted.
    case archiveUnreadable
    /// The archive does not contain the module this query needs (「档案未包含」).
    case moduleNotIncluded
}

public struct ArchiveViewerUseCases: Sendable {
    private let store: ArchiveSnapshotStore

    public init(store: ArchiveSnapshotStore) {
        self.store = store
    }

    /// Reads and validates the installed snapshot off the caller's thread.
    public func load() async throws -> ArchiveViewerContent {
        let store = self.store
        return try await Task.detached(priority: .userInitiated) {
            do {
                guard let snapshot = try store.load() else {
                    throw ArchiveViewerError.noArchive
                }
                return ArchiveViewerContent(snapshot: snapshot)
            } catch let error as ArchiveViewerError {
                throw error
            } catch {
                throw ArchiveViewerError.archiveUnreadable
            }
        }.value
    }

    /// kg/lb, cm/in and list density; defaults when nothing valid is stored.
    public func displaySettings() -> ArchiveDisplaySettings {
        store.readDisplaySettings()
    }

    /// Writes `display-settings.json` only. Archive content is never touched (M2-FR-032).
    public func updateDisplaySettings(_ settings: ArchiveDisplaySettings) throws {
        do {
            try store.writeDisplaySettings(settings)
        } catch ArchiveSnapshotStoreError.noArchive {
            throw ArchiveViewerError.noArchive
        }
    }
}

// MARK: - Filters

/// Training-record filter (M2-FR-031). Every criterion is optional and they combine with AND;
/// the body-part set is an any-match (M1B-FR-026 / D-013).
public struct ArchiveSessionFilter: Equatable, Sendable {
    public var dateRange: ClosedRange<LocalDate>?
    public var trainingFocus: Set<BodyPart>
    /// Exercise-name search. Only usable when the archive includes exercise info.
    public var exerciseNameQuery: String?

    public init(
        dateRange: ClosedRange<LocalDate>? = nil,
        trainingFocus: Set<BodyPart> = [],
        exerciseNameQuery: String? = nil
    ) {
        self.dateRange = dateRange
        self.trainingFocus = trainingFocus
        self.exerciseNameQuery = exerciseNameQuery
    }

    var normalizedQuery: String? {
        guard let trimmed = exerciseNameQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    public var isEmpty: Bool {
        dateRange == nil && trainingFocus.isEmpty && normalizedQuery == nil
    }
}

/// An exercise that appears in at least one training record, for the trend picker and the
/// exercise-info list.
public struct ArchiveExerciseEntry: Equatable, Sendable {
    public let key: String
    /// The 「动作 N」 number (D-001). Always present.
    public let placeholderNumber: Int
    public let kind: ArchiveExerciseKind
    public let isAssisted: Bool
    /// Present only when the archive includes exercise info.
    public let info: ArchiveExerciseInfo?
}

// MARK: - Content

/// The loaded archive plus every read-only query the viewer screens need.
public struct ArchiveViewerContent: Sendable {
    public let snapshot: ArchiveSnapshot
    private let adapter: ArchiveComparisonAdapter

    public init(snapshot: ArchiveSnapshot) {
        self.snapshot = snapshot
        self.adapter = ArchiveComparisonAdapter(snapshot: snapshot)
    }

    // MARK: Facts and module availability

    public var manifest: ArchiveManifest { snapshot.manifest }
    /// The four digits of 「来源 · NNNN」 (D-007).
    public var sourceLabel: String { ArchiveIdentityService.shortLabel(forSourceID: manifest.sourceID) }
    /// The exported display name, or `nil` (the UI then shows its generic title).
    public var studentDisplayName: String? { snapshot.student?.displayName }
    public var studentSex: StudentSex? { snapshot.student?.sex }

    public var hasTrainingRecords: Bool { manifest.modules.trainingRecords }
    public var hasBodyData: Bool { manifest.modules.bodyData }
    public var hasSummaries: Bool { manifest.modules.summaries }
    public var hasExerciseInfo: Bool { manifest.modules.exerciseInfo }
    /// Trends and personal records exist only when exported, and the module itself depends on
    /// training records (D-009).
    public var isTrendsAvailable: Bool { manifest.modules.trends && manifest.modules.trainingRecords }
    /// Name search needs exercise info (M2-FR-031).
    public var isNameSearchAvailable: Bool { manifest.modules.exerciseInfo && manifest.modules.trainingRecords }

    // MARK: Training records

    /// Newest first (completion time, then key for a stable order).
    public func sessions(matching filter: ArchiveSessionFilter = ArchiveSessionFilter()) throws -> [ArchiveSession] {
        guard hasTrainingRecords else {
            throw ArchiveViewerError.moduleNotIncluded
        }
        let query = filter.normalizedQuery
        if query != nil, !isNameSearchAvailable {
            throw ArchiveViewerError.moduleNotIncluded
        }
        let matchingKeys: Set<String>? = query.map { query in
            Set(
                snapshot.exercises.compactMap { exercise in
                    exercise.info?.name.localizedStandardContains(query) == true ? exercise.key : nil
                }
            )
        }
        return snapshot.sessions
            .filter { session in
                if let range = filter.dateRange, !range.contains(session.localDate) {
                    return false
                }
                guard
                    HistoryFilterCriteria.matchesTrainingFocus(
                        sessionFocus: session.trainingFocus,
                        filter: filter.trainingFocus
                    )
                else {
                    return false
                }
                if let matchingKeys {
                    let keys = session.sections.flatMap(\.exercises).map(\.exerciseKey)
                    guard keys.contains(where: matchingKeys.contains) else {
                        return false
                    }
                }
                return true
            }
            .sorted {
                $0.completedAtUTC != $1.completedAtUTC ? $0.completedAtUTC > $1.completedAtUTC : $0.key < $1.key
            }
    }

    public func session(key: String) -> ArchiveSession? {
        snapshot.sessions.first { $0.key == key }
    }

    public func exercise(key: String) -> ArchiveExercise? {
        snapshot.exercises.first { $0.key == key }
    }

    /// Course summaries for a session, or the ones not tied to any session when `nil`.
    public func summaries(forSessionKey key: String?) throws -> [ArchiveSummary] {
        guard hasSummaries else {
            throw ArchiveViewerError.moduleNotIncluded
        }
        return snapshot.summaries.filter { $0.sessionKey == key }
    }

    // MARK: Exercises

    /// Exercises that appear in at least one training record, by placeholder number. With a
    /// `nameQuery` (exercise info required) only name matches are returned.
    public func exercises(nameQuery: String? = nil) throws -> [ArchiveExerciseEntry] {
        guard hasTrainingRecords else {
            throw ArchiveViewerError.moduleNotIncluded
        }
        let query = ArchiveSessionFilter(exerciseNameQuery: nameQuery).normalizedQuery
        if query != nil, !isNameSearchAvailable {
            throw ArchiveViewerError.moduleNotIncluded
        }
        let used = Set(snapshot.sessions.flatMap(\.sections).flatMap(\.exercises).map(\.exerciseKey))
        return snapshot.exercises
            .filter { used.contains($0.key) }
            .filter { exercise in
                guard let query else { return true }
                return exercise.info?.name.localizedStandardContains(query) == true
            }
            .sorted { $0.placeholderNumber < $1.placeholderNumber }
            .map {
                ArchiveExerciseEntry(
                    key: $0.key,
                    placeholderNumber: $0.placeholderNumber,
                    kind: $0.kind,
                    isAssisted: $0.isAssisted,
                    info: $0.info
                )
            }
    }

    // MARK: Trends and personal records (archive sessions only, D-009)

    /// Exercises the trend picker offers. Throws when the archive has no trends module.
    public func trendExercises() throws -> [ArchiveExerciseEntry] {
        guard isTrendsAvailable else {
            throw ArchiveViewerError.moduleNotIncluded
        }
        return try exercises()
    }

    /// The record modes an exercise was logged in, in `RecordMode` declaration order. Trends
    /// and records never mix modes (Comparison compatibility rule).
    public func recordModes(forExerciseKey key: String) -> [RecordMode] {
        let used = Set(
            snapshot.sessions.flatMap(\.sections).flatMap(\.exercises)
                .filter { $0.exerciseKey == key }
                .map(\.recordMode)
        )
        return RecordMode.allCases.filter(used.contains)
    }

    public func trend(forExerciseKey key: String, recordMode: RecordMode) throws -> [Comparison.SetTrendPoint] {
        guard isTrendsAvailable else {
            throw ArchiveViewerError.moduleNotIncluded
        }
        return adapter.trend(forExerciseKey: key, recordMode: recordMode)
    }

    public func personalRecords(
        forExerciseKey key: String,
        recordMode: RecordMode
    ) throws -> Comparison.PersonalRecordSet {
        guard isTrendsAvailable else {
            throw ArchiveViewerError.moduleNotIncluded
        }
        return adapter.personalRecords(forExerciseKey: key, recordMode: recordMode)
    }

    /// The loading direction trends and records use for this exercise.
    public func loadDirection(forExerciseKey key: String) -> Comparison.LoadDirection {
        adapter.loadDirection(forExerciseKey: key)
    }

    /// Maps a `sessionID` from a trend point or record back to the archive session key.
    public func sessionKey(for id: StableUUID) -> String? {
        adapter.sessionKey(for: id)
    }

    // MARK: Body data

    public func bodyMetrics() throws -> [ArchiveBodyMetric] {
        guard hasBodyData else {
            throw ArchiveViewerError.moduleNotIncluded
        }
        return snapshot.bodyMetrics
    }

    /// Oldest first.
    public func measurements(forMetricKey key: String) throws -> [ArchiveBodyMeasurement] {
        guard hasBodyData else {
            throw ArchiveViewerError.moduleNotIncluded
        }
        return snapshot.bodyMeasurements
            .filter { $0.metricKey == key }
            .sorted { $0.localDay < $1.localDay }
    }
}

// MARK: - Display conversion

/// A value ready to show, with the unit label it is in.
public struct ArchiveDisplayQuantity: Equatable, Sendable {
    public let value: DecimalValue
    public let unit: String
}

/// Display-only unit conversion for the local settings (M2-FR-032). Pure: it returns a new
/// value to show and never touches the stored one. Custom metrics keep the unit they were
/// entered in (M1B-FR-025).
public struct ArchiveDisplayConverter: Equatable, Sendable {
    public let settings: ArchiveDisplaySettings

    public init(settings: ArchiveDisplaySettings) {
        self.settings = settings
    }

    private static let poundsPerKilogram = "2.2046226218"

    /// A set weight (or left/right value). Only kg and lb sets convert; any other unit is
    /// returned as stored with an empty label.
    public func weight(_ value: DecimalValue, storedUnit: MeasurementUnit) -> ArchiveDisplayQuantity {
        switch storedUnit {
        case .kilograms: return convertKilograms(value)
        case .pounds: return convertPounds(value)
        case .repetitions, .seconds, .none: return ArchiveDisplayQuantity(value: value, unit: "")
        }
    }

    /// A body measurement. Built-in metrics convert from their canonical unit; custom metrics
    /// and percentages are returned exactly as entered.
    public func measurement(_ measurement: ArchiveBodyMeasurement, of metric: ArchiveBodyMetric) -> ArchiveDisplayQuantity {
        guard case .builtIn(let builtIn) = metric.kind, measurement.enteredUnit == builtIn.canonicalUnit else {
            return ArchiveDisplayQuantity(value: measurement.value, unit: measurement.enteredUnit)
        }
        switch builtIn.unitRuleKind {
        case .weight: return convertKilograms(measurement.value)
        case .length: return convertCentimeters(measurement.value)
        case .percent, .customUnit: return ArchiveDisplayQuantity(value: measurement.value, unit: measurement.enteredUnit)
        }
    }

    private func convertKilograms(_ value: DecimalValue) -> ArchiveDisplayQuantity {
        switch settings.weightUnit {
        case .kg:
            return ArchiveDisplayQuantity(value: value, unit: "kg")
        case .lb:
            let converted = (try? BuiltInUnitConversion.weight(canonicalKilograms: value, displayedAs: .pounds)) ?? value
            return ArchiveDisplayQuantity(value: converted, unit: "lb")
        }
    }

    private func convertPounds(_ value: DecimalValue) -> ArchiveDisplayQuantity {
        switch settings.weightUnit {
        case .lb:
            return ArchiveDisplayQuantity(value: value, unit: "lb")
        case .kg:
            let kilograms =
                (try? BuiltInUnitConversion.canonicalKilograms(fromDisplayed: value, unit: .pounds)) ?? value
            return ArchiveDisplayQuantity(value: Self.rounded(kilograms), unit: "kg")
        }
    }

    private func convertCentimeters(_ value: DecimalValue) -> ArchiveDisplayQuantity {
        switch settings.lengthUnit {
        case .cm:
            return ArchiveDisplayQuantity(value: value, unit: "cm")
        case .inch:
            let converted = (try? BuiltInUnitConversion.length(canonicalCentimeters: value, displayedAs: .inches)) ?? value
            return ArchiveDisplayQuantity(value: converted, unit: "in")
        }
    }

    private static func rounded(_ value: DecimalValue) -> DecimalValue {
        var input = value.decimal
        var output = Decimal()
        NSDecimalRound(&output, &input, 2, .plain)
        return (try? DecimalValue(NSDecimalNumber(decimal: output).stringValue)) ?? value
    }
}
