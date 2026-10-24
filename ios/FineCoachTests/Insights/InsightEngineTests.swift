import XCTest

@testable import FineCoach

final class InsightEngineTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z")!
    private let squat = try! StableExerciseID("a2f5b6ef-b780-49c0-8d96-fdaff23e27ce")
    private let other = try! StableExerciseID("aaaaaaaa-0000-4000-8000-000000000001")
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func student(age: Int = 0, archived: Bool = false) throws -> Student {
        try Student(
            id: StableUUID(UUID()), draft: StudentDraft(displayName: "虚构学员", sex: .undisclosed),
            lifecycle: archived ? .archived : .active, createdAtUTC: date(-age), updatedAtUTC: now)
    }

    private func date(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: now)!
    }

    private func evaluate(_ input: InsightEngine.Input, calendar: Calendar? = nil) -> [Insight] {
        InsightEngine.evaluate(input: input, now: now, calendar: calendar ?? self.calendar)
    }

    private func session(
        student: Student, day: Int, action: StableExerciseID? = nil, value: String = "80", reps: String = "5",
        mode: RecordMode = .weightReps, state: SetRecordingState = .completed, at: Date? = nil,
        sourceKind: ExerciseSourceKind = .builtIn
    ) throws -> CompletedSession {
        let sessionID = StableUUID(UUID())
        let exerciseID = StableUUID(UUID())
        let time = at ?? date(day)
        let set = TrainingSet(
            id: StableUUID(UUID()), sessionExerciseID: exerciseID, orderIndex: 0, state: state,
            recordMode: mode, weightValue: mode == .weightReps ? try DecimalValue(value) : nil,
            repetitionCount: try DecimalValue(mode == .reps ? value : reps),
            durationSeconds: mode == .duration || mode == .cardio ? try DecimalValue(value) : nil,
            unit: mode == .weightReps ? .kilograms : .none, side: .none, leftValue: nil, rightValue: nil,
            createdAtUTC: time, updatedAtUTC: time, completedAtUTC: state == .completed ? time : nil)
        let exercise = SessionExercise(
            id: exerciseID, sessionID: sessionID, orderIndex: 0, sourceKind: sourceKind, sourceID: action ?? squat,
            displayNameSnapshot: try NormalizedName("虚构动作"), recordModeSnapshot: mode,
            actionPrivateNote: nil, sets: [set])
        return CompletedSession(
            id: sessionID, studentID: student.id, studentDisplayName: student.displayName,
            startedAtUTC: time, completedAtUTC: time, trainingFocus: [],
            notes: SessionNotes(privateCoachNote: nil, studentFacingSummary: nil, actionPrivateNotes: [:]),
            exercises: [exercise],
            statistics: SessionStatistics(
                completedSetCount: 1, displayedDurationSeconds: .zero, ordinaryTrainingVolume: nil),
            revision: 1, latestReport: nil)
    }

    private func package(_ student: Student, balance: Int, end: Int? = nil) throws -> InsightEngine.Input {
        let item = try CoursePackage(
            id: StableUUID(UUID()), studentID: student.id, totalCredits: 10, remainingCreditsCache: 99,
            endDate: end.map { LocalDate(date: date($0), calendar: calendar) }, createdAtUTC: now, updatedAtUTC: now)
        return InsightEngine.Input(students: [student], packages: [student.id: .init(package: item, balance: balance)])
    }

    func testPackageThresholdsPriorityAndPresentationValues() throws {
        let s = try student()
        XCTAssertTrue(evaluate(try package(s, balance: 3)).isEmpty)
        XCTAssertEqual(evaluate(try package(s, balance: 2)).first?.kind, .packageLow)
        XCTAssertEqual(evaluate(try package(s, balance: 0)).first?.kind, .packageExhausted)
        XCTAssertTrue(evaluate(try package(s, balance: 8, end: 8)).isEmpty)
        let seven = try XCTUnwrap(evaluate(try package(s, balance: 8, end: 7)).first)
        XCTAssertEqual(seven.kind, .packageLow)
        XCTAssertEqual(seven.daysUntilExpiry, 7)
        XCTAssertEqual(seven.balance, 8)
        XCTAssertEqual(seven.packageEndDate, LocalDate(date: date(7), calendar: calendar))
        XCTAssertEqual(evaluate(try package(s, balance: 8, end: 0)).first?.daysUntilExpiry, 0)
        XCTAssertEqual(evaluate(try package(s, balance: 8, end: -1)).first?.kind, .packageExpired)
        XCTAssertEqual(evaluate(try package(s, balance: 0, end: -1)).first?.kind, .packageExhausted)
    }

    func testInactiveBoundariesNeverTrainedAndArchivedExclusion() throws {
        let s = try student(age: 30)
        for (days, count) in [(13, 0), (14, 1)] {
            let output = evaluate(.init(students: [s], history: [try session(student: s, day: -days)]))
            XCTAssertEqual(output.count, count)
            if let insight = output.first {
                XCTAssertEqual(insight.daysInactive, 14)
                XCTAssertFalse(insight.hasNeverTrained)
            }
        }
        let never = evaluate(.init(students: [try student(age: 14)])).first
        XCTAssertEqual(never?.daysInactive, 14)
        XCTAssertEqual(never?.hasNeverTrained, true)
        let archived = try student(age: 30, archived: true)
        XCTAssertTrue(evaluate(try package(archived, balance: 0, end: -1)).isEmpty)
        let history = try [-30, -3, -2, -1].map { try session(student: archived, day: $0) }
        XCTAssertTrue(evaluate(.init(students: [archived], history: history)).isEmpty)
    }

    func testOnlyStrictlyFutureScheduledAppointmentSuppressesInactivity() throws {
        let s = try student(age: 21)
        let future = try Appointment(
            id: StableUUID(UUID()), studentID: s.id, seriesID: nil,
            date: LocalDate(date: date(1), calendar: calendar), startTime: LocalTime(hour: 12, minute: 0),
            durationMinutes: 60, reminderEnabled: false, reminderLeadMinutes: nil, createdAtUTC: now, updatedAtUTC: now)
        XCTAssertTrue(evaluate(.init(students: [s], appointments: [future])).isEmpty)
        let cancelled = try future.cancelling(reason: nil, now: now)
        let absent = try future.markingAbsent(creditChoice: .notCharged, now: now)
        XCTAssertEqual(evaluate(.init(students: [s], appointments: [cancelled, absent])).first?.kind, .inactive)
        let equal = try Appointment(
            id: StableUUID(UUID()), studentID: s.id, seriesID: nil,
            date: LocalDate(date: now, calendar: calendar), startTime: LocalTime(hour: 12, minute: 0),
            durationMinutes: 60, reminderEnabled: false, reminderLeadMinutes: nil, createdAtUTC: now, updatedAtUTC: now)
        XCTAssertEqual(evaluate(.init(students: [s], appointments: [equal])).first?.kind, .inactive)
    }

    func testStagnationRequiresThreeRecentValuesAndOlderBaseline() throws {
        let s = try student()
        let history = try [-40, -20, -10, -1].map { try session(student: s, day: $0) }
        XCTAssertTrue(evaluate(.init(students: [s], history: Array(history.suffix(3)))).isEmpty)
        XCTAssertTrue(evaluate(.init(students: [s], history: Array(history.prefix(3)))).isEmpty)
        let output = evaluate(.init(students: [s], history: history))
        XCTAssertEqual(output.count, 1)
        XCTAssertEqual(output.first?.kind, .stagnant)
        XCTAssertEqual(output.first?.stagnantSessionCount, 3)
        XCTAssertEqual(output.first?.baselineMetric, .estimatedOneRepMax)
        XCTAssertEqual(
            output.first?.baselineBest,
            EstimatedOneRepMax.value(weight: try DecimalValue("80"), reps: try DecimalValue("5"), exerciseID: squat))
        let outside = try [-40, -29, -10, -1].map { try session(student: s, day: $0) }
        XCTAssertTrue(evaluate(.init(students: [s], history: outside)).isEmpty)
        let inclusive = try [-40, -28, -10, -1].map { try session(student: s, day: $0) }
        XCTAssertEqual(evaluate(.init(students: [s], history: inclusive)).first?.kind, .stagnant)
    }

    func testAnyRecentImprovementAndSameWeightMoreRepsRemoveStagnation() throws {
        let s = try student()
        let base = try session(student: s, day: -90, value: "80")
        for improvedIndex in 0..<3 {
            let recent = try [-3, -2, -1].enumerated().map {
                try session(student: s, day: $0.element, reps: $0.offset == improvedIndex ? "7" : "5")
            }
            XCTAssertTrue(evaluate(.init(students: [s], history: [base] + recent)).isEmpty)
        }
        let strongerOld = try session(student: s, day: -100, value: "100")
        let recent = try [-3, -2, -1].map { try session(student: s, day: $0) }
        let output = evaluate(.init(students: [s], history: [strongerOld, base] + recent))
        XCTAssertEqual(
            output.first?.baselineBest,
            EstimatedOneRepMax.value(weight: try DecimalValue("100"), reps: try DecimalValue("5"), exerciseID: squat))
    }

    func testInapplicableAndUnconfirmedSetsDoNotCountAsSessions() throws {
        let s = try student()
        let valid = try [-40, -20, -10].map { try session(student: s, day: $0) }
        for excluded in [
            try session(student: s, day: -2, reps: "11"),
            try session(student: s, day: -2, value: "0"),
            try session(student: s, day: -2, state: .pending),
            try session(student: s, day: -2, state: .draft),
        ] {
            XCTAssertTrue(evaluate(.init(students: [s], history: valid + [excluded])).isEmpty)
            let complete = try session(student: s, day: -3)
            XCTAssertEqual(
                evaluate(.init(students: [s], history: valid + [excluded, complete])).first?.kind, .stagnant)
        }
    }

    func testNonlistedMainMetricsAndAssistedDirection() throws {
        let s = try student()
        for (mode, expected) in [
            (RecordMode.weightReps, Insight.Metric.highestWeight), (.reps, .mostReps), (.duration, .longestDuration),
            (.cardio, .longestDuration),
        ] {
            let history = try [-40, -20, -10, -1].map {
                try session(student: s, day: $0, action: other, reps: $0 == -1 ? "9" : "5", mode: mode)
            }
            let output = evaluate(.init(students: [s], history: history))
            XCTAssertEqual(output.first?.baselineMetric, expected)
            XCTAssertEqual(output.first?.baselineBest, try DecimalValue("80"))
            let improved = try session(student: s, day: 0, action: other, value: "81", mode: mode)
            XCTAssertTrue(evaluate(.init(students: [s], history: history + [improved])).isEmpty)
        }
        let history = try [-40, -20, -10, -1].map {
            try session(student: s, day: $0, action: other, value: $0 == -40 ? "20" : "30")
        }
        let input = InsightEngine.Input(students: [s], history: history, assistedExerciseIDs: [other])
        XCTAssertEqual(evaluate(input).first?.baselineMetric, .lowestAssistance)
        XCTAssertEqual(evaluate(input).first?.baselineBest, try DecimalValue("20"))
        var improved = input
        improved.history.append(try session(student: s, day: 0, action: other, value: "19"))
        XCTAssertTrue(evaluate(improved).isEmpty)
    }

    func testOneBestValuePerSessionAndActionIsolation() throws {
        let s = try student()
        let history = try [-40, -20, -10, -1].map { try session(student: s, day: $0) }
        let newest = try XCTUnwrap(history.last)
        let better = try session(student: s, day: -1, value: "90").exercises[0]
        let combined = CompletedSession(
            id: newest.id, studentID: s.id, studentDisplayName: s.displayName,
            startedAtUTC: newest.startedAtUTC, completedAtUTC: newest.completedAtUTC, trainingFocus: [],
            notes: newest.notes, exercises: newest.exercises + [better], statistics: newest.statistics,
            revision: 1, latestReport: nil)
        XCTAssertTrue(evaluate(.init(students: [s], history: Array(history.dropLast()) + [combined])).isEmpty)
        let variant = try StableExerciseID("9c31b616-0fe1-5fc1-bc97-9dba29be61ca")
        let variantSession = try session(student: s, day: -40, action: variant)
        XCTAssertTrue(evaluate(.init(students: [s], history: Array(history.suffix(3)) + [variantSession])).isEmpty)
    }

    func testOnlyLatestRecordModeCountsForCustomExerciseStagnation() throws {
        let s = try student()
        let reps = try [-8, -7, -6, -5].map {
            try session(student: s, day: $0, action: other, value: "200", mode: .reps, sourceKind: .custom)
        }
        let weights = try [-4, -3, -2, -1].map {
            try session(student: s, day: $0, action: other, value: "80", sourceKind: .custom)
        }
        let output = evaluate(.init(students: [s], history: reps + weights))
        XCTAssertEqual(output.count, 1)
        XCTAssertEqual(output.first?.kind, .stagnant)
        XCTAssertEqual(output.first?.exerciseID, other)
        XCTAssertEqual(output.first?.baselineMetric, .highestWeight)
        XCTAssertEqual(output.first?.baselineBest, try DecimalValue("80"))
        XCTAssertEqual(evaluate(.init(students: [s], history: (reps + weights).reversed())), output)
        // Earlier reps sessions must not supply the missing weightReps baseline.
        XCTAssertTrue(evaluate(.init(students: [s], history: reps + weights.suffix(3))).isEmpty)
        let improved = try session(student: s, day: 0, action: other, value: "81", sourceKind: .custom)
        XCTAssertTrue(evaluate(.init(students: [s], history: reps + weights + [improved])).isEmpty)
        // Even a latest session without a statistical value selects the current mode.
        let changed = try session(
            student: s, day: 0, action: other, mode: .duration, state: .pending, sourceKind: .custom)
        XCTAssertTrue(evaluate(.init(students: [s], history: reps + weights + [changed])).isEmpty)
    }

    func testStableOrderingAndGroupedSnoozeFiltering() throws {
        let exhausted = try student()
        let expired = try student()
        let low = try student()
        let inactive = try student(age: 30)
        let stagnant = try student()
        let older = try student(age: 40)
        var input = try package(exhausted, balance: 0)
        input.students += [expired, low, inactive, stagnant, older]
        input.packages.merge(try package(expired, balance: 5, end: -1).packages) { first, _ in first }
        input.packages.merge(try package(low, balance: 2).packages) { first, _ in first }
        input.history = try [-40, -3, -2, -1].map { try session(student: stagnant, day: $0) }
        let output = evaluate(input)
        XCTAssertEqual(
            output.map(\.kind), [.packageExhausted, .packageExpired, .packageLow, .inactive, .inactive, .stagnant])
        XCTAssertEqual(output.filter { $0.kind == .inactive }.map(\.studentID), [older.id, inactive.id])
        input.students.reverse()
        input.history.reverse()
        XCTAssertEqual(evaluate(input), output)
        input.snoozedKeys = [try XCTUnwrap(output.first).snoozeKey]
        XCTAssertEqual(evaluate(input), Array(output.dropFirst()))
        let lowKey = Insight(kind: .packageLow, studentID: exhausted.id).snoozeKey
        XCTAssertEqual(lowKey, output.first?.snoozeKey)
        let ties = try [student(age: 30), student(age: 30)]
        XCTAssertEqual(
            evaluate(.init(students: ties)).map(\.studentID),
            ties.map(\.id).sorted { $0.rawValue.uuidString < $1.rawValue.uuidString })
    }

    func testLocalDateTimeZoneBoundaryAndDaylightSaving() throws {
        let s = try student()
        let completed = try session(student: s, day: 0, at: ISO8601DateFormatter().date(from: "2026-10-11T01:00:00Z"))
        var losAngeles = calendar
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertTrue(evaluate(.init(students: [s], history: [completed])).isEmpty)
        XCTAssertEqual(
            evaluate(.init(students: [s], history: [completed]), calendar: losAngeles).first?.daysInactive, 14)
        let start = ISO8601DateFormatter().date(from: "2026-03-01T20:00:00Z")!
        let end = ISO8601DateFormatter().date(from: "2026-03-15T19:00:00Z")!
        let past = try session(student: s, day: 0, at: start)
        let output = InsightEngine.evaluate(
            input: .init(students: [s], history: [past]), now: end, calendar: losAngeles)
        XCTAssertEqual(output.first?.daysInactive, 14)
    }

    func testHundredStudentsWithTwoHundredSessionsDeterministicOrder() throws {
        let students = try (0..<100).map { _ in try student() }
        let history = try students.flatMap { student in
            try (0..<200).map { try session(student: student, day: -$0) }
        }
        let input = InsightEngine.Input(students: students, history: history)
        let output = evaluate(input)
        XCTAssertEqual(output.count, 100)
        XCTAssertEqual(
            output.map(\.studentID), students.map(\.id).sorted { $0.rawValue.uuidString < $1.rawValue.uuidString })
        XCTAssertEqual(output, evaluate(.init(students: students.reversed(), history: history.reversed())))
    }
}
