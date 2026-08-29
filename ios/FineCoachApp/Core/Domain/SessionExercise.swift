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
            sets: sets.enumerated().map { offset, trainingSet in
                trainingSet.relocating(sessionExerciseID: id, orderIndex: UInt32(offset))
            }
        )
    }
}
