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

struct DeletedSetUndo: Equatable {
    let set: TrainingSet
    let originalIndex: Int
}

/// One successful set confirmation (D-FR-010). Published together with the
/// updated Session and record holders so the training page can give exactly
/// one haptic per confirmation; `sequence` makes two identical booleans two
/// distinct events. Recomputation (edit, delete, undo, restore, reload) never
/// publishes one (D-FR-012).
struct ConfirmationFeedback: Equatable, Sendable {
    let sequence: Int
    /// The confirmed set is in `strictRecordHolderSetIDs` after recomputation.
    let isRecordImprovement: Bool
}

/// A new-record value float the training page has not claimed yet (README
/// §14.4, Penpot D-a3; D-FR-013). `sequence` makes two identical records two
/// distinct requests, so claiming one can never swallow or replay another.
struct RecordFloatRequest: Equatable, Sendable {
    let setID: StableUUID
    let sequence: Int
}

/// The coach-facing credit question or notice shown after a Session
/// finishes (M1B-FR-013/014). Appointment-linked debits need no prompt.
enum SessionCreditPrompt: Equatable {
    /// Ad-hoc Session: debit the current active package or not.
    case adhocChoice(CoursePackage, balance: Int)
    /// Expired or zero balance: nothing debited; skip or adjust manually.
    case unusable(CoursePackage, SessionCreditUnusableReason)
    /// The automatic settlement failed; nothing more was debited.
    case failed(CoursePackage)

    var package: CoursePackage {
        switch self {
        case .adhocChoice(let package, _), .unusable(let package, _), .failed(let package):
            return package
        }
    }
}

@MainActor
final class ActiveSessionViewModel: ObservableObject {
    private struct RecordState {
        let session: Session?
        let holders: Set<StableUUID>
        /// Holders whose main metric is also strictly above every earlier set
        /// this session; only these give the new-record haptic (D-FR-013).
        let strictHolders: Set<StableUUID>
    }
    @Published private var recordState = RecordState(session: nil, holders: [], strictHolders: [])
    private var completedHistory: [CompletedSession] = []
    var session: Session? {
        get { recordState.session }
        set {
            guard let newValue else {
                recordState = RecordState(session: nil, holders: [], strictHolders: [])
                return
            }
            let gains = SessionGains(
                current: newValue, history: completedHistory, assistedExerciseIDs: entryFlags.assisted)
            recordState = RecordState(
                session: newValue, holders: gains.recordHolderSetIDs,
                strictHolders: gains.strictRecordHolderSetIDs)
        }
    }
    var recordHolderSetIDs: Set<StableUUID> { recordState.holders }
    var strictRecordHolderSetIDs: Set<StableUUID> { recordState.strictHolders }
    /// The most recent successful confirmation; nil until the first one and
    /// after a reload. Drives the single confirmation haptic.
    @Published private(set) var confirmationFeedback: ConfirmationFeedback?
    private var confirmationSequence = 0

    /// The newest strict-record float the training page has not claimed yet.
    /// Only a successful confirmation whose set is a strict record holder
    /// publishes one; recomputation (edit, delete, undo, restore, reload)
    /// never does (D-FR-012), so no row can float without a confirmation.
    @Published private(set) var recordFloatRequest: RecordFloatRequest?
    private var recordFloatSequence = 0

    /// Publishes the one confirmation event for `setID` after the new Session
    /// (and therefore the record holders) has been assigned, so the view sees
    /// both in the same main-thread update. Only successful confirmations call
    /// this -- recomputation paths must not (D-FR-012).
    private func publishConfirmationFeedback(for setID: StableUUID) {
        confirmationSequence += 1
        let isRecordImprovement = strictRecordHolderSetIDs.contains(setID)
        confirmationFeedback = ConfirmationFeedback(
            sequence: confirmationSequence,
            isRecordImprovement: isRecordImprovement)
        if isRecordImprovement {
            recordFloatSequence += 1
            recordFloatRequest = RecordFloatRequest(setID: setID, sequence: recordFloatSequence)
        }
    }

