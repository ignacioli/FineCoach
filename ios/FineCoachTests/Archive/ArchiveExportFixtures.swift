import CoreData
import Foundation
import XCTest

@testable import FineCoach

/// Fictional Core Data fixture and doubles for the M2 export tests (T036, T037). Compiled into
/// both test targets. Every value is invented; the `excluded...` and `included...` constants are
/// the sentinels the tests scan for.
enum ArchiveExportFixtures {
    // MARK: Identities

    static let studentID = StableUUID(UUID(uuidString: "a1000000-0000-4000-8000-000000000001")!)
    static let customExerciseID = UUID(uuidString: "a1000000-0000-4000-8000-0000000000e1")!
    static let session1ID = StableUUID(UUID(uuidString: "a1000000-0000-4000-8000-0000000000a1")!)
    static let session2ID = StableUUID(UUID(uuidString: "a1000000-0000-4000-8000-0000000000a2")!)
    static let inProgressSessionID = StableUUID(UUID(uuidString: "a1000000-0000-4000-8000-0000000000a3")!)
    static let abandonedSessionID = StableUUID(UUID(uuidString: "a1000000-0000-4000-8000-0000000000a4")!)
    static let sectionID = StableUUID(UUID(uuidString: "a1000000-0000-4000-8000-0000000000b1")!)
    static let customMetricID = StableUUID(UUID(uuidString: "a1000000-0000-4000-8000-0000000000c1")!)
    static let identity = ArchiveIdentity(
        sourceID: UUID(uuidString: "b1000000-0000-4000-8000-000000000001")!,
        studentArchiveID: UUID(uuidString: "b1000000-0000-4000-8000-000000000002")!
    )

    /// Built-in catalog entries (provenance.json): CC-BY-SA-3.0, CC-BY-SA-4.0.
    static let builtInID = "275fb49f-975c-4d6e-9d63-2c86ed740f40"
    static let builtInName = "杠铃上斜卧推"
    static let secondBuiltInID = "e4966cb8-9089-4595-9c78-99a27821e6ff"
    static let secondBuiltInName = "哑铃地板卧推"

    // MARK: Values that must never reach an archive (M2-FR-010)

    static let excludedInjury = "示例伤病：左膝术后恢复期"
    static let excludedCoachNote = "示例教练私有备注：对批评敏感"
    static let excludedGoal = "示例训练目标：半马完赛"
    static let excludedPhone = "13000000001"
    static let excludedWeChat = "示例微信号fc_test"
    static let excludedSessionNote = "示例课程私有备注：别提体重"
    static let excludedActionNote = "示例动作私有备注：右肩弹响"
    static let excludedPackageName = "示例课包十次卡"
    static let excludedAdjustmentReason = "示例课时调整原因：补记一次训练"
    static let excludedCancellationReason = "示例取消原因：学员出差"
    static let excludedTemplateName = "示例模板上肢日"
    static var excludedValues: [String] {
        [
            excludedInjury, excludedCoachNote, excludedGoal, excludedPhone, excludedWeChat,
            excludedSessionNote, excludedActionNote, excludedPackageName, excludedAdjustmentReason,
            excludedCancellationReason, excludedTemplateName,
        ]
    }

    // MARK: Values that exist only behind a module switch

    static let studentName = "示例学员甲乙"
    static let customExerciseName = "示例自定义动作"
    static let oneOffNames = ["示例仅本次甲", "示例仅本次乙", "示例仅本次丙"]
    static let summaryOne = "课后总结甲：深蹲节奏稳定，下次加两公斤。"
    static let summaryTwo = "课后总结乙：肩部热身要做足。"
    static let inProgressSummary = "课后总结丙：进行中不应出现。"
    static let bodyWeightValues = ["81.7", "80.9"]
    static let customMetricName = "示例臂围"
    static let customMetricValue = "35.4"
    static var summaries: [String] { [summaryOne, summaryTwo] }

    // MARK: Time

    /// 2026-09-01T02:00:00.123Z and 2026-09-08T11:30:00.456Z: sub-millisecond-exact on purpose.
    static let completed1 = Date(timeIntervalSince1970: 1_788_228_000.123)
    static let completed2 = Date(timeIntervalSince1970: 1_788_867_000.456)
    static let now = Date(timeIntervalSince1970: 1_791_532_800.789)
    static let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    // MARK: Store

    final class Store: @unchecked Sendable {
        let directory: TemporaryProtectedDirectory
        let controller: PersistenceController
        var writer: PersistenceWriter { controller.writer }

