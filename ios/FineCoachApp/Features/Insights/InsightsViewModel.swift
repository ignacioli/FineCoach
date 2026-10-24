import Foundation

@MainActor
final class InsightsViewModel: ObservableObject {
    static let didSnooze = Notification.Name("insights.didSnooze")
    @Published private(set) var insights: [Insight] = []
    @Published var errorMessage: String?
    private var studentNames: [StableUUID: String] = [:]
    private var exerciseNames: [StableExerciseID: String] = [:]
    private var generation = 0
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
            insights = rows
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
        insights.removeAll { $0.snoozeKey == key }
    }

    func snooze(_ insight: Insight) async {
        guard let useCases else { return }
        do {
            try await useCases.snooze(insight, now: Date())
            generation += 1
            insights.removeAll { $0.id == insight.id }
            errorMessage = nil
            NotificationCenter.default.post(name: Self.didSnooze, object: insight.snoozeKey)
        } catch {
            errorMessage = String(localized: "student.error.generic")
        }
    }
}
