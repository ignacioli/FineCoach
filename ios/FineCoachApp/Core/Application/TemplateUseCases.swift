import Foundation

/// Orchestrates `TrainingTemplate`/`TemplateExercise`/template-owned
/// `SessionSection` lifecycle (T030). Applying a template onto a live,
/// in-progress Session is deliberately NOT done here -- that mutation MUST
/// go through `ActiveSessionUseCases.applyTemplate`, which alone owns the
/// crash-recovery snapshot machinery (`ActiveSessionCoordinator`) that
/// `SessionExercise`/`TrainingSet` writes require. This type only ever
/// builds the read-only snapshot (`loadApplicationSnapshot`) that caller
/// hands to `ActiveSessionUseCases.applyTemplate`, and separately persists
/// the resulting NEW `SessionSection` rows once that call succeeds.
public struct TemplateUseCases: Sendable {
    private let templateRepository: CoreDataTemplateRepository
    private let sectionRepository: CoreDataSessionSectionRepository
    private let clock: any Clock
    private let ids: any IDGenerator

    public init(
        templateRepository: CoreDataTemplateRepository,
        sectionRepository: CoreDataSessionSectionRepository,
        clock: any Clock,
        ids: any IDGenerator
    ) {
        self.templateRepository = templateRepository
        self.sectionRepository = sectionRepository
        self.clock = clock
        self.ids = ids
    }

    // MARK: - Template lifecycle (M1B-FR-017)

    /// Creates a blank name-only template skeleton -- Exercises can be added
    /// later, or never (M1B-FR-017: "允许保存尚无动作的名称骨架").
    @discardableResult
    public func createBlankTemplate(name: String, trainingFocus: Set<BodyPart> = []) async throws -> TrainingTemplate {
        let now = clock.nowUTC()
        let template = try TrainingTemplate(
            id: StableUUID(ids.makeID()),
            name: name,
            trainingFocus: trainingFocus,
            createdAtUTC: now,
            updatedAtUTC: now
        )
        return try await templateRepository.createTemplate(template)
    }

    @discardableResult
    public func renameTemplate(id: StableUUID, name: String) async throws -> TrainingTemplate {
        let current = try await templateRepository.template(id: id)
        let renamed = try current.renamed(name, now: clock.nowUTC())
        return try await templateRepository.updateTemplate(renamed)
    }

    @discardableResult
    public func updateTrainingFocus(id: StableUUID, trainingFocus: Set<BodyPart>) async throws -> TrainingTemplate {
        let current = try await templateRepository.template(id: id)
        let updated = try current.updatingTrainingFocus(trainingFocus, now: clock.nowUTC())
        return try await templateRepository.updateTemplate(updated)
    }

    public func templates() async throws -> [TrainingTemplate] {
        try await templateRepository.templates()
    }

    public func template(id: StableUUID) async throws -> TrainingTemplate {
        try await templateRepository.template(id: id)
    }

    public func exercises(templateID: StableUUID) async throws -> [TemplateExercise] {
        try await templateRepository.exercises(templateID: templateID)
    }

    public func sections(templateID: StableUUID) async throws -> [SessionSection] {
        try await sectionRepository.sections(ownerKind: .template, ownerID: templateID)
    }

    /// Deletes the template, its `TemplateExercise` rows, and its OWN
    /// `SessionSection` rows -- and nothing else. Any Session that already
    /// applied this template is untouched by construction: neither
    /// repository call here ever fetches a `SessionMO`/`SessionExerciseMO`/
    /// `TrainingSetMO` row (M1B-FR-019, D-009).
    public func deleteTemplate(id: StableUUID) async throws {
        try await sectionRepository.deleteAll(ownerKind: .template, ownerID: id)
        try await templateRepository.deleteTemplate(id: id)
    }

    // MARK: - Save an existing Session as a NEW template (M1B-FR-018)

