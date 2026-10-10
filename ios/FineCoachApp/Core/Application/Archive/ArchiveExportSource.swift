import CoreData
import Foundation

// M2 export projection (T027, plan §7.1, D-M2-004).
//
// `ArchiveExportSource` is the ONLY thing `ArchiveExportPolicy` reads. Permanent exclusions
// (M2-FR-010) are enforced by projection, not by filtering: injury notes, coach private notes,
// exercise private notes, packages, schedule / appointment links, credit adjustments, contacts,
// training goal, templates and images have no field on any type below, and the reader never
// fetches those attributes. The projection holds only completed sessions and confirmed sets.
//
// `Exercise.Identity` carries the Coach-side stable exercise identity ONLY so the policy can give
// the same exercise the same archive key and placeholder number. It is never emitted.

public struct ArchiveExportSource: Equatable, Sendable {
    public struct Student: Equatable, Sendable {
        public let displayName: String
        public let sex: StudentSex
    }

    /// Text facts of a built-in exercise plus what its attribution frame needs (contract §4).
    public struct CatalogReference: Equatable, Sendable {
        public let primaryMuscles: [String]
        public let secondaryMuscles: [String]
        public let equipment: String
        public let sourceName: String
        public let licenseName: String
        public let licenseText: String
    }

    /// One exercise occurrence inside one completed session.
    public struct Exercise: Equatable, Sendable {
        public enum Identity: Hashable, Sendable {
            /// Built-in or custom exercise: the Coach catalog ID. Policy-internal only.
            case stable(String)
            /// Session-only exercise: no identity; every occurrence is its own exercise (D-001).
            case oneOff
        }

        public let identity: Identity
        public let kind: ArchiveExerciseKind
        /// From the Coach `ExercisePreference` (spec Revision 1.1.2); false for one-off.
        public let isAssisted: Bool
        /// The name the session recorded (`displayNameSnapshot`); written only with exerciseInfo.
        public let name: String
        /// Built-in exercises only.
        public let catalog: CatalogReference?
        public let recordMode: RecordMode
        /// Confirmed sets only.
        public let sets: [ArchiveSet]
    }

    public struct Section: Equatable, Sendable {
        /// `nil` is the unsectioned group.
        public let name: String?
        public let exercises: [Exercise]
    }

    public struct Session: Equatable, Sendable {
        public let completedAtUTC: Date
        public let localDate: LocalDate
        public let durationMinutes: Int
        public let trainingFocus: Set<BodyPart>
        /// Non-empty student-facing summary, verbatim. Never the coach private note.
        public let summary: String?
        public let sections: [Section]
    }

    public struct Measurement: Equatable, Sendable {
        public let localDay: LocalDate
        public let value: DecimalValue
        public let enteredUnit: String
    }

    public struct BodyMetric: Equatable, Sendable {
        /// Coach metric ID: identifies the metric in the selection UI only. Never emitted.
        public let id: StableUUID
        public let kind: ArchiveBodyMetricKind
        /// Custom metrics only.
        public let name: String?
        public let unit: String?
        public let measurements: [Measurement]
    }

    public let student: Student
    /// Completed sessions, oldest first.
    public let sessions: [Session]
    /// Built-in metrics in `BuiltInBodyMetric` order, then custom metrics; only metrics with
    /// at least one measurement.
    public let bodyMetrics: [BodyMetric]

    /// Facts for the selection screen and for `ArchiveModuleSelection` (D-005).
    public var availability: ArchiveModuleAvailability {
        let ordered = sessions.enumerated().sorted {
            ($0.element.completedAtUTC, $0.offset) < ($1.element.completedAtUTC, $1.offset)
        }.map(\.element)
        var stableIdentities = Set<Exercise.Identity>()
        var oneOffCount = 0
        var setCount = 0
        for exercise in ordered.flatMap({ $0.sections.flatMap(\.exercises) }) {
            setCount += exercise.sets.count
            if case .stable = exercise.identity {
                stableIdentities.insert(exercise.identity)
            } else {
                oneOffCount += 1
            }
        }
        return ArchiveModuleAvailability(
            hasDisplayName: !student.displayName.isEmpty,
            // 「不透露」carries no information, so it counts as no data (D-005, owner 2026-10-10).
            hasSex: student.sex != .undisclosed,
            completedSessionCount: ordered.count,
            earliestSessionDate: ordered.first?.localDate,
            latestSessionDate: ordered.last?.localDate,
            confirmedSetCount: setCount,
            summaryCount: ordered.filter { $0.summary != nil }.count,
            exerciseCount: stableIdentities.count + oneOffCount,
            bodyMetrics: bodyMetrics.map {
                .init(id: $0.id, kind: $0.kind, name: $0.name, measurementCount: $0.measurements.count)
            }
        )
    }
}

