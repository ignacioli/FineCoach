import Foundation

public enum ExerciseSourceKind: String, Codable, Sendable {
    case builtIn
    case custom
    case sessionOnly
}

public struct SessionExercise: Hashable, Codable, Sendable, Identifiable {
    public let id: StableUUID
    public let sessionID: StableUUID
    public let orderIndex: UInt32
    public let sourceKind: ExerciseSourceKind
    public let sourceID: StableExerciseID?
    public let displayNameSnapshot: NormalizedName
    public let recordModeSnapshot: RecordMode
    public let actionPrivateNote: ValidatedText?
    /// Optional `SessionSection` this Exercise belongs to (M1B-FR-020/021).
    /// `nil` means "unsectioned" -- it lives directly in the Session's flat,
    /// unified `orderIndex` axis alongside any Section headers. A blank
    /// Session defaults to entirely unsectioned Exercises; Sections are
    /// opt-in and never forced (data-model §2.7).
    public let sectionID: StableUUID?
    public let sets: [TrainingSet]

    public var hasCompletedSet: Bool {
        sets.contains(where: \.contributesToStatistics)
    }

    public init(
        id: StableUUID,
        sessionID: StableUUID,
        orderIndex: UInt32,
        sourceKind: ExerciseSourceKind,
        sourceID: StableExerciseID?,
        displayNameSnapshot: NormalizedName,
        recordModeSnapshot: RecordMode,
        actionPrivateNote: ValidatedText?,
        sectionID: StableUUID? = nil,
        sets: [TrainingSet]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.orderIndex = orderIndex
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.displayNameSnapshot = displayNameSnapshot
        self.recordModeSnapshot = recordModeSnapshot
        self.actionPrivateNote = actionPrivateNote
        self.sectionID = sectionID
        self.sets = sets
    }

    func relocating(orderIndex: UInt32) -> SessionExercise {
        SessionExercise(
            id: id,
            sessionID: sessionID,
            orderIndex: orderIndex,
            sourceKind: sourceKind,
            sourceID: sourceID,
            displayNameSnapshot: displayNameSnapshot,
            recordModeSnapshot: recordModeSnapshot,
            actionPrivateNote: actionPrivateNote,
            sectionID: sectionID,
            sets: sets.enumerated().map { offset, trainingSet in
                trainingSet.relocating(sessionExerciseID: id, orderIndex: UInt32(offset))
            }
        )
    }

    func relocating(orderIndex: UInt32, sectionID: StableUUID?) -> SessionExercise {
        SessionExercise(
            id: id,
            sessionID: sessionID,
            orderIndex: orderIndex,
            sourceKind: sourceKind,
            sourceID: sourceID,
            displayNameSnapshot: displayNameSnapshot,
            recordModeSnapshot: recordModeSnapshot,
            actionPrivateNote: actionPrivateNote,
            sectionID: sectionID,
            sets: sets.enumerated().map { offset, trainingSet in
                trainingSet.relocating(sessionExerciseID: id, orderIndex: UInt32(offset))
            }
        )
    }

    func replacingActionPrivateNote(_ note: ValidatedText?) -> SessionExercise {
        SessionExercise(
            id: id,
            sessionID: sessionID,
            orderIndex: orderIndex,
            sourceKind: sourceKind,
            sourceID: sourceID,
            displayNameSnapshot: displayNameSnapshot,
            recordModeSnapshot: recordModeSnapshot,
            actionPrivateNote: note,
            sectionID: sectionID,
            sets: sets
        )
    }

    func replacingSets(_ sets: [TrainingSet]) -> SessionExercise {
        SessionExercise(
            id: id,
            sessionID: sessionID,
            orderIndex: orderIndex,
            sourceKind: sourceKind,
            sourceID: sourceID,
            displayNameSnapshot: displayNameSnapshot,
            recordModeSnapshot: recordModeSnapshot,
            actionPrivateNote: actionPrivateNote,
            sectionID: sectionID,
            sets: sets.enumerated().map { offset, trainingSet in
                trainingSet.relocating(sessionExerciseID: id, orderIndex: UInt32(offset))
            }
        )
    }
}
