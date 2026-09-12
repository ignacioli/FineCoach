import Foundation

public enum SessionState: String, Codable, Sendable {
    case inProgress
    case completed
    case abandonedEmpty
}

public enum SessionFinishGate: Equatable, Sendable {
    case canComplete
    case abandonEmpty
    case unresolvedDrafts
}

public enum ActiveSessionPointerKey {
    public static let singleton = "active"
}

public struct Session: Hashable, Codable, Sendable, Identifiable {
    public let id: StableUUID
    public let studentID: StableUUID
    public let state: SessionState
    public let startedAtUTC: Date
    public let lastCheckpointUTC: Date
    public let elapsedSeconds: DecimalValue
    public let interruptionStartedAtUTC: Date?
    public let durationNeedsReview: Bool
    public let coachAdjustedDurationSeconds: DecimalValue?
    public let trainingFocus: ValidatedText?
    public let studentFacingSummary: ValidatedText?
    public let privateCoachNote: ValidatedText?
    public let revision: UInt64
    public let createdAtUTC: Date
    public let updatedAtUTC: Date
    public let completedAtUTC: Date?
    public let exercises: [SessionExercise]

    public var finishGate: SessionFinishGate {
        if completedSetCount == 0 {
            return .abandonEmpty
        }
        if hasUnresolvedSets {
            return .unresolvedDrafts
        }
        return .canComplete
    }

    public var completedSetCount: Int {
        statisticsSets.count
    }

    public var displayedDurationSeconds: DecimalValue {
        coachAdjustedDurationSeconds ?? elapsedSeconds
    }

    public var sessionNotes: SessionNotes {
        var actionPrivateNotes: [StableUUID: ValidatedText] = [:]
        for exercise in exercises {
            if let note = exercise.actionPrivateNote {
                actionPrivateNotes[exercise.id] = note
            }
        }
        return SessionNotes(
            privateCoachNote: privateCoachNote,
            studentFacingSummary: studentFacingSummary,
            actionPrivateNotes: actionPrivateNotes
        )
    }

    public var statistics: SessionStatistics {
        (try? SessionStatistics.make(from: self))
            ?? SessionStatistics(
                completedSetCount: completedSetCount,
                displayedDurationSeconds: displayedDurationSeconds,
                ordinaryTrainingVolume: nil
            )
    }

    public var statisticsSets: [TrainingSet] {
        exercises.flatMap(\.sets).filter(\.contributesToStatistics)
    }

    public var hasUnresolvedSets: Bool {
        exercises.contains { exercise in
            exercise.sets.contains { $0.state != .completed }
        }
    }

    public init(
        id: StableUUID,
        studentID: StableUUID,
        state: SessionState,
        startedAtUTC: Date,
        lastCheckpointUTC: Date,
        elapsedSeconds: DecimalValue,
        interruptionStartedAtUTC: Date?,
        durationNeedsReview: Bool,
        coachAdjustedDurationSeconds: DecimalValue?,
        trainingFocus: ValidatedText?,
        studentFacingSummary: ValidatedText?,
        privateCoachNote: ValidatedText?,
        revision: UInt64,
        createdAtUTC: Date,
        updatedAtUTC: Date,
        completedAtUTC: Date?,
        exercises: [SessionExercise]
    ) {
        self.id = id
        self.studentID = studentID
        self.state = state
        self.startedAtUTC = startedAtUTC
        self.lastCheckpointUTC = lastCheckpointUTC
        self.elapsedSeconds = elapsedSeconds
        self.interruptionStartedAtUTC = interruptionStartedAtUTC
        self.durationNeedsReview = durationNeedsReview
        self.coachAdjustedDurationSeconds = coachAdjustedDurationSeconds
        self.trainingFocus = trainingFocus
        self.studentFacingSummary = studentFacingSummary
        self.privateCoachNote = privateCoachNote
        self.revision = revision
        self.createdAtUTC = createdAtUTC
        self.updatedAtUTC = updatedAtUTC
        self.completedAtUTC = completedAtUTC
        self.exercises = exercises
    }

    public static func start(id: StableUUID, studentID: StableUUID, now: Date) -> Session {
        Session(
            id: id,
            studentID: studentID,
            state: .inProgress,
            startedAtUTC: now,
            lastCheckpointUTC: now,
            elapsedSeconds: .zero,
            interruptionStartedAtUTC: nil,
            durationNeedsReview: false,
            coachAdjustedDurationSeconds: nil,
            trainingFocus: nil,
            studentFacingSummary: nil,
            privateCoachNote: nil,
            revision: 1,
            createdAtUTC: now,
            updatedAtUTC: now,
            completedAtUTC: nil,
            exercises: []
        )
    }

