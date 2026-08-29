import Foundation

public struct SessionNotes: Hashable, Codable, Sendable {
    public let privateCoachNote: ValidatedText?
    public let studentFacingSummary: ValidatedText?
    public let actionPrivateNotes: [StableUUID: ValidatedText]

    public init(
        privateCoachNote: ValidatedText?,
        studentFacingSummary: ValidatedText?,
        actionPrivateNotes: [StableUUID: ValidatedText]
    ) {
        self.privateCoachNote = privateCoachNote
        self.studentFacingSummary = studentFacingSummary
        self.actionPrivateNotes = actionPrivateNotes
    }
}

public struct SessionStatistics: Hashable, Codable, Sendable {
    public let completedSetCount: Int
    public let displayedDurationSeconds: DecimalValue
    public let ordinaryTrainingVolume: DecimalValue?

    public init(
        completedSetCount: Int,
        displayedDurationSeconds: DecimalValue,
        ordinaryTrainingVolume: DecimalValue?
    ) {
        self.completedSetCount = completedSetCount
        self.displayedDurationSeconds = displayedDurationSeconds
        self.ordinaryTrainingVolume = ordinaryTrainingVolume
    }

    public static func make(from session: Session) throws -> SessionStatistics {
        var volume: DecimalValue?
        for trainingSet in session.statisticsSets {
            guard let contribution = try trainingSet.ordinaryVolumeContribution() else {
                continue
            }
            volume = try volume.map { try $0.adding(contribution) } ?? contribution
        }
        return SessionStatistics(
            completedSetCount: session.completedSetCount,
            displayedDurationSeconds: session.displayedDurationSeconds,
            ordinaryTrainingVolume: volume
        )
    }
}

public struct CompletedSession: Hashable, Codable, Sendable, Identifiable {
    public let id: StableUUID
    public let studentID: StableUUID
    public let studentDisplayName: NormalizedName
    public let startedAtUTC: Date
    public let completedAtUTC: Date
    public let trainingFocus: ValidatedText?
    public let notes: SessionNotes
    public let exercises: [SessionExercise]
    public let statistics: SessionStatistics
    public let revision: UInt64
    public let latestReport: ShareReport?

    public init(
        id: StableUUID,
        studentID: StableUUID,
        studentDisplayName: NormalizedName,
        startedAtUTC: Date,
        completedAtUTC: Date,
        trainingFocus: ValidatedText?,
        notes: SessionNotes,
        exercises: [SessionExercise],
        statistics: SessionStatistics,
        revision: UInt64,
        latestReport: ShareReport?
    ) {
        self.id = id
        self.studentID = studentID
        self.studentDisplayName = studentDisplayName
        self.startedAtUTC = startedAtUTC
        self.completedAtUTC = completedAtUTC
        self.trainingFocus = trainingFocus
        self.notes = notes
        self.exercises = exercises
        self.statistics = statistics
        self.revision = revision
        self.latestReport = latestReport
    }

    public static func make(from session: Session, studentDisplayName: NormalizedName) throws -> CompletedSession {
        guard session.state == .completed, let completedAtUTC = session.completedAtUTC else {
            throw DomainError.invalidState
        }
        return CompletedSession(
            id: session.id,
            studentID: session.studentID,
            studentDisplayName: studentDisplayName,
            startedAtUTC: session.startedAtUTC,
            completedAtUTC: completedAtUTC,
            trainingFocus: session.trainingFocus,
            notes: session.sessionNotes,
            exercises: session.exercises,
            statistics: session.statistics,
            revision: session.revision,
            latestReport: nil
        )
    }

    public func attaching(latestReport: ShareReport?) -> CompletedSession {
        CompletedSession(
            id: id,
            studentID: studentID,
            studentDisplayName: studentDisplayName,
            startedAtUTC: startedAtUTC,
            completedAtUTC: completedAtUTC,
            trainingFocus: trainingFocus,
            notes: notes,
            exercises: exercises,
            statistics: statistics,
            revision: revision,
            latestReport: latestReport
        )
    }
}
