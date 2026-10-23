import Foundation

/// Serializes Session writes through one `PersistGate`, but keeps the
/// in-memory pending copy and save status keyed by Session id so several
/// Students' Sessions can be in progress at once (M1A-FR-018 revision).
public final class ActiveSessionCoordinator: @unchecked Sendable {
    private let sessionRepository: CoreDataSessionRepository
    private let recoveryStore: ActiveSessionRecoveryStore
    private let storeGenerationUUID: UUID
    private let reconciler: RecoveryReconciler
    private let timing: SessionTimingCoordinator
    private let clock: any Clock
    private let lock = NSLock()
    private let persistGate = PersistGate()
    private var statuses: [StableUUID: PersistenceProjectionStatus] = [:]
    private var pending: [StableUUID: Session] = [:]

    /// Aggregate status for the single-Session call sites. With one known
    /// Session it is exactly that Session's status; with several it reports
    /// the most recent failure, otherwise saving, otherwise the newest save.
    public var saveStatus: PersistenceProjectionStatus {
        lock.lock()
        defer { lock.unlock() }
        if statuses.count == 1 {
            return statuses.values.first ?? .saved(revision: 0)
        }
        let failures = statuses.values.compactMap { status -> (UInt64, PersistenceProjectionStatus)? in
            if case .failed(let revision, _) = status {
                return (revision, status)
            }
            return nil
        }
        if let failure = failures.max(by: { $0.0 < $1.0 }) {
            return failure.1
        }
        if statuses.values.contains(.saving) {
            return .saving
        }
        let revision =
            statuses.values.compactMap { status -> UInt64? in
                if case .saved(let revision) = status {
                    return revision
                }
                return nil
            }.max() ?? 0
        return .saved(revision: revision)
    }

