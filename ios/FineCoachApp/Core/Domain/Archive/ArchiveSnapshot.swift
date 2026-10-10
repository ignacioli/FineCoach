import Foundation

// M2 personal training archive snapshot (data-model §1, contract archive-file-v1 §4).
//
// `ArchiveSnapshot` is the decoded in-memory form of an archive payload, shared by the
// export side and the viewer. The `Codable` shapes below ARE the wire shapes of the
// payload frames (contract §4), so they are deliberately explicit rather than synthesized
// for the types whose wire form differs from the Swift form (dates, local dates, flat
// exercise info, body-metric kind).
//
// Privacy: no Coach-side stable IDs (student, exercise, session, metric UUIDs) exist in
// these types. Local keys (`e1`, `s1`, `m1`) are archive-local and carry no identity.

public enum ArchiveSnapshotError: Error, Equatable, Sendable {
    case moduleDependencyViolation
    case noModuleSelected
    case textTooLong
    case invalidBodyMetric
    case invalidKey
    case invalidDate
    case duplicateKey
    case danglingReference
    case moduleContentMismatch
    case countsMismatch
    case limitExceeded
}

/// Resource limits for a decoded archive (plan §7.3). Fail-closed safety ceilings, not
/// product promises.
public enum ArchiveLimits {
    public static let maxSessions = 10_000
    public static let maxSets = 300_000
    public static let maxExercises = 5_000
    public static let maxBodyMetrics = 64
    public static let maxBodyMeasurements = 20_000
    public static let maxSummaries = 10_000
    public static let maxTextUTF8Bytes = ValidatedText.maximumUTF8Bytes
}

// MARK: - Wire helpers

enum ArchiveWireCoding {
    static func string(from date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    static func date(from string: String) throws -> Date {
        do {
            return try Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        } catch {
            throw ArchiveSnapshotError.invalidDate
        }
    }

    static func localDate(from string: String) throws -> LocalDate {
        guard let parsed = try? LocalDate(canonicalString: string),
            parsed.canonicalString == string
        else {
            throw ArchiveSnapshotError.invalidDate
        }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = parsed.year
        components.month = parsed.month
        components.day = parsed.day
        guard components.isValidDate else {
            throw ArchiveSnapshotError.invalidDate
        }
        return parsed
    }

    static func isValidKey(_ key: String, prefix: Character) -> Bool {
        guard key.first == prefix else {
            return false
        }
        let digits = key.dropFirst()
        guard !digits.isEmpty, digits.count <= 9, digits.first != "0" else {
            return false
        }
        return digits.allSatisfy { $0 >= "0" && $0 <= "9" }
    }
}

extension KeyedDecodingContainer {
    fileprivate func decodeArchiveDate(forKey key: Key) throws -> Date {
        try ArchiveWireCoding.date(from: decode(String.self, forKey: key))
    }

    fileprivate func decodeArchiveLocalDate(forKey key: Key) throws -> LocalDate {
        try ArchiveWireCoding.localDate(from: decode(String.self, forKey: key))
    }
}

// MARK: - Modules and manifest

public struct ArchiveModuleSet: Hashable, Codable, Sendable {
    public let displayName: Bool
    public let sex: Bool
    public let bodyData: Bool
    public let trainingRecords: Bool
    public let trends: Bool
    public let summaries: Bool
    public let exerciseInfo: Bool

    /// Dependencies: trends => trainingRecords (D-009); exerciseInfo => trainingRecords
    /// (D-015). Summaries are independent.
    public init(
        displayName: Bool,
        sex: Bool,
        bodyData: Bool,
        trainingRecords: Bool,
        trends: Bool,
        summaries: Bool,
        exerciseInfo: Bool
    ) throws {
        guard !trends || trainingRecords, !exerciseInfo || trainingRecords else {
            throw ArchiveSnapshotError.moduleDependencyViolation
        }
        self.displayName = displayName
        self.sex = sex
        self.bodyData = bodyData
        self.trainingRecords = trainingRecords
        self.trends = trends
        self.summaries = summaries
        self.exerciseInfo = exerciseInfo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            displayName: container.decode(Bool.self, forKey: .displayName),
            sex: container.decode(Bool.self, forKey: .sex),
            bodyData: container.decode(Bool.self, forKey: .bodyData),
            trainingRecords: container.decode(Bool.self, forKey: .trainingRecords),
            trends: container.decode(Bool.self, forKey: .trends),
            summaries: container.decode(Bool.self, forKey: .summaries),
            exerciseInfo: container.decode(Bool.self, forKey: .exerciseInfo)
        )
    }