    public func addingSessionOnlyExercise(
        id: StableUUID,
        displayName: String,
        recordMode: RecordMode,
        now: Date
    ) throws -> Session {
        try ensureInProgress()
        let exercise = try SessionExercise(
            id: id,
            sessionID: self.id,
            orderIndex: UInt32(exercises.count),
            sourceKind: .sessionOnly,
            sourceID: nil,
            displayNameSnapshot: NormalizedName(displayName),
            recordModeSnapshot: recordMode,
            actionPrivateNote: nil,
            sets: []
        )
        return replacing(exercises: exercises + [exercise], revision: nextRevision, updatedAtUTC: now)
    }

    public func addingCatalogExercise(
        id: StableUUID,
        item: ExerciseCatalogItem,
        now: Date
    ) throws -> Session {
        try ensureInProgress()
        guard item.lifecycle == .active else {
            throw DomainError.invalidState
        }
        let sourceKind: ExerciseSourceKind = item.kind == .builtIn ? .builtIn : .custom
        let exercise = try SessionExercise(
            id: id,
            sessionID: self.id,
            orderIndex: UInt32(exercises.count),
            sourceKind: sourceKind,
            sourceID: item.id,
            displayNameSnapshot: item.canonicalName,
            recordModeSnapshot: item.recordMode,
            actionPrivateNote: nil,
            sets: []
        )
        return replacing(exercises: exercises + [exercise], revision: nextRevision, updatedAtUTC: now)
    }

    /// Appends externally-constructed `SessionExercise` values as-is, without
    /// recomputing their `orderIndex`/`sectionID` (used by template
    /// application, M1B-FR-019 -- `TrainingTemplate.applying` computes the
    /// correct unified-axis `orderIndex` for each new Exercise/Section before
    /// calling this). Callers MUST have already validated `sessionID` on each
    /// exercise; this only re-checks it defensively.
    public func appendingTemplateExercises(_ newExercises: [SessionExercise], now: Date) throws -> Session {
        try ensureInProgress()
        guard newExercises.allSatisfy({ $0.sessionID == id }) else {
            throw DomainError.invalidState
        }
        return replacing(exercises: exercises + newExercises, revision: nextRevision, updatedAtUTC: now)
    }

    public func reorderingExercises(ids: [StableUUID], now: Date) throws -> Session {
        try ensureInProgress()
        guard ids.count == exercises.count, Set(ids).count == ids.count else {
            throw DomainError.invalidState
        }
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        var reordered: [SessionExercise] = []
        reordered.reserveCapacity(ids.count)
        for id in ids {
            guard let exercise = byID[id] else {
                throw DomainError.invalidState
            }
            reordered.append(exercise)
        }
        return replacing(
            exercises: reordered.enumerated().map { offset, exercise in
                exercise.relocating(orderIndex: UInt32(offset))
            },
            revision: nextRevision,
            updatedAtUTC: now
        )
    }

    /// Moves one Exercise into `sectionID` (`nil` = unsectioned) without
    /// changing its position in the unified order axis (M1B-FR-020/021).
    public func updatingExerciseSection(exerciseID: StableUUID, sectionID: StableUUID?, now: Date) throws -> Session {
        try ensureInProgress()
        let (index, exercise) = try requireExercise(exerciseID)
        let relocated = exercise.relocating(orderIndex: exercise.orderIndex, sectionID: sectionID)
        return replacingExercise(at: index, with: relocated, now: now)
    }

    public func removingExercise(id: StableUUID, confirmedIfCompleted: Bool, now: Date) throws -> Session {
        try ensureInProgress()
        guard let exercise = exercises.first(where: { $0.id == id }) else {
            throw DomainError.notFound
        }
        if exercise.hasCompletedSet && !confirmedIfCompleted {
            throw DomainError.invalidState
        }
        let remaining = exercises.filter { $0.id != id }
        return replacing(
            exercises: remaining.enumerated().map { offset, item in
                item.relocating(orderIndex: UInt32(offset))
            },
            revision: nextRevision,
            updatedAtUTC: now
        )
    }