public protocol ArchiveExportSourceReading: Sendable {
    func read(studentID: StableUUID) async throws -> ArchiveExportSource
}

/// Builds the projection in one read-only `PersistenceWriter.read`. Archived students are read
/// exactly like active ones (D-006); nothing is written.
public struct ArchiveExportSourceReader: ArchiveExportSourceReading {
    private let writer: PersistenceWriter
    private let calendarProvider: any LocalCalendarProvider
    private let catalogLoader: @Sendable () -> PlaceholderExerciseCatalog?

    public init(
        writer: PersistenceWriter,
        calendarProvider: any LocalCalendarProvider = SystemLocalCalendarProvider(),
        catalogLoader: @escaping @Sendable () -> PlaceholderExerciseCatalog? = {
            try? PlaceholderExerciseCatalogLoader.loadFromBundle(Bundle.main)
        }
    ) {
        self.writer = writer
        self.calendarProvider = calendarProvider
        self.catalogLoader = catalogLoader
    }

    public func read(studentID: StableUUID) async throws -> ArchiveExportSource {
        let calendar = calendarProvider.currentCalendar()
        let catalog = catalogLoader()
        return try await writer.read { context in
            try Self.project(studentID: studentID.rawValue, calendar: calendar, catalog: catalog, in: context)
        }
    }

    // MARK: Projection

    private static func project(
        studentID: UUID,
        calendar: Calendar,
        catalog: PlaceholderExerciseCatalog?,
        in context: NSManagedObjectContext
    ) throws -> ArchiveExportSource {
        let studentObject = try StudentManagedObjectMapping.requireStudent(id: studentID, in: context)
        guard let displayName = studentObject.value(forKey: "displayName") as? String,
            let sexRaw = studentObject.value(forKey: "sex") as? String,
            let sex = StudentSex(rawValue: sexRaw)
        else {
            throw DomainError.incompatibleInput
        }

        let references = CatalogReferences(catalog)
        let assisted = try assistedFlags(in: context)
        let sessions = try completedSessions(
            studentID: studentID,
            calendar: calendar,
            references: references,
            assisted: assisted,
            in: context
        )
        return ArchiveExportSource(
            student: .init(displayName: displayName, sex: sex),
            sessions: sessions,
            bodyMetrics: try bodyMetrics(studentID: studentID, in: context)
        )
    }

    private static func assistedFlags(in context: NSManagedObjectContext) throws -> [String: Bool] {
        var flags: [String: Bool] = [:]
        for object in try ExerciseManagedObjectMapping.fetchPreferences(in: context) {
            if let exerciseID = object.value(forKey: "exerciseID") as? String {
                flags[exerciseID] = object.value(forKey: "isAssisted") as? Bool ?? false
            }
        }
        return flags
    }

    private static func completedSessions(
        studentID: UUID,
        calendar: Calendar,
        references: CatalogReferences,
        assisted: [String: Bool],
        in context: NSManagedObjectContext
    ) throws -> [ArchiveExportSource.Session] {
        let completed = SessionState.completed.rawValue
        let sessionRequest = NSFetchRequest<NSManagedObject>(entityName: SessionManagedObjectMapping.sessionEntityName)
        sessionRequest.predicate = NSPredicate(
            format: "studentID == %@ AND state == %@ AND completedAtUTC != nil",
            studentID as CVarArg,
            completed
        )
        sessionRequest.sortDescriptors = [NSSortDescriptor(key: "completedAtUTC", ascending: true)]
        let sessionObjects = try context.fetch(sessionRequest)

        // Exercises and confirmed sets of this student's completed sessions, one fetch each.
        let exerciseRequest = NSFetchRequest<NSManagedObject>(entityName: SessionManagedObjectMapping.exerciseEntityName)
        exerciseRequest.predicate = NSPredicate(
            format: "session.studentID == %@ AND session.state == %@",
            studentID as CVarArg,
            completed
        )
        exerciseRequest.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
        let setRequest = NSFetchRequest<NSManagedObject>(entityName: SessionManagedObjectMapping.setEntityName)
        setRequest.predicate = NSPredicate(
            format:
                "sessionExercise.session.studentID == %@ AND sessionExercise.session.state == %@ AND state == %@",
            studentID as CVarArg,
            completed,
            SetRecordingState.completed.rawValue
        )
        setRequest.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]