    public var isEmpty: Bool {
        !(displayName || sex || bodyData || trainingRecords || trends || summaries || exerciseInfo)
    }
}

public struct ArchiveCounts: Hashable, Codable, Sendable {
    public let student: Int
    public let exercise: Int
    public let session: Int
    public let summary: Int
    public let bodyMetric: Int
    public let bodyMeasurement: Int
    public let attribution: Int

    public init(
        student: Int,
        exercise: Int,
        session: Int,
        summary: Int,
        bodyMetric: Int,
        bodyMeasurement: Int,
        attribution: Int
    ) {
        self.student = student
        self.exercise = exercise
        self.session = session
        self.summary = summary
        self.bodyMetric = bodyMetric
        self.bodyMeasurement = bodyMeasurement
        self.attribution = attribution
    }
}

public struct ArchiveManifest: Hashable, Codable, Sendable {
    public let sourceID: UUID
    public let studentArchiveID: UUID
    /// Millisecond precision on the wire.
    public let snapshotAtUTC: Date
    public let modules: ArchiveModuleSet
    public let counts: ArchiveCounts

    public init(
        sourceID: UUID,
        studentArchiveID: UUID,
        snapshotAtUTC: Date,
        modules: ArchiveModuleSet,
        counts: ArchiveCounts
    ) throws {
        guard !modules.isEmpty else {
            throw ArchiveSnapshotError.noModuleSelected
        }
        self.sourceID = sourceID
        self.studentArchiveID = studentArchiveID
        self.snapshotAtUTC = snapshotAtUTC
        self.modules = modules
        self.counts = counts
    }

    private enum CodingKeys: String, CodingKey {
        case sourceID, studentArchiveID, snapshotAtUTC, modules, counts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let sourceID = UUID(uuidString: try container.decode(String.self, forKey: .sourceID)),
            let studentArchiveID = UUID(uuidString: try container.decode(String.self, forKey: .studentArchiveID))
        else {
            throw ArchiveSnapshotError.invalidKey
        }
        try self.init(
            sourceID: sourceID,
            studentArchiveID: studentArchiveID,
            snapshotAtUTC: container.decodeArchiveDate(forKey: .snapshotAtUTC),
            modules: container.decode(ArchiveModuleSet.self, forKey: .modules),
            counts: container.decode(ArchiveCounts.self, forKey: .counts)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceID.uuidString, forKey: .sourceID)
        try container.encode(studentArchiveID.uuidString, forKey: .studentArchiveID)
        try container.encode(ArchiveWireCoding.string(from: snapshotAtUTC), forKey: .snapshotAtUTC)
        try container.encode(modules, forKey: .modules)
        try container.encode(counts, forKey: .counts)
    }
}

// MARK: - Student and exercises

public struct ArchiveStudent: Hashable, Codable, Sendable {
    public let displayName: String?
    public let sex: StudentSex?

    public init(displayName: String? = nil, sex: StudentSex? = nil) {
        self.displayName = displayName
        self.sex = sex
    }
}

public enum ArchiveExerciseKind: String, Hashable, Codable, Sendable {
    case builtIn
    case custom
    case oneOff
}

/// Exercise reference data. Only present when the `exerciseInfo` module is selected.
public struct ArchiveExerciseInfo: Hashable, Sendable {
    public let name: String
    public let primaryMuscles: [String]
    public let secondaryMuscles: [String]
    public let equipment: String

    public init(name: String, primaryMuscles: [String], secondaryMuscles: [String], equipment: String) {
        self.name = name
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
    }
}

public struct ArchiveExercise: Hashable, Codable, Sendable {
    public let key: String
    public let placeholderNumber: Int
    public let kind: ArchiveExerciseKind
    /// Required. From the Coach exercise preference (M1B-FR-028); false for one-off
    /// exercises. Independent of `exerciseInfo` (spec Revision 1.1.2).
    public let isAssisted: Bool
    public let info: ArchiveExerciseInfo?

    public init(
        key: String,
        placeholderNumber: Int,
        kind: ArchiveExerciseKind,
        isAssisted: Bool,
        info: ArchiveExerciseInfo? = nil
    ) {
        self.key = key
        self.placeholderNumber = placeholderNumber
        self.kind = kind
        self.isAssisted = isAssisted
        self.info = info
    }

