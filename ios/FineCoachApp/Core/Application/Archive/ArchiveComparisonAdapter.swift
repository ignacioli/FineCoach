import CryptoKit
import Foundation

// T045: maps archive sessions onto the inputs `Comparison` already accepts, so the viewer's
// trends and personal records come from the same code as the Coach side (D-009, M1B-FR-028/029)
// without changing it. Pure value mapping: no store, no Coach data.
//
// Identity: every ID is derived deterministically from an archive-local key (`e1`, `s1`, ...)
// with SHA-256, so the same archive always maps to the same IDs and no Coach-side ID can appear
// (D-M2-004). The reverse maps let the UI turn a result's `StableUUID` back into a session key.

public struct ArchiveComparisonAdapter: Sendable {
    private let exercisesByKey: [String: ArchiveExercise]
    private let sessions: [ArchiveSession]
    private let sessionKeysByID: [StableUUID: String]

    public init(snapshot: ArchiveSnapshot) {
        self.exercisesByKey = Dictionary(uniqueKeysWithValues: snapshot.exercises.map { ($0.key, $0) })
        self.sessions = snapshot.sessions
        self.sessionKeysByID = Dictionary(
            uniqueKeysWithValues: snapshot.sessions.map { (Self.sessionID(forKey: $0.key), $0.key) }
        )
    }

    // MARK: Identity

    /// `StableExerciseID` for an archive exercise key. Contains only the archive-local key.
    public static func exerciseID(forKey key: String) -> StableExerciseID {
        // A non-empty key of at most 64 KiB always yields a valid ID.
        StableExerciseID(rawValue: "archive.exercise.\(key)")!
    }

    public static func sessionID(forKey key: String) -> StableUUID {
        derivedUUID("session/\(key)")
    }

    /// The archive session key behind a `StableUUID` that came out of a trend or record.
    public func sessionKey(for id: StableUUID) -> String? {
        sessionKeysByID[id]
    }

    private static func derivedUUID(_ seed: String) -> StableUUID {
        let digest = Array(SHA256.hash(data: Data("fcpa.v1/\(seed)".utf8)))
        let bytes = Array(digest.prefix(16))
        return StableUUID(
            UUID(
                uuid: (
                    bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                    bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
                )
            )
        )
    }

    // MARK: Direction

    /// An assisted exercise improves as the load goes down (M1B-FR-028, spec Revision 1.1.2).
    /// Unknown keys use the ordinary direction.
    public func loadDirection(forExerciseKey key: String) -> Comparison.LoadDirection {
        exercisesByKey[key]?.isAssisted == true ? .decreaseIsImprovement : .increaseIsImprovement
    }

    // MARK: Mapping

    /// The archive's sessions as `CompletedSession`s. With `exerciseKeys` only those exercises
    /// are kept, which is all `Comparison` looks at and avoids mapping every set of a large
    /// archive for one chart.
    public func completedSessions(exerciseKeys: Set<String>? = nil) -> [CompletedSession] {
        sessions.compactMap { Self.map($0, exerciseKeys: exerciseKeys) }
    }

    private static func map(_ session: ArchiveSession, exerciseKeys: Set<String>?) -> CompletedSession? {
        let sessionID = Self.sessionID(forKey: session.key)
        var mapped: [SessionExercise] = []
        var order: UInt32 = 0
        for (sectionIndex, section) in session.sections.enumerated() {
            for (entryIndex, entry) in section.exercises.enumerated() {
                defer { order += 1 }
                if let exerciseKeys, !exerciseKeys.contains(entry.exerciseKey) {
                    continue
                }
                let entryID = derivedUUID("entry/\(session.key)/\(sectionIndex)/\(entryIndex)")
                let sets = entry.sets.enumerated().map { setIndex, set in
                    TrainingSet(
                        id: derivedUUID("set/\(session.key)/\(sectionIndex)/\(entryIndex)/\(setIndex)"),
                        sessionExerciseID: entryID,
                        orderIndex: UInt32(setIndex),
                        state: .completed,
                        recordMode: entry.recordMode,
                        weightValue: set.weightValue,
                        repetitionCount: set.repetitionCount,
                        durationSeconds: set.durationSeconds,
                        unit: set.unit,
                        side: set.side,
                        leftValue: set.leftValue,
                        rightValue: set.rightValue,
                        distanceValue: set.distanceValue,
                        speedValue: set.speedValue,
                        resistanceValue: set.resistanceValue,
                        createdAtUTC: session.completedAtUTC,
                        updatedAtUTC: session.completedAtUTC,
                        completedAtUTC: session.completedAtUTC
                    )
                }
                guard let name = try? NormalizedName(entry.exerciseKey) else {
                    continue
                }
                mapped.append(
                    SessionExercise(
                        id: entryID,
                        sessionID: sessionID,
                        orderIndex: order,
                        sourceKind: .custom,
                        sourceID: exerciseID(forKey: entry.exerciseKey),
                        displayNameSnapshot: name,
                        recordModeSnapshot: entry.recordMode,
                        actionPrivateNote: nil,
                        sets: sets
                    )
                )
            }
        }
        guard let placeholderName = try? NormalizedName("archive"),
            let duration = try? DecimalValue(String(max(0, session.durationMinutes) * 60))
        else {
            return nil
        }
        return CompletedSession(
            id: sessionID,
            studentID: derivedUUID("student"),
            studentDisplayName: placeholderName,
            startedAtUTC: session.completedAtUTC.addingTimeInterval(-Double(session.durationMinutes) * 60),
            completedAtUTC: session.completedAtUTC,
            trainingFocus: session.trainingFocus,
            notes: SessionNotes(privateCoachNote: nil, studentFacingSummary: nil, actionPrivateNotes: [:]),
            exercises: mapped,
            statistics: SessionStatistics(
                completedSetCount: mapped.reduce(0) { $0 + $1.sets.count },
                displayedDurationSeconds: duration,
                ordinaryTrainingVolume: nil
            ),
            revision: 0,
            latestReport: nil
        )
    }

    // MARK: Comparison

    /// `Comparison.exerciseTrend` over the archive's own sessions only.
    public func trend(forExerciseKey key: String, recordMode: RecordMode) -> [Comparison.SetTrendPoint] {
        Comparison.exerciseTrend(
            exerciseID: Self.exerciseID(forKey: key),
            recordMode: recordMode,
            across: completedSessions(exerciseKeys: [key]),
            loadDirection: loadDirection(forExerciseKey: key)
        )
    }

    /// `Comparison.personalRecords` over the archive's own sessions only.
    public func personalRecords(forExerciseKey key: String, recordMode: RecordMode) -> Comparison.PersonalRecordSet {
        Comparison.personalRecords(
            exerciseID: Self.exerciseID(forKey: key),
            recordMode: recordMode,
            across: completedSessions(exerciseKeys: [key]),
            loadDirection: loadDirection(forExerciseKey: key)
        )
    }
}