        init(inMemory: Bool = true) throws {
            let directory = try TemporaryProtectedDirectory()
            self.directory = directory
            self.controller = try PersistenceController(
                storeURL: directory.url.appendingPathComponent("store", isDirectory: true)
                    .appendingPathComponent("fc.sqlite"),
                inMemory: inMemory
            )
        }
    }

    // MARK: Seeding

    /// One student with every sensitive datum, two completed sessions (built-in, custom and
    /// three one-off exercises; a section; confirmed, draft and pending sets), an in-progress
    /// session, an abandoned session, body data, a package with an adjustment, an appointment
    /// and a template. `archived` archives the student afterwards (D-006).
    static func seed(_ store: Store, archived: Bool = false) async throws {
        let writer = store.writer
        let clock = TestClock(utcDate: now)
        let repository = CoreDataStudentRepository(writer: writer)
        let students = StudentUseCases(
            repository: repository, clock: clock, ids: TestIDGenerator(ids: [studentID.rawValue]))
        _ = try await students.create(
            draft: StudentDraft(
                displayName: studentName,
                sex: .female,
                trainingGoal: excludedGoal,
                injuryNotes: excludedInjury,
                privateCoachNote: excludedCoachNote,
                phone: excludedPhone,
                wechatID: excludedWeChat
            )
        )

        let library = ExerciseLibraryUseCases(
            repository: CoreDataExerciseRepository(writer: writer),
            clock: clock,
            ids: TestIDGenerator(ids: [customExerciseID])
        )
        try await library.seedIfNeeded()
        _ = try await library.createCustom(name: customExerciseName, recordMode: .weightReps)
        try await library.setAssisted(id: try StableExerciseID(customExerciseID.uuidString), isAssisted: true)

        let sections = CoreDataSessionSectionRepository(writer: writer)
        _ = try await sections.upsert(
            SessionSection(
                id: sectionID, ownerKind: .session, ownerID: session1ID,
                name: try NormalizedName("热身与主项"), orderIndex: 0)
        )

        let sessions = CoreDataSessionRepository(writer: writer)
        _ = try await sessions.save(try session1())
        _ = try await sessions.save(try session2())
        _ = try await sessions.save(try abandonedSession())
        _ = try await sessions.save(try inProgressSession())

        try await seedBodyData(writer: writer, clock: clock)
        try await seedCoachOnlyRecords(writer: writer)
        if archived {
            _ = try await students.archive(id: studentID)
        }
    }

    // MARK: Sessions

    private static func dec(_ raw: String) -> DecimalValue { try! DecimalValue(raw) }

    private static func set(
        _ index: UInt32, owner: StableUUID, state: SetRecordingState = .completed,
        weight: String, reps: String, at: Date
    ) -> TrainingSet {
        TrainingSet(
            id: StableUUID(UUID()), sessionExerciseID: owner, orderIndex: index, state: state,
            recordMode: .weightReps, weightValue: dec(weight), repetitionCount: dec(reps),
            durationSeconds: nil, unit: .kilograms, side: .none, leftValue: nil, rightValue: nil,
            createdAtUTC: at, updatedAtUTC: at, completedAtUTC: state == .completed ? at : nil
        )
    }

    private static func exercise(
        _ session: StableUUID, order: UInt32, kind: ExerciseSourceKind, sourceID: String?, name: String,
        section: StableUUID? = nil, note: String? = nil, sets: (StableUUID) -> [TrainingSet]
    ) throws -> SessionExercise {
        let id = StableUUID(UUID())
        return SessionExercise(
            id: id, sessionID: session, orderIndex: order, sourceKind: kind,
            sourceID: try sourceID.map { try StableExerciseID($0) },
            displayNameSnapshot: try NormalizedName(name), recordModeSnapshot: .weightReps,
            actionPrivateNote: try note.map { try ValidatedText($0) }, sectionID: section, sets: sets(id))
    }

    private static func session(
        _ id: StableUUID, state: SessionState, completedAt: Date?, summary: String?, focus: Set<BodyPart>,
        exercises: [SessionExercise], elapsed: String = "3720"
    ) throws -> Session {
        let started = (completedAt ?? now).addingTimeInterval(-3_720)
        return Session(
            id: id, studentID: studentID, state: state, startedAtUTC: started, lastCheckpointUTC: started,
            elapsedSeconds: dec(elapsed), interruptionStartedAtUTC: nil, durationNeedsReview: false,
            coachAdjustedDurationSeconds: nil, trainingFocus: focus,
            studentFacingSummary: try summary.map { try ValidatedText($0) },
            privateCoachNote: try ValidatedText(excludedSessionNote), revision: 1, createdAtUTC: started,
            updatedAtUTC: completedAt ?? now, completedAtUTC: completedAt, exercises: exercises)
    }