    public func saveStatus(sessionID: StableUUID) -> PersistenceProjectionStatus {
        lock.lock()
        defer { lock.unlock() }
        return statuses[sessionID] ?? .saved(revision: 0)
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

    // MARK: - Working copies

    public func workingCopy() async throws -> Session? {
        guard let sessionID = try await soleKnownSessionID() else {
            return nil
        }
        return try await workingCopy(sessionID: sessionID)
    }

    public func workingCopy(sessionID: StableUUID) async throws -> Session? {
        if let pending = copyPending(sessionID) {
            return pending
        }
        let snapshot = try? recoveryStore.load(sessionID: sessionID)
        let database = try? await sessionRepository.session(id: sessionID)
        if let snapshot, snapshot.storeGenerationUUID == storeGenerationUUID {
            if let database {
                return snapshot.revision >= database.revision ? snapshot.session : database
            }
            return snapshot.session
        }
        return database
    }

    public func workingCopy(studentID: StableUUID) async throws -> Session? {
        if let pending = copyPendingSessions().values.first(where: { $0.studentID == studentID }) {
            return pending
        }
        let snapshots = (try? recoveryStore.loadAll()) ?? []
        let snapshot =
            snapshots
            .filter {
                $0.storeGenerationUUID == storeGenerationUUID
                    && $0.session.studentID == studentID
                    && $0.session.state == .inProgress
            }
            .max { $0.revision < $1.revision }
        let database = try? await sessionRepository.loadActive(studentID: studentID)
        if let snapshot {
            if let database, database.revision > snapshot.revision {
                return database
            }
            return snapshot.session
        }
        return database
    }

    /// The Session id when exactly one Session is open. Used only by the
    /// compatibility overloads that predate per-Student Sessions.
    public func soleKnownSessionID() async throws -> StableUUID? {
        let known = await knownSessionIDs()
        guard known.count <= 1 else {
            throw DomainError.invalidState
        }
        return known.first
    }

    // MARK: - Persistence

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

    public func retry(sessionID explicitSessionID: StableUUID? = nil) async throws -> Session {
        try await persistGate.run {
            let sessionID = try await self.resolveSessionID(explicitSessionID)
            let snapshot = try self.recoveryStore.load(sessionID: sessionID)
            let pending = self.copyPending(sessionID)
            let session: Session
            if let pending, pending.revision >= (snapshot?.revision ?? 0) {
                session = pending
            } else if let snapshot {
                session = snapshot.session
            } else if let database = try await self.sessionRepository.loadActive(sessionID: sessionID) {
                self.setStatus(.saved(revision: database.revision), for: sessionID)
                self.setPending(nil, for: sessionID)
                return database
            } else {
                throw DomainError.notFound
            }
            return try await self.persistUnlocked(session)
        }
    }

    // MARK: - Launch reconciliation

    public func reconcileOnLaunch() async throws -> RecoveryLaunchDecision {
        try await persistGate.run {
            try await self.reconcileUnlocked()
        }
    }

    private func reconcileUnlocked() async throws -> RecoveryLaunchDecision {
        try await sessionRepository.migrateLegacyPointer()

        let snapshots: [ActiveSessionRecoverySnapshot]
        do {
            snapshots = try recoveryStore.migrateAndLoadAll()
        } catch DomainError.incompatibleInput {
            return .failClosed(.corruptSnapshot)
        }

        var databaseByID: [StableUUID: Session] = [:]
        for session in try await sessionRepository.loadAllActive() {
            databaseByID[session.id] = session
        }
        // A snapshot may outlive the in-progress database row (for example a
        // crash after a terminal write but before the snapshot removal), so
        // reconcile against the Session's current row, whatever its state.
        for snapshot in snapshots where databaseByID[snapshot.session.id] == nil {
            if let database = try? await sessionRepository.session(id: snapshot.session.id) {
                databaseByID[snapshot.session.id] = database
            }
        }

        let ids = Set(databaseByID.keys).union(snapshots.map(\.session.id))
        var perSession: [(id: StableUUID, decision: RecoveryLaunchDecision, session: Session?)] = []
        var firstFailure: RecoveryIsolationReason?

        for id in ids.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
            let snapshot = snapshots.first { $0.session.id == id }
            let database = databaseByID[id]
            let decision = reconciler.decide(
                snapshot: snapshot,
                databaseSession: database,
                currentGenerationUUID: storeGenerationUUID
            )

            switch decision {
            case .noActiveSession:
                clearState(for: id)
            case .failClosed(let reason):
                if reason == .generationMismatch {
                    try recoveryStore.isolate(sessionID: id)
                }
                if let database {
                    recordReconciledState(database, for: id)
                } else {
                    clearState(for: id)
                }
                if firstFailure == nil {
                    firstFailure = reason
                }
                perSession.append((id, decision, nil))
            case .ignoreOlderSnapshot(let session):
                let resumed = try applyLaunchTiming(to: session)
                if resumed.revision != session.revision {
                    _ = try await persistUnlocked(resumed)
                } else {
                    recordReconciledState(resumed, for: id)
                }
                perSession.append((id, .ignoreOlderSnapshot(resumed), resumed))
            case .consistent(let session):
                let resumed = try applyLaunchTiming(to: session)
                if resumed.revision != session.revision {
                    _ = try await persistUnlocked(resumed)
                } else {
                    recordReconciledState(resumed, for: id)
                }
                perSession.append((id, .consistent(resumed), resumed))
            case .replay(let snapshot):
                let resumed = try applyLaunchTiming(to: snapshot.session)
                _ = try await persistUnlocked(resumed)
                perSession.append((id, .replay(snapshot), resumed))
            }
        }

        if let firstFailure {
            return .failClosed(firstFailure)
        }
        let activeSessions = perSession.compactMap {
            item -> (decision: RecoveryLaunchDecision, session: Session)? in
            guard let session = item.session, session.state == .inProgress else { return nil }
            return (item.decision, session)
        }
        guard let first = activeSessions.first else {
            return .noActiveSession
        }
        if activeSessions.count == 1 {
            return first.decision
        }
        return .consistent(first.session)
    }

    /// A terminal Session has no live projection to remember; keeping its
    /// status under `knownSessionIDs()` would make the single-Session
    /// compatibility lookup see a second, already-finished Session.
    private func recordReconciledState(_ session: Session, for id: StableUUID) {
        guard session.state == .inProgress else {
            clearState(for: id)
            return
        }
        setPending(nil, for: id)
        setStatus(.saved(revision: session.revision), for: id)
    }

    // MARK: - Background checkpoint / completion readiness

    public func checkpointOnBackground() async throws -> [Session] {
        try await persistGate.run {
            let now = self.clock.nowUTC()
            var byID: [StableUUID: Session] = [:]
            for session in try await self.sessionRepository.loadAllActive() {
                byID[session.id] = session
            }
            for pending in self.copyPendingSessions().values where pending.state == .inProgress {
                if let existing = byID[pending.id], existing.revision > pending.revision {
                    continue
                }
                byID[pending.id] = pending
            }
            var saved: [Session] = []
            for session in byID.values.sorted(by: { $0.startedAtUTC < $1.startedAtUTC }) {
                guard session.state == .inProgress else { continue }
                var updated = try self.timing.checkpoint(session: session, nowUTC: now)
                updated = updated.updatingTiming(
                    elapsedSeconds: updated.elapsedSeconds,
                    lastCheckpointUTC: updated.lastCheckpointUTC,
                    interruptionStartedAtUTC: now,
                    durationNeedsReview: updated.durationNeedsReview,
                    now: now
                )
                saved.append(try await self.persistUnlocked(updated))
            }
            return saved
        }
    }