        var setsByExercise: [UUID: [ArchiveSet]] = [:]
        for object in try context.fetch(setRequest) {
            let trainingSet = try SessionManagedObjectMapping.makeTrainingSet(from: object)
            setsByExercise[trainingSet.sessionExerciseID.rawValue, default: []].append(
                ArchiveSet(
                    weightValue: trainingSet.weightValue,
                    repetitionCount: trainingSet.repetitionCount,
                    durationSeconds: trainingSet.durationSeconds,
                    unit: trainingSet.unit,
                    side: trainingSet.side,
                    leftValue: trainingSet.leftValue,
                    rightValue: trainingSet.rightValue,
                    distanceValue: trainingSet.distanceValue,
                    speedValue: trainingSet.speedValue,
                    resistanceValue: trainingSet.resistanceValue
                )
            )
        }

        var exercisesBySession: [UUID: [NSManagedObject]] = [:]
        for object in try context.fetch(exerciseRequest) {
            guard let sessionID = object.value(forKey: "sessionID") as? UUID else {
                throw DomainError.incompatibleInput
            }
            exercisesBySession[sessionID, default: []].append(object)
        }

        let sectionNames = try sessionSectionNames(in: context)

        var sessions: [ArchiveExportSource.Session] = []
        sessions.reserveCapacity(sessionObjects.count)
        for object in sessionObjects {
            guard let sessionID = object.value(forKey: "id") as? UUID,
                let completedAtUTC = object.value(forKey: "completedAtUTC") as? Date
            else {
                throw DomainError.incompatibleInput
            }
            let sections = try projectSections(
                exerciseObjects: exercisesBySession[sessionID] ?? [],
                setsByExercise: setsByExercise,
                sectionNames: sectionNames,
                references: references,
                assisted: assisted
            )
            let summaryText = object.value(forKey: "studentFacingSummary") as? String
            sessions.append(
                ArchiveExportSource.Session(
                    completedAtUTC: completedAtUTC,
                    localDate: LocalDate(date: completedAtUTC, calendar: calendar),
                    durationMinutes: try durationMinutes(of: object),
                    trainingFocus: BodyPartCoding.parts(
                        fromMask: object.value(forKey: "trainingFocusMask") as? Int32 ?? 0
                    ),
                    summary: summaryText.flatMap {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                    },
                    sections: sections
                )
            )
        }
        return sessions
    }

    /// The same rule history shows: coach-adjusted duration when present, otherwise elapsed;
    /// rounded to whole minutes, never below one.
    private static func durationMinutes(of session: NSManagedObject) throws -> Int {
        let adjusted = session.value(forKey: "coachAdjustedDurationSeconds") as? NSDecimalNumber
        guard let seconds = adjusted ?? (session.value(forKey: "elapsedSeconds") as? NSDecimalNumber) else {
            throw DomainError.incompatibleInput
        }
        return max(1, Int((seconds.doubleValue / 60).rounded()))
    }

    private static func sessionSectionNames(in context: NSManagedObjectContext) throws -> [UUID: String] {
        let request = NSFetchRequest<NSManagedObject>(entityName: SessionSectionManagedObjectMapping.entityName)
        request.predicate = NSPredicate(format: "ownerKind == %@", SessionSectionOwnerKind.session.rawValue)
        var names: [UUID: String] = [:]
        for object in try context.fetch(request) {
            if let id = object.value(forKey: "id") as? UUID, let name = object.value(forKey: "name") as? String {
                names[id] = name
            }
        }
        return names
    }

    /// Groups consecutive exercises by section, the way the Coach screens do. Exercises
    /// without a confirmed set and sections left empty are dropped.
    private static func projectSections(
        exerciseObjects: [NSManagedObject],
        setsByExercise: [UUID: [ArchiveSet]],
        sectionNames: [UUID: String],
        references: CatalogReferences,
        assisted: [String: Bool]
    ) throws -> [ArchiveExportSource.Section] {
        var sections: [ArchiveExportSource.Section] = []
        var runSectionID: UUID?
        var runExercises: [ArchiveExportSource.Exercise] = []
        var hasRun = false

        func closeRun() {
            if hasRun, !runExercises.isEmpty {
                sections.append(
                    .init(name: runSectionID.flatMap { sectionNames[$0] }, exercises: runExercises)
                )
            }
            runExercises = []
        }

        for object in exerciseObjects {
            guard let id = object.value(forKey: "id") as? UUID else {
                throw DomainError.incompatibleInput
            }
            guard let sets = setsByExercise[id], !sets.isEmpty else {
                continue
            }
            let sectionID = object.value(forKey: "sectionID") as? UUID
            if !hasRun || sectionID != runSectionID {
                closeRun()
                runSectionID = sectionID
                hasRun = true
            }
            runExercises.append(
                try projectExercise(object, sets: sets, references: references, assisted: assisted)
            )
        }
        closeRun()
        return sections
    }

    private static func projectExercise(
        _ object: NSManagedObject,
        sets: [ArchiveSet],
        references: CatalogReferences,
        assisted: [String: Bool]
    ) throws -> ArchiveExportSource.Exercise {
        guard let kindRaw = object.value(forKey: "sourceKind") as? String,
            let sourceKind = ExerciseSourceKind(rawValue: kindRaw),
            let name = object.value(forKey: "displayNameSnapshot") as? String,
            let modeRaw = object.value(forKey: "recordModeSnapshot") as? String,
            let recordMode = RecordMode(rawValue: modeRaw)
        else {
            throw DomainError.incompatibleInput
        }
        let sourceID = object.value(forKey: "sourceID") as? String
        switch sourceKind {
        case .sessionOnly:
            return .init(
                identity: .oneOff, kind: .oneOff, isAssisted: false, name: name, catalog: nil,
                recordMode: recordMode, sets: sets)
        case .builtIn, .custom:
            guard let sourceID, !sourceID.isEmpty else {
                throw DomainError.incompatibleInput
            }
            let isBuiltIn = sourceKind == .builtIn
            return .init(
                identity: .stable(sourceID),
                kind: isBuiltIn ? .builtIn : .custom,
                isAssisted: assisted[sourceID] ?? false,
                name: name,
                catalog: isBuiltIn ? references.reference(forExerciseID: sourceID) : nil,
                recordMode: recordMode,
                sets: sets
            )
        }
    }

    // MARK: Body data

    private static func bodyMetrics(
        studentID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [ArchiveExportSource.BodyMetric] {
        var measurementsByMetric: [UUID: [ArchiveExportSource.Measurement]] = [:]
        for object in try BodyMetricManagedObjectMapping.fetchMeasurements(studentID: studentID, in: context) {
            let measurement = try BodyMetricManagedObjectMapping.makeMeasurement(from: object)
            measurementsByMetric[measurement.metricID.rawValue, default: []].append(
                .init(
                    localDay: measurement.localCalendarDay,
                    value: measurement.value,
                    enteredUnit: measurement.enteredUnit
                )
            )
        }

        var metrics: [ArchiveExportSource.BodyMetric] = []
        for builtIn in BuiltInBodyMetric.allCases {
            if let measurements = measurementsByMetric[builtIn.id.rawValue], !measurements.isEmpty {
                metrics.append(
                    .init(
                        id: builtIn.id,
                        kind: .builtIn(builtIn),
                        name: nil,
                        unit: nil,
                        measurements: measurements.sorted { $0.localDay < $1.localDay }
                    )
                )
            }
        }
        // Custom metrics, archived ones included: their history stays exportable.
        for object in try BodyMetricManagedObjectMapping.fetchMetrics(studentID: studentID, in: context) {
            let metric = try BodyMetricManagedObjectMapping.makeMetric(from: object)
            guard metric.kind == .custom,
                let measurements = measurementsByMetric[metric.id.rawValue], !measurements.isEmpty
            else {
                continue
            }
            metrics.append(
                .init(
                    id: metric.id,
                    kind: .custom,
                    name: metric.name.value,
                    unit: metric.currentUnit,
                    measurements: measurements.sorted { $0.localDay < $1.localDay }
                )
            )
        }
        return metrics
    }

    // MARK: Built-in catalog facts (provenance.json)

    private struct CatalogReferences {
        private var exercises: [String: PlaceholderCatalogExercise] = [:]
        private var records: [String: ExerciseProvenanceRecord] = [:]

        init(_ catalog: PlaceholderExerciseCatalog?) {
            guard let catalog else { return }
            exercises = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            records = Dictionary(
                catalog.provenance.records.map { ($0.recordID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        /// `nil` when the catalog has no usable entry (then the policy writes unknown facts and
        /// no attribution for that exercise).
        func reference(forExerciseID id: String) -> ArchiveExportSource.CatalogReference? {
            guard let exercise = exercises[id],
                let primary = exercise.primaryMuscleGroup,
                let equipment = exercise.equipmentClass,
                let record = records[exercise.provenanceRef]
            else {
                return nil
            }
            let sourceName = record.sourceIdentifier.split(separator: ":", maxSplits: 1).first.map(String.init)
            return .init(
                primaryMuscles: [primary],
                secondaryMuscles: exercise.secondaryMuscleGroups ?? [],
                equipment: equipment,
                sourceName: sourceName ?? record.authorOrOwner,
                licenseName: record.licenseIdentifier,
                licenseText: record.licenseText
            )
        }
    }
}
