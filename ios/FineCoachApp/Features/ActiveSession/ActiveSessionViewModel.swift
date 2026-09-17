import Combine
import Foundation

enum ActiveSessionSheet: Identifiable, Equatable {
    case finish(SessionFinishGate)
    case deleteExercise(StableUUID)
    case durationReview

    var id: String {
        switch self {
        case .finish(let gate):
            return "finish-\(String(describing: gate))"
        case .deleteExercise(let id):
            return "delete-\(id.rawValue.uuidString)"
        case .durationReview:
            return "duration-review"
        }
    }
}

@MainActor
final class ActiveSessionViewModel: ObservableObject {
    @Published var session: Session?
    @Published var errorMessage: String?
    @Published var saveStatus: PersistenceProjectionStatus = .saved(revision: 0)
    @Published var exerciseName = ""
    @Published var exerciseNameConflict: String?
    @Published var catalogMatches: [ExerciseLibraryEntry] = []
    @Published var recordMode: RecordMode = .weightReps
    @Published var isAddingExercise = false
    @Published var weight = ""
    @Published var reps = ""
    @Published var duration = ""
    @Published var side: SetSide = .none
    @Published var left = ""
    @Published var right = ""
    @Published var distance = ""
    @Published var speed = ""
    @Published var resistance = ""
    @Published var selectedExerciseID: StableUUID?
    @Published var presentedSheet: ActiveSessionSheet?
    @Published private(set) var isMutationInFlight = false
    @Published var sections: [SessionSection] = []
    @Published var isSavingAsTemplate = false
    @Published var saveAsTemplateName = ""
    @Published var newSectionName = ""
    @Published var pendingSectionDeletion: SessionSection?
    /// The set currently expanded for inline row editing (M1-A fix:
    /// explicit id addressing -- at most one row may be expanded at a
    /// time; setting this to a different id auto-collapses the other).
    @Published var editingSetID: StableUUID?

    let studentID: StableUUID
    let useCases: ActiveSessionUseCases
    let templateUseCases: TemplateUseCases?
    private let signposts: PerformanceSignposts
    private var catalogSearchGeneration = 0
    private var catalogSearchTask: Task<Void, Never>?
    /// The set most recently created via the bottom "add set" form, so
    /// the form's own "confirm" button (`confirmActiveDraftSet()`) can
    /// target it explicitly instead of falling back to `exercise.sets.last`.
    private var activeDraftSetID: StableUUID?

    init(
        studentID: StableUUID,
        useCases: ActiveSessionUseCases,
        templateUseCases: TemplateUseCases? = nil,
        signposts: PerformanceSignposts = .shared
    ) {
        self.studentID = studentID
        self.useCases = useCases
        self.templateUseCases = templateUseCases
        self.signposts = signposts
    }

    var currentExercise: SessionExercise? {
        guard let session else {
            return nil
        }
        if let selectedExerciseID {
            return session.exercises.first { $0.id == selectedExerciseID }
        }
        return session.exercises.last
    }

    var statsText: String {
        let count = session?.completedSetCount ?? 0
        return "\(String(localized: "session.stats.completedLabel")) \(count)"
    }

    var canCompleteSession: Bool {
        if case .saved = saveStatus {
            return session?.state == .inProgress
        }
        return false
    }

    func load() async {
        do {
            _ = try await useCases.reconcileOnLaunch()
            session = try await useCases.startOrOpen(studentID: studentID)
            selectedExerciseID = session?.exercises.last?.id
            errorMessage = nil
            saveStatus = useCases.saveStatus
            await loadSections()
        } catch {
            present(error)
        }
    }

    // MARK: - Template save/section management (M1B-FR-018/019/020/021)

    func loadSections() async {
        sections = (try? await useCases.sessionSections()) ?? []
    }

    func saveAsTemplate() async {
        guard let session, let templateUseCases else {
            return
        }
        let name = saveAsTemplateName
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        do {
            _ = try await templateUseCases.saveAsTemplate(
                from: session,
                existingSessionSections: sections,
                name: name
            )
            saveAsTemplateName = ""
            isSavingAsTemplate = false
            errorMessage = nil
        } catch {
            present(error)
        }
    }

    func createSection() async {
        let name = newSectionName
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        do {
            _ = try await useCases.createSection(name: name)
            newSectionName = ""
            await loadSections()
        } catch {
            present(error)
        }
    }

    func moveExercise(_ exerciseID: StableUUID, toSectionID sectionID: StableUUID?) async {
        await run {
            self.session = try await self.useCases.moveExerciseToSection(
                exerciseID: exerciseID,
                toSectionID: sectionID
            )
        }
    }