    public func addingSet(
        exerciseID: StableUUID,
        setID: StableUUID,
        input: TrainingSetInput,
        now: Date
    ) throws -> Session {
        try ensureInProgress()
        let (index, exercise) = try requireExercise(exerciseID)
        guard input.recordMode == exercise.recordModeSnapshot else {
            throw DomainError.invalidMode
        }
        let trainingSet = try TrainingSet.makeDraft(
            id: setID,
            sessionExerciseID: exercise.id,
            orderIndex: UInt32(exercise.sets.count),
            input: input,
            now: now
        )
        return replacingExercise(at: index, with: exercise.replacingSets(exercise.sets + [trainingSet]), now: now)
    }

    public func editingSet(setID: StableUUID, input: TrainingSetInput, now: Date) throws -> Session {
        try mutateSet(setID, now: now) { trainingSet in
            guard input.recordMode == trainingSet.recordMode else {
                throw DomainError.invalidMode
            }
            return try trainingSet.updating(input: input, now: now)
        }
    }

    public func confirmingSet(setID: StableUUID, now: Date) throws -> Session {
        try mutateSet(setID, now: now) { try $0.confirmed(now: now) }
    }

    public func copyingSet(sourceSetID: StableUUID, newSetID: StableUUID, now: Date) throws -> Session {
        try ensureInProgress()
        let (index, exercise, source) = try requireSet(sourceSetID)
        let copy = try source.copiedAsPending(
            id: newSetID,
            orderIndex: UInt32(exercise.sets.count),
            now: now
        )
        return replacingExercise(at: index, with: exercise.replacingSets(exercise.sets + [copy]), now: now)
    }

    public func undoingSet(setID: StableUUID, now: Date) throws -> Session {
        try mutateSet(setID, now: now) { try $0.undone(now: now) }
    }

    public func deletingSet(setID: StableUUID, now: Date) throws -> Session {
        try ensureInProgress()
        let (index, exercise, _) = try requireSet(setID)
        let remaining = exercise.sets.filter { $0.id != setID }
        return replacingExercise(at: index, with: exercise.replacingSets(remaining), now: now)
    }

    public func discardingUnresolvedSets(now: Date) throws -> Session {
        try ensureInProgress()
        let cleaned = exercises.map { exercise in
            exercise.replacingSets(exercise.sets.filter(\.contributesToStatistics))
        }
        return replacing(exercises: cleaned, revision: nextRevision, updatedAtUTC: now)
    }

    public func applyingCoachAdjustedDuration(_ seconds: DecimalValue, now: Date) throws -> Session {
        try ensureInProgress()
        guard seconds.decimal >= 0, seconds.isInteger else {
            throw DomainError.invalidNumber
        }
        return replacing(
            durationNeedsReview: false,
            coachAdjustedDurationSeconds: .some(seconds),
            revision: nextRevision,
            updatedAtUTC: now
        )
    }

    public func finished(now: Date) throws -> Session {
        try ensureInProgress()
        guard finishGate == .canComplete else {
            throw DomainError.invalidState
        }
        if durationNeedsReview && coachAdjustedDurationSeconds == nil {
            throw DomainError.invalidState
        }
        return replacing(
            state: .completed,
            revision: nextRevision,
            updatedAtUTC: now,
            completedAtUTC: now
        )
    }

    public func abandoned(now: Date) throws -> Session {
        try ensureInProgress()
        guard finishGate == .abandonEmpty else {
            throw DomainError.invalidState
        }
        return replacing(
            state: .abandonedEmpty,
            revision: nextRevision,
            updatedAtUTC: now,
            completedAtUTC: nil
        )
    }

    private var nextRevision: UInt64 {
        revision + 1
    }

    private func ensureInProgress() throws {
        guard state == .inProgress else {
            throw DomainError.invalidState
        }
    }

    private func ensureCompleted() throws {
        guard state == .completed else {
            throw DomainError.invalidState
        }
    }