    /// Saves `session` (typically completed, but any state is accepted --
    /// the Coach may also snapshot an in-progress course) as a brand-new
    /// template. Reads ONLY the ordered Exercise list + planned Set shape;
    /// deliberately never touches `session.studentID`,
    /// `session.privateCoachNote`, `session.studentFacingSummary`, or any
    /// `exercise.actionPrivateNote` (M1B-FR-018) -- see
    /// `TrainingTemplate.snapshotFromSession`.
    @discardableResult
    public func saveAsTemplate(
        from session: Session,
        existingSessionSections: [SessionSection],
        name: String,
        trainingFocus: Set<BodyPart> = []
    ) async throws -> TrainingTemplate {
        let now = clock.nowUTC()
        let newTemplateID = StableUUID(ids.makeID())
        let (exercises, sections) = TrainingTemplate.snapshotFromSession(
            session,
            existingSessionSections: existingSessionSections,
            newTemplateID: newTemplateID,
            newExerciseIDGenerator: { self.ids.makeID() },
            newSectionIDGenerator: { self.ids.makeID() }
        )
        let template = try TrainingTemplate(
            id: newTemplateID,
            name: name,
            trainingFocus: trainingFocus,
            createdAtUTC: now,
            updatedAtUTC: now
        )
        let saved = try await templateRepository.createTemplate(template)
        try await templateRepository.replaceExercises(templateID: newTemplateID, with: exercises)
        try await sectionRepository.upsertAll(sections)
        return saved
    }

    // MARK: - Template Exercise management (M1B-FR-020/021 for templates)

    /// Appends a new planned Exercise at the end of the template's unified
    /// order axis (after every existing Exercise/Section).
    @discardableResult
    public func addExercise(
        templateID: StableUUID,
        displayName: String,
        recordMode: RecordMode,
        sectionID: StableUUID? = nil,
        plannedSets: [TemplatePlannedSet] = []
    ) async throws -> [TemplateExercise] {
        let existingExercises = try await templateRepository.exercises(templateID: templateID)
        let existingSections = try await sectionRepository.sections(ownerKind: .template, ownerID: templateID)
        let nextOrder =
            (existingExercises.map(\.orderIndex) + existingSections.map(\.orderIndex)).max().map { $0 + 1 } ?? 0
        let exercise = TemplateExercise(
            id: StableUUID(ids.makeID()),
            templateID: templateID,
            sectionID: sectionID,
            orderIndex: nextOrder,
            sourceKind: .sessionOnly,
            sourceID: nil,
            displayNameSnapshot: try NormalizedName(displayName),
            recordModeSnapshot: recordMode,
            plannedSets: plannedSets
        )
        let updated = existingExercises + [exercise]
        try await templateRepository.replaceExercises(templateID: templateID, with: updated)
        return updated
    }

    @discardableResult
    public func removeExercise(templateID: StableUUID, exerciseID: StableUUID) async throws -> [TemplateExercise] {
        let existing = try await templateRepository.exercises(templateID: templateID)
        let remaining = existing.filter { $0.id != exerciseID }
        try await templateRepository.replaceExercises(templateID: templateID, with: remaining)
        return remaining
    }

    @discardableResult
    public func replacePlannedSets(
        templateID: StableUUID,
        exerciseID: StableUUID,
        plannedSets: [TemplatePlannedSet]
    ) async throws -> [TemplateExercise] {
        let existing = try await templateRepository.exercises(templateID: templateID)
        let updated = existing.map { exercise in
            exercise.id == exerciseID ? exercise.replacingPlannedSets(plannedSets) : exercise
        }
        try await templateRepository.replaceExercises(templateID: templateID, with: updated)
        return updated
    }

    /// Renumbers the template's combined Section+Exercise display order in
    /// one step (create/reorder Sections and move Exercises between
    /// Sections/unsectioned all resolve to this single renumbering,
    /// T028/`SessionSectionOrdering`).
    public func reorderAxis(templateID: StableUUID, axis: [SessionSectionAxisItem]) async throws {
        let existingExercises = try await templateRepository.exercises(templateID: templateID)
        let existingSections = try await sectionRepository.sections(ownerKind: .template, ownerID: templateID)
        let (sectionOrder, exerciseOrder) = try SessionSectionOrdering.renumbering(axis)

        let exercisesByID = Dictionary(uniqueKeysWithValues: existingExercises.map { ($0.id, $0) })
        let sectionsByID = Dictionary(uniqueKeysWithValues: existingSections.map { ($0.id, $0) })

        let updatedExercises = try exerciseOrder.map { id, order -> TemplateExercise in
            guard let exercise = exercisesByID[id] else {
                throw DomainError.notFound
            }
            return exercise.relocating(orderIndex: order, sectionID: exercise.sectionID)
        }
        let updatedSections = try sectionOrder.map { id, order -> SessionSection in
            guard let section = sectionsByID[id] else {
                throw DomainError.notFound
            }
            return section.relocating(orderIndex: order)
        }
        try await templateRepository.replaceExercises(templateID: templateID, with: updatedExercises)
        try await sectionRepository.upsertAll(updatedSections)
    }