    /// Non-empty Sections MUST require an explicit disposition
    /// (M1B-FR-020/021) -- routes through `pendingSectionDeletion` so there
    /// is no direct action that skips the choice.
    func requestDeleteSection(_ section: SessionSection) {
        let hasMembers = session?.exercises.contains { $0.sectionID == section.id } ?? false
        guard hasMembers else {
            Task { await deleteSection(section, disposition: .deleteWithExercises) }
            return
        }
        pendingSectionDeletion = section
    }

    func deleteSection(_ section: SessionSection, disposition: SessionSectionDeletionDisposition) async {
        await run {
            self.session = try await self.useCases.deleteSection(sectionID: section.id, disposition: disposition)
        }
        pendingSectionDeletion = nil
        await loadSections()
    }

    func unsectionedExercises(in session: Session) -> [SessionExercise] {
        session.exercises.filter { $0.sectionID == nil }
    }

    func exercises(in section: SessionSection, of session: Session) -> [SessionExercise] {
        session.exercises.filter { $0.sectionID == section.id }
    }

    var orderedSections: [SessionSection] {
        sections.sorted { $0.orderIndex < $1.orderIndex }
    }

    func retrySave() async {
        await run {
            self.session = try await self.useCases.retry()
        }
    }

    func saveExercise() async {
        exerciseNameConflict = nil
        let name = exerciseName
        let mode = recordMode
        await run {
            let updated = try await self.useCases.addSessionOnlyExercise(
                displayName: name,
                recordMode: mode
            )
            self.applySavedExercise(updated, mode: mode)
        }
    }

    func saveExerciseToLibrary() async {
        exerciseNameConflict = nil
        let name = exerciseName
        let mode = recordMode
        await run {
            let updated = try await self.useCases.addCustomToLibraryAndSession(
                name: name,
                recordMode: mode
            )
            self.applySavedExercise(updated, mode: mode)
        }
    }

    func scheduleCatalogSearch() {
        catalogSearchTask?.cancel()
        catalogSearchTask = Task { await refreshCatalogMatches() }
    }

    func addCatalogMatch(_ id: StableExerciseID) async {
        await run {
            let updated = try await self.useCases.addCatalogExercise(itemID: id)
            let mode = updated.exercises.last?.recordModeSnapshot ?? .weightReps
            self.applySavedExercise(updated, mode: mode)
        }
    }

    func selectExercise(_ id: StableUUID) {
        selectedExerciseID = id
        if let mode = session?.exercises.first(where: { $0.id == id })?.recordModeSnapshot {
            recordMode = mode
            resetSetFields(for: mode)
        }
    }

    func moveExercise(offset: Int) async {
        guard let session, let current = currentExercise else {
            return
        }
        var ids = session.exercises.map(\.id)
        guard let index = ids.firstIndex(of: current.id) else {
            return
        }
        let destination = index + offset
        guard ids.indices.contains(destination) else {
            return
        }
        ids.swapAt(index, destination)
        await run {
            self.session = try await self.signposts.measureExerciseReorder {
                try await self.useCases.reorderExercises(orderedIDs: ids)
            }
        }
    }

    func requestDeleteExercise() {
        guard let exercise = currentExercise else {
            return
        }
        if exercise.hasCompletedSet {
            presentedSheet = .deleteExercise(exercise.id)
            return
        }
        Task {
            await run {
                self.session = try await self.useCases.removeExercise(
                    exerciseID: exercise.id,
                    confirmedIfCompleted: false
                )
                self.selectedExerciseID = self.session?.exercises.last?.id
            }
        }
    }

    func confirmDeleteExercise() async {
        guard case .deleteExercise(let exerciseID) = presentedSheet else {
            return
        }
        presentedSheet = nil
        await run {
            self.session = try await self.useCases.removeExercise(
                exerciseID: exerciseID,
                confirmedIfCompleted: true
            )
            self.selectedExerciseID = self.session?.exercises.last?.id
        }
    }

    func addDraftSet() async {
        guard let exercise = currentExercise else {
            return
        }
        await run {
            let updated = try await self.useCases.addSet(
                exerciseID: exercise.id,
                input: self.currentInput(for: exercise)
            )
            self.session = updated
            // Newly appended by `addingSet`, so `.sets.last` here captures
            // the id of the set this call just created -- not a positional
            // guess about which set to mutate later.
            self.activeDraftSetID = updated.exercises.first(where: { $0.id == exercise.id })?.sets.last?.id
        }
    }

