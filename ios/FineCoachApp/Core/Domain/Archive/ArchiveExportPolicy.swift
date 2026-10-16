import Foundation

// M2 export allow-list policy (T028, T061 export half; plan D-M2-004, data-model §1).
//
// Pure and deterministic: `makeSnapshot` reads only `ArchiveExportSource` (which has no field for
// any permanently excluded datum) and writes only what `ArchiveModuleSelection` selects. The
// snapshot it returns is exactly what the preview renders and what the archive file encodes
// (M2-FR-008). No Coach-side stable ID (student, session, exercise, metric) is ever copied.

public enum ArchiveExportPolicyError: Error, Equatable, Sendable {
    /// The effective selection is empty: nothing to preview or export.
    case nothingSelected
    /// The selection was built from different student data than the source passed in.
    case selectionOutOfDate
}

public enum ArchiveExportPolicy {
    /// Equipment written for exercises the app has no equipment class for (custom and
    /// session-only exercises). The existing catalog taxonomy's fallback class.
    public static let unknownEquipment = "其他"

    public static func makeSnapshot(
        source: ArchiveExportSource,
        selection: ArchiveModuleSelection,
        identity: ArchiveIdentity,
        now: Date
    ) throws -> ArchiveSnapshot {
        guard selection.availability == source.availability else {
            throw ArchiveExportPolicyError.selectionOutOfDate
        }
        guard let modules = selection.effectiveModules else {
            throw ArchiveExportPolicyError.nothingSelected
        }

        // Oldest first; equal times keep the source order.
        let sessions = source.sessions.enumerated().sorted {
            ($0.element.completedAtUTC, $0.offset) < ($1.element.completedAtUTC, $1.offset)
        }.map(\.element)

        let student = makeStudent(source.student, modules: modules)
        var exercises: [ArchiveExercise] = []
        var archiveSessions: [ArchiveSession] = []
        var sessionKeys: [String] = []
        var numbering = ExerciseNumbering(includeInfo: modules.exerciseInfo)
        if modules.trainingRecords {
            for (index, session) in sessions.enumerated() {
                let key = "s\(index + 1)"
                sessionKeys.append(key)
                archiveSessions.append(
                    ArchiveSession(
                        key: key,
                        localDate: session.localDate,
                        completedAtUTC: wireDate(session.completedAtUTC),
                        durationMinutes: session.durationMinutes,
                        trainingFocus: session.trainingFocus,
                        sections: session.sections.map { section in
                            ArchiveSection(
                                name: section.name,
                                exercises: section.exercises.map { exercise in
                                    ArchiveSessionExercise(
                                        exerciseKey: numbering.key(for: exercise),
                                        recordMode: exercise.recordMode,
                                        sets: exercise.sets
                                    )
                                }
                            )
                        }
                    )
                )
            }
            exercises = numbering.exercises()
        }

        let attribution = modules.exerciseInfo ? makeAttribution(numbering.attributedBuiltIns()) : nil

        var summaries: [ArchiveSummary] = []
        if modules.summaries {
            for (index, session) in sessions.enumerated() {
                guard let text = session.summary else { continue }
                summaries.append(
                    try ArchiveSummary(
                        localDate: session.localDate,
                        sessionKey: modules.trainingRecords ? sessionKeys[index] : nil,
                        text: text
                    )
                )
            }
        }

        var bodyMetrics: [ArchiveBodyMetric] = []
        var bodyMeasurements: [ArchiveBodyMeasurement] = []
        if modules.bodyData {
            let selected = Set(selection.effectiveBodyMetricIDs)
            for metric in source.bodyMetrics where selected.contains(metric.id) {
                let key = "m\(bodyMetrics.count + 1)"
                bodyMetrics.append(
                    try ArchiveBodyMetric(key: key, kind: metric.kind, name: metric.name, unit: metric.unit))
                for measurement in metric.measurements {
                    bodyMeasurements.append(
                        ArchiveBodyMeasurement(
                            metricKey: key,
                            localDay: measurement.localDay,
                            value: measurement.value,
                            enteredUnit: measurement.enteredUnit
                        )
                    )
                }
            }
        }

        let counts = ArchiveCounts(
            student: student == nil ? 0 : 1,
            exercise: exercises.count,
            session: archiveSessions.count,
            summary: summaries.count,
            bodyMetric: bodyMetrics.count,
            bodyMeasurement: bodyMeasurements.count,
            attribution: attribution == nil ? 0 : 1
        )
        let manifest = try ArchiveManifest(
            sourceID: identity.sourceID,
            studentArchiveID: identity.studentArchiveID,
            snapshotAtUTC: wireDate(now),
            modules: modules,
            counts: counts
        )
        return ArchiveSnapshot(
            manifest: manifest,
            student: student,
            exercises: exercises,
            sessions: archiveSessions,
            summaries: summaries,
            bodyMetrics: bodyMetrics,
            bodyMeasurements: bodyMeasurements,
            attribution: attribution
        )
    }

