import Foundation

public struct ActiveSessionUseCases: Sendable {
    private let sessionRepository: CoreDataSessionRepository
    private let studentRepository: CoreDataStudentRepository
    private let exerciseRepository: CoreDataExerciseRepository
    private let sectionRepository: CoreDataSessionSectionRepository
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
        sectionRepository: CoreDataSessionSectionRepository,
        recoveryStore: ActiveSessionRecoveryStore,
        storeGenerationUUID: UUID,
        clock: any Clock,
        ids: any IDGenerator
    ) {
        self.sessionRepository = sessionRepository
        self.studentRepository = studentRepository
        self.exerciseRepository = exerciseRepository
        self.sectionRepository = sectionRepository
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
        let decision = try await coordinator.reconcileOnLaunch()
        try await reapSessionScopeClaims(for: decision)
        return decision
    }

    public func retry() async throws -> Session {
        try await coordinator.retry()
    }

    public func checkpointOnBackground() async throws -> Session? {
        try await coordinator.checkpointOnBackground()
    }

    /// The Student's completed history indexed for the "上次" reference and
    /// first-set prefill (experience P0-D1). Read-only.
    public func lastPerformances(studentID: StableUUID) async throws -> LastExercisePerformanceLookup {
        LastExercisePerformanceLookup(sessions: try await sessionRepository.listCompleted(studentID: studentID))
    }

    public func startOrOpen(studentID: StableUUID, trainingFocus: Set<BodyPart> = []) async throws -> Session {
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
            trainingFocus: trainingFocus,
            now: clock.nowUTC()
        )
        return try await coordinator.persist(session)
    }

    public func loadActive() async throws -> Session? {
        try await sessionRepository.loadActive()
    }

    /// The CURRENT Session's own `SessionSection` rows (T032 UI: grouping
    /// display + the exclusion set `TemplateUseCases.saveAsTemplate` needs).
    public func sessionSections() async throws -> [SessionSection] {
        guard let current = try await coordinator.workingCopy() else {
            return []
        }
        return try await sectionRepository.sections(ownerKind: .session, ownerID: current.id)
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
            if !(await workingCopyContainsExercise(id: exerciseID)) {
                await releaseClaimBestEffort(ownerID: ownerID)
            }
            throw error
        }
    }

    public func searchCatalog(query: String) async throws -> [ExerciseLibraryEntry] {
        try await exerciseRepository.searchActive(query: query)
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

    /// The library flags the set entry needs (P0-D8): which exercises are
    /// unilateral, and which of those count a lower load as progress.
    public func exerciseEntryFlags() async throws -> ExerciseEntryFlags {
        let entries = try await exerciseRepository.searchActive(query: "", includeHidden: true)
        return ExerciseEntryFlags(
            unilateral: Set(entries.filter(\.isUnilateral).map(\.id)),
            assisted: Set(entries.filter { $0.preference?.isAssisted == true }.map(\.id))
        )
    }

    public func addCustomToLibraryAndSession(
        name: String,
        recordMode: RecordMode,
        isUnilateral: Bool = false
    ) async throws -> Session {
        let item = try await exerciseRepository.createCustom(
            name: name,
            recordMode: recordMode,
            id: try StableExerciseID(ids.makeID().uuidString),
            now: clock.nowUTC()
        )
        do {
            if isUnilateral {
                _ = try await exerciseRepository.setPreference(
                    exerciseID: item.id,
                    alias: nil,
                    isFavorite: nil,
                    isHidden: nil,
                    isUnilateral: true
                )
            }
            return try await mutate { session in
                try session.addingCatalogExercise(
                    id: StableUUID(ids.makeID()),
                    item: item,
                    now: clock.nowUTC()
                )
            }
        } catch {
            if !(await workingCopyContainsCatalogSource(id: item.id)) {
                await archiveCustomBestEffort(id: item.id)
            }
            throw error
        }
    }

    public func reorderExercises(orderedIDs: [StableUUID]) async throws -> Session {
        try await mutate { try $0.reorderingExercises(ids: orderedIDs, now: clock.nowUTC()) }
    }

    public func removeExercise(exerciseID: StableUUID, confirmedIfCompleted: Bool) async throws -> Session {
        let session = try await mutate {
            try $0.removingExercise(
                id: exerciseID,
                confirmedIfCompleted: confirmedIfCompleted,
                now: clock.nowUTC()
            )
        }
        try await reconcileSessionScopeClaims(for: session)
        return session
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

    public func restoreDeletedSet(_ set: TrainingSet, at originalIndex: Int) async throws -> Session {
        try await mutate {
            try $0.restoringSet(set, at: originalIndex, now: clock.nowUTC())
        }
    }

    public func discardUnresolved() async throws -> Session {
        try await mutate { try $0.discardingUnresolvedSets(now: clock.nowUTC()) }
    }

    // MARK: - Template application (M1B-FR-019, D-009) and Sections (M1B-FR-020/021)

    /// Deep-copies a template's Exercise/Section snapshot onto the CURRENT
    /// working-copy Session as new, independent `.pending` Exercises/Sets
    /// (M1B-FR-019). `templateExercises`/`templateSections` are the
    /// read-only snapshot `TemplateUseCases.loadApplicationSnapshot` already
    /// fetched; `existingSessionSections` is this Session's current Section
    /// rows (from `TemplateUseCases.sessionSections`). The returned
    /// `newSections` MUST be persisted by the caller via
    /// `TemplateUseCases.persistAppliedSections` -- this call only persists
    /// the Session side (through the same crash-recovery-safe
    /// `ActiveSessionCoordinator` every other Session mutation here uses).
    public func applyTemplate(
        templateExercises: [TemplateExercise],
        templateSections: [SessionSection],
        templateTrainingFocus: Set<BodyPart> = [],
        existingSessionSections: [SessionSection]
    ) async throws -> TemplateApplicationResult {
        guard let current = try await coordinator.workingCopy() else {
            throw DomainError.notFound
        }
        let now = clock.nowUTC()
        let result = try TrainingTemplate.applying(
            exercises: templateExercises,
            sections: templateSections,
            trainingFocus: templateTrainingFocus,
            to: current,
            existingSessionSections: existingSessionSections,
            newExerciseIDGenerator: { self.ids.makeID() },
            newSetIDGenerator: { self.ids.makeID() },
            newSectionIDGenerator: { self.ids.makeID() },
            now: now
        )
        let savedSession = try await coordinator.persist(result.session)
        return TemplateApplicationResult(session: savedSession, newSections: result.newSections)
    }

    /// Creates a new, empty Section at the end of the CURRENT Session's
    /// unified order axis (M1B-FR-020). Does not touch any Exercise.
    public func createSection(name: String) async throws -> SessionSection {
        guard let current = try await coordinator.workingCopy() else {
            throw DomainError.notFound
        }
        let existingSections = try await sectionRepository.sections(ownerKind: .session, ownerID: current.id)
        let nextOrder =
            (current.exercises.map(\.orderIndex) + existingSections.map(\.orderIndex)).max().map { $0 + 1 } ?? 0
        let section = SessionSection(
            id: StableUUID(ids.makeID()),
            ownerKind: .session,
            ownerID: current.id,
            name: try NormalizedName(name),
            orderIndex: nextOrder
        )
        return try await sectionRepository.upsert(section)
    }

    @discardableResult
    public func renameSection(sectionID: StableUUID, name: String) async throws -> SessionSection {
        guard let current = try await coordinator.workingCopy() else {
            throw DomainError.notFound
        }
        let existingSections = try await sectionRepository.sections(ownerKind: .session, ownerID: current.id)
        guard let section = existingSections.first(where: { $0.id == sectionID }) else {
            throw DomainError.notFound
        }
        return try await sectionRepository.upsert(section.renamed(try NormalizedName(name)))
    }

    /// Moves one Exercise into `targetSectionID` (`nil` = unsectioned)
    /// without changing its position in the unified order axis
    /// (M1B-FR-020/021).
    public func moveExerciseToSection(exerciseID: StableUUID, toSectionID targetSectionID: StableUUID?)
        async throws -> Session
    {
        try await mutate { session in
            try session.updatingExerciseSection(
                exerciseID: exerciseID,
                sectionID: targetSectionID,
                now: self.clock.nowUTC()
            )
        }
    }

    /// Deletes a Section from the CURRENT Session, requiring an explicit
    /// disposition for its member Exercises (M1B-FR-020/021) -- there is no
    /// overload that omits `disposition`.
    public func deleteSection(
        sectionID: StableUUID,
        disposition: SessionSectionDeletionDisposition
    ) async throws -> Session {
        guard let current = try await coordinator.workingCopy() else {
            throw DomainError.notFound
        }
        let existingSections = try await sectionRepository.sections(ownerKind: .session, ownerID: current.id)
        let memberIDs = Set(current.exercises.filter { $0.sectionID == sectionID }.map(\.id))
        let resolution = try SessionSectionOrdering.resolveSectionDeletion(
            sectionID: sectionID,
            exerciseIDsInSection: memberIDs,
            disposition: disposition,
            existingSections: existingSections
        )
        let now = clock.nowUTC()
        var updated = current
        if !resolution.exerciseIDsToDelete.isEmpty {
            for exerciseID in resolution.exerciseIDsToDelete {
                updated = try updated.removingExercise(id: exerciseID, confirmedIfCompleted: true, now: now)
            }
        } else {
            for exerciseID in memberIDs {
                updated = try updated.updatingExerciseSection(
                    exerciseID: exerciseID,
                    sectionID: resolution.relocatedSectionID,
                    now: now
                )
            }
        }
        let saved = try await coordinator.persist(updated)
        try await reconcileSessionScopeClaims(for: saved)
        try await sectionRepository.delete(id: sectionID)
        return saved
    }

    public func applyCoachAdjustedDuration(_ seconds: DecimalValue) async throws -> Session {
        try await mutate { try $0.applyingCoachAdjustedDuration(seconds, now: clock.nowUTC()) }
    }

    public func finish() async throws -> Session {
        try await coordinator.ensureProjectionReadyForCompletion()
        guard let current = try await coordinator.workingCopy() else {
            throw DomainError.notFound
        }
        let finished = try await coordinator.persistAndReleaseSessionScopeClaims(
            try current.finished(now: clock.nowUTC())
        )
        await reconcileSessionScopeClaimsBestEffort(for: finished)
        return finished
    }

    public func abandonEmpty() async throws -> Session {
        guard let current = try await coordinator.workingCopy() else {
            throw DomainError.notFound
        }
        let abandoned = try await coordinator.persistAndReleaseSessionScopeClaims(
            try current.abandoned(now: clock.nowUTC())
        )
        await reconcileSessionScopeClaimsBestEffort(for: abandoned)
        return abandoned
    }

    private func mutate(_ transform: (Session) throws -> Session) async throws -> Session {
        guard let current = try await coordinator.workingCopy() else {
            throw DomainError.notFound
        }
        return try await coordinator.persist(transform(current))
    }

    private func reapSessionScopeClaims(for decision: RecoveryLaunchDecision) async throws {
        let session: Session?
        switch decision {
        case .noActiveSession:
            session = nil
        case .failClosed:
            session = try await sessionRepository.loadActive()
        case .consistent(let recovered), .ignoreOlderSnapshot(let recovered):
            session = recovered
        case .replay(let snapshot):
            session = snapshot.session
        }
        try await reconcileSessionScopeClaims(for: session)
    }

    /// Drops claims for removed session-only exercises and restores any
    /// shadowed built-in names in the same persistence transaction.
    private func reconcileSessionScopeClaims(for session: Session?) async throws {
        let keepIDs: Set<String>
        if session?.state == .inProgress {
            keepIDs = Set(
                (session?.exercises ?? [])
                    .filter { $0.sourceKind == .sessionOnly }
                    .map { $0.id.rawValue.uuidString }
            )
        } else {
            keepIDs = []
        }
        try await exerciseRepository.reapSessionScopeClaims(keepingOwnerIDs: keepIDs)
    }

    private func reconcileSessionScopeClaimsBestEffort(for session: Session) async {
        do {
            try await reconcileSessionScopeClaims(for: session)
        } catch {
            // Terminal session durability is already committed. Launch
            // recovery retries this derived catalog reconciliation later.
        }
    }

    private func workingCopyContainsExercise(id: StableUUID) async -> Bool {
        (try? await coordinator.workingCopy())?.exercises.contains { $0.id == id } == true
    }

    private func workingCopyContainsCatalogSource(id: StableExerciseID) async -> Bool {
        (try? await coordinator.workingCopy())?.exercises.contains { $0.sourceID == id } == true
    }

    private func releaseClaimBestEffort(ownerID: StableExerciseID) async {
        do {
            try await exerciseRepository.releaseClaims(ownerID: ownerID)
        } catch {
            return
        }
    }

    private func archiveCustomBestEffort(id: StableExerciseID) async {
        do {
            _ = try await exerciseRepository.archiveCustom(id: id, now: clock.nowUTC())
        } catch {
            return
        }
    }

}

/// Library flags read by the set entry (P0-D8).
public struct ExerciseEntryFlags: Equatable, Sendable {
    public var unilateral: Set<StableExerciseID>
    public var assisted: Set<StableExerciseID>

    public static let empty = ExerciseEntryFlags(unilateral: [], assisted: [])

    public init(unilateral: Set<StableExerciseID>, assisted: Set<StableExerciseID>) {
        self.unilateral = unilateral
        self.assisted = assisted
    }
}