    private enum CodingKeys: String, CodingKey {
        case key, placeholderNumber, kind, isAssisted, name, primaryMuscles, secondaryMuscles, equipment
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        let primary = try container.decodeIfPresent([String].self, forKey: .primaryMuscles)
        let secondary = try container.decodeIfPresent([String].self, forKey: .secondaryMuscles)
        let equipment = try container.decodeIfPresent(String.self, forKey: .equipment)
        let info: ArchiveExerciseInfo?
        switch (name, primary, secondary, equipment) {
        case (nil, nil, nil, nil):
            info = nil
        case (let name?, let primary?, let secondary?, let equipment?):
            info = ArchiveExerciseInfo(
                name: name,
                primaryMuscles: primary,
                secondaryMuscles: secondary,
                equipment: equipment
            )
        default:
            // Partial exercise info is never produced by a conforming writer.
            throw ArchiveSnapshotError.moduleContentMismatch
        }
        self.init(
            key: try container.decode(String.self, forKey: .key),
            placeholderNumber: try container.decode(Int.self, forKey: .placeholderNumber),
            kind: try container.decode(ArchiveExerciseKind.self, forKey: .kind),
            isAssisted: try container.decode(Bool.self, forKey: .isAssisted),
            info: info
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(placeholderNumber, forKey: .placeholderNumber)
        try container.encode(kind, forKey: .kind)
        try container.encode(isAssisted, forKey: .isAssisted)
        if let info {
            try container.encode(info.name, forKey: .name)
            try container.encode(info.primaryMuscles, forKey: .primaryMuscles)
            try container.encode(info.secondaryMuscles, forKey: .secondaryMuscles)
            try container.encode(info.equipment, forKey: .equipment)
        }
    }
}

// MARK: - Sessions

/// A confirmed set. Same value semantics as a completed M1 `TrainingSet`; the assisted
/// direction lives on `ArchiveExercise.isAssisted`, not on the set. Draft and pending sets
/// never appear.
public struct ArchiveSet: Hashable, Codable, Sendable {
    public let weightValue: DecimalValue?
    public let repetitionCount: DecimalValue?
    public let durationSeconds: DecimalValue?
    public let unit: MeasurementUnit
    public let side: SetSide
    public let leftValue: DecimalValue?
    public let rightValue: DecimalValue?
    public let distanceValue: DecimalValue?
    public let speedValue: DecimalValue?
    public let resistanceValue: DecimalValue?

    public init(
        weightValue: DecimalValue? = nil,
        repetitionCount: DecimalValue? = nil,
        durationSeconds: DecimalValue? = nil,
        unit: MeasurementUnit,
        side: SetSide = .none,
        leftValue: DecimalValue? = nil,
        rightValue: DecimalValue? = nil,
        distanceValue: DecimalValue? = nil,
        speedValue: DecimalValue? = nil,
        resistanceValue: DecimalValue? = nil
    ) {
        self.weightValue = weightValue
        self.repetitionCount = repetitionCount
        self.durationSeconds = durationSeconds
        self.unit = unit
        self.side = side
        self.leftValue = leftValue
        self.rightValue = rightValue
        self.distanceValue = distanceValue
        self.speedValue = speedValue
        self.resistanceValue = resistanceValue
    }
}

public struct ArchiveSessionExercise: Hashable, Codable, Sendable {
    public let exerciseKey: String
    public let recordMode: RecordMode
    public let sets: [ArchiveSet]

    public init(exerciseKey: String, recordMode: RecordMode, sets: [ArchiveSet]) {
        self.exerciseKey = exerciseKey
        self.recordMode = recordMode
        self.sets = sets
    }
}

public struct ArchiveSection: Hashable, Codable, Sendable {
    /// `nil` is the unsectioned group.
    public let name: String?
    public let exercises: [ArchiveSessionExercise]

    public init(name: String?, exercises: [ArchiveSessionExercise]) {
        self.name = name
        self.exercises = exercises
    }
}

public struct ArchiveSession: Hashable, Codable, Sendable {
    public let key: String
    public let localDate: LocalDate
    public let completedAtUTC: Date
    public let durationMinutes: Int
    public let trainingFocus: Set<BodyPart>
    public let sections: [ArchiveSection]

    public init(
        key: String,
        localDate: LocalDate,
        completedAtUTC: Date,
        durationMinutes: Int,
        trainingFocus: Set<BodyPart>,
        sections: [ArchiveSection]
    ) {
        self.key = key
        self.localDate = localDate
        self.completedAtUTC = completedAtUTC
        self.durationMinutes = durationMinutes
        self.trainingFocus = trainingFocus
        self.sections = sections
    }