    /// `FineCoach-档案-YYYYMMDD-HHmm.fcarchive` in the snapshot's local time (contract §1).
    /// Nothing but the time goes into the name.
    public static func fileName(snapshotAtUTC: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: snapshotAtUTC)
        return String(
            format: "FineCoach-档案-%04d%02d%02d-%02d%02d.fcarchive",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
        )
    }

    // MARK: Student

    private static func makeStudent(_ student: ArchiveExportSource.Student, modules: ArchiveModuleSet)
        -> ArchiveStudent?
    {
        guard modules.displayName || modules.sex else {
            return nil
        }
        return ArchiveStudent(
            displayName: modules.displayName ? student.displayName : nil,
            sex: modules.sex ? student.sex : nil
        )
    }

    // MARK: Exercise numbering (D-001)

    /// Assigns archive keys and placeholder numbers in order of first appearance. The same
    /// stable identity keeps its key; every one-off occurrence gets a new one. Numbers never
    /// derive from names.
    private struct ExerciseNumbering {
        private struct Entry {
            var kind: ArchiveExerciseKind
            var isAssisted: Bool
            var name: String
            var catalog: ArchiveExportSource.CatalogReference?
        }

        private let includeInfo: Bool
        private var indexByIdentity: [ArchiveExportSource.Exercise.Identity: Int] = [:]
        private var entries: [Entry] = []

        init(includeInfo: Bool) {
            self.includeInfo = includeInfo
        }

        mutating func key(for exercise: ArchiveExportSource.Exercise) -> String {
            let entry = Entry(
                kind: exercise.kind,
                isAssisted: exercise.isAssisted,
                name: exercise.name,
                catalog: exercise.catalog
            )
            if case .stable = exercise.identity, let index = indexByIdentity[exercise.identity] {
                // Later occurrences refresh name, assist flag and catalog facts.
                entries[index] = entry
                return "e\(index + 1)"
            }
            entries.append(entry)
            if case .stable = exercise.identity {
                indexByIdentity[exercise.identity] = entries.count - 1
            }
            return "e\(entries.count)"
        }

        func exercises() -> [ArchiveExercise] {
            entries.enumerated().map { index, entry in
                ArchiveExercise(
                    key: "e\(index + 1)",
                    placeholderNumber: index + 1,
                    kind: entry.kind,
                    isAssisted: entry.isAssisted,
                    info: includeInfo
                        ? ArchiveExerciseInfo(
                            name: entry.name,
                            primaryMuscles: entry.catalog?.primaryMuscles ?? [],
                            secondaryMuscles: entry.catalog?.secondaryMuscles ?? [],
                            equipment: entry.catalog?.equipment ?? ArchiveExportPolicy.unknownEquipment
                        ) : nil
                )
            }
        }

        /// Built-in exercises with usable catalog facts, in key order.
        func attributedBuiltIns() -> [(key: String, catalog: ArchiveExportSource.CatalogReference)] {
            entries.enumerated().compactMap { index, entry in
                guard entry.kind == .builtIn, let catalog = entry.catalog else { return nil }
                return ("e\(index + 1)", catalog)
            }
        }
    }

    // MARK: Attribution (T061)

    /// One frame (contract §4). The built-in catalog's records carry different licenses and
    /// versions (CC-BY-SA 3.0 / 4.0, CC0), so the frame lists every distinct source and license
    /// that applies to the exported built-in exercises, sorted; it does not pick one.
    private static func makeAttribution(
        _ builtIns: [(key: String, catalog: ArchiveExportSource.CatalogReference)]
    ) -> ArchiveAttribution? {
        guard !builtIns.isEmpty else {
            return nil
        }
        func distinctSorted(_ values: [String]) -> [String] {
            Array(Set(values)).sorted()
        }
        let catalogs = builtIns.map(\.catalog)
        let licenseNames = distinctSorted(catalogs.map(\.licenseName))
        var licenseTexts: [String] = []
        for name in licenseNames {
            if let text = catalogs.first(where: { $0.licenseName == name })?.licenseText {
                licenseTexts.append(text)
            }
        }
        return ArchiveAttribution(
            sourceName: distinctSorted(catalogs.map(\.sourceName)).joined(separator: ", "),
            licenseName: licenseNames.joined(separator: " / "),
            licenseText: licenseTexts.joined(separator: "\n"),
            exerciseKeys: builtIns.map(\.key)
        )
    }

    // MARK: Wire precision

    /// Dates are written with millisecond precision (contract §4). The value is moved to a fixed
    /// point of the wire round trip (`date(string(x)) == x`), so the in-memory snapshot, the
    /// preview and the decoded archive are field-equal; a plain rounding to milliseconds can
    /// land one millisecond off after formatting.
    private static func wireDate(_ date: Date) -> Date {
        var current = date
        for _ in 0..<8 {
            guard let next = try? ArchiveWireCoding.date(from: ArchiveWireCoding.string(from: current)) else {
                return current
            }
            if next == current {
                return current
            }
            current = next
        }
        return current
    }
}