    /// Confirms the set most recently created by the bottom "add set" form
    /// (`activeDraftSetID`), or -- if the coach typed values and tapped
    /// confirm without an explicit "add" first -- creates and confirms a new
    /// set from the current form fields. Preserves the existing single
    /// "确认" button UX; does not address by `exercise.sets.last`.
    func confirmActiveDraftSet() async {
        if let setID = activeDraftSetID {
            await confirmSet(setID: setID)
            return
        }
        guard let exercise = currentExercise else {
            return
        }
        await run {
            let input = self.currentInput(for: exercise)
            let added = try await self.useCases.addSet(exerciseID: exercise.id, input: input)
            guard let newSetID = added.exercises.first(where: { $0.id == exercise.id })?.sets.last?.id else {
                throw DomainError.notFound
            }
            self.session = try await self.signposts.measureSetConfirm {
                try await self.useCases.confirmSet(setID: newSetID)
            }
        }
    }

    /// Confirms an explicitly identified set (M1-A fix). MUST NOT fall back
    /// to `exercise.sets.last` -- confirming one draft/pending set out of
    /// order MUST NOT affect any other set's state.
    func confirmSet(setID: StableUUID) async {
        await run {
            self.session = try await self.signposts.measureSetConfirm {
                try await self.useCases.confirmSet(setID: setID)
            }
        }
        if errorMessage == nil, activeDraftSetID == setID {
            activeDraftSetID = nil
        }
    }

    /// Begins inline editing of an explicitly identified set's row. Only one
    /// row may be expanded at a time -- setting `editingSetID` to a new
    /// value automatically collapses whichever row was previously open.
    func beginEditingSet(_ set: TrainingSet) {
        editingSetID = set.id
        recordMode = set.recordMode
        weight = set.weightValue?.canonicalString ?? ""
        reps = set.repetitionCount?.canonicalString ?? ""
        duration = set.recordMode == .cardio
            ? Self.minutesDisplay(fromSeconds: set.durationSeconds)
            : (set.durationSeconds?.canonicalString ?? "")
        side = set.side
        left = set.leftValue?.canonicalString ?? ""
        right = set.rightValue?.canonicalString ?? ""
        distance = set.distanceValue?.canonicalString ?? ""
        speed = set.speedValue?.canonicalString ?? ""
        resistance = set.resistanceValue?.canonicalString ?? ""
    }

    func cancelEditingSet() {
        editingSetID = nil
        resetSetFields(for: recordMode)
    }

    /// Saves the inline-editing form's fields onto the explicitly addressed
    /// `editingSetID`. Looks up the owning Exercise by scanning for the set
    /// id (the row being edited need not belong to the currently *selected*
    /// Exercise) instead of assuming `currentExercise`.
    func saveEditingSet() async {
        guard let setID = editingSetID,
            let exercise = exercise(containingSetID: setID)
        else {
            return
        }
        let input = currentInput(for: exercise)
        await run {
            self.session = try await self.useCases.editSet(setID: setID, input: input)
        }
        if errorMessage == nil {
            editingSetID = nil
            resetSetFields(for: recordMode)
        }
    }

    /// Removes an explicitly identified set (M1-A fix). Used by the per-row
    /// swipe-to-delete action; MUST NOT rely on array order.
    func removeSet(setID: StableUUID) async {
        await run {
            self.session = try await self.useCases.deleteSet(setID: setID)
        }
        guard errorMessage == nil else {
            return
        }
        if editingSetID == setID {
            editingSetID = nil
            resetSetFields(for: recordMode)
        }
        if activeDraftSetID == setID {
            activeDraftSetID = nil
        }
    }

    private func exercise(containingSetID setID: StableUUID) -> SessionExercise? {
        session?.exercises.first { $0.sets.contains { $0.id == setID } }
    }

    func copyPrevious() async {
        guard let exercise = currentExercise,
            let source = CopySetFlow.previousSet(in: exercise)
        else {
            return
        }
        await copy(sourceID: source.id)
    }

    func copyLastSame() async {
        guard let exercise = currentExercise,
            let source = CopySetFlow.lastCompletedSet(in: exercise)
        else {
            return
        }
        await copy(sourceID: source.id)
    }

    func undoLastSet() async {
        guard let setID = currentExercise?.sets.last?.id else {
            return
        }
        await run {
            self.session = try await self.useCases.undoSet(setID: setID)
        }
    }

    func requestFinish() {
        guard let session else {
            return
        }
        if case .failed = saveStatus {
            return
        }
        if session.durationNeedsReview && session.coachAdjustedDurationSeconds == nil {
            presentedSheet = .durationReview
            return
        }
        let gate = session.finishGate
        if gate == .canComplete {
            Task { await finishNow() }
            return
        }
        presentedSheet = .finish(gate)
    }