    private enum CodingKeys: String, CodingKey {
        case key, localDate, completedAtUTC, durationMinutes, trainingFocus, sections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            key: try container.decode(String.self, forKey: .key),
            localDate: try container.decodeArchiveLocalDate(forKey: .localDate),
            completedAtUTC: try container.decodeArchiveDate(forKey: .completedAtUTC),
            durationMinutes: try container.decode(Int.self, forKey: .durationMinutes),
            trainingFocus: Set(try container.decode([BodyPart].self, forKey: .trainingFocus)),
            sections: try container.decode([ArchiveSection].self, forKey: .sections)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(localDate.canonicalString, forKey: .localDate)
        try container.encode(ArchiveWireCoding.string(from: completedAtUTC), forKey: .completedAtUTC)
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encode(BodyPart.ordered(trainingFocus), forKey: .trainingFocus)
        try container.encode(sections, forKey: .sections)
    }
}

// MARK: - Summaries, body data, attribution

public struct ArchiveSummary: Hashable, Codable, Sendable {
    public let localDate: LocalDate
    /// Only when the archive also contains training records.
    public let sessionKey: String?
    public let text: String

    public init(localDate: LocalDate, sessionKey: String?, text: String) throws {
        guard text.utf8.count <= ArchiveLimits.maxTextUTF8Bytes else {
            throw ArchiveSnapshotError.textTooLong
        }
        self.localDate = localDate
        self.sessionKey = sessionKey
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case localDate, sessionKey, text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            localDate: container.decodeArchiveLocalDate(forKey: .localDate),
            sessionKey: container.decodeIfPresent(String.self, forKey: .sessionKey),
            text: container.decode(String.self, forKey: .text)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(localDate.canonicalString, forKey: .localDate)
        try container.encodeIfPresent(sessionKey, forKey: .sessionKey)
        try container.encode(text, forKey: .text)
    }
}

/// Wire form is a single string: a `BuiltInBodyMetric` raw value, or `custom`.
public enum ArchiveBodyMetricKind: Hashable, Codable, Sendable {
    case builtIn(BuiltInBodyMetric)
    case custom

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "custom" {
            self = .custom
        } else if let builtIn = BuiltInBodyMetric(rawValue: raw) {
            self = .builtIn(builtIn)
        } else {
            throw ArchiveSnapshotError.invalidBodyMetric
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .builtIn(let metric):
            try container.encode(metric.rawValue)
        case .custom:
            try container.encode("custom")
        }
    }
}

public struct ArchiveBodyMetric: Hashable, Codable, Sendable {
    public let key: String
    public let kind: ArchiveBodyMetricKind
    public let name: String?
    public let unit: String?

    /// Custom metrics require a non-empty name and unit; built-ins carry neither (their
    /// name and unit come from the app).
    public init(key: String, kind: ArchiveBodyMetricKind, name: String? = nil, unit: String? = nil) throws {
        switch kind {
        case .builtIn:
            guard name == nil, unit == nil else {
                throw ArchiveSnapshotError.invalidBodyMetric
            }
        case .custom:
            guard let name, let unit, !name.isEmpty, !unit.isEmpty else {
                throw ArchiveSnapshotError.invalidBodyMetric
            }
        }
        self.key = key
        self.kind = kind
        self.name = name
        self.unit = unit
    }

    private enum CodingKeys: String, CodingKey {
        case key, kind, name, unit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            key: container.decode(String.self, forKey: .key),
            kind: container.decode(ArchiveBodyMetricKind.self, forKey: .kind),
            name: container.decodeIfPresent(String.self, forKey: .name),
            unit: container.decodeIfPresent(String.self, forKey: .unit)
        )
    }
}

public struct ArchiveBodyMeasurement: Hashable, Codable, Sendable {
    public let metricKey: String
    public let localDay: LocalDate
    public let value: DecimalValue
    public let enteredUnit: String

    public init(metricKey: String, localDay: LocalDate, value: DecimalValue, enteredUnit: String) {
        self.metricKey = metricKey
        self.localDay = localDay
        self.value = value
        self.enteredUnit = enteredUnit
    }

