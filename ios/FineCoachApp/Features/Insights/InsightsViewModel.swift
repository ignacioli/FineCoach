import Foundation

@MainActor
final class InsightsViewModel: ObservableObject {
    static let didSnooze = Notification.Name("insights.didSnooze")
    static let didUnsnooze = Notification.Name("insights.didUnsnooze")
    @Published private(set) var undoState = InsightUndoState()
    private var undoTasks: [String: Task<Void, Never>] = [:]
    private var writingKeys: Set<String> = []
    @Published private(set) var insights: [Insight] = []
    @Published var errorMessage: String?
    private var studentNames: [StableUUID: String] = [:]
    private var exerciseNames: [StableExerciseID: String] = [:]
    private var generation = 0
    private var presentationGeneration = 0
    private let useCases: InsightUseCases?
    private let students: StudentUseCases
    private let exercises: ExerciseLibraryUseCases?
    private let history: HistoryUseCases?
    private let studentID: StableUUID?

    init(
        useCases: InsightUseCases?, students: StudentUseCases,
        exercises: ExerciseLibraryUseCases?, history: HistoryUseCases?, studentID: StableUUID? = nil
    ) {
        self.useCases = useCases
        self.students = students
        self.exercises = exercises
        self.history = history
        self.studentID = studentID
    }

    func reload() async {
        guard let useCases, let exercises, let history else { return }
        generation += 1
        let request = generation
        do {
            let rows: [Insight]
            let people: [Student]
            let sessions: [CompletedSession]
            if let studentID {
                async let loaded = useCases.studentInsights(studentID: studentID, now: Date())
                async let person = students.student(id: studentID)
                async let completed = history.listHistory(studentID: studentID)
                let currentStudent = try await person
                (rows, people, sessions) = try await (loaded, [currentStudent], completed)
            } else {
                async let loaded = useCases.load(now: Date())
                async let active = students.searchActive(query: "")
                async let completed = history.listAllHistory()
                (rows, people, sessions) = try await (loaded, active, completed)
            }
            let library = try await exercises.search(query: "", includeHidden: true)
            guard request == generation, !Task.isCancelled else { return }
            studentNames = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0.displayName.value) })
            var names: [StableExerciseID: String] = [:]
            for session in sessions.sorted(by: {
                if $0.completedAtUTC != $1.completedAtUTC { return $0.completedAtUTC < $1.completedAtUTC }
                return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
            }) {
                for exercise in session.exercises {
                    if let id = exercise.sourceID { names[id] = exercise.displayNameSnapshot.value }
                }
            }
            for entry in library { names[entry.id] = entry.displayedName }
            exerciseNames = names
            insights = undoState.reconcile(rows)
            errorMessage = nil
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            errorMessage = String(localized: "student.error.generic")
        }
    }

    func content(for insight: Insight, context: InsightRowContent.Context) -> InsightRowContent {
        .make(
            insight: insight, studentName: studentNames[insight.studentID] ?? "",
            exerciseName: insight.exerciseID.flatMap { exerciseNames[$0] } ?? "", context: context)
    }

    func removeSnoozed(_ notification: Notification) {
        guard let key = notification.object as? String else { return }
        generation += 1
        guard undoState.pending[key] == nil else { return }
        undoState.removeSlots(at: insights.indices.filter { insights[$0].snoozeKey == key })
        insights.removeAll { $0.snoozeKey == key }
    }

    func snooze(_ insight: Insight) async {
        guard let useCases, writingKeys.insert(insight.snoozeKey).inserted else { return }
        defer { writingKeys.remove(insight.snoozeKey) }
        let presentation = presentationGeneration
        do {
            try await useCases.snooze(insight, now: Date())
            generation += 1
            guard presentation == presentationGeneration else {
                insights.removeAll { $0.snoozeKey == insight.snoozeKey }
                NotificationCenter.default.post(name: Self.didSnooze, object: insight.snoozeKey)
                return
            }
            undoState.begin(insight, in: insights, now: Date())
            undoTasks[insight.snoozeKey]?.cancel()
            undoTasks[insight.snoozeKey] = Task { [weak self] in
                do { try await Task.sleep(for: FCUndoRow.undoWindow) } catch { return }
                guard let self else { return }
                let expired = self.undoState.expire(now: Date(), excluding: self.writingKeys)
                self.insights.removeAll { expired.contains($0.snoozeKey) }
                self.undoTasks[insight.snoozeKey] = nil
            }
            errorMessage = nil
            NotificationCenter.default.post(name: Self.didSnooze, object: insight.snoozeKey)
        } catch {
            errorMessage = String(localized: "student.error.generic")
        }
    }
    func undoSnooze(_ insight: Insight) async {
        guard let useCases, writingKeys.insert(insight.snoozeKey).inserted else { return }
        defer { writingKeys.remove(insight.snoozeKey) }
        // Keep the slot alive while the durable undo is in flight.
        undoTasks[insight.snoozeKey]?.cancel()
        do {
            try await useCases.unsnooze(insight)
            generation += 1
            undoState.undo(insight)
            undoTasks[insight.snoozeKey] = nil
            errorMessage = nil
            NotificationCenter.default.post(name: Self.didUnsnooze, object: insight.snoozeKey)
        } catch {
            let indices = insights.indices.filter { insights[$0].snoozeKey == insight.snoozeKey }
            undoState.undo(insight)
            undoState.removeSlots(at: indices)
            undoTasks[insight.snoozeKey] = nil
            insights.removeAll { $0.snoozeKey == insight.snoozeKey }
            errorMessage = String(localized: "student.error.generic")
        }
    }

    func endUndoWindows() {
        presentationGeneration += 1
        for task in undoTasks.values { task.cancel() }
        undoTasks.removeAll()
        insights.removeAll { undoState.pending[$0.snoozeKey] != nil }
        undoState = InsightUndoState()
    }

    func undoMessage(for insight: Insight, context: InsightRowContent.Context) -> String {
        if context == .studentDetail { return String(localized: "insights.snoozed") }
        return String(format: String(localized: "insights.snoozed.withName"), studentNames[insight.studentID] ?? "")
    }

}

