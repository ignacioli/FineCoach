import Foundation

public struct ActiveSessionUseCases: Sendable {
    private let sessionRepository: CoreDataSessionRepository
    private let studentRepository: CoreDataStudentRepository
    private let exerciseRepository: CoreDataExerciseRepository
    private let sectionRepository: CoreDataSessionSectionRepository
    private let coordinator: ActiveSessionCoordinator
    private let clock: any Clock
    private let widgetSnapshots: any WidgetSnapshotPublishing
    private let ids: any IDGenerator
    public let sessionActivities: any SessionActivityControlling

    /// Aggregate status for the single-Session call sites.
    public var saveStatus: PersistenceProjectionStatus {
        coordinator.saveStatus
    }

    public func saveStatus(sessionID: StableUUID) -> PersistenceProjectionStatus {
        coordinator.saveStatus(sessionID: sessionID)
    }

    public init(
        sessionRepository: CoreDataSessionRepository,
        studentRepository: CoreDataStudentRepository,
        exerciseRepository: CoreDataExerciseRepository,
        sectionRepository: CoreDataSessionSectionRepository,
        recoveryStore: ActiveSessionRecoveryStore,
        storeGenerationUUID: UUID,
        clock: any Clock,
        ids: any IDGenerator,
        widgetSnapshots: any WidgetSnapshotPublishing = NoopWidgetSnapshotPublisher(),
        sessionActivities: any SessionActivityControlling = NoopSessionActivityController()
    ) {
        self.sessionRepository = sessionRepository
        self.studentRepository = studentRepository
        self.exerciseRepository = exerciseRepository
        self.sectionRepository = sectionRepository
        self.clock = clock
        self.ids = ids
        self.widgetSnapshots = widgetSnapshots
        self.sessionActivities = sessionActivities
        self.coordinator = ActiveSessionCoordinator(
            sessionRepository: sessionRepository,
            recoveryStore: recoveryStore,
            storeGenerationUUID: storeGenerationUUID,
            clock: clock
        )
    }

    public func reconcileOnLaunch() async throws -> RecoveryLaunchDecision {
        let decision = try await coordinator.reconcileOnLaunch()
        // Reap only session-scope claims that no CURRENT in-progress Session
        // still owns; finishing or launching one Student must not release
        // another Student's session-only names (M1A-FR-018 revision). If the
        // read fails, leave claims alone rather than deleting every Session's.
        if let active = try? await sessionRepository.loadAllActive() {
            try await reconcileSessionScopeClaims(for: active)
        }
        return decision
    }

    public func retry(sessionID: StableUUID? = nil) async throws -> Session {
        try await coordinator.retry(sessionID: sessionID)
    }

    public func checkpointOnBackground() async throws -> [Session] {
        try await coordinator.checkpointOnBackground()
    }

    public func completedHistory(studentID: StableUUID) async throws -> [CompletedSession] {
        try await sessionRepository.listCompleted(studentID: studentID)
    }

    /// The Student's completed history indexed for the "上次" reference and
    /// first-set prefill (experience P0-D1). Read-only.
    public func lastPerformances(studentID: StableUUID) async throws -> LastExercisePerformanceLookup {
        LastExercisePerformanceLookup(sessions: try await sessionRepository.listCompleted(studentID: studentID))
    }

    /// The current student's most recently completed catalog exercises for the
    /// add-exercise panel. Session-only exercises are excluded by the pure
    /// selector and never become catalog suggestions.
    public func recentCatalogExercises(studentID: StableUUID) async throws -> [ExerciseLibraryEntry] {
        let history = try await sessionRepository.listCompleted(studentID: studentID)
        let available = try await exerciseRepository.searchActive(query: "")
        return RecentExerciseSelection.entries(
            from: history,
            studentID: studentID,
            availableEntries: available
        )
    }