    /// The training page claims the pending float in the same update that
    /// renders it, so a row built later (scroll, List reuse, reload) has
    /// nothing left to replay. Claiming the same sequence twice, or a stale
    /// sequence after a newer request, is a no-op.
    func consumeRecordFloat(sequence: Int) {
        guard recordFloatRequest?.sequence == sequence else { return }
        recordFloatRequest = nil
    }

    @Published var errorMessage: String?
    @Published var saveStatus: PersistenceProjectionStatus = .saved(revision: 0)
    @Published var exerciseName = ""
    @Published var exerciseNameConflict: String?
    @Published var catalogMatches: [ExerciseLibraryEntry] = []
    @Published private(set) var catalogEntries: [ExerciseLibraryEntry] = []
    @Published var catalogMuscleFilter: String?
    @Published var catalogEquipmentFilter: String?
    @Published private(set) var recentCatalogMatches: [ExerciseLibraryEntry] = []
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
    /// Set after finishing when the coach must answer a credit question;
    /// the summary page is pushed only once this is resolved.
    @Published var creditPrompt: SessionCreditPrompt?
    /// "上次" per Exercise for this Student (experience P0-D1). Loaded once
    /// with the Session; a failed read only hides the reference.
    @Published private(set) var lastPerformances: LastExercisePerformanceLookup = .empty
    /// Between-sets rest countdown, started by every confirmed set (P0-D3).
    @Published var restTimer: RestTimerState?
    /// The set the bottom form just recorded; its row offers undo instead
    /// of its status until `undoWindow` passes (P0-D11).
    @Published private(set) var undoableSetID: StableUUID?
    /// The most recently deleted completed set, retained only for the shared
    /// undo window so the row can be restored at its original position.
    @Published private(set) var deletedSetUndo: DeletedSetUndo?
    static let undoWindow: Duration = FCUndoRow.undoWindow
    /// Unilateral entry (P0-D8): `false` shows one 「每侧重量」 stepper
    /// bound to `weight`; `true` shows 左 / 右 steppers bound to `left` and
    /// `right`. Either way the set is recorded with `side = .bilateral`.
    @Published var splitSides = false
    /// Quick-create's 「单侧动作」 toggle (P0-D8).
    @Published var newExerciseIsUnilateral = false
    /// Library flags for the set entry, loaded with the Session.
    @Published private(set) var entryFlags: ExerciseEntryFlags = .empty
    /// Session-only exercises created with 「单侧动作」 on. They have no
    /// library row, so the flag lives only as long as this view model.
    private var sessionOnlyUnilateralIDs: Set<StableUUID> = []

    let studentID: StableUUID
    let useCases: ActiveSessionUseCases
    let templateUseCases: TemplateUseCases?
    private let creditSettlement: SessionCreditSettlement?
    private let signposts: PerformanceSignposts
    private let notifications: (any LocalNotificationScheduling)?
    private let now: () -> Date
    private var restNotificationTask: Task<Void, Never>?
    private var undoExpiryTask: Task<Void, Never>?
    private var deletedSetUndoExpiryTask: Task<Void, Never>?
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
        creditSettlement: SessionCreditSettlement? = nil,
        signposts: PerformanceSignposts = .shared,
        notifications: (any LocalNotificationScheduling)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.studentID = studentID
        self.useCases = useCases
        self.templateUseCases = templateUseCases
        self.creditSettlement = creditSettlement
        self.signposts = signposts
        self.notifications = notifications
        self.now = now
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

    /// This page owns exactly one Session; every use-case call names it so a
    /// concurrently open Student's Session is never touched.
    private var sessionID: StableUUID? { session?.id }

