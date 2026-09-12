import Foundation

/// Pure, derived-view computations over already-persisted `CompletedSession`/
/// `SessionExercise`/`TrainingSet` (data-model §2.10, M1B-FR-027/028/029).
/// Nothing in this file is persisted -- every function recomputes its answer
/// live from whatever Sessions/Sets are passed in. There is deliberately no
/// caching type, no "TrendMO", no stored comparison/PR object anywhere.
public enum Comparison {

    // MARK: - Session-level comparison (M1B-FR-027, D-007)

    public enum SessionComparisonResult: Sendable {
        case compatible(SessionComparisonDetail)
        /// `trainingFocus` differs in a way that makes the two Sessions
        /// incompatible for comparison (one nil/empty + one non-empty, or two
        /// different non-empty values). The two Sessions MUST be shown
        /// separately -- never force-merged into one combined view.
        case incompatibleTrainingFocus
        case differentStudent
    }

    public struct SessionComparisonDetail: Sendable {
        public let sessionA: StableUUID
        public let sessionB: StableUUID
        /// Exercises present in A by `sourceID`/name but absent from B, and
        /// vice versa.
        public let exercisesOnlyInA: [NormalizedName]
        public let exercisesOnlyInB: [NormalizedName]
        public let totalSetCountA: Int
        public let totalSetCountB: Int
        public let totalRepCountA: DecimalValue?
        public let totalRepCountB: DecimalValue?
        public let totalDurationSecondsA: DecimalValue
        public let totalDurationSecondsB: DecimalValue
        public let trainingVolumeA: DecimalValue?
        public let trainingVolumeB: DecimalValue?
    }

    /// Focus is "exactly equal" per M1B-FR-027/D-007: both nil/empty counts as
    /// mutually compatible; one empty + one non-empty is INCOMPATIBLE.
    private static func focusEqual(_ a: ValidatedText?, _ b: ValidatedText?) -> Bool {
        let aEmpty = a == nil || a?.isEmpty == true
        let bEmpty = b == nil || b?.isEmpty == true
        if aEmpty && bEmpty {
            return true
        }
        if aEmpty != bEmpty {
            return false
        }
        return a?.value == b?.value
    }

    public static func compareSessions(_ a: CompletedSession, _ b: CompletedSession) -> SessionComparisonResult {
        guard a.studentID == b.studentID else {
            return .differentStudent
        }
        guard focusEqual(a.trainingFocus, b.trainingFocus) else {
            return .incompatibleTrainingFocus
        }

        let namesA = Set(a.exercises.map(\.displayNameSnapshot.value))
        let namesB = Set(b.exercises.map(\.displayNameSnapshot.value))
        let onlyA = namesA.subtracting(namesB).sorted()
        let onlyB = namesB.subtracting(namesA).sorted()

        func totals(_ session: CompletedSession) -> (sets: Int, reps: DecimalValue?, duration: DecimalValue) {
            var repTotal: DecimalValue?
            var setCount = 0
            for exercise in session.exercises {
                for set in exercise.sets where set.contributesToStatistics {
                    setCount += 1
                    if let reps = set.repetitionCount {
                        repTotal = (try? repTotal?.adding(reps)) ?? repTotal ?? reps
                    }
                }
            }
            return (setCount, repTotal, session.statistics.displayedDurationSeconds)
        }

        let totalsA = totals(a)
        let totalsB = totals(b)

        return .compatible(
            SessionComparisonDetail(
                sessionA: a.id,
                sessionB: b.id,
                exercisesOnlyInA: onlyA.compactMap { try? NormalizedName($0) },
                exercisesOnlyInB: onlyB.compactMap { try? NormalizedName($0) },
                totalSetCountA: totalsA.sets,
                totalSetCountB: totalsB.sets,
                totalRepCountA: totalsA.reps,
                totalRepCountB: totalsB.reps,
                totalDurationSecondsA: totalsA.duration,
                totalDurationSecondsB: totalsB.duration,
                trainingVolumeA: a.statistics.ordinaryTrainingVolume,
                trainingVolumeB: b.statistics.ordinaryTrainingVolume
            )
        )
    }

    // MARK: - Exercise-level trend (M1B-FR-028)

    /// Whether an INCREASE or a DECREASE in `weightValue` represents progress
    /// for a given exercise lineage. Ordinary external load (barbell, dumbbell,
    /// machine stack) is `.increaseIsImprovement`; assisted-load machines
    /// (e.g. an assisted pull-up's counterweight) are `.decreaseIsImprovement`.
    /// The Domain has no persisted "is this exercise assisted" flag today, so
    /// callers (Application/UI) MUST supply this explicitly per exercise --
    /// this function never infers it from the exercise name or any other
    /// heuristic. The two directions are represented as DISTINCT enum cases
    /// specifically so a caller can never average or combine them into one
    /// number by accident.
    public enum LoadDirection: Sendable {
        case increaseIsImprovement
        case decreaseIsImprovement
    }

    public struct SetTrendPoint: Sendable {
        public let sessionID: StableUUID
        public let completedAtUTC: Date
        public let recordMode: RecordMode
        public let maxWeight: DecimalValue?
        public let bestReps: DecimalValue?
        public let bestDurationSeconds: DecimalValue?
        public let bestDistance: DecimalValue?
        public let volume: DecimalValue?
        /// Positive = the plain numeric value increased vs the previous point
        /// in the series (direction-agnostic; UI applies `LoadDirection` to
        /// decide if that increase is progress or regression).
        public let weightDelta: DecimalValue?
        /// Left/right imbalance for this point, `nil` when the exercise/sets
        /// aren't sided. Always its own field -- never folded into `volume`.
        public let asymmetry: DecimalValue?
    }