    public func startOrOpen(studentID: StableUUID, trainingFocus: Set<BodyPart> = []) async throws -> Session {
        if let active = try await coordinator.workingCopy(studentID: studentID) {
            await ensureSessionActivity(for: active)
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
        do {
            let saved = try await coordinator.persist(session)
            await ensureSessionActivity(for: saved)
            return saved
        } catch DomainError.conflict {
            // A concurrent start for the same Student won; return his Session
            // instead of creating a second one.
            if let existing = try await coordinator.workingCopy(studentID: studentID) {
                await ensureSessionActivity(for: existing)
                return existing
            }
            throw DomainError.conflict
        }
    }

    /// Opens an in-progress Session without creating or persisting one.
    public func openExisting(studentID: StableUUID) async throws -> Session? {
        guard let active = try await coordinator.workingCopy(studentID: studentID),
            active.state == .inProgress
        else { return nil }
        await ensureSessionActivity(for: active)
        return active
    }

    /// Compatibility for single-Session call sites. With several Sessions in
    /// progress this throws rather than returning a different Student's class.
    public func loadActive() async throws -> Session? {
        try await sessionRepository.loadActive()
    }

    public func loadActive(sessionID: StableUUID) async throws -> Session? {
        if let working = try await coordinator.workingCopy(sessionID: sessionID),
            working.state == .inProgress
        {
            return working
        }
        return try await sessionRepository.loadActive(sessionID: sessionID)
    }

    public func loadActive(studentID: StableUUID) async throws -> Session? {
        if let working = try await coordinator.workingCopy(studentID: studentID),
            working.state == .inProgress
        {
            return working
        }
        return try await sessionRepository.loadActive(studentID: studentID)
    }

    public func loadAllActive() async throws -> [Session] {
        let database = try await sessionRepository.loadAllActive()
        var byID = Dictionary(uniqueKeysWithValues: database.map { ($0.id, $0) })
        for session in database {
            if let working = try? await coordinator.workingCopy(sessionID: session.id),
                working.state == .inProgress, working.revision >= session.revision
            {
                byID[session.id] = working
            }
        }
        return byID.values.sorted { $0.startedAtUTC < $1.startedAtUTC }
    }

    /// The Session's own `SessionSection` rows (T032 UI: grouping display +
    /// the exclusion set `TemplateUseCases.saveAsTemplate` needs).
    public func sessionSections(sessionID: StableUUID? = nil) async throws -> [SessionSection] {
        let sessionID = try await resolveSessionID(sessionID)
        guard let current = try await coordinator.workingCopy(sessionID: sessionID) else {
            return []
        }
        return try await sectionRepository.sections(ownerKind: .session, ownerID: current.id)
    }

    public func addSessionOnlyExercise(
        sessionID: StableUUID? = nil,
        displayName: String,
        recordMode: RecordMode
    ) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
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
            return try await mutate(sessionID: sessionID) { session in
                try session.addingSessionOnlyExercise(
                    id: exerciseID,
                    displayName: displayName,
                    recordMode: recordMode,
                    now: clock.nowUTC()
                )
            }
        } catch {
            if !(await workingCopyContainsExercise(sessionID: sessionID, id: exerciseID)) {
                await releaseClaimBestEffort(ownerID: ownerID)
            }
            throw error
        }
    }

    public func searchCatalog(query: String) async throws -> [ExerciseLibraryEntry] {
        try await exerciseRepository.searchActive(query: query)
    }

    public func addCatalogExercise(sessionID: StableUUID? = nil, itemID: StableExerciseID) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
        let item = try await exerciseRepository.selectableCatalogItem(id: itemID)
        return try await mutate(sessionID: sessionID) { session in
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
        sessionID: StableUUID? = nil,
        name: String,
        recordMode: RecordMode,
        isUnilateral: Bool = false
    ) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
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
            return try await mutate(sessionID: sessionID) { session in
                try session.addingCatalogExercise(
                    id: StableUUID(ids.makeID()),
                    item: item,
                    now: clock.nowUTC()
                )
            }
        } catch {
            if !(await workingCopyContainsCatalogSource(sessionID: sessionID, id: item.id)) {
                await archiveCustomBestEffort(id: item.id)
            }
            throw error
        }
    }

    public func reorderExercises(sessionID: StableUUID? = nil, orderedIDs: [StableUUID]) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
        return try await mutate(sessionID: sessionID) {
            try $0.reorderingExercises(ids: orderedIDs, now: clock.nowUTC())
        }
    }

    public func removeExercise(
        sessionID: StableUUID? = nil,
        exerciseID: StableUUID,
        confirmedIfCompleted: Bool
    ) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
        let session = try await mutate(sessionID: sessionID) {
            try $0.removingExercise(
                id: exerciseID,
                confirmedIfCompleted: confirmedIfCompleted,
                now: clock.nowUTC()
            )
        }
        if let active = try? await sessionRepository.loadAllActive() {
            try await reconcileSessionScopeClaims(for: active)
        }
        return session
    }

    public func addSet(
        sessionID: StableUUID? = nil,
        exerciseID: StableUUID,
        input: TrainingSetInput
    ) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
        return try await mutate(sessionID: sessionID) {
            try $0.addingSet(
                exerciseID: exerciseID,
                setID: StableUUID(ids.makeID()),
                input: input,
                now: clock.nowUTC()
            )
        }
    }

    public func editSet(
        sessionID: StableUUID? = nil,
        setID: StableUUID,
        input: TrainingSetInput
    ) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
        return try await mutate(sessionID: sessionID) {
            try $0.editingSet(setID: setID, input: input, now: clock.nowUTC())
        }
    }

    public func confirmSet(sessionID: StableUUID? = nil, setID: StableUUID) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
        return try await mutate(sessionID: sessionID) {
            try $0.confirmingSet(setID: setID, now: clock.nowUTC())
        }
    }

    public func copySet(sessionID: StableUUID? = nil, sourceSetID: StableUUID) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
        return try await mutate(sessionID: sessionID) {
            try $0.copyingSet(
                sourceSetID: sourceSetID,
                newSetID: StableUUID(ids.makeID()),
                now: clock.nowUTC()
            )
        }
    }

    public func undoSet(sessionID: StableUUID? = nil, setID: StableUUID) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
        return try await mutate(sessionID: sessionID) {
            try $0.undoingSet(setID: setID, now: clock.nowUTC())
        }
    }

    public func deleteSet(sessionID: StableUUID? = nil, setID: StableUUID) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
        return try await mutate(sessionID: sessionID) {
            try $0.deletingSet(setID: setID, now: clock.nowUTC())
        }
    }

    public func restoreDeletedSet(
        sessionID: StableUUID? = nil,
        _ set: TrainingSet,
        at originalIndex: Int
    ) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
        return try await mutate(sessionID: sessionID) {
            try $0.restoringSet(set, at: originalIndex, now: clock.nowUTC())
        }
    }

    public func discardUnresolved(sessionID: StableUUID? = nil) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
        return try await mutate(sessionID: sessionID) {
            try $0.discardingUnresolvedSets(now: clock.nowUTC())
        }
    }

    // MARK: - Template application (M1B-FR-019, D-009) and Sections (M1B-FR-020/021)

    /// Deep-copies a template's Exercise/Section snapshot onto the addressed
    /// working-copy Session as new, independent `.pending` Exercises/Sets
    /// (M1B-FR-019). The returned `newSections` MUST be persisted by the
    /// caller via `TemplateUseCases.persistAppliedSections` -- this call only
    /// persists the Session side (through the same crash-recovery-safe
    /// `ActiveSessionCoordinator` every other Session mutation here uses).
    public func applyTemplate(
        sessionID: StableUUID? = nil,
        templateExercises: [TemplateExercise],
        templateSections: [SessionSection],
        templateTrainingFocus: Set<BodyPart> = [],
        existingSessionSections: [SessionSection]
    ) async throws -> TemplateApplicationResult {
        let sessionID = try await resolveSessionID(sessionID)
        guard let current = try await coordinator.workingCopy(sessionID: sessionID) else {
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

    /// Creates a new, empty Section at the end of the addressed Session's
    /// unified order axis (M1B-FR-020). Does not touch any Exercise.
    public func createSection(sessionID: StableUUID? = nil, name: String) async throws -> SessionSection {
        let sessionID = try await resolveSessionID(sessionID)
        guard let current = try await coordinator.workingCopy(sessionID: sessionID) else {
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
    public func renameSection(
        sessionID: StableUUID? = nil,
        sectionID: StableUUID,
        name: String
    ) async throws -> SessionSection {
        let sessionID = try await resolveSessionID(sessionID)
        guard let current = try await coordinator.workingCopy(sessionID: sessionID) else {
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
    public func moveExerciseToSection(
        sessionID: StableUUID? = nil,
        exerciseID: StableUUID,
        toSectionID targetSectionID: StableUUID?
    ) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
        return try await mutate(sessionID: sessionID) { session in
            try session.updatingExerciseSection(
                exerciseID: exerciseID,
                sectionID: targetSectionID,
                now: self.clock.nowUTC()
            )
        }
    }

    /// Deletes a Section from the addressed Session, requiring an explicit
    /// disposition for its member Exercises (M1B-FR-020/021) -- there is no
    /// overload that omits `disposition`.
    public func deleteSection(
        sessionID: StableUUID? = nil,
        sectionID: StableUUID,
        disposition: SessionSectionDeletionDisposition
    ) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
        guard let current = try await coordinator.workingCopy(sessionID: sessionID) else {
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
        if let active = try? await sessionRepository.loadAllActive() {
            try await reconcileSessionScopeClaims(for: active)
        }
        try await sectionRepository.delete(id: sectionID)
        return saved
    }

    public func applyCoachAdjustedDuration(
        sessionID: StableUUID? = nil,
        _ seconds: DecimalValue
    ) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
        return try await mutate(sessionID: sessionID) {
            try $0.applyingCoachAdjustedDuration(seconds, now: clock.nowUTC())
        }
    }

    public func finish(sessionID: StableUUID? = nil) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
        try await coordinator.ensureProjectionReadyForCompletion(sessionID: sessionID)
        guard let current = try await coordinator.workingCopy(sessionID: sessionID) else {
            throw DomainError.notFound
        }
        let finished = try await coordinator.persistAndReleaseSessionScopeClaims(
            try current.finished(now: clock.nowUTC())
        )
        if let active = try? await sessionRepository.loadAllActive() {
            await reconcileSessionScopeClaimsBestEffort(for: active)
        }
        await sessionActivities.end(sessionID: finished.id.rawValue.uuidString.lowercased())
        await widgetSnapshots.refresh()
        return finished
    }

    public func abandonEmpty(sessionID: StableUUID? = nil) async throws -> Session {
        let sessionID = try await resolveSessionID(sessionID)
        guard let current = try await coordinator.workingCopy(sessionID: sessionID) else {
            throw DomainError.notFound
        }
        let abandoned = try await coordinator.persistAndReleaseSessionScopeClaims(
            try current.abandoned(now: clock.nowUTC())
        )
        if let active = try? await sessionRepository.loadAllActive() {
            await reconcileSessionScopeClaimsBestEffort(for: active)
        }
        await sessionActivities.end(sessionID: abandoned.id.rawValue.uuidString.lowercased())
        await widgetSnapshots.refresh()
        return abandoned
    }

    private func ensureSessionActivity(for session: Session) async {
        guard session.state == .inProgress, case .saved = coordinator.saveStatus(sessionID: session.id) else { return }
        let exercise = session.exercises.last
        await sessionActivities.start(
            sessionID: session.id.rawValue.uuidString.lowercased(),
            content: SessionActivityAttributes.ContentState(
                exerciseName: exercise?.displayNameSnapshot.value ?? "",
                completedSetCount: exercise?.sets.filter { $0.state == .completed }.count ?? 0,
                restEndsAt: nil))
    }

    private func mutate(
        sessionID: StableUUID,
        _ transform: (Session) throws -> Session
    ) async throws -> Session {
        guard let current = try await coordinator.workingCopy(sessionID: sessionID) else {
            throw DomainError.notFound
        }
        return try await coordinator.persist(transform(current))
    }

    private func resolveSessionID(_ explicit: StableUUID?) async throws -> StableUUID {
        if let explicit {
            return explicit
        }
        if let sole = try await coordinator.soleKnownSessionID() {
            return sole
        }
        throw DomainError.notFound
    }

    /// Drops claims for removed session-only exercises and restores any
    /// shadowed built-in names in the same persistence transaction. Keeps the
    /// union of every in-progress Session's session-only ids.
    private func reconcileSessionScopeClaims(for sessions: [Session]) async throws {
        let keepIDs = Set(
            sessions
                .filter { $0.state == .inProgress }
                .flatMap { $0.exercises }
                .filter { $0.sourceKind == .sessionOnly }
                .map { $0.id.rawValue.uuidString }
        )
        try await exerciseRepository.reapSessionScopeClaims(keepingOwnerIDs: keepIDs)
    }

    private func reconcileSessionScopeClaimsBestEffort(for sessions: [Session]) async {
        do {
            try await reconcileSessionScopeClaims(for: sessions)
        } catch {
            // Terminal session durability is already committed. Launch
            // recovery retries this derived catalog reconciliation later.
        }
    }

    private func workingCopyContainsExercise(sessionID: StableUUID, id: StableUUID) async -> Bool {
        (try? await coordinator.workingCopy(sessionID: sessionID))?.exercises.contains { $0.id == id } == true
    }

    private func workingCopyContainsCatalogSource(sessionID: StableUUID, id: StableExerciseID) async -> Bool {
        (try? await coordinator.workingCopy(sessionID: sessionID))?.exercises.contains { $0.sourceID == id } == true
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