    private var resolvedSaveStatus: PersistenceProjectionStatus {
        guard let sessionID else {
            return .saved(revision: 0)
        }
        return useCases.saveStatus(sessionID: sessionID)
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
        // A reload is not a confirmation: anything still pending from an
        // earlier confirmation is dropped, never replayed.
        recordFloatRequest = nil
        do {
            _ = try await useCases.reconcileOnLaunch()
            session = try await useCases.startOrOpen(studentID: studentID)
            selectedExerciseID = session?.exercises.last?.id
            errorMessage = nil
            saveStatus = resolvedSaveStatus
            await loadSections()
            let sessionStudentID = session?.studentID ?? studentID
            completedHistory = try await useCases.completedHistory(studentID: sessionStudentID)
            lastPerformances = LastExercisePerformanceLookup(sessions: completedHistory)
            do {
                recentCatalogMatches = RecentExerciseSelection.entries(
                    from: completedHistory, studentID: sessionStudentID,
                    availableEntries: try await useCases.searchCatalog(query: ""))
            } catch {
                recentCatalogMatches = []
                present(error)
            }
            catalogEntries = try await useCases.searchCatalog(query: "")
            await refreshEntryFlags()
            if editingSetID == nil {
                prefillSetFields(for: currentExercise)
            }
        } catch {
            present(error)
        }
    }

    var catalogSections: [ExerciseCatalogBrowse.Section] {
        let source =
            exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? catalogEntries
            : catalogMatches
        return ExerciseCatalogBrowse.sections(
            from: source,
            muscleFilter: catalogMuscleFilter,
            equipmentFilter: catalogEquipmentFilter
        )
    }

    var showsRecentCatalogMatches: Bool {
        exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && catalogMuscleFilter == nil
            && catalogEquipmentFilter == nil
            && !recentCatalogMatches.isEmpty
    }

    func selectCatalogMuscle(_ value: String?) {
        catalogMuscleFilter = value
    }

    func selectCatalogEquipment(_ value: String?) {
        catalogEquipmentFilter = value
    }

    // MARK: - Template save/section management (M1B-FR-018/019/020/021)

