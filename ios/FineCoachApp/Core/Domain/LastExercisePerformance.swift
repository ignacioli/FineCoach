import Foundation

/// The completed sets the same Student did for an Exercise in their most
/// recent completed Session that contains it (experience P0-D1,
/// `design/experience-p0/implementation-map.md`). Derived, never persisted --
/// same stance as `Comparison`.
public struct LastExercisePerformance: Hashable, Sendable {
    public let sessionID: StableUUID
    public let completedAtUTC: Date
    /// Completed sets only, in recorded order; never empty.
    public let sets: [TrainingSet]

    public var firstSet: TrainingSet { sets[0] }

    /// P0-a / P0-b trailing caption: "上次 120 kg × 8 · 4 组". The first
    /// completed set uses the shared set summary; the count is every
    /// completed set in that session. Matching stays in the lookup.
    public var referenceText: String {
        String(
            format: String(localized: "session.lastReferenceFormat"),
            locale: Locale(identifier: "en_US_POSIX"),
            firstSet.displaySummary,
            sets.count
        )
    }
}

/// Indexes a Student's completed history once so the active Session can look
/// up "上次" per Exercise without reloading. Matching follows the trend view
/// (`Comparison`): same `sourceID` and record mode; an Exercise without a
/// `sourceID` (session-only) matches another session-only Exercise with the
/// same name and record mode.
public struct LastExercisePerformanceLookup: Sendable {
    private struct Key: Hashable, Sendable {
        let sourceID: StableExerciseID?
        let name: String?
        let recordMode: RecordMode
    }

    private let performances: [Key: LastExercisePerformance]

    public static let empty = LastExercisePerformanceLookup(sessions: [])

    public init(sessions: [CompletedSession]) {
        var performances: [Key: LastExercisePerformance] = [:]
        let newestFirst = sessions.sorted { $0.completedAtUTC > $1.completedAtUTC }
        for session in newestFirst {
            for exercise in session.exercises {
                let key = Self.key(for: exercise)
                guard performances[key] == nil else {
                    continue
                }
                let completed = exercise.sets.filter(\.contributesToStatistics)
                guard !completed.isEmpty else {
                    continue
                }
                performances[key] = LastExercisePerformance(
                    sessionID: session.id,
                    completedAtUTC: session.completedAtUTC,
                    sets: completed
                )
            }
        }
        self.performances = performances
    }

    public func performance(for exercise: SessionExercise) -> LastExercisePerformance? {
        performances[Self.key(for: exercise)]
    }

    private static func key(for exercise: SessionExercise) -> Key {
        if let sourceID = exercise.sourceID {
            return Key(sourceID: sourceID, name: nil, recordMode: exercise.recordModeSnapshot)
        }
        return Key(sourceID: nil, name: exercise.displayNameSnapshot.value, recordMode: exercise.recordModeSnapshot)
    }
}
