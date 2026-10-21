import Foundation

/// Derived facts only. The baseline is scoped to the student and the current
/// session's position, so a later workout cannot rewrite an older report.
public struct SessionGains: Hashable, Sendable {
    public enum RecordKind: Hashable, Sendable {
        case mostRepsAtWeight, highestWeight, longestDuration, longestDistance
    }

    public struct Record: Hashable, Sendable {
        public let exerciseID: StableExerciseID
        public let displayName: String
        public let kind: RecordKind
        public let set: TrainingSet
    }

    public struct Progress: Hashable, Sendable {
        public let exerciseID: StableExerciseID
        public let displayName: String
        public let previous: TrainingSet
        public let current: TrainingSet
    }

    public let recordHolderSetIDs: Set<StableUUID>
    public let records: [Record]
    public let progress: [Progress]
    public let milestoneSessionNumber: Int?
    public var isEmpty: Bool { records.isEmpty && progress.isEmpty && milestoneSessionNumber == nil }
    public static let empty = SessionGains(
        recordHolderSetIDs: [], records: [], progress: [], milestoneSessionNumber: nil)

    private init(
        recordHolderSetIDs: Set<StableUUID>, records: [Record], progress: [Progress], milestoneSessionNumber: Int?
    ) {
        self.recordHolderSetIDs = recordHolderSetIDs
        self.records = records
        self.progress = progress
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
        let ordered = exercises.sorted { $0.orderIndex < $1.orderIndex }
        var seen = Set<Key>()
        var holders = Set<StableUUID>()
        var records: [Record] = []
        var progress: [Progress] = []
        for exercise in ordered {
            guard let sourceID = exercise.sourceID else { continue }
            let key = Key(id: sourceID, mode: exercise.recordModeSnapshot)
            guard seen.insert(key).inserted else { continue }
            let matching: (SessionExercise) -> Bool = {
                $0.sourceID == key.id && $0.recordModeSnapshot == key.mode
            }
            let historicalSets = baseline.flatMap(\.exercises).filter(matching).flatMap(\.sets)
                .filter(\.contributesToStatistics)
            guard !historicalSets.isEmpty else { continue }
            let currentSets = ordered.filter(matching).flatMap { $0.sets.sorted { $0.orderIndex < $1.orderIndex } }
                .filter(\.contributesToStatistics)
            let direction: Comparison.LoadDirection =
                assistedExerciseIDs.contains(sourceID) ? .decreaseIsImprovement : .increaseIsImprovement
            let baselineRecords = Comparison.personalRecords(
                exerciseID: sourceID, recordMode: key.mode, across: baseline, loadDirection: direction)
            var metricHolders: [RecordKind: TrainingSet] = [:]
            for kind in [RecordKind.mostRepsAtWeight, .highestWeight, .longestDuration, .longestDistance] {
                guard kind != .longestDistance || key.mode == .cardio else { continue }
                var best = bestSet(in: historicalSets, kind: kind, direction: direction)
                // A missing historical metric may be established only when the
                // compatible exercise already has statistical history.
                let hasMetric: Bool
                switch kind {
                case .mostRepsAtWeight: hasMetric = baselineRecords.mostRepsAtWeight != nil
                case .highestWeight: hasMetric = baselineRecords.highestWeight != nil
                case .longestDuration: hasMetric = baselineRecords.longestDuration != nil
                case .longestDistance: hasMetric = baselineRecords.longestDistance != nil
                }
                if !hasMetric { best = nil }
                for set in currentSets where hasValue(set, kind: kind) {
                    if best == nil || better(set, than: best!, kind: kind, direction: direction) {
                        best = set
                        metricHolders[kind] = set
                    }
                }
            }
            holders.formUnion(metricHolders.values.map(\.id))
            if let kind = [RecordKind.mostRepsAtWeight, .highestWeight, .longestDuration, .longestDistance]
                .first(where: { metricHolders[$0] != nil }), let set = metricHolders[kind]
            {
                records.append(
                    Record(exerciseID: sourceID, displayName: exercise.displayNameSnapshot.value, kind: kind, set: set))
                continue
            }
            let kind: RecordKind
            switch key.mode {
            case .reps: continue
            case .weightReps: kind = .mostRepsAtWeight
            case .duration: kind = .longestDuration
            case .cardio: kind = .longestDuration
            }
            let lastSets =
                baseline.reversed().compactMap { session -> [TrainingSet]? in
                    let sets = session.exercises.filter(matching).flatMap(\.sets).filter(\.contributesToStatistics)
                    return sets.isEmpty ? nil : sets
                }.first ?? []
            if let previous = bestSet(in: lastSets, kind: kind, direction: direction),
                let current = bestSet(in: currentSets, kind: kind, direction: direction),
                better(current, than: previous, kind: kind, direction: direction)
            {
                progress.append(
                    Progress(
                        exerciseID: sourceID, displayName: exercise.displayNameSnapshot.value, previous: previous,
                        current: current))
            }
        }
        let number = baseline.count + 1
        let milestone = [10, 25, 50, 100].contains(number) || (number > 100 && number % 50 == 0)
        return SessionGains(
            recordHolderSetIDs: holders, records: records, progress: progress,
            milestoneSessionNumber: milestone ? number : nil)
    }

    private static func hasValue(_ set: TrainingSet, kind: RecordKind) -> Bool {
        switch kind {
        case .mostRepsAtWeight: return set.weightValue != nil && set.repetitionCount != nil
        case .highestWeight: return set.weightValue != nil
        case .longestDuration: return set.durationSeconds != nil
        case .longestDistance: return set.distanceValue != nil
        }
    }

    private static func bestSet(in sets: [TrainingSet], kind: RecordKind, direction: Comparison.LoadDirection)
        -> TrainingSet?
    {
        sets.filter { hasValue($0, kind: kind) }.reduce(nil) { best, candidate in
            guard let best else { return candidate }
            return better(candidate, than: best, kind: kind, direction: direction) ? candidate : best
        }
    }

    private static func better(
        _ candidate: TrainingSet, than current: TrainingSet, kind: RecordKind, direction: Comparison.LoadDirection
    ) -> Bool {
        switch kind {
        case .mostRepsAtWeight:
            return Comparison.isStrictlyBetter(
                weight: candidate.weightValue!, reps: candidate.repetitionCount!, thanWeight: current.weightValue!,
                reps: current.repetitionCount!, direction: direction)
        case .highestWeight:
            return Comparison.isStrictlyBetter(candidate.weightValue!, than: current.weightValue!, direction: direction)
        case .longestDuration:
            return Comparison.isStrictlyBetter(candidate.durationSeconds!, than: current.durationSeconds!)
        case .longestDistance:
            return Comparison.isStrictlyBetter(candidate.distanceValue!, than: current.distanceValue!)
        }
    }
}