    static func session1() throws -> Session {
        let id = session1ID
        return try session(
            id, state: .completed, completedAt: completed1, summary: summaryOne, focus: [.chest, .arms],
            exercises: [
                try exercise(
                    id, order: 1, kind: .builtIn, sourceID: builtInID, name: builtInName, section: sectionID,
                    note: excludedActionNote
                ) { owner in
                    [
                        set(0, owner: owner, weight: "60", reps: "8", at: completed1),
                        set(1, owner: owner, weight: "62.5", reps: "6", at: completed1),
                        set(2, owner: owner, state: .draft, weight: "99", reps: "1", at: completed1),
                        set(3, owner: owner, state: .pending, weight: "98", reps: "2", at: completed1),
                    ]
                },
                try exercise(
                    id, order: 2, kind: .custom, sourceID: customExerciseID.uuidString,
                    name: customExerciseName, section: sectionID
                ) { owner in
                    [set(0, owner: owner, weight: "20", reps: "10", at: completed1)]
                },
                try exercise(id, order: 3, kind: .sessionOnly, sourceID: nil, name: oneOffNames[0]) { owner in
                    [set(0, owner: owner, weight: "10", reps: "12", at: completed1)]
                },
                // Only unconfirmed sets: carries no data and is dropped.
                try exercise(id, order: 4, kind: .sessionOnly, sourceID: nil, name: "示例仅草稿动作") { owner in
                    [set(0, owner: owner, state: .draft, weight: "5", reps: "5", at: completed1)]
                },
            ])
    }

    static func session2() throws -> Session {
        let id = session2ID
        return try session(
            id, state: .completed, completedAt: completed2, summary: summaryTwo, focus: [.chest],
            exercises: [
                try exercise(id, order: 0, kind: .builtIn, sourceID: builtInID, name: builtInName) { owner in
                    [set(0, owner: owner, weight: "65", reps: "5", at: completed2)]
                },
                try exercise(id, order: 1, kind: .builtIn, sourceID: secondBuiltInID, name: secondBuiltInName) {
                    owner in
                    [set(0, owner: owner, weight: "22", reps: "10", at: completed2)]
                },
                try exercise(id, order: 2, kind: .sessionOnly, sourceID: nil, name: oneOffNames[1]) { owner in
                    [set(0, owner: owner, weight: "12", reps: "10", at: completed2)]
                },
                try exercise(id, order: 3, kind: .sessionOnly, sourceID: nil, name: oneOffNames[2]) { owner in
                    [set(0, owner: owner, weight: "14", reps: "8", at: completed2)]
                },
            ])
    }

    private static func abandonedSession() throws -> Session {
        try session(
            abandonedSessionID, state: .abandonedEmpty, completedAt: nil, summary: nil, focus: [], exercises: [])
    }

    private static func inProgressSession() throws -> Session {
        let id = inProgressSessionID
        return try session(
            id, state: .inProgress, completedAt: nil, summary: inProgressSummary, focus: [.core],
            exercises: [
                try exercise(id, order: 0, kind: .sessionOnly, sourceID: nil, name: "示例进行中动作") { owner in
                    [set(0, owner: owner, weight: "7", reps: "7", at: now)]
                }
            ])
    }

    // MARK: Body data and Coach-only records

    private static func seedBodyData(writer: PersistenceWriter, clock: TestClock) async throws {
        let body = CoreDataBodyDataRepository(writer: writer)
        let days = [try! LocalDate(year: 2026, month: 8, day: 20), try! LocalDate(year: 2026, month: 9, day: 5)]
        for (index, value) in bodyWeightValues.enumerated() {
            _ = try await body.recordMeasurement(
                studentID: studentID, metricID: BuiltInBodyMetric.weight.id, localCalendarDay: days[index],
                value: dec(value), enteredUnit: "kg", newID: StableUUID(UUID()), now: now)
        }
        _ = try await body.createCustomMetric(
            try BodyMetricDefinition.makeCustom(
                id: customMetricID, studentID: studentID, name: customMetricName, unit: "cm", now: now))
        _ = try await body.recordMeasurement(
            studentID: studentID, metricID: customMetricID, localCalendarDay: days[1],
            value: dec(customMetricValue), enteredUnit: "cm", newID: StableUUID(UUID()), now: now)
    }

