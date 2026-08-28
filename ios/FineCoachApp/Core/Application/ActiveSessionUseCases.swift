import Foundation

public struct ActiveSessionUseCases: Sendable {
    private let sessionRepository: CoreDataSessionRepository
    private let studentRepository: CoreDataStudentRepository
    private let exerciseRepository: CoreDataExerciseRepository
    private let coordinator: ActiveSessionCoordinator
    private let clock: any Clock
    private let ids: any IDGenerator

    public var saveStatus: PersistenceProjectionStatus {
        coordinator.saveStatus
    }

    public init(
        sessionRepository: CoreDataSessionRepository,
        studentRepository: CoreDataStudentRepository,
        exerciseRepository: CoreDataExerciseRepository,
        recoveryStore: ActiveSessionRecoveryStore,
        storeGenerationUUID: UUID,
        clock: any Clock,
        ids: any IDGenerator
    ) {
        self.sessionRepository = sessionRepository
        self.studentRepository = studentRepository
        self.exerciseRepository = exerciseRepository
        self.clock = clock
        self.ids = ids
        self.coordinator = ActiveSessionCoordinator(
            sessionRepository: sessionRepository,
            recoveryStore: recoveryStore,
            storeGenerationUUID: storeGenerationUUID,
            clock: clock
        )
    }

    public func reconcileOnLaunch() async throws -> RecoveryLaunchDecision {
        try await coordinator.reconcileOnLaunch()
    }

    public func retry() async throws -> Session {
        try await coordinator.retry()
    }

    public func checkpointOnBackground() async throws -> Session? {
        try await coordinator.checkpointOnBackground()
    }

    public func startOrOpen(studentID: StableUUID) async throws -> Session {
        if let active = try await coordinator.workingCopy() {
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
        return try await coordinator.persist(session)
    }

    public func loadActive() async throws -> Session? {
        try await sessionRepository.loadActive()
    }

    public func addSessionOnlyExercise(displayName: String, recordMode: RecordMode) async throws -> Session {
        let exerciseID = StableUUID(ids.makeID())
        let ownerID = try StableExerciseID(exerciseID.rawValue.uuidString)
        let claim = try ExerciseNameClaim(
            normalizedName: displayName,
            ownerKind: .sessionOnly,
            ownerID: ownerID,
            scope: .currentSession
        )
        try await exerciseRepository.acquireUnifiedClaim(claim)
        do {
            return try await mutate { session in
                try session.addingSessionOnlyExercise(
                    id: exerciseID,
                    displayName: displayName,
                    recordMode: recordMode,
                    now: clock.nowUTC()
                )
            }
        } catch {
            try? await exerciseRepository.releaseClaims(ownerID: ownerID)
            throw error
        }
    }

    public func addCatalogExercise(itemID: StableExerciseID) async throws -> Session {
        let item = try await exerciseRepository.catalogItem(id: itemID)
        return try await mutate { session in
            try session.addingCatalogExercise(
                id: StableUUID(ids.makeID()),
                item: item,
                now: clock.nowUTC()
            )
        }
    }

    public func addCustomToLibraryAndSession(name: String, recordMode: RecordMode) async throws -> Session {
        let item = try await exerciseRepository.createCustom(
            name: name,
            recordMode: recordMode,
            id: try StableExerciseID(ids.makeID().uuidString),
            now: clock.nowUTC()
        )
        return try await mutate { session in
            try session.addingCatalogExercise(
                id: StableUUID(ids.makeID()),
                item: item,
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

    public func applyCoachAdjustedDuration(_ seconds: DecimalValue) async throws -> Session {
        try await mutate { try $0.applyingCoachAdjustedDuration(seconds, now: clock.nowUTC()) }
    }

    public func finish() async throws -> Session {
        try await coordinator.ensureProjectionReadyForCompletion()
        let session = try await mutate { try $0.finished(now: clock.nowUTC()) }
        try await exerciseRepository.releaseSessionScopeClaims()
        return session
    }

    public func abandonEmpty() async throws -> Session {
        let session = try await mutate { try $0.abandoned(now: clock.nowUTC()) }
        try await exerciseRepository.releaseSessionScopeClaims()
        return session
    }

    private func mutate(_ transform: (Session) throws -> Session) async throws -> Session {
        guard let current = try await coordinator.workingCopy() else {
            throw DomainError.notFound
        }
        return try await coordinator.persist(transform(current))
    }
}
