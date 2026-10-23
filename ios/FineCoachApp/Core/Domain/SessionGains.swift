import Foundation

/// Derived facts only. The baseline is scoped to the student and the current
/// session's position, so a later workout cannot rewrite an older report.
///
/// Spec 004 Revision 1.5 (README §10 C16): a new record is judged on the ONE
/// main metric of each record mode -- weight (strictly heavier; strictly
/// lighter for an assisted exercise), duration, or repetitions. Extra reps at
/// the same weight, a higher single-set volume, and an estimated 1RM are not
/// records. "比上次进步" compares each session's best set and is independent of
/// the record result: a record action can also be progress, and vice versa.
public struct SessionGains: Hashable, Sendable {
    public enum RecordKind: Hashable, Sendable {
        /// `weightReps`: the heaviest weight for an ordinary exercise, the
        /// lightest for an assisted one (M1B-FR-028).
        case highestWeight
        case longestDuration
        /// `reps`: strictly more repetitions (Revision 1.5).
        case mostReps

        /// The display-order kind for a record mode (Revision 1.5, D-FR-001).
        public static func mainMetric(for mode: RecordMode) -> RecordKind {
            switch mode {
            case .weightReps: return .highestWeight
            case .duration, .cardio: return .longestDuration
            case .reps: return .mostReps
            }
        }
    }

    public struct Record: Hashable, Sendable {
        public let exerciseID: StableExerciseID
        public let displayName: String
        public let kind: RecordKind
        /// The one set that holds this action's record (D-FR-013).
        public let set: TrainingSet
    }

    /// One "上次 … → 本次 …" action row (D-FR-022). Every row is one action;
    /// `isNewRecord` marks the actions that also set a record in this session.
    public struct GainRow: Hashable, Sendable {
        public let exerciseID: StableExerciseID
        public let displayName: String
        public let isNewRecord: Bool
        public let previous: TrainingSet
        public let current: TrainingSet
    }

    /// Every record holder this session, at most one set per action (D-FR-013).
    public let recordHolderSetIDs: Set<StableUUID>
    /// The subset of `recordHolderSetIDs` whose main metric is also strictly
    /// better than every earlier set of this session. Only these sets give the
    /// new-record haptic; a same-weight-more-reps transfer keeps `.success`.
    public let strictRecordHolderSetIDs: Set<StableUUID>
    public let records: [Record]
    /// Action rows in the order the exercises appear in this session.
    public let rows: [GainRow]
    public let milestoneSessionNumber: Int?

    /// 比上次进步 rows: actions that improved without setting a record, so the
    /// share hint never counts an action twice (D-FR-031).
    public var progress: [GainRow] { rows.filter { !$0.isNewRecord } }

    public var isEmpty: Bool { rows.isEmpty && milestoneSessionNumber == nil }

    public static let empty = SessionGains(
        recordHolderSetIDs: [], strictRecordHolderSetIDs: [], records: [], rows: [], milestoneSessionNumber: nil)

    private init(
        recordHolderSetIDs: Set<StableUUID>, strictRecordHolderSetIDs: Set<StableUUID>, records: [Record],
        rows: [GainRow], milestoneSessionNumber: Int?
    ) {
        self.recordHolderSetIDs = recordHolderSetIDs
        self.strictRecordHolderSetIDs = strictRecordHolderSetIDs
        self.records = records
        self.rows = rows
        self.milestoneSessionNumber = milestoneSessionNumber
    }

    public init(current: CompletedSession, history: [CompletedSession], assistedExerciseIDs: Set<StableExerciseID> = [])
    {
        self = Self.evaluate(
            id: current.id, studentID: current.studentID, at: current.completedAtUTC,
            exercises: current.exercises, history: history, assistedExerciseIDs: assistedExerciseIDs)
    }

    public init(current: Session, history: [CompletedSession], assistedExerciseIDs: Set<StableExerciseID> = []) {
        self = Self.evaluate(
            id: current.id, studentID: current.studentID, at: current.completedAtUTC ?? .distantFuture,
            exercises: current.exercises, history: history, assistedExerciseIDs: assistedExerciseIDs)
    }

    private struct Key: Hashable {
        let id: StableExerciseID
        let mode: RecordMode
    }