    /// Moves one Exercise into `targetSectionID` (`nil` = unsectioned)
    /// without changing its position in the unified order axis
    /// (M1B-FR-020/021).
    @discardableResult
    public func moveExercise(
        templateID: StableUUID,
        exerciseID: StableUUID,
        toSectionID targetSectionID: StableUUID?
    ) async throws -> [TemplateExercise] {
        let existing = try await templateRepository.exercises(templateID: templateID)
        guard existing.contains(where: { $0.id == exerciseID }) else {
            throw DomainError.notFound
        }
        let updated = existing.map { current in
            current.id == exerciseID
                ? current.relocating(orderIndex: current.orderIndex, sectionID: targetSectionID) : current
        }
        try await templateRepository.replaceExercises(templateID: templateID, with: updated)
        return updated
    }

    // MARK: - Template Section management

    @discardableResult
    public func createSection(templateID: StableUUID, name: String) async throws -> SessionSection {
        let existingExercises = try await templateRepository.exercises(templateID: templateID)
        let existingSections = try await sectionRepository.sections(ownerKind: .template, ownerID: templateID)
        let nextOrder =
            (existingExercises.map(\.orderIndex) + existingSections.map(\.orderIndex)).max().map { $0 + 1 } ?? 0
        let section = SessionSection(
            id: StableUUID(ids.makeID()),
            ownerKind: .template,
            ownerID: templateID,
            name: try NormalizedName(name),
            orderIndex: nextOrder
        )
        return try await sectionRepository.upsert(section)
    }

    @discardableResult
    public func renameSectionInTemplate(
        templateID: StableUUID,
        sectionID: StableUUID,
        name: String
    ) async throws -> SessionSection {
        let sections = try await sectionRepository.sections(ownerKind: .template, ownerID: templateID)
        guard let section = sections.first(where: { $0.id == sectionID }) else {
            throw DomainError.notFound
        }
        return try await sectionRepository.upsert(section.renamed(try NormalizedName(name)))
    }

    /// Deletes a template Section, requiring an explicit disposition for its
    /// member Exercises (M1B-FR-020/021) -- there is no overload that omits
    /// `disposition`.
    public func deleteSection(
        templateID: StableUUID,
        sectionID: StableUUID,
        disposition: SessionSectionDeletionDisposition
    ) async throws {
        let existingExercises = try await templateRepository.exercises(templateID: templateID)
        let existingSections = try await sectionRepository.sections(ownerKind: .template, ownerID: templateID)
        let memberIDs = Set(existingExercises.filter { $0.sectionID == sectionID }.map(\.id))

        let resolution = try SessionSectionOrdering.resolveSectionDeletion(
            sectionID: sectionID,
            exerciseIDsInSection: memberIDs,
            disposition: disposition,
            existingSections: existingSections
        )

        let survivingExercises =
            existingExercises
            .filter { !resolution.exerciseIDsToDelete.contains($0.id) }
            .map { exercise -> TemplateExercise in
                guard memberIDs.contains(exercise.id) else {
                    return exercise
                }
                return exercise.relocating(orderIndex: exercise.orderIndex, sectionID: resolution.relocatedSectionID)
            }

        try await templateRepository.replaceExercises(templateID: templateID, with: survivingExercises)
        try await sectionRepository.delete(id: sectionID)
    }

    // MARK: - Applying a template onto a Session (read-only snapshot half)

    /// Loads the template's current Exercise + Section snapshot for
    /// `ActiveSessionUseCases.applyTemplate` to deep-copy (M1B-FR-019). Pure
    /// read -- no write happens here.
    public func loadApplicationSnapshot(templateID: StableUUID) async throws -> (
        exercises: [TemplateExercise], sections: [SessionSection]
    ) {
        let exercises = try await templateRepository.exercises(templateID: templateID)
        let sections = try await sectionRepository.sections(ownerKind: .template, ownerID: templateID)
        return (exercises, sections)
    }

    /// Persists the brand-new `SessionSection` rows produced by
    /// `ActiveSessionUseCases.applyTemplate` -- called by the caller only
    /// AFTER that Session write has succeeded.
    public func persistAppliedSections(_ sections: [SessionSection]) async throws {
        try await sectionRepository.upsertAll(sections)
    }

    // MARK: - Session-owned Section read access (for callers assembling UI)

    public func sessionSections(sessionID: StableUUID) async throws -> [SessionSection] {
        try await sectionRepository.sections(ownerKind: .session, ownerID: sessionID)
    }
}