    /// Only Sessions for the SAME Student, filtered to `SessionExercise`s
    /// matching `exerciseID` AND the same record-mode family (compatibility
    /// rule shared with PR, below). `sessions` need not be pre-sorted.
    public static func exerciseTrend(
        exerciseID: StableExerciseID,
        recordMode: RecordMode,
        across sessions: [CompletedSession]
    ) -> [SetTrendPoint] {
        let ordered = sessions.sorted { $0.completedAtUTC < $1.completedAtUTC }
        var points: [SetTrendPoint] = []
        var previousWeight: DecimalValue?

        for session in ordered {
            let matching = session.exercises.filter { $0.sourceID == exerciseID && $0.recordModeSnapshot == recordMode }
            guard !matching.isEmpty else { continue }
            let completedSets = matching.flatMap(\.sets).filter(\.contributesToStatistics)
            guard !completedSets.isEmpty else { continue }

            let maxWeight = completedSets.compactMap(\.weightValue).max()
            let bestReps = completedSets.compactMap(\.repetitionCount).max()
            let bestDuration = completedSets.compactMap(\.durationSeconds).max()
            let bestDistance = completedSets.compactMap(\.distanceValue).max()

            var volume: DecimalValue?
            for set in completedSets {
                guard let contribution = (try? set.ordinaryVolumeContribution()) ?? nil else { continue }
                volume = (try? volume?.adding(contribution)) ?? volume ?? contribution
            }

            var asymmetry: DecimalValue?
            let sided = completedSets.filter { $0.leftValue != nil && $0.rightValue != nil }
            if let firstSided = sided.first, let left = firstSided.leftValue, let right = firstSided.rightValue {
                let diff = NSDecimalNumber(decimal: left.decimal).subtracting(NSDecimalNumber(decimal: right.decimal))
                asymmetry = try? DecimalValue(diff.stringValue)
            }

            var delta: DecimalValue?
            if let maxWeight, let previousWeight {
                let diff = NSDecimalNumber(decimal: maxWeight.decimal)
                    .subtracting(NSDecimalNumber(decimal: previousWeight.decimal))
                delta = try? DecimalValue(diff.stringValue)
            }
            if let maxWeight {
                previousWeight = maxWeight
            }

            points.append(
                SetTrendPoint(
                    sessionID: session.id,
                    completedAtUTC: session.completedAtUTC,
                    recordMode: recordMode,
                    maxWeight: maxWeight,
                    bestReps: bestReps,
                    bestDurationSeconds: bestDuration,
                    bestDistance: bestDistance,
                    volume: volume,
                    weightDelta: delta,
                    asymmetry: asymmetry
                )
            )
        }
        return points
    }

    // MARK: - Personal Record (M1B-FR-029)

    /// ONLY these three explicit rules. There is INTENTIONALLY no estimated
    /// 1RM and no composite/aggregate "strength score" anywhere in this
    /// file -- that is a hard prohibition from the spec, not a placeholder
    /// for future work. Do not add one.
    public struct PersonalRecordSet: Sendable {
        public let exerciseID: StableExerciseID
        public let highestWeight: (sessionID: StableUUID, weight: DecimalValue)?
        /// Most reps recorded AT the same weight as `highestWeight` -- i.e.
        /// "most reps at a given load", not reps in isolation.
        public let mostRepsAtWeight: (sessionID: StableUUID, weight: DecimalValue, reps: DecimalValue)?
        public let longestDuration: (sessionID: StableUUID, seconds: DecimalValue)?
        public let longestDistance: (sessionID: StableUUID, distance: DecimalValue)?
    }

    /// Compatibility = same Student (Sessions already filtered to one Student
    /// by the caller) + same `StableExerciseID` + same record-mode family.
    public static func personalRecords(
        exerciseID: StableExerciseID,
        recordMode: RecordMode,
        across sessions: [CompletedSession]
    ) -> PersonalRecordSet {
        var highestWeight: (StableUUID, DecimalValue)?
        var mostRepsAtWeight: (StableUUID, DecimalValue, DecimalValue)?
        var longestDuration: (StableUUID, DecimalValue)?
        var longestDistance: (StableUUID, DecimalValue)?

        for session in sessions {
            let matching = session.exercises.filter { $0.sourceID == exerciseID && $0.recordModeSnapshot == recordMode }
            for exercise in matching {
                for set in exercise.sets where set.contributesToStatistics {
                    if let weight = set.weightValue {
                        if highestWeight == nil || weight > highestWeight!.1 {
                            highestWeight = (session.id, weight)
                        }
                        if let reps = set.repetitionCount {
                            if mostRepsAtWeight == nil || weight > mostRepsAtWeight!.1
                                || (weight == mostRepsAtWeight!.1 && reps > mostRepsAtWeight!.2)
                            {
                                mostRepsAtWeight = (session.id, weight, reps)
                            }
                        }
                    }
                    if let duration = set.durationSeconds {
                        if longestDuration == nil || duration > longestDuration!.1 {
                            longestDuration = (session.id, duration)
                        }
                    }
                    if recordMode == .cardio, let distance = set.distanceValue {
                        if longestDistance == nil || distance > longestDistance!.1 {
                            longestDistance = (session.id, distance)
                        }
                    }
                }
            }
        }

        return PersonalRecordSet(
            exerciseID: exerciseID,
            highestWeight: highestWeight,
            mostRepsAtWeight: mostRepsAtWeight,
            longestDuration: longestDuration,
            longestDistance: longestDistance
        )
    }
}
