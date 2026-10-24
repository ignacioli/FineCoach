import Foundation

public struct Insight: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case packageExhausted, packageExpired, packageLow, inactive, stagnant
    }

    public enum Metric: Hashable, Sendable {
        case estimatedOneRepMax, highestWeight, lowestAssistance, mostReps, longestDuration
    }

    public let kind: Kind
    public let studentID: StableUUID
    public var exerciseID: StableExerciseID? = nil
    public var balance: Int? = nil
    public var packageEndDate: LocalDate? = nil
    public var daysUntilExpiry: Int? = nil
    public var daysInactive: Int? = nil
    public var hasNeverTrained: Bool = false
    public var stagnantSessionCount: Int? = nil
    public var baselineBest: DecimalValue? = nil
    public var baselineMetric: Metric? = nil

    public var snoozeKey: String {
        let group: String
        switch kind {
        case .packageExhausted, .packageExpired, .packageLow: group = "package"
        case .inactive: group = "inactive"
        case .stagnant: group = "stagnant"
        }
        return group + ":" + studentID.rawValue.uuidString
            + (exerciseID.map { ":" + $0.rawValue } ?? "")
    }

    public var id: String { snoozeKey }
}

public enum InsightEngine {
    public struct PackageBalance: Sendable {
        public let package: CoursePackage
        public let balance: Int

        public init(package: CoursePackage, balance: Int) {
            self.package = package
            self.balance = balance
        }
    }

    public struct Input: Sendable {
        public var students: [Student]
        public var packages: [StableUUID: PackageBalance]
        public var appointments: [Appointment]
        public var history: [CompletedSession]
        public var snoozedKeys: Set<String>
        public var assistedExerciseIDs: Set<StableExerciseID>

        public init(
            students: [Student], packages: [StableUUID: PackageBalance] = [:], appointments: [Appointment] = [],
            history: [CompletedSession] = [], snoozedKeys: Set<String> = [],
            assistedExerciseIDs: Set<StableExerciseID> = []
        ) {
            self.students = students
            self.packages = packages
            self.appointments = appointments
            self.history = history
            self.snoozedKeys = snoozedKeys
            self.assistedExerciseIDs = assistedExerciseIDs
        }
    }

    public static func evaluate(input: Input, now: Date, calendar: Calendar) -> [Insight] {
        let today = LocalDate(date: now, calendar: calendar)
        let history = Dictionary(grouping: input.history, by: \.studentID)
        let booked = Set(
            input.appointments.filter { $0.status == .scheduled && $0.startInstant(calendar: calendar) > now }
                .map(\.studentID))
        var result: [Insight] = []
        for student in input.students where student.lifecycle == .active {
            if let item = input.packages[student.id] {
                let days = item.package.endDate.map { $0.daysSince(today, calendar: calendar) }
                let kind: Insight.Kind?
                if item.balance <= 0 {
                    kind = .packageExhausted
                } else if item.package.isExpired(asOf: today) {
                    kind = .packageExpired
                } else if item.balance <= 2 || days.map({ $0 <= 7 }) == true {
                    kind = .packageLow
                } else {
                    kind = nil
                }
                if let kind {
                    result.append(
                        Insight(
                            kind: kind, studentID: student.id, balance: item.balance,
                            packageEndDate: item.package.endDate, daysUntilExpiry: days))
                }
            }
            let sessions = history[student.id] ?? []
            let last = sessions.map(\.completedAtUTC).max()
            let days = today.daysSince(
                LocalDate(date: last ?? student.createdAtUTC, calendar: calendar), calendar: calendar)
            if days >= 14 && !booked.contains(student.id) {
                result.append(
                    Insight(kind: .inactive, studentID: student.id, daysInactive: days, hasNeverTrained: last == nil))
            }
            result.append(
                contentsOf: stagnant(
                    studentID: student.id, sessions: sessions, today: today, calendar: calendar,
                    assisted: input.assistedExerciseIDs))
        }
        return result.filter { !input.snoozedKeys.contains($0.snoozeKey) }.sorted(by: precedes)
    }

    private struct Action: Hashable {
        let id: StableExerciseID
        let mode: RecordMode
    }

    private struct Point {
        let date: Date
        let sessionID: StableUUID
        let value: DecimalValue
    }

