import Foundation

public final class ActiveSessionCoordinator: @unchecked Sendable {
    private let sessionRepository: CoreDataSessionRepository
    private let recoveryStore: ActiveSessionRecoveryStore
    private let storeGenerationUUID: UUID
    private let reconciler: RecoveryReconciler
    private let timing: SessionTimingCoordinator
    private let clock: any Clock
    private let lock = NSLock()
    private let persistGate = PersistGate()
    private var status: PersistenceProjectionStatus = .saved(revision: 0)
    private var pending: Session?

    public var saveStatus: PersistenceProjectionStatus {
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    public init(
        sessionRepository: CoreDataSessionRepository,
        recoveryStore: ActiveSessionRecoveryStore,
        storeGenerationUUID: UUID,
        clock: any Clock,
        reconciler: RecoveryReconciler = RecoveryReconciler(),
        timing: SessionTimingCoordinator = SessionTimingCoordinator()
    ) {
        self.sessionRepository = sessionRepository
        self.recoveryStore = recoveryStore
        self.storeGenerationUUID = storeGenerationUUID
        self.clock = clock
        self.reconciler = reconciler
        self.timing = timing
    }

    public func workingCopy() async throws -> Session? {
        if let pending = copyPending() {
            return pending
        }
        let snapshot = try? recoveryStore.load()
        let database = try await sessionRepository.loadActive()
        if let snapshot, snapshot.storeGenerationUUID == storeGenerationUUID {
            if let database {
                return snapshot.revision >= database.revision ? snapshot.session : database
            }
            return snapshot.session
        }
        return database
    }

    public func persist(_ session: Session) async throws -> Session {
        try await persistGate.run {
            try await self.persistUnlocked(session)
        }
    }

    /// Persists a terminal Session and releases its temporary exercise-name
    /// claims in one Core Data writer transaction.
    public func persistAndReleaseSessionScopeClaims(_ session: Session) async throws -> Session {
        try await persistGate.run {
            try await self.persistUnlocked(session, releaseSessionScopeClaims: true)
        }
    }

    public func retry() async throws -> Session {
        try await persistGate.run {
            let snapshot = try self.recoveryStore.load()
            let pending = self.copyPending()
            let session: Session
            if let pending, pending.revision >= (snapshot?.revision ?? 0) {
                session = pending
            } else if let snapshot {
                session = snapshot.session
            } else if let database = try await self.sessionRepository.loadActive() {
                self.setStatus(.saved(revision: database.revision))
                self.setPending(nil)
                return database
            } else {
                throw DomainError.notFound
            }
            return try await self.persistUnlocked(session)
        }
    }

    public func reconcileOnLaunch() async throws -> RecoveryLaunchDecision {
        try await persistGate.run {
            let snapshot: ActiveSessionRecoverySnapshot?
            do {
                snapshot = try self.recoveryStore.load()
            } catch DomainError.incompatibleInput {
                return RecoveryLaunchDecision.failClosed(.corruptSnapshot)
            }

            let database = try await self.sessionRepository.loadActive()
            let decision = self.reconciler.decide(
                snapshot: snapshot,
                databaseSession: database,
                currentGenerationUUID: self.storeGenerationUUID
            )

            switch decision {
            case .noActiveSession:
                self.setPending(nil)
                self.setStatus(.saved(revision: 0))
                return decision
            case .failClosed(let reason):
                if reason == .generationMismatch {
                    try self.recoveryStore.isolateCurrent()
                }
                if let database {
                    self.setPending(nil)
                    self.setStatus(.saved(revision: database.revision))
                }
                return decision
            case .ignoreOlderSnapshot(let session):
                let resumed = try self.applyLaunchTiming(to: session)
                if resumed.revision != session.revision {
                    _ = try await self.persistUnlocked(resumed)
                } else {
                    self.setPending(nil)
                    self.setStatus(.saved(revision: session.revision))
                }
                return .ignoreOlderSnapshot(resumed)
            case .consistent(let session):
                let resumed = try self.applyLaunchTiming(to: session)
                if resumed.revision != session.revision {
                    _ = try await self.persistUnlocked(resumed)
                    return .consistent(resumed)
                }
                self.setPending(nil)
                self.setStatus(.saved(revision: session.revision))
                return .consistent(session)
            case .replay(let snapshot):
                let resumed = try self.applyLaunchTiming(to: snapshot.session)
                _ = try await self.persistUnlocked(resumed)
                return .replay(snapshot)
            }
        }
    }

    public func checkpointOnBackground() async throws -> Session? {
        try await persistGate.run {
            guard var session = try await self.workingCopy(), session.state == .inProgress else {
                return nil
            }
            let now = self.clock.nowUTC()
            session = try self.timing.checkpoint(session: session, nowUTC: now)
            session = session.updatingTiming(
                elapsedSeconds: session.elapsedSeconds,
                lastCheckpointUTC: session.lastCheckpointUTC,
                interruptionStartedAtUTC: now,
                durationNeedsReview: session.durationNeedsReview,
                now: now
            )
            return try await self.persistUnlocked(session)
        }
    }

    public func ensureProjectionReadyForCompletion() async throws {
        if case .failed = saveStatus {
            throw DomainError.invalidState
        }
        if case .saving = saveStatus {
            throw DomainError.invalidState
        }
        let database = try await sessionRepository.loadActive()
        let snapshot = try recoveryStore.load()
        if let snapshot, let database, snapshot.revision != database.revision {
            throw DomainError.invalidState
        }
        if let pending = copyPending(), let database, pending.revision != database.revision {
            throw DomainError.invalidState
        }
    }

    private func persistUnlocked(_ session: Session, releaseSessionScopeClaims: Bool = false) async throws -> Session {
        setStatus(.saving)
        let snapshot: ActiveSessionRecoverySnapshot
        do {
            snapshot = try ActiveSessionRecoverySnapshot(
                storeGenerationUUID: storeGenerationUUID,
                session: session
            )
            try recoveryStore.replace(snapshot)
        } catch {
            let failedRevision: UInt64
            if let pendingRevision = copyPending()?.revision {
                failedRevision = pendingRevision
            } else if let database = try? await sessionRepository.loadActive() {
                failedRevision = database.revision
            } else {
                failedRevision = 0
            }
            setStatus(.failed(revision: failedRevision, retryable: true))
            throw error
        }

        do {
            let saved: Session
            if releaseSessionScopeClaims || session.state != .inProgress {
                saved = try await sessionRepository.saveAndReleaseSessionScopeClaims(session)
            } else {
                saved = try await sessionRepository.save(session)
            }
            setPending(nil)
            setStatus(.saved(revision: saved.revision))
            if saved.state != .inProgress {
                try recoveryStore.remove()
            }
            return saved
        } catch {
            setPending(session)
            setStatus(.failed(revision: session.revision, retryable: true))
            throw error
        }
    }

    private func applyLaunchTiming(to session: Session) throws -> Session {
        guard session.state == .inProgress else {
            return session
        }
        let now = clock.nowUTC()
        if let interruption = session.interruptionStartedAtUTC {
            return try timing.resumeAfterInterruption(
                session: session,
                nowUTC: now,
                interruptionStartedAtUTC: interruption
            )
        }
        return try timing.checkpoint(session: session, nowUTC: now)
    }

    private func copyPending() -> Session? {
        lock.lock()
        defer { lock.unlock() }
        return pending
    }

    private func setPending(_ session: Session?) {
        lock.lock()
        pending = session
        lock.unlock()
    }

    private func setStatus(_ newStatus: PersistenceProjectionStatus) {
        lock.lock()
        status = newStatus
        lock.unlock()
    }
}

private actor PersistGate {
    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        try await body()
    }
}
