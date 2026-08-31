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
    @Published var selectedExerciseID: StableUUID?
    @Published var presentedSheet: ActiveSessionSheet?
    @Published private(set) var isMutationInFlight = false

    let studentID: StableUUID
    let useCases: ActiveSessionUseCases
    private let signposts: PerformanceSignposts
    private var catalogSearchGeneration = 0
    private var catalogSearchTask: Task<Void, Never>?

    init(
        studentID: StableUUID,
        useCases: ActiveSessionUseCases,
        signposts: PerformanceSignposts = .shared
    ) {
        self.studentID = studentID
        self.useCases = useCases
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
        } catch {
            present(error)
        }
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
            self.session = try await self.useCases.addSet(
                exerciseID: exercise.id,
                input: self.currentInput(for: exercise)
            )
        }
    }

    func confirmSet() async {
        guard let exerciseID = currentExercise?.id,
            let session,
            let exercise = session.exercises.first(where: { $0.id == exerciseID })
        else {
            return
        }
        await run {
            let input = self.currentInput(for: exercise)
            let targetID: StableUUID
            if let last = exercise.sets.last, last.state != .completed {
                self.session = try await self.useCases.editSet(setID: last.id, input: input)
                targetID = last.id
            } else {
                let added = try await self.useCases.addSet(exerciseID: exercise.id, input: input)
                self.session = added
                guard let setID = added.exercises.first(where: { $0.id == exercise.id })?.sets.last?.id else {
                    throw DomainError.notFound
                }
                targetID = setID
            }
            self.session = try await self.signposts.measureSetConfirm {
                try await self.useCases.confirmSet(setID: targetID)
            }
        }
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
        TrainingSetInput(
            recordMode: exercise.recordModeSnapshot,
            weightValue: weight,
            repetitionCount: reps,
            durationSeconds: duration,
            unit: unit(for: exercise.recordModeSnapshot),
            side: side,
            leftValue: left,
            rightValue: right
        )
    }

    private func unit(for mode: RecordMode) -> MeasurementUnit {
        switch mode {
        case .weightReps: return .kilograms
        case .reps: return .repetitions
        case .duration: return .seconds
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