    public func ensureProjectionReadyForCompletion(sessionID explicitSessionID: StableUUID? = nil) async throws {
        let sessionID = try await resolveSessionID(explicitSessionID)
        let status = saveStatus(sessionID: sessionID)
        if case .failed = status {
            throw DomainError.invalidState
        }
        if case .saving = status {
            throw DomainError.invalidState
        }
        let database = try? await sessionRepository.session(id: sessionID)
        let snapshot = try? recoveryStore.load(sessionID: sessionID)
        if let snapshot, let database, snapshot.revision != database.revision {
            throw DomainError.invalidState
        }
        if let pending = copyPending(sessionID), let database, pending.revision != database.revision {
            throw DomainError.invalidState
        }
    }

    // MARK: - Private

    private func persistUnlocked(_ session: Session, releaseSessionScopeClaims: Bool = false) async throws -> Session {
        setStatus(.saving, for: session.id)
        let snapshot: ActiveSessionRecoverySnapshot
        do {
            snapshot = try ActiveSessionRecoverySnapshot(
                storeGenerationUUID: storeGenerationUUID,
                session: session
            )
            try recoveryStore.replace(snapshot)
        } catch {
            let failedRevision: UInt64
            if let pendingRevision = copyPending(session.id)?.revision {
                failedRevision = pendingRevision
            } else if let database = try? await sessionRepository.session(id: session.id) {
                failedRevision = database.revision
            } else {
                failedRevision = 0
            }
            setStatus(.failed(revision: failedRevision, retryable: true), for: session.id)
            throw error
        }

        do {
            let saved: Session
            if releaseSessionScopeClaims || session.state != .inProgress {
                saved = try await sessionRepository.saveAndReleaseSessionScopeClaims(session)
            } else {
                saved = try await sessionRepository.save(session)
            }
            if saved.state == .inProgress {
                setPending(nil, for: session.id)
                setStatus(.saved(revision: saved.revision), for: session.id)
            } else {
                // Terminal Sessions are no longer "known Session ids": their
                // pending/status/snapshot entries would otherwise leak and
                // make `soleKnownSessionID()` see a phantom second Session.
                clearState(for: saved.id)
                try? recoveryStore.remove(sessionID: saved.id)
            }
            return saved
        } catch {
            if let domainError = error as? DomainError, domainError == .conflict {
                // A concurrent start for the same Student won. This attempt
                // never became the Student's Session, so drop its snapshot and
                // in-memory copy instead of offering them as a retry target.
                setPending(nil, for: session.id)
                clearState(for: session.id)
                try? recoveryStore.remove(sessionID: session.id)
                throw error
            }
            setPending(session, for: session.id)
            setStatus(.failed(revision: session.revision, retryable: true), for: session.id)
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

    private func knownSessionIDs() async -> Set<StableUUID> {
        var ids = snapshotKnownSessionIDs()
        if let active = try? await sessionRepository.loadAllActive() {
            ids.formUnion(active.map(\.id))
        }
        return ids
    }

    /// Only Sessions that can still need a write count as "known": pending
    /// retries, failed saves, and (via `knownSessionIDs`) database-active
    /// Sessions. A saved status is only a projection for the page, not a
    /// Session that a compatibility overload should locate.
    private func snapshotKnownSessionIDs() -> Set<StableUUID> {
        lock.lock()
        defer { lock.unlock() }
        var ids = Set(pending.keys)
        for (id, status) in statuses {
            if case .failed = status {
                ids.insert(id)
            }
        }
        return ids
    }

    private func resolveSessionID(_ explicitSessionID: StableUUID?) async throws -> StableUUID {
        if let explicitSessionID {
            return explicitSessionID
        }
        if let sole = try await soleKnownSessionID() {
            return sole
        }
        throw DomainError.notFound
    }

    private func copyPending(_ sessionID: StableUUID) -> Session? {
        lock.lock()
        defer { lock.unlock() }
        return pending[sessionID]
    }

    private func copyPendingSessions() -> [StableUUID: Session] {
        lock.lock()
        defer { lock.unlock() }
        return pending
    }

    private func setPending(_ session: Session?, for sessionID: StableUUID) {
        lock.lock()
        if let session {
            pending[sessionID] = session
        } else {
            pending.removeValue(forKey: sessionID)
        }
        lock.unlock()
    }

    private func setStatus(_ newStatus: PersistenceProjectionStatus, for sessionID: StableUUID) {
        lock.lock()
        statuses[sessionID] = newStatus
        lock.unlock()
    }

    private func clearState(for sessionID: StableUUID) {
        lock.lock()
        pending.removeValue(forKey: sessionID)
        statuses.removeValue(forKey: sessionID)
        lock.unlock()
    }
}

private actor PersistGate {
    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        try await body()
    }
}