    func confirmDurationReview(_ seconds: String) async {
        presentedSheet = nil
        await run {
            self.session = try await self.useCases.applyCoachAdjustedDuration(try DecimalValue(seconds))
        }
        if session?.finishGate == .canComplete, session?.coachAdjustedDurationSeconds != nil {
            requestFinish()
        }
    }

    func abandon() async {
        presentedSheet = nil
        await run {
            self.session = try await self.signposts.measureSessionFinish {
                try await self.useCases.abandonEmpty()
            }
        }
    }

    func discardDraftsAndFinish() async {
        presentedSheet = nil
        await run {
            _ = try await self.useCases.discardUnresolved()
            if let gate = try await self.useCases.loadActive()?.finishGate, gate == .canComplete {
                try await self.finishNowThrowing()
            } else {
                self.session = try await self.useCases.loadActive()
            }
        }
    }

    func returnToDrafts() {
        presentedSheet = nil
    }

    func finishNow() async {
        await run { try await self.finishNowThrowing() }
    }

    private func finishNowThrowing() async throws {
        session = try await signposts.measureSessionFinish {
            try await self.useCases.finish()
        }
    }

    private func copy(sourceID: StableUUID) async {
        await run {
            self.session = try await self.useCases.copySet(sourceSetID: sourceID)
        }
    }

    private func currentInput(for exercise: SessionExercise) -> TrainingSetInput {
        let durationSecondsText = exercise.recordModeSnapshot == .cardio
            ? Self.secondsInput(fromMinutesText: duration)
            : duration
        return TrainingSetInput(
            recordMode: exercise.recordModeSnapshot,
            weightValue: weight,
            repetitionCount: reps,
            durationSeconds: durationSecondsText,
            unit: unit(for: exercise.recordModeSnapshot),
            side: side,
            leftValue: left,
            rightValue: right,
            distanceValue: distance,
            speedValue: speed,
            resistanceValue: resistance
        )
    }

    /// Cardio's duration field is entered/displayed in minutes; storage
    /// (`TrainingSet.durationSeconds`, Core Data, Comparison/ShareReport
    /// statistics) remains in seconds unchanged. These two helpers are the
    /// only place that conversion happens -- never change the storage unit.
    private static func secondsInput(fromMinutesText minutesText: String) -> String {
        guard let minutes = try? DecimalValue(minutesText) else { return minutesText }
        let seconds = minutes.decimal * 60
        return NSDecimalNumber(decimal: seconds).stringValue
    }

    private static func minutesDisplay(fromSeconds seconds: DecimalValue?) -> String {
        guard let seconds else { return "" }
        return DecimalValue.minutes(fromSeconds: seconds).canonicalString
    }

    private func unit(for mode: RecordMode) -> MeasurementUnit {
        switch mode {
        case .weightReps: return .kilograms
        case .reps: return .repetitions
        case .duration: return .seconds
        case .cardio: return .seconds
        }
    }

    private func applySavedExercise(_ updated: Session, mode: RecordMode) {
        session = updated
        selectedExerciseID = updated.exercises.last?.id
        exerciseName = ""
        exerciseNameConflict = nil
        catalogMatches = []
        isAddingExercise = false
        resetSetFields(for: mode)
    }

    private func resetSetFields(for mode: RecordMode) {
        weight = ""
        reps = ""
        duration = ""
        side = .none
        left = ""
        right = ""
        distance = ""
        speed = ""
        resistance = ""
        recordMode = mode
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        guard !isMutationInFlight else {
            return
        }
        isMutationInFlight = true
        saveStatus = .saving
        defer { isMutationInFlight = false }
        do {
            try await work()
            errorMessage = nil
            exerciseNameConflict = nil
            saveStatus = useCases.saveStatus
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        saveStatus = useCases.saveStatus
        if error as? DomainError == .conflict {
            exerciseNameConflict = String(localized: "exercise.conflict")
            errorMessage = nil
            return
        }
        exerciseNameConflict = nil
        errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
    }

    private func refreshCatalogMatches() async {
        catalogSearchGeneration += 1
        let generation = catalogSearchGeneration
        let query = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            catalogMatches = []
            return
        }
        do {
            let matches = try await useCases.searchCatalog(query: query)
            guard generation == catalogSearchGeneration, !Task.isCancelled else {
                return
            }
            catalogMatches = Array(matches.prefix(8))
        } catch is CancellationError {
            return
        } catch {
            guard generation == catalogSearchGeneration else {
                return
            }
            catalogMatches = []
        }
    }
}