    private static func seedCoachOnlyRecords(writer: PersistenceWriter) async throws {
        let packageID = StableUUID(UUID())
        let packages = CoreDataCoursePackageRepository(writer: writer)
        _ = try await packages.activatePackage(
            try CoursePackage(
                id: packageID, studentID: studentID, name: try ValidatedText(excludedPackageName), totalCredits: 10,
                startDate: try LocalDate(year: 2026, month: 8, day: 1), createdAtUTC: now, updatedAtUTC: now),
            now: now)
        let capturedNow = now
        _ = try await packages.recordIdempotentAdjustment(
            packageID: packageID, sourceEventKey: "export-fixture-1", now: now
        ) { _ in
            try CreditAdjustment(
                id: StableUUID(UUID()), packageID: packageID, direction: .debit, amount: 1,
                reasonKind: .manualCorrection, reasonText: try ValidatedText(excludedAdjustmentReason),
                linkedSessionID: session1ID, sourceEventKey: "export-fixture-1", createdAtUTC: capturedNow)
        }
        _ = try await CoreDataAppointmentRepository(writer: writer).create(
            try Appointment(
                id: StableUUID(UUID()), studentID: studentID, seriesID: nil,
                date: try LocalDate(year: 2026, month: 9, day: 20), startTime: try LocalTime(hour: 9, minute: 0),
                status: .cancelled, cancellationReason: try ValidatedText(excludedCancellationReason),
                reminderEnabled: false, reminderLeadMinutes: nil, createdAtUTC: now, updatedAtUTC: now))
        _ = try await CoreDataTemplateRepository(writer: writer).createTemplate(
            try TrainingTemplate(
                id: StableUUID(UUID()), name: excludedTemplateName, trainingFocus: [.arms],
                createdAtUTC: now, updatedAtUTC: now))
    }

    // MARK: Selections

    static func selection(
        for source: ArchiveExportSource,
        keeping kept: Set<ArchiveModuleItem>
    ) -> ArchiveModuleSelection {
        var selection = ArchiveModuleSelection(availability: source.availability)
        for item in selection.availability.allItems where !kept.contains(item) {
            selection.setSelected(false, item: item)
        }
        return selection
    }

    static func readSource(_ store: Store, calendar: TestCalendarProvider? = nil) async throws -> ArchiveExportSource {
        try await ArchiveExportSourceReader(
            writer: store.writer,
            calendarProvider: calendar ?? TestCalendarProvider(timeZone: shanghai)
        ).read(studentID: studentID)
    }
}

// MARK: - Doubles

final class StubArchiveIdentity: ArchiveExportIdentityProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var failure: Error?
    let identity: ArchiveIdentity

    init(identity: ArchiveIdentity = ArchiveExportFixtures.identity, failure: Error? = nil) {
        self.identity = identity
        self.failure = failure
    }

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func setFailure(_ error: Error?) {
        lock.lock()
        failure = error
        lock.unlock()
    }

    func ensureIdentity(forStudent studentID: StableUUID) async throws -> ArchiveIdentity {
        let pending: Error? = lock.withLock {
            count += 1
            return failure
        }
        if let pending { throw pending }
        return identity
    }
}

struct StubSourceReader: ArchiveExportSourceReading {
    let source: ArchiveExportSource

    func read(studentID: StableUUID) async throws -> ArchiveExportSource { source }
}

final class RecordingLogger: AppLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func info(_ event: AppLogEvent, operation: AppLogOperation) {
        lock.lock()
        recorded.append(event.rawValue)
        lock.unlock()
    }

    func failure(_ event: AppLogEvent, operation: AppLogOperation, category: AppLogErrorCategory) {
        lock.lock()
        recorded.append(event.rawValue)
        lock.unlock()
    }
}

/// A share presenter that returns scripted outcomes and records the file it was handed
/// (including what the file looked like at that moment).
final class ScriptedSharePresenter: SystemSharePresenting, @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [SystemShareOutcome]
    private(set) var presentedURLs: [URL] = []
    private(set) var presentedData: [Data?] = []

    init(_ outcomes: [SystemShareOutcome]) {
        self.outcomes = outcomes
    }

    func present(fileURLs: [URL]) async -> SystemShareOutcome {
        let data = fileURLs.first.flatMap { try? Data(contentsOf: $0) }
        return lock.withLock {
            presentedURLs.append(contentsOf: fileURLs)
            presentedData.append(data)
            return outcomes.isEmpty ? .failed : outcomes.removeFirst()
        }
    }
}
