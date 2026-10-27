import Foundation

/// Reads fresh value snapshots; async work and evaluation stay off the UI actor.
public struct InsightUseCases: Sendable {
    private let students: StudentUseCases
    private let history: HistoryUseCases
    private let appointments: AppointmentUseCases
    private let credits: CreditLedgerUseCases
    private let exercises: ExerciseLibraryUseCases
    private let snoozes: InsightSnoozeStore
    private let calendarProvider: any LocalCalendarProvider

    public init(
        students: StudentUseCases, history: HistoryUseCases, appointments: AppointmentUseCases,
        credits: CreditLedgerUseCases, exercises: ExerciseLibraryUseCases, snoozes: InsightSnoozeStore,
        calendarProvider: any LocalCalendarProvider = SystemLocalCalendarProvider()
    ) {
        self.students = students
        self.history = history
        self.appointments = appointments
        self.credits = credits
        self.exercises = exercises
        self.snoozes = snoozes
        self.calendarProvider = calendarProvider
    }

    public func load(now: Date) async throws -> [Insight] {
        let calendar = calendarProvider.currentCalendar()
        async let active = students.searchActive(query: "")
        async let completed = history.listAllHistory()
        async let assisted = exercises.assistedExerciseIDs()
        async let keys = snoozes.activeKeys(now: now, calendar: calendar)
        let activeStudents = try await active
        async let readings = input(students: activeStudents, now: now, calendar: calendar)
        var input = try await readings
        input.history = try await completed
        return try await evaluate(input, assisted: assisted, keys: keys, now: now, calendar: calendar)
    }

    public func studentInsights(studentID: StableUUID, now: Date) async throws -> [Insight] {
        let calendar = calendarProvider.currentCalendar()
        let student = try await students.student(id: studentID)
        guard student.lifecycle == .active else { return [] }
        async let completed = history.listHistory(studentID: studentID)
        async let assisted = exercises.assistedExerciseIDs()
        async let keys = snoozes.activeKeys(now: now, calendar: calendar)
        async let readings = input(students: [student], now: now, calendar: calendar)
        var input = try await readings
        input.history = try await completed
        return try await evaluate(input, assisted: assisted, keys: keys, now: now, calendar: calendar)
    }

    public func snooze(_ insight: Insight, now: Date) async throws {
        try await snoozes.snooze(insight, now: now, calendar: calendarProvider.currentCalendar())
    }

    public func unsnooze(_ insight: Insight) async throws {
        try await snoozes.unsnooze(insight)
    }

    private struct StudentRead: Sendable {
        let studentID: StableUUID
        let package: InsightEngine.PackageBalance?
        let appointments: [Appointment]
    }

    private func input(students: [Student], now: Date, calendar: Calendar) async throws
        -> InsightEngine.Input
    {
        try await withThrowingTaskGroup(of: StudentRead.self) { group in
            for student in students {
                group.addTask {
                    async let booked = self.appointments.appointments(studentID: student.id)
                    let package: InsightEngine.PackageBalance?
                    if let active = try await credits.activePackage(studentID: student.id) {
                        let balance = try await credits.balance(packageID: active.id)
                        package = InsightEngine.PackageBalance(package: active, balance: balance)
                    } else {
                        package = nil
                    }
                    return try await StudentRead(
                        studentID: student.id, package: package,
                        appointments: booked.filter {
                            $0.status == .scheduled && $0.startInstant(calendar: calendar) > now
                        })
                }
            }
            var input = InsightEngine.Input(students: students)
            for try await read in group {
                input.packages[read.studentID] = read.package
                input.appointments.append(contentsOf: read.appointments)
            }
            return input
        }
    }

    private func evaluate(
        _ input: InsightEngine.Input, assisted: Set<StableExerciseID>, keys: Set<String>, now: Date, calendar: Calendar
    ) async -> [Insight] {
        var snapshot = input
        snapshot.assistedExerciseIDs = assisted
        snapshot.snoozedKeys = keys
        let value = snapshot
        return await Task.detached {
            InsightEngine.evaluate(input: value, now: now, calendar: calendar)
        }.value
    }
}
