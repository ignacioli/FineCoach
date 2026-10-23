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
    public let trainingFocus: Set<BodyPart>
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
        trainingFocus: Set<BodyPart>,
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

    /// Newest-by-`completedAtUTC` session in `sessions`, independent of the
    /// array's fetch/insertion order. Shared by any UI (e.g.
    /// `StudentDetailView`'s "most recently completed training" preview)
    /// that needs "the latest one" rather than "whatever the repository
    /// happened to return first".
    public static func mostRecent(in sessions: [CompletedSession]) -> CompletedSession? {
        sessions.max { $0.completedAtUTC < $1.completedAtUTC }
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

/// Selects the most recently completed catalog exercises that are still
/// selectable in the current exercise list. The caller supplies the history
/// scope: a student id limits the result to that student's sessions, while
/// `nil` considers all completed sessions for the coach.
public enum RecentExerciseSelection {
    public static func entries(
        from sessions: [CompletedSession],
        studentID: StableUUID? = nil,
        availableEntries: [ExerciseLibraryEntry],
        limit: Int = 5
    ) -> [ExerciseLibraryEntry] {
        guard limit > 0 else { return [] }

        let availableByID = Dictionary(
            availableEntries.compactMap { entry -> (StableExerciseID, ExerciseLibraryEntry)? in
                guard entry.item.lifecycle == .active,
                    !entry.item.isRetired,
                    entry.preference?.isHidden != true
                else {
                    return nil
                }
                return (entry.id, entry)
            },
            uniquingKeysWith: { first, _ in first }
        )
        guard !availableByID.isEmpty else { return [] }

        let scopedSessions =
            sessions
            .filter { studentID == nil || $0.studentID == studentID }
            .sorted { $0.completedAtUTC > $1.completedAtUTC }
        var seen = Set<StableExerciseID>()
        var result: [ExerciseLibraryEntry] = []
        result.reserveCapacity(min(limit, availableByID.count))

        for session in scopedSessions {
            for exercise in session.exercises {
                guard exercise.sourceKind != .sessionOnly,
                    let sourceID = exercise.sourceID,
                    let entry = availableByID[sourceID],
                    seen.insert(sourceID).inserted
                else {
                    continue
                }
                result.append(entry)
                if result.count == limit {
                    return result
                }
            }
        }
        return result
    }
}