    private static func stagnant(
        studentID: StableUUID, sessions: [CompletedSession], today: LocalDate, calendar: Calendar,
        assisted: Set<StableExerciseID>
    ) -> [Insight] {
        // Each exercise ID can produce at most one insight. Only its latest session's
        // record mode counts; other modes contribute neither sessions nor baseline values.
        let orderedSessions = sessions.sorted {
            if $0.completedAtUTC != $1.completedAtUTC { return $0.completedAtUTC < $1.completedAtUTC }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
        var latestModes: [StableExerciseID: RecordMode] = [:]
        for session in orderedSessions {
            for exercise in session.exercises {
                if let id = exercise.sourceID { latestModes[id] = exercise.recordModeSnapshot }
            }
        }
        var points: [Action: [Point]] = [:]
        for session in sessions {
            let grouped = Dictionary(
                grouping: session.exercises.filter {
                    guard let id = $0.sourceID else { return false }
                    return $0.recordModeSnapshot == latestModes[id]
                }
            ) {
                Action(id: $0.sourceID!, mode: $0.recordModeSnapshot)
            }
            for (action, exercises) in grouped {
                let sets = exercises.flatMap(\.sets).filter(\.contributesToStatistics)
                let value: DecimalValue?
                if EstimatedOneRepMax.exerciseIDs.contains(action.id) {
                    // Listed exercises still require weightReps sets for estimated 1RM.
                    value = sets.filter { $0.recordMode == .weightReps }.compactMap { set -> DecimalValue? in
                        guard let weight = set.weightValue, let reps = set.repetitionCount else { return nil }
                        return EstimatedOneRepMax.value(weight: weight, reps: reps, exerciseID: action.id)
                    }.max()
                } else {
                    value = SessionGains.bestMetricValue(
                        in: sets, kind: .mainMetric(for: action.mode),
                        direction: assisted.contains(action.id) ? .decreaseIsImprovement : .increaseIsImprovement)
                }
                if let value {
                    points[action, default: []].append(
                        Point(date: session.completedAtUTC, sessionID: session.id, value: value))
                }
            }
        }
        var result: [Insight] = []
        for (action, values) in points {
            guard values.count >= 4 else { continue }
            let ordered = values.sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                return $0.sessionID.rawValue.uuidString < $1.sessionID.rawValue.uuidString
            }
            let recent = ordered.suffix(3)
            guard
                recent.allSatisfy({
                    (0...28).contains(today.daysSince(LocalDate(date: $0.date, calendar: calendar), calendar: calendar))
                })
            else { continue }
            let estimated = EstimatedOneRepMax.exerciseIDs.contains(action.id)
            let kind = SessionGains.RecordKind.mainMetric(for: action.mode)
            let direction: Comparison.LoadDirection =
                !estimated && assisted.contains(action.id) ? .decreaseIsImprovement : .increaseIsImprovement
            let better: (DecimalValue, DecimalValue) -> Bool = {
                SessionGains.isBetter($0, than: $1, kind: kind, direction: direction)
            }
            let baseline = ordered.dropLast(3).map(\.value).reduce(nil as DecimalValue?) { best, value in
                guard let best else { return value }
                return better(value, best) ? value : best
            }!
            guard !recent.contains(where: { better($0.value, baseline) }) else { continue }
            let metric: Insight.Metric
            if estimated {
                metric = .estimatedOneRepMax
            } else {
                switch kind {
                case .highestWeight: metric = assisted.contains(action.id) ? .lowestAssistance : .highestWeight
                case .mostReps: metric = .mostReps
                case .longestDuration: metric = .longestDuration
                }
            }
            result.append(
                Insight(
                    kind: .stagnant, studentID: studentID, exerciseID: action.id, stagnantSessionCount: 3,
                    baselineBest: baseline, baselineMetric: metric))
        }
        return result
    }

    private static func precedes(_ lhs: Insight, _ rhs: Insight) -> Bool {
        func rank(_ kind: Insight.Kind) -> Int {
            switch kind {
            case .packageExhausted, .packageExpired: return 0
            case .packageLow: return 1
            case .inactive: return 2
            case .stagnant: return 3
            }
        }
        if rank(lhs.kind) != rank(rhs.kind) { return rank(lhs.kind) < rank(rhs.kind) }
        switch lhs.kind {
        case .packageExhausted, .packageExpired, .packageLow:
            if lhs.balance != rhs.balance { return (lhs.balance ?? 0) < (rhs.balance ?? 0) }
        case .inactive:
            if lhs.daysInactive != rhs.daysInactive { return (lhs.daysInactive ?? 0) > (rhs.daysInactive ?? 0) }
        case .stagnant: break
        }
        if lhs.studentID != rhs.studentID {
            return lhs.studentID.rawValue.uuidString < rhs.studentID.rawValue.uuidString
        }
        return (lhs.exerciseID?.rawValue ?? "") < (rhs.exerciseID?.rawValue ?? "")
    }
}