    func loadSections() async {
        sections = (try? await useCases.sessionSections(sessionID: sessionID)) ?? []
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
            _ = try await useCases.createSection(sessionID: sessionID, name: name)
            newSectionName = ""
            await loadSections()
        } catch {
            present(error)
        }
    }

    func moveExercise(_ exerciseID: StableUUID, toSectionID sectionID: StableUUID?) async {
        await run {
            self.session = try await self.useCases.moveExerciseToSection(
                sessionID: self.sessionID,
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
            self.session = try await self.useCases.deleteSection(
                sessionID: self.sessionID,
                sectionID: section.id,
                disposition: disposition
            )
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
            self.session = try await self.useCases.retry(sessionID: self.sessionID)
        }
    }

    func saveExercise() async {
        exerciseNameConflict = nil
        let name = exerciseName
        let mode = recordMode
        let unilateral = newExerciseIsUnilateral && mode == .weightReps
        await run {
            let updated = try await self.useCases.addSessionOnlyExercise(
                sessionID: self.sessionID,
                displayName: name,
                recordMode: mode
            )
            if unilateral, let added = updated.exercises.last {
                self.sessionOnlyUnilateralIDs.insert(added.id)
            }
            self.applySavedExercise(updated, mode: mode)
        }
    }

    func saveExerciseToLibrary() async {
        exerciseNameConflict = nil
        let name = exerciseName
        let mode = recordMode
        let unilateral = newExerciseIsUnilateral && mode == .weightReps
        await run {
            let updated = try await self.useCases.addCustomToLibraryAndSession(
                sessionID: self.sessionID,
                name: name,
                recordMode: mode,
                isUnilateral: unilateral
            )
            await self.refreshEntryFlags()
            self.applySavedExercise(updated, mode: mode)
        }
    }

    func scheduleCatalogSearch() {
        catalogSearchTask?.cancel()
        catalogSearchTask = Task { await refreshCatalogMatches() }
    }

    func addCatalogMatch(_ id: StableExerciseID) async {
        await run {
            let updated = try await self.useCases.addCatalogExercise(
                sessionID: self.sessionID,
                itemID: id
            )
            let mode = updated.exercises.last?.recordModeSnapshot ?? .weightReps
            await self.refreshEntryFlags()
            self.applySavedExercise(updated, mode: mode)
        }
    }

    func selectExercise(_ id: StableUUID) {
        selectedExerciseID = id
        if let exercise = session?.exercises.first(where: { $0.id == id }) {
            prefillSetFields(for: exercise)
        }
    }

    /// Deletes an exercise from its row swipe (P0-D10). One with a
    /// completed set asks for confirmation first.
    func requestDeleteExercise(_ exerciseID: StableUUID) {
        guard let exercise = session?.exercises.first(where: { $0.id == exerciseID }) else {
            return
        }
        if exercise.hasCompletedSet {
            presentedSheet = .deleteExercise(exercise.id)
            return
        }
        Task {
            await run {
                self.session = try await self.useCases.removeExercise(
                    sessionID: self.sessionID,
                    exerciseID: exercise.id,
                    confirmedIfCompleted: false
                )
                self.reselectAfterRemoving(exercise.id)
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
                sessionID: self.sessionID,
                exerciseID: exerciseID,
                confirmedIfCompleted: true
            )
            self.reselectAfterRemoving(exerciseID)
        }
    }

    /// Keeps the selection unless the removed exercise was the selected one.
    private func reselectAfterRemoving(_ exerciseID: StableUUID) {
        guard selectedExerciseID == exerciseID || selectedExerciseID == nil else {
            return
        }
        selectedExerciseID = session?.exercises.last?.id
        if let exercise = currentExercise {
            prefillSetFields(for: exercise)
        }
    }

    func addDraftSet() async {
        guard let exercise = currentExercise else {
            return
        }
        await run {
            let updated = try await self.useCases.addSet(
                sessionID: self.sessionID,
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
        let confirmed = await run {
            let input = self.currentInput(for: exercise)
            let added = try await self.useCases.addSet(
                sessionID: self.sessionID,
                exerciseID: exercise.id,
                input: input
            )
            guard let newSetID = added.exercises.first(where: { $0.id == exercise.id })?.sets.last?.id else {
                throw DomainError.notFound
            }
            self.session = try await self.signposts.measureSetConfirm {
                try await self.useCases.confirmSet(sessionID: self.sessionID, setID: newSetID)
            }
            self.publishConfirmationFeedback(for: newSetID)
            self.offerUndo(for: newSetID)
        }
        if confirmed {
            startRest()
        }
    }

    /// Confirms an explicitly identified set (M1-A fix). MUST NOT fall back
    /// to `exercise.sets.last` -- confirming one draft/pending set out of
    /// order MUST NOT affect any other set's state.
    func confirmSet(setID: StableUUID) async {
        let confirmed = await run {
            self.session = try await self.signposts.measureSetConfirm {
                try await self.useCases.confirmSet(sessionID: self.sessionID, setID: setID)
            }
            self.publishConfirmationFeedback(for: setID)
        }
        if errorMessage == nil, activeDraftSetID == setID {
            activeDraftSetID = nil
        }
        if confirmed {
            startRest()
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
        switch set.recordMode {
        case .cardio, .duration:
            duration = DurationTextParser.formatForEditing(secondsText: set.durationSeconds?.canonicalString)
        case .weightReps, .reps:
            duration = set.durationSeconds?.canonicalString ?? ""
        }
        side = set.side
        left = set.leftValue?.canonicalString ?? ""
        right = set.rightValue?.canonicalString ?? ""
        splitSides = set.side == .bilateral && left != right
        distance = set.distanceValue?.canonicalString ?? ""
        speed = set.speedValue?.canonicalString ?? ""
        resistance = set.resistanceValue?.canonicalString ?? ""
    }

    func cancelEditingSet() {
        editingSetID = nil
        prefillSetFields(for: currentExercise)
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
            self.session = try await self.useCases.editSet(
                sessionID: self.sessionID,
                setID: setID,
                input: input
            )
        }
        if errorMessage == nil {
            editingSetID = nil
            prefillSetFields(for: currentExercise)
        }
    }

    /// Removes an explicitly identified set (M1-A fix). Used by the per-row
    /// swipe-to-delete action; MUST NOT rely on array order.
    func removeSet(setID: StableUUID) async {
        guard let exercise = exercise(containingSetID: setID),
            let setIndex = exercise.sets.firstIndex(where: { $0.id == setID }),
            exercise.sets.indices.contains(setIndex)
        else {
            return
        }
        let set = exercise.sets[setIndex]

        if set.state == .completed {
            let removed = await run {
                self.session = try await self.useCases.deleteSet(sessionID: self.sessionID, setID: setID)
            }
            guard removed else {
                return
            }
            if editingSetID == setID {
                editingSetID = nil
                prefillSetFields(for: currentExercise)
            }
            if activeDraftSetID == setID {
                activeDraftSetID = nil
            }
            if undoableSetID == setID {
                withdrawUndo()
            }
            offerDeletedSetUndo(DeletedSetUndo(set: set, originalIndex: setIndex))
            return
        }

        await run {
            self.session = try await self.useCases.deleteSet(sessionID: self.sessionID, setID: setID)
        }
        guard errorMessage == nil else {
            return
        }
        if editingSetID == setID {
            editingSetID = nil
            prefillSetFields(for: currentExercise)
        }
        if activeDraftSetID == setID {
            activeDraftSetID = nil
        }
        if undoableSetID == setID {
            withdrawUndo()
        }
    }

    /// Restores the deleted completed set without replacing the current
    /// session snapshot, preserving edits made during the undo window.
    func undoDeletedSet() async {
        guard let deletedSetUndo else {
            return
        }
        let restored = await run {
            self.session = try await self.useCases.restoreDeletedSet(
                sessionID: self.sessionID,
                deletedSetUndo.set,
                at: deletedSetUndo.originalIndex
            )
        }
        guard restored else {
            return
        }
        withdrawDeletedSetUndo()
    }

    /// The deletion is already durable. Clearing this state removes only the
    /// temporary undo affordance, for example when leaving the page or going
    /// into the background.
    func expireDeletedSetUndo() {
        withdrawDeletedSetUndo()
    }

    /// Undoes the set the bottom form just recorded (P0-D11): the set is
    /// removed, the rest bar closes, and its values go back into the form.
    func undoRecentSet() async {
        guard let setID = undoableSetID,
            let recorded = exercise(containingSetID: setID)?.sets.first(where: { $0.id == setID })
        else {
            return
        }
        let undone = await run {
            self.session = try await self.useCases.deleteSet(sessionID: self.sessionID, setID: setID)
        }
        guard undone else {
            return
        }
        withdrawUndo()
        clearRest()
        fillSetFields(from: recorded)
    }

    private func exercise(containingSetID setID: StableUUID) -> SessionExercise? {
        session?.exercises.first { $0.sets.contains { $0.id == setID } }
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
            self.session = try await self.useCases.applyCoachAdjustedDuration(
                sessionID: self.sessionID,
                try DecimalValue(seconds)
            )
        }
        if session?.finishGate == .canComplete, session?.coachAdjustedDurationSeconds != nil {
            requestFinish()
        }
    }

    func abandon() async {
        presentedSheet = nil
        await run {
            let abandoned = try await self.signposts.measureSessionFinish {
                try await self.useCases.abandonEmpty(sessionID: self.sessionID)
            }
            // The Session is already abandoned; a failed Appointment update
            // must not turn that into a visible failure.
            try? await self.creditSettlement?.settleAbandonedSession(abandoned)
            self.session = abandoned
            self.expireDeletedSetUndo()
            self.clearRest()
        }
    }

    func discardDraftsAndFinish() async {
        presentedSheet = nil
        await run {
            guard let sessionID = self.sessionID else { throw DomainError.notFound }
            _ = try await self.useCases.discardUnresolved(sessionID: sessionID)
            if let gate = try await self.useCases.loadActive(sessionID: sessionID)?.finishGate,
                gate == .canComplete
            {
                try await self.finishNowThrowing()
            } else {
                self.session = try await self.useCases.loadActive(sessionID: sessionID)
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
        let finished = try await signposts.measureSessionFinish {
            try await self.useCases.finish(sessionID: self.sessionID)
        }
        // Set before `session` so the view holds the summary push until the
        // coach has answered (M1B-FR-013/014).
        creditPrompt = await settleCredits(for: finished)
        session = finished
        expireDeletedSetUndo()
        clearRest()
    }

    /// The Session is already completed when this runs, so a settlement
    /// failure never undoes the finish; it is surfaced as a notice instead.
    private func settleCredits(for finished: Session) async -> SessionCreditPrompt? {
        guard let creditSettlement else {
            return nil
        }
        do {
            switch try await creditSettlement.settleFinishedSession(finished) {
            case .noActivePackage, .debited:
                return nil
            case .adhocChoiceRequired(let package, let balance):
                return .adhocChoice(package, balance: balance)
            case .packageUnusable(let package, let reason):
                return .unusable(package, reason)
            }
        } catch {
            return await failurePrompt(studentID: finished.studentID, creditSettlement: creditSettlement)
        }
    }

    private func failurePrompt(
        studentID: StableUUID,
        creditSettlement: SessionCreditSettlement
    ) async -> SessionCreditPrompt? {
        guard let package = try? await creditSettlement.activePackage(studentID: studentID) else {
            return nil
        }
        return .failed(package)
    }

    /// "扣 1 课时" on the ad-hoc question. Returns whether the prompt is
    /// resolved; on failure the prompt turns into the matching notice.
    func debitAdhocSession() async -> Bool {
        guard case .adhocChoice(let package, _) = creditPrompt, let session, let creditSettlement else {
            creditPrompt = nil
            return true
        }
        do {
            try await creditSettlement.debitAdhocSession(packageID: package.id, sessionID: session.id)
            creditPrompt = nil
            return true
        } catch DomainError.invalidState {
            creditPrompt = .unusable(package, .insufficientBalance)
        } catch {
            creditPrompt = .failed(package)
        }
        return false
    }

    /// "不扣课" / scrim tap: nothing is written to the ledger.
    func skipCreditDebit() {
        creditPrompt = nil
    }

    private func currentInput(for exercise: SessionExercise) -> TrainingSetInput {
        let durationSecondsText: String
        switch exercise.recordModeSnapshot {
        case .cardio, .duration:
            durationSecondsText = DurationTextParser.parseSeconds(duration) ?? duration
        case .weightReps, .reps:
            durationSecondsText = duration
        }
        if usesSideEntry(exercise) {
            return sideEntryInput(for: exercise)
        }
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

    /// Unilateral entry (P0-D8) records `side = .bilateral`: 「每侧重量」
    /// puts the same value on both sides; 「左右不同」 records each side and
    /// keeps the heavier one as the set's weight (the lighter one for an
    /// assisted exercise, where less load is progress), so trends and
    /// records keep reading `weightValue`.
    private func sideEntryInput(for exercise: SessionExercise) -> TrainingSetInput {
        let leftText = splitSides ? left : weight
        let rightText = splitSides ? right : weight
        return TrainingSetInput(
            recordMode: .weightReps,
            weightValue: splitSides ? Self.recordedWeight(leftText, rightText, assisted: isAssisted(exercise)) : weight,
            repetitionCount: reps,
            unit: .kilograms,
            side: .bilateral,
            leftValue: leftText,
            rightValue: rightText
        )
    }

    /// The heavier side, or the lighter one when `assisted`. A side that is
    /// not a number yet leaves the weight empty, so validation names it.
    static func recordedWeight(_ left: String, _ right: String, assisted: Bool) -> String {
        guard let leftValue = try? DecimalValue(left.trimmingCharacters(in: .whitespacesAndNewlines)),
            let rightValue = try? DecimalValue(right.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return ""
        }
        let leftWins = assisted ? leftValue.decimal <= rightValue.decimal : leftValue.decimal >= rightValue.decimal
        return (leftWins ? leftValue : rightValue).canonicalString
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
        newExerciseIsUnilateral = false
        catalogMatches = []
        isAddingExercise = false
        recordMode = mode
        prefillSetFields(for: updated.exercises.last)
    }

    // MARK: - Faster set entry (experience P0, design/experience-p0)

    /// Whether left/right entry applies to this exercise (P0-D8): the
    /// library flag, or quick-create's toggle for a session-only exercise.
    func isUnilateral(_ exercise: SessionExercise) -> Bool {
        if let sourceID = exercise.sourceID {
            return entryFlags.unilateral.contains(sourceID)
        }
        return sessionOnlyUnilateralIDs.contains(exercise.id)
    }

    /// Whether the entry shows 「每侧重量」/「左右不同」 instead of one weight:
    /// weight × reps on a unilateral exercise, or editing a set that was
    /// already recorded per side.
    func usesSideEntry(_ exercise: SessionExercise) -> Bool {
        guard exercise.recordModeSnapshot == .weightReps else {
            return false
        }
        return side == .bilateral || (side == .none && isUnilateral(exercise))
    }

    private func isAssisted(_ exercise: SessionExercise) -> Bool {
        exercise.sourceID.map { entryFlags.assisted.contains($0) } ?? false
    }

    /// 「左右不同」 / 「左右相同」. Splitting starts both sides at the shared
    /// weight; joining keeps the recorded weight (heavier side).
    func toggleSplitSides(for exercise: SessionExercise) {
        if splitSides {
            weight = Self.recordedWeight(left, right, assisted: isAssisted(exercise))
            left = ""
            right = ""
            splitSides = false
        } else {
            left = weight
            right = weight
            splitSides = true
        }
    }

    /// − / + on the 左 or 右 field (P0-D4 weight step).
    func stepSide(_ which: SetSide, up: Bool) {
        switch which {
        case .left: left = SetValueStepping.stepped(left, field: .weight, up: up)
        case .right: right = SetValueStepping.stepped(right, field: .weight, up: up)
        case .none, .bilateral: break
        }
    }

    private func refreshEntryFlags() async {
        if let flags = try? await useCases.exerciseEntryFlags() {
            entryFlags = flags
            let current = session
            session = current
        }
    }

    func lastPerformance(for exercise: SessionExercise) -> LastExercisePerformance? {
        lastPerformances.performance(for: exercise)
    }

    /// − / + on the weight or reps field (P0-D4: ±2.5 kg, ±1).
    func step(_ field: SetValueStepping.Field, up: Bool) {
        switch field {
        case .weight: weight = SetValueStepping.stepped(weight, field: .weight, up: up)
        case .reps: reps = SetValueStepping.stepped(reps, field: .reps, up: up)
        }
    }

    func adjustRest(by seconds: TimeInterval) {
        restTimer?.adjust(by: seconds, now: now())
        syncRestNotification()
    }

    func dismissRest() {
        clearRest()
    }

    private func offerUndo(for setID: StableUUID) {
        undoableSetID = setID
        undoExpiryTask?.cancel()
        undoExpiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled, self?.undoableSetID == setID else {
                return
            }
            self?.undoableSetID = nil
        }
    }

    private func offerDeletedSetUndo(_ value: DeletedSetUndo) {
        deletedSetUndoExpiryTask?.cancel()
        deletedSetUndo = value
        deletedSetUndoExpiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled, self?.deletedSetUndo == value else {
                return
            }
            self?.withdrawDeletedSetUndo()
        }
    }

    private func withdrawDeletedSetUndo() {
        deletedSetUndoExpiryTask?.cancel()
        deletedSetUndoExpiryTask = nil
        deletedSetUndo = nil
    }

    private func withdrawUndo() {
        undoExpiryTask?.cancel()
        undoExpiryTask = nil
        undoableSetID = nil
    }

    private func startRest() {
        restTimer = RestTimerState(startedAt: now())
        syncRestNotification()
    }

    /// Drops the in-app bar and the pending end notification together.
    private func clearRest() {
        restTimer = nil
        syncRestNotification()
    }

    /// P0-D5: one generic local notification at the rest end. +15 / −15
    /// replace it; skip, dismiss, abandon, and finish remove it. Requests
    /// permission only through the existing not-yet-determined path.
    private func syncRestNotification() {
        guard let notifications else {
            return
        }
        let plan = RestEndNotification.plan(
            endsAt: restTimer?.endsAt,
            now: now(),
            sessionID: sessionID
        )
        let previous = restNotificationTask
        restNotificationTask = Task { @MainActor in
            _ = await previous?.value
            await RestEndNotification.apply(plan, with: notifications)
        }
    }

    /// Fills the bottom form for `exercise` (P0-D1/D2): the latest set
    /// already recorded in this Session (completed first), else this
    /// Student's first set of the Exercise last time, else empty. Values
    /// only become a set when the coach confirms (M1A-FR-022 unchanged).
    /// Weight/reps modes only; duration and cardio keep starting empty.
    private func prefillSetFields(for exercise: SessionExercise?) {
        let mode = exercise?.recordModeSnapshot ?? recordMode
        resetSetFields(for: mode)
        guard let exercise, mode == .weightReps || mode == .reps else {
            return
        }
        let source =
            exercise.sets.last(where: \.contributesToStatistics)
            ?? exercise.sets.last
            ?? lastPerformances.performance(for: exercise)?.firstSet
        guard let source else {
            return
        }
        fillSetFields(from: source)
        // Sides only show for exercises marked unilateral (P0-D8); a new set
        // always starts from the exercise's flag, not the source's side.
        side = .none
        if !isUnilateral(exercise) || !splitSides {
            splitSides = false
            left = ""
            right = ""
        }
    }

    /// Copies a set's values into the form; a per-side set with different
    /// sides reopens 「左右不同」, one with equal sides shows 「每侧重量」.
    private func fillSetFields(from source: TrainingSet) {
        reps = source.repetitionCount?.canonicalString ?? ""
        side = source.side
        left = source.leftValue?.canonicalString ?? ""
        right = source.rightValue?.canonicalString ?? ""
        splitSides = source.side == .bilateral && left != right
        if source.side == .bilateral, !splitSides, !left.isEmpty {
            weight = left
        } else {
            weight = source.weightValue?.canonicalString ?? ""
        }
    }

    private func resetSetFields(for mode: RecordMode) {
        weight = ""
        reps = ""
        duration = ""
        side = .none
        left = ""
        right = ""
        splitSides = false
        distance = ""
        speed = ""
        resistance = ""
        recordMode = mode
    }

    /// Returns whether `work` ran and succeeded.
    @discardableResult
    private func run(_ work: @escaping () async throws -> Void) async -> Bool {
        guard !isMutationInFlight else {
            return false
        }
        isMutationInFlight = true
        saveStatus = .saving
        defer { isMutationInFlight = false }
        do {
            try await work()
            errorMessage = nil
            exerciseNameConflict = nil
            saveStatus = resolvedSaveStatus
            return true
        } catch {
            present(error)
            return false
        }
    }

    private func present(_ error: Error) {
        saveStatus = resolvedSaveStatus
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
            catalogMatches = matches
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