    private static func evaluate(
        id: StableUUID, studentID: StableUUID, at date: Date, exercises: [SessionExercise],
        history: [CompletedSession], assistedExerciseIDs: Set<StableExerciseID>
    ) -> SessionGains {
        let baseline = history.filter {
            $0.studentID == studentID && $0.id != id
                && ($0.completedAtUTC < date
                    || ($0.completedAtUTC == date && $0.id.rawValue.uuidString < id.rawValue.uuidString))
        }.sorted {
            if $0.completedAtUTC != $1.completedAtUTC { return $0.completedAtUTC < $1.completedAtUTC }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
        // Same "上次" rule as the active session (experience P0-D1): the most
        // recent baseline Session that contains statistical sets for the action,
        // using the baseline's (completedAtUTC, id) order for equal times.
        let ordered = exercises.sorted { $0.orderIndex < $1.orderIndex }
        var seen = Set<Key>()
        var holders = Set<StableUUID>()
        var strictHolders = Set<StableUUID>()
        var records: [Record] = []
        var rows: [GainRow] = []
        for exercise in ordered {
            guard let sourceID = exercise.sourceID else { continue }
            let key = Key(id: sourceID, mode: exercise.recordModeSnapshot)
            guard seen.insert(key).inserted else { continue }
            let kind = RecordKind.mainMetric(for: key.mode)
            let direction: Comparison.LoadDirection =
                assistedExerciseIDs.contains(sourceID) ? .decreaseIsImprovement : .increaseIsImprovement
            let matching: (SessionExercise) -> Bool = {
                $0.sourceID == key.id && $0.recordModeSnapshot == key.mode
            }
            let historicalSets = baseline.flatMap(\.exercises).filter(matching).flatMap(\.sets)
                .filter(\.contributesToStatistics)
            // "第一次做": no compatible statistical set before this session. It
            // is a baseline, never a record and never a progress row (D-FR-002).
            guard !historicalSets.isEmpty else { continue }
            let currentSets = ordered.filter(matching).flatMap(\.sets).sorted { $0.orderIndex < $1.orderIndex }
                .filter(\.contributesToStatistics)
            guard let current = bestSet(in: currentSets, kind: kind, direction: direction) else { continue }

            let historicalMetric = bestMetricValue(in: historicalSets, kind: kind, direction: direction)
            let isNewRecord: Bool
            if let historicalMetric, let value = metricValue(current, kind: kind),
                isBetter(value, than: historicalMetric, kind: kind, direction: direction)
            {
                isNewRecord = true
                holders.insert(current.id)
                if isStrictHolder(current, in: currentSets, kind: kind, direction: direction) {
                    strictHolders.insert(current.id)
                }
                records.append(
                    Record(
                        exerciseID: sourceID, displayName: exercise.displayNameSnapshot.value, kind: kind,
                        set: current))
            } else {
                isNewRecord = false
            }

            let previousSets =
                baseline.reversed().compactMap { session -> [TrainingSet]? in
                    let sets = session.exercises.filter(matching).flatMap(\.sets).filter(\.contributesToStatistics)
                    return sets.isEmpty ? nil : sets
                }.first
            guard let previousSets,
                let previous = bestSet(in: previousSets, kind: kind, direction: direction)
            else { continue }
            let isProgress = improved(previous, current, kind: kind, direction: direction)
            guard isNewRecord || isProgress else { continue }
            rows.append(
                GainRow(
                    exerciseID: sourceID, displayName: exercise.displayNameSnapshot.value, isNewRecord: isNewRecord,
                    previous: previous, current: current))
        }
        let number = baseline.count + 1
        let milestone = [10, 25, 50, 100].contains(number) || (number > 100 && number % 50 == 0)
        return SessionGains(
            recordHolderSetIDs: holders, strictRecordHolderSetIDs: strictHolders, records: records, rows: rows,
            milestoneSessionNumber: milestone ? number : nil)
    }

    /// The main metric value, or `nil` when this set does not record it.
    private static func metricValue(_ set: TrainingSet, kind: RecordKind) -> DecimalValue? {
        switch kind {
        case .highestWeight: return set.weightValue
        case .longestDuration: return set.durationSeconds
        case .mostReps: return set.repetitionCount
        }
    }

    /// Strictly better on the main metric alone (Revision 1.5: reps never make
    /// a heavier weight a new record, and vice versa).
    private static func isBetter(
        _ candidate: DecimalValue, than current: DecimalValue, kind: RecordKind, direction: Comparison.LoadDirection
    ) -> Bool {
        switch kind {
        case .highestWeight:
            return Comparison.isStrictlyBetter(candidate, than: current, direction: direction)
        case .longestDuration, .mostReps:
            return candidate > current
        }
    }

    private static func bestMetricValue(
        in sets: [TrainingSet], kind: RecordKind, direction: Comparison.LoadDirection
    ) -> DecimalValue? {
        var best: DecimalValue?
        for set in sets {
            guard let value = metricValue(set, kind: kind) else { continue }
            if best == nil || isBetter(value, than: best!, kind: kind, direction: direction) {
                best = value
            }
        }
        return best
    }

    /// The best set of a session (D-FR-013/D-FR-022): heaviest, then most reps;
    /// assisted exercises reverse the weight direction; duration and reps take
    /// the largest main metric. Equality keeps the earlier set.
    private static func bestSet(
        in sets: [TrainingSet], kind: RecordKind, direction: Comparison.LoadDirection
    ) -> TrainingSet? {
        var best: TrainingSet?
        for candidate in sets {
            guard metricValue(candidate, kind: kind) != nil else { continue }
            guard let currentBest = best else {
                best = candidate
                continue
            }
            if better(candidate, than: currentBest, kind: kind, direction: direction) {
                best = candidate
            }
        }
        return best
    }

    private static func better(
        _ candidate: TrainingSet, than current: TrainingSet, kind: RecordKind, direction: Comparison.LoadDirection
    ) -> Bool {
        guard let candidateValue = metricValue(candidate, kind: kind),
            let currentValue = metricValue(current, kind: kind)
        else { return false }
        if isBetter(candidateValue, than: currentValue, kind: kind, direction: direction) { return true }
        guard kind == .highestWeight, candidateValue == currentValue else { return false }
        // Same weight: the set with more reps is the better set (D-FR-013).
        // This tie-break never makes a new record on its own.
        return (candidate.repetitionCount ?? DecimalValue.zero)
            > (current.repetitionCount ?? DecimalValue.zero)
    }

    /// Whether `candidate` is the holder AND its main metric is strictly better
    /// than every other recorded set of this session (D-FR-013, Revision 1.5).
    /// Comparing against every other set -- not only lower order indices -- also
    /// covers confirming an earlier pending row after a later one.
    private static func isStrictHolder(
        _ candidate: TrainingSet, in sets: [TrainingSet], kind: RecordKind, direction: Comparison.LoadDirection
    ) -> Bool {
        guard let value = metricValue(candidate, kind: kind) else { return false }
        return sets.allSatisfy { other in
            guard other.id != candidate.id else { return true }
            guard let otherValue = metricValue(other, kind: kind) else { return true }
            return isBetter(value, than: otherValue, kind: kind, direction: direction)
        }
    }

    /// 比上次进步 (D-FR-022): weight modes compare weight AND reps -- one better
    /// with the other not worse; duration/reps compare the main metric only.
    private static func improved(
        _ previous: TrainingSet, _ current: TrainingSet, kind: RecordKind, direction: Comparison.LoadDirection
    ) -> Bool {
        switch kind {
        case .highestWeight:
            guard let previousWeight = previous.weightValue, let currentWeight = current.weightValue else {
                return false
            }
            let weightBetter = Comparison.isStrictlyBetter(
                currentWeight, than: previousWeight, direction: direction)
            let weightWorse = Comparison.isStrictlyBetter(
                previousWeight, than: currentWeight, direction: direction)
            let previousReps = previous.repetitionCount ?? DecimalValue.zero
            let currentReps = current.repetitionCount ?? DecimalValue.zero
            return (weightBetter && currentReps >= previousReps) || (currentReps > previousReps && !weightWorse)
        case .longestDuration, .mostReps:
            guard let previousValue = metricValue(previous, kind: kind),
                let currentValue = metricValue(current, kind: kind)
            else { return false }
            return isBetter(currentValue, than: previousValue, kind: kind, direction: direction)
        }
    }
}