/// Value-only state: pending rows occupy their original slots until the shared window expires.
struct InsightUndoState {
    struct Pending {
        let insight: Insight
        var index: Int
        let expiresAt: Date
    }
    private(set) var pending: [String: Pending] = [:]

    mutating func begin(_ insight: Insight, in rows: [Insight], now: Date) {
        guard let index = rows.firstIndex(where: { $0.id == insight.id }) else { return }
        let duration = FCUndoRow.undoWindow.components
        let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        pending[insight.snoozeKey] = Pending(insight: insight, index: index, expiresAt: now.addingTimeInterval(seconds))
    }

    mutating func undo(_ insight: Insight) { pending[insight.snoozeKey] = nil }

    mutating func removeSlots(at indices: [Int]) {
        for key in pending.keys {
            guard var item = pending[key] else { continue }
            item.index -= indices.filter { $0 < item.index }.count
            pending[key] = item
        }
    }

    mutating func expire(now: Date, excluding: Set<String> = []) -> Set<String> {
        let keys = Set(pending.filter { $0.value.expiresAt <= now && !excluding.contains($0.key) }.keys)
        let indices = keys.compactMap { pending[$0]?.index }
        for key in keys { pending[key] = nil }
        removeSlots(at: indices)
        return keys
    }

    func reconcile(_ fresh: [Insight]) -> [Insight] {
        var rows = fresh.filter { pending[$0.snoozeKey] == nil }
        for item in pending.values.sorted(by: { $0.index < $1.index }) {
            rows.insert(item.insight, at: min(item.index, rows.count))
        }
        return rows
    }
}

enum InsightSwipeHint {
    static let defaultsKey = "insights.swipeHintShown"

    static func shouldPlay(isToday: Bool, hasRows: Bool, shown: Bool, reduceMotion: Bool) -> Bool {
        isToday && hasRows && !shown && !reduceMotion
    }
}