    private enum CodingKeys: String, CodingKey {
        case metricKey, localDay, value, enteredUnit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            metricKey: try container.decode(String.self, forKey: .metricKey),
            localDay: try container.decodeArchiveLocalDate(forKey: .localDay),
            value: try container.decode(DecimalValue.self, forKey: .value),
            enteredUnit: try container.decode(String.self, forKey: .enteredUnit)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metricKey, forKey: .metricKey)
        try container.encode(localDay.canonicalString, forKey: .localDay)
        try container.encode(value, forKey: .value)
        try container.encode(enteredUnit, forKey: .enteredUnit)
    }
}

public struct ArchiveAttribution: Hashable, Codable, Sendable {
    public let sourceName: String
    public let licenseName: String
    public let licenseText: String
    public let exerciseKeys: [String]

    public init(sourceName: String, licenseName: String, licenseText: String, exerciseKeys: [String]) {
        self.sourceName = sourceName
        self.licenseName = licenseName
        self.licenseText = licenseText
        self.exerciseKeys = exerciseKeys
    }
}

// MARK: - Snapshot

public struct ArchiveSnapshot: Hashable, Codable, Sendable {
    public let manifest: ArchiveManifest
    public let student: ArchiveStudent?
    public let exercises: [ArchiveExercise]
    public let sessions: [ArchiveSession]
    public let summaries: [ArchiveSummary]
    public let bodyMetrics: [ArchiveBodyMetric]
    public let bodyMeasurements: [ArchiveBodyMeasurement]
    public let attribution: ArchiveAttribution?

    public init(
        manifest: ArchiveManifest,
        student: ArchiveStudent? = nil,
        exercises: [ArchiveExercise] = [],
        sessions: [ArchiveSession] = [],
        summaries: [ArchiveSummary] = [],
        bodyMetrics: [ArchiveBodyMetric] = [],
        bodyMeasurements: [ArchiveBodyMeasurement] = [],
        attribution: ArchiveAttribution? = nil
    ) {
        self.manifest = manifest
        self.student = student
        self.exercises = exercises
        self.sessions = sessions
        self.summaries = summaries
        self.bodyMetrics = bodyMetrics
        self.bodyMeasurements = bodyMeasurements
        self.attribution = attribution
    }

    /// Section counts derived from the content, for building and checking a manifest.
    public var derivedCounts: ArchiveCounts {
        ArchiveCounts(
            student: student == nil ? 0 : 1,
            exercise: exercises.count,
            session: sessions.count,
            summary: summaries.count,
            bodyMetric: bodyMetrics.count,
            bodyMeasurement: bodyMeasurements.count,
            attribution: attribution == nil ? 0 : 1
        )
    }

    public var totalSetCount: Int {
        sessions.reduce(0) { total, session in
            total + session.sections.reduce(0) { sectionTotal, section in
                sectionTotal + section.exercises.reduce(0) { $0 + $1.sets.count }
            }
        }
    }

