import Foundation

public struct ActiveSessionUseCases: Sendable {
    private let sessionRepository: CoreDataSessionRepository
    private let studentRepository: CoreDataStudentRepository
    private let clock: any Clock
    private let ids: any IDGenerator

    public init(
        sessionRepository: CoreDataSessionRepository,
        studentRepository: CoreDataStudentRepository,
        clock: any Clock,
        ids: any IDGenerator
    ) {
        self.sessionRepository = sessionRepository
        self.studentRepository = studentRepository
        self.clock = clock
        self.ids = ids
    }

    public func startOrOpen(studentID: StableUUID) async throws -> Session {
        if let active = try await sessionRepository.loadActive() {
            return active
        }
        let student = try await studentRepository.student(id: studentID)
        guard student.canStartSession() else {
            throw DomainError.invalidState
        }
        let session = Session.start(
            id: StableUUID(ids.makeID()),
            studentID: student.id,
            now: clock.nowUTC()
        )
        return try await sessionRepository.save(session)
    }

    public func loadActive() async throws -> Session? {
        try await sessionRepository.loadActive()
    }

    public func addSessionOnlyExercise(displayName: String, recordMode: RecordMode) async throws -> Session {
        try await mutate { session in
            try session.addingSessionOnlyExercise(
                id: StableUUID(ids.makeID()),
                displayName: displayName,
                recordMode: recordMode,
                now: clock.nowUTC()
            )
        }
    }

    public func reorderExercises(orderedIDs: [StableUUID]) async throws -> Session {
        try await mutate { try $0.reorderingExercises(ids: orderedIDs, now: clock.nowUTC()) }
    }

    public func removeExercise(exerciseID: StableUUID, confirmedIfCompleted: Bool) async throws -> Session {
        try await mutate {
            try $0.removingExercise(
                id: exerciseID,
                confirmedIfCompleted: confirmedIfCompleted,
                now: clock.nowUTC()
            )
        }
    }

    public func addSet(exerciseID: StableUUID, input: TrainingSetInput) async throws -> Session {
        try await mutate {
            try $0.addingSet(
                exerciseID: exerciseID,
                setID: StableUUID(ids.makeID()),
                input: input,
                now: clock.nowUTC()
            )
        }
    }

    public func editSet(setID: StableUUID, input: TrainingSetInput) async throws -> Session {
        try await mutate { try $0.editingSet(setID: setID, input: input, now: clock.nowUTC()) }
    }

    public func confirmSet(setID: StableUUID) async throws -> Session {
        try await mutate { try $0.confirmingSet(setID: setID, now: clock.nowUTC()) }
    }

    public func copySet(sourceSetID: StableUUID) async throws -> Session {
        try await mutate {
            try $0.copyingSet(
                sourceSetID: sourceSetID,
                newSetID: StableUUID(ids.makeID()),
                now: clock.nowUTC()
            )
        }
    }

    public func undoSet(setID: StableUUID) async throws -> Session {
        try await mutate { try $0.undoingSet(setID: setID, now: clock.nowUTC()) }
    }

    public func deleteSet(setID: StableUUID) async throws -> Session {
        try await mutate { try $0.deletingSet(setID: setID, now: clock.nowUTC()) }
    }

    public func discardUnresolved() async throws -> Session {
        try await mutate { try $0.discardingUnresolvedSets(now: clock.nowUTC()) }
    }

    public func finish() async throws -> Session {
        try await mutate { try $0.finished(now: clock.nowUTC()) }
    }

    public func abandonEmpty() async throws -> Session {
        try await mutate { try $0.abandoned(now: clock.nowUTC()) }
    }

    private func mutate(_ transform: (Session) throws -> Session) async throws -> Session {
        guard let current = try await sessionRepository.loadActive() else {
            throw DomainError.notFound
        }
        return try await sessionRepository.save(transform(current))
    }
}