    private func requireExercise(_ exerciseID: StableUUID) throws -> (Int, SessionExercise) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else {
            throw DomainError.notFound
        }
        return (index, exercises[index])
    }

    private func requireSet(_ setID: StableUUID) throws -> (Int, SessionExercise, TrainingSet) {
        for (index, exercise) in exercises.enumerated() {
            if let trainingSet = exercise.sets.first(where: { $0.id == setID }) {
                return (index, exercise, trainingSet)
            }
        }
        throw DomainError.notFound
    }

    private func mutateSet(
        _ setID: StableUUID,
        now: Date,
        transform: (TrainingSet) throws -> TrainingSet
    ) throws -> Session {
        try ensureInProgress()
        let (index, exercise, source) = try requireSet(setID)
        let updated = try transform(source)
        let sets = exercise.sets.map { $0.id == setID ? updated : $0 }
        return replacingExercise(at: index, with: exercise.replacingSets(sets), now: now)
    }

    private func replacingExercise(at index: Int, with exercise: SessionExercise, now: Date) -> Session {
        var exercises = self.exercises
        exercises[index] = exercise
        return replacing(exercises: exercises, revision: nextRevision, updatedAtUTC: now)
    }

    private func replacing(
        state: SessionState? = nil,
        exercises: [SessionExercise]? = nil,
        elapsedSeconds: DecimalValue? = nil,
        lastCheckpointUTC: Date? = nil,
        interruptionStartedAtUTC: Date?? = nil,
        durationNeedsReview: Bool? = nil,
        coachAdjustedDurationSeconds: DecimalValue?? = nil,
        trainingFocus: ValidatedText?? = nil,
        studentFacingSummary: ValidatedText?? = nil,
        privateCoachNote: ValidatedText?? = nil,
        revision: UInt64,
        updatedAtUTC: Date,
        completedAtUTC: Date? = nil
    ) -> Session {
        Session(
            id: id,
            studentID: studentID,
            state: state ?? self.state,
            startedAtUTC: startedAtUTC,
            lastCheckpointUTC: lastCheckpointUTC ?? updatedAtUTC,
            elapsedSeconds: elapsedSeconds ?? self.elapsedSeconds,
            interruptionStartedAtUTC: interruptionStartedAtUTC ?? self.interruptionStartedAtUTC,
            durationNeedsReview: durationNeedsReview ?? self.durationNeedsReview,
            coachAdjustedDurationSeconds: coachAdjustedDurationSeconds ?? self.coachAdjustedDurationSeconds,
            trainingFocus: trainingFocus ?? self.trainingFocus,
            studentFacingSummary: studentFacingSummary ?? self.studentFacingSummary,
            privateCoachNote: privateCoachNote ?? self.privateCoachNote,
            revision: revision,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC,
            completedAtUTC: completedAtUTC ?? self.completedAtUTC,
            exercises: exercises ?? self.exercises
        )
    }

    public func updatingTiming(
        elapsedSeconds: DecimalValue,
        lastCheckpointUTC: Date,
        interruptionStartedAtUTC: Date?,
        durationNeedsReview: Bool,
        now: Date
    ) -> Session {
        replacing(
            elapsedSeconds: elapsedSeconds,
            lastCheckpointUTC: lastCheckpointUTC,
            interruptionStartedAtUTC: .some(interruptionStartedAtUTC),
            durationNeedsReview: durationNeedsReview,
            revision: nextRevision,
            updatedAtUTC: now
        )
    }

    public func updatingTrainingFocus(_ value: ValidatedText?, now: Date) throws -> Session {
        try ensureCompleted()
        return replacing(trainingFocus: .some(value), revision: nextRevision, updatedAtUTC: now)
    }

    public func updatingStudentFacingSummary(_ value: ValidatedText?, now: Date) throws -> Session {
        try ensureCompleted()
        return replacing(studentFacingSummary: .some(value), revision: nextRevision, updatedAtUTC: now)
    }

    public func updatingPrivateCoachNote(_ value: ValidatedText?, now: Date) throws -> Session {
        try ensureCompleted()
        return replacing(privateCoachNote: .some(value), revision: nextRevision, updatedAtUTC: now)
    }

    public func updatingActionPrivateNote(exerciseID: StableUUID, note: ValidatedText?, now: Date) throws -> Session {
        try ensureCompleted()
        let (index, exercise) = try requireExercise(exerciseID)
        return replacingExercise(at: index, with: exercise.replacingActionPrivateNote(note), now: now)
    }

    public func updatingCompletedSummary(
        trainingFocus: ValidatedText?,
        privateCoachNote: ValidatedText?,
        studentFacingSummary: ValidatedText?,
        now: Date
    ) throws -> Session {
        try ensureCompleted()
        return replacing(
            trainingFocus: .some(trainingFocus),
            studentFacingSummary: .some(studentFacingSummary),
            privateCoachNote: .some(privateCoachNote),
            revision: nextRevision,
            updatedAtUTC: now
        )
    }

    public func editingCompletedSet(setID: StableUUID, input: TrainingSetInput, now: Date) throws -> Session {
        try ensureCompleted()
        let (index, exercise, source) = try requireSet(setID)
        let updated = try source.updating(input: input, now: now)
        let confirmed = try updated.confirmed(now: now)
        let sets = exercise.sets.map { $0.id == setID ? confirmed : $0 }
        return replacingExercise(at: index, with: exercise.replacingSets(sets), now: now)
    }
}