    /// Structural validation shared by the file decoder and the local snapshot loader:
    /// limits, counts, module/content agreement, key uniqueness and reference integrity.
    public func validateIntegrity() throws {
        let modules = manifest.modules
        let limit = ArchiveLimits.maxTextUTF8Bytes

        guard exercises.count <= ArchiveLimits.maxExercises,
            sessions.count <= ArchiveLimits.maxSessions,
            summaries.count <= ArchiveLimits.maxSummaries,
            bodyMetrics.count <= ArchiveLimits.maxBodyMetrics,
            bodyMeasurements.count <= ArchiveLimits.maxBodyMeasurements,
            totalSetCount <= ArchiveLimits.maxSets
        else {
            throw ArchiveSnapshotError.limitExceeded
        }
        guard manifest.counts == derivedCounts else {
            throw ArchiveSnapshotError.countsMismatch
        }

        // Module / content agreement: content of an unselected module must not appear.
        if let student {
            guard modules.displayName || modules.sex,
                student.displayName == nil || modules.displayName,
                student.sex == nil || modules.sex,
                student.displayName != nil || student.sex != nil
            else {
                throw ArchiveSnapshotError.moduleContentMismatch
            }
            if let name = student.displayName, name.utf8.count > limit {
                throw ArchiveSnapshotError.textTooLong
            }
        }
        guard (exercises.isEmpty && sessions.isEmpty) || modules.trainingRecords,
            summaries.isEmpty || modules.summaries,
            (bodyMetrics.isEmpty && bodyMeasurements.isEmpty) || modules.bodyData,
            attribution == nil || modules.exerciseInfo
        else {
            throw ArchiveSnapshotError.moduleContentMismatch
        }

        // Exercises.
        var exerciseKinds: [String: ArchiveExerciseKind] = [:]
        var placeholderNumbers = Set<Int>()
        for exercise in exercises {
            guard ArchiveWireCoding.isValidKey(exercise.key, prefix: "e"), exercise.placeholderNumber >= 1 else {
                throw ArchiveSnapshotError.invalidKey
            }
            guard exerciseKinds.updateValue(exercise.kind, forKey: exercise.key) == nil,
                placeholderNumbers.insert(exercise.placeholderNumber).inserted
            else {
                throw ArchiveSnapshotError.duplicateKey
            }
            if let info = exercise.info {
                guard modules.exerciseInfo else {
                    throw ArchiveSnapshotError.moduleContentMismatch
                }
                let texts = [info.name, info.equipment] + info.primaryMuscles + info.secondaryMuscles
                guard texts.allSatisfy({ $0.utf8.count <= limit }) else {
                    throw ArchiveSnapshotError.textTooLong
                }
            }
        }

        // Sessions.
        var sessionKeys = Set<String>()
        for session in sessions {
            guard ArchiveWireCoding.isValidKey(session.key, prefix: "s"), session.durationMinutes >= 0 else {
                throw ArchiveSnapshotError.invalidKey
            }
            guard sessionKeys.insert(session.key).inserted else {
                throw ArchiveSnapshotError.duplicateKey
            }
            for section in session.sections {
                if let name = section.name, name.utf8.count > limit {
                    throw ArchiveSnapshotError.textTooLong
                }
                for entry in section.exercises where exerciseKinds[entry.exerciseKey] == nil {
                    throw ArchiveSnapshotError.danglingReference
                }
            }
        }

        // Summaries.
        for summary in summaries {
            guard summary.text.utf8.count <= limit else {
                throw ArchiveSnapshotError.textTooLong
            }
            if let sessionKey = summary.sessionKey {
                guard modules.trainingRecords else {
                    throw ArchiveSnapshotError.moduleContentMismatch
                }
                guard sessionKeys.contains(sessionKey) else {
                    throw ArchiveSnapshotError.danglingReference
                }
            }
        }

        // Body data.
        var metricKeys = Set<String>()
        for metric in bodyMetrics {
            guard ArchiveWireCoding.isValidKey(metric.key, prefix: "m") else {
                throw ArchiveSnapshotError.invalidKey
            }
            guard metricKeys.insert(metric.key).inserted else {
                throw ArchiveSnapshotError.duplicateKey
            }
            if (metric.name?.utf8.count ?? 0) > limit || (metric.unit?.utf8.count ?? 0) > limit {
                throw ArchiveSnapshotError.textTooLong
            }
        }
        for measurement in bodyMeasurements {
            guard metricKeys.contains(measurement.metricKey) else {
                throw ArchiveSnapshotError.danglingReference
            }
            guard !measurement.enteredUnit.isEmpty, measurement.enteredUnit.utf8.count <= limit else {
                throw ArchiveSnapshotError.textTooLong
            }
        }

        // Attribution covers built-in exercises only.
        if let attribution {
            let texts = [attribution.sourceName, attribution.licenseName, attribution.licenseText]
            guard texts.allSatisfy({ $0.utf8.count <= limit }) else {
                throw ArchiveSnapshotError.textTooLong
            }
            guard !attribution.exerciseKeys.isEmpty else {
                throw ArchiveSnapshotError.moduleContentMismatch
            }
            for key in attribution.exerciseKeys {
                guard let kind = exerciseKinds[key] else {
                    throw ArchiveSnapshotError.danglingReference
                }
                guard kind == .builtIn else {
                    throw ArchiveSnapshotError.moduleContentMismatch
                }
            }
        }
    }
}

// MARK: - Local display settings (data-model §5)

public struct ArchiveDisplaySettings: Hashable, Codable, Sendable {
    public enum WeightUnit: String, Codable, Sendable {
        case kg
        case lb
    }

    public enum LengthUnit: String, Codable, Sendable {
        case cm
        case inch = "in"
    }

    public enum Density: String, Codable, Sendable {
        case standard
        case compact
    }

    public var weightUnit: WeightUnit
    public var lengthUnit: LengthUnit
    public var density: Density

    public init(weightUnit: WeightUnit = .kg, lengthUnit: LengthUnit = .cm, density: Density = .standard) {
        self.weightUnit = weightUnit
        self.lengthUnit = lengthUnit
        self.density = density
    }

    public static let defaults = ArchiveDisplaySettings()
}
