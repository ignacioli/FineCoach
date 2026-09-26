import FineCoach
import XCTest

final class RecurrenceAppointmentTests: XCTestCase {
    private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    private let seriesID = StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
    private let appointmentID = StableUUID(UUID(uuidString: "33333333-3333-4333-8333-333333333333")!)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - D-012 materialization bound

    func testRepeatCountWithinCapPasses() throws {
        try RecurrenceSeries.validateMaterializationBound(
            termination: .repeatCount(366),
            firstOccurrenceDate: try LocalDate(year: 2026, month: 1, day: 1),
            calendar: utc
        )
    }

    func testRepeatCountOverCapThrows() {
        XCTAssertThrowsError(
            try RecurrenceSeries.validateMaterializationBound(
                termination: .repeatCount(367),
                firstOccurrenceDate: try LocalDate(year: 2026, month: 1, day: 1),
                calendar: utc
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .recurrenceLimitExceeded)
        }
    }

    func testEndDateWithinOneYearPasses() throws {
        let first = try LocalDate(year: 2026, month: 1, day: 1)
        let end = first.addingDays(366, calendar: utc)
        try RecurrenceSeries.validateMaterializationBound(
            termination: .endDate(end),
            firstOccurrenceDate: first,
            calendar: utc
        )
    }

    func testEndDateOverOneYearThrows() throws {
        let first = try LocalDate(year: 2026, month: 1, day: 1)
        let end = first.addingDays(367, calendar: utc)
        XCTAssertThrowsError(
            try RecurrenceSeries.validateMaterializationBound(
                termination: .endDate(end),
                firstOccurrenceDate: first,
                calendar: utc
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .recurrenceLimitExceeded)
        }
    }

    func testEndDateBeforeFirstOccurrenceThrows() throws {
        let first = try LocalDate(year: 2026, month: 1, day: 10)
        let end = try LocalDate(year: 2026, month: 1, day: 1)
        XCTAssertThrowsError(
            try RecurrenceSeries.validateMaterializationBound(
                termination: .endDate(end),
                firstOccurrenceDate: first,
                calendar: utc
            )
        )
    }

    // MARK: - Materialization

    func testMaterializedDatesStepByIntervalDaysAndRepeatCount() throws {
        // 2026-01-05 is a Monday.
        let first = try LocalDate(year: 2026, month: 1, day: 5)
        let dates = RecurrenceSeries.materializedDates(
            intervalDays: .everyTwoDays,
            firstOccurrenceDate: first,
            termination: .repeatCount(4),
            calendar: utc
        )
        XCTAssertEqual(dates.count, 4)
        XCTAssertEqual(dates[0], first)
        XCTAssertEqual(dates[1], first.addingDays(3, calendar: utc))
        XCTAssertEqual(dates[2], first.addingDays(6, calendar: utc))
        XCTAssertEqual(dates[3], first.addingDays(9, calendar: utc))
    }

    func testMaterializedDatesStepByIntervalDaysUntilEndDate() throws {
        let first = try LocalDate(year: 2026, month: 1, day: 1)
        let end = try LocalDate(year: 2026, month: 1, day: 15)
        let dates = RecurrenceSeries.materializedDates(
            intervalDays: .everyWeek,
            firstOccurrenceDate: first,
            termination: .endDate(end),
            calendar: utc
        )
        // Jan 1, 8, 15 -- Jan 22 would be past the end date.
        XCTAssertEqual(dates, [first, first.addingDays(7, calendar: utc), first.addingDays(14, calendar: utc)])
    }

    func testMaterializedDatesNeverExceedsHardCapRegardlessOfInput() throws {
        let first = try LocalDate(year: 2020, month: 1, day: 1)
        let dates = RecurrenceSeries.materializedDates(
            intervalDays: .everyOtherDay,
            firstOccurrenceDate: first,
            termination: .repeatCount(10_000),
            calendar: utc
        )
        XCTAssertLessThanOrEqual(dates.count, RecurrenceSeries.maximumMaterializedInstances)
    }

    // MARK: - RecurrenceSeries construction / ended()

    func testEndedPreservesFieldsAndTerminationPersists() throws {
        let series = try RecurrenceSeries(
            id: seriesID,
            studentID: studentID,
            intervalDays: .everyWeek,
            termination: .endDate(try LocalDate(year: 2026, month: 6, day: 1)),
            defaultStartTime: try LocalTime(hour: 9, minute: 0),
            createdAtUTC: now,
            updatedAtUTC: now
        )
        let ended = series.ended(now: now.addingTimeInterval(60))
        XCTAssertEqual(ended.status, .ended)
        XCTAssertEqual(ended.termination, series.termination)
        XCTAssertEqual(ended.intervalDays, series.intervalDays)
        XCTAssertEqual(ended.updatedAtUTC, now.addingTimeInterval(60))
    }

    // MARK: - Appointment overlap

    func testOverlappingAppointmentsDetected() throws {
        let a = try makeAppointment(hour: 9, minute: 0, durationMinutes: 60)
        let b = try makeAppointment(hour: 9, minute: 30, durationMinutes: 60)
        XCTAssertTrue(a.overlaps(b, calendar: utc))
        XCTAssertTrue(b.overlaps(a, calendar: utc))
    }

    func testAdjacentAppointmentsDoNotOverlap() throws {
        let a = try makeAppointment(hour: 9, minute: 0, durationMinutes: 60)
        let b = try makeAppointment(hour: 10, minute: 0, durationMinutes: 60)
        XCTAssertFalse(a.overlaps(b, calendar: utc))
    }

    // MARK: - Overdue is derived, never auto-transitioned

    func testScheduledAppointmentPastWindowIsOverdueButStatusUnchanged() throws {
        let appointment = try makeAppointment(hour: 9, minute: 0, durationMinutes: 30)
        let pastEnd = appointment.endInstant(calendar: utc).addingTimeInterval(1)
        XCTAssertTrue(appointment.isOverdue(now: pastEnd, calendar: utc))
        XCTAssertEqual(appointment.status, .scheduled)
    }

    func testCompletedAppointmentIsNeverOverdue() throws {
        let appointment = try makeAppointment(hour: 9, minute: 0, durationMinutes: 30)
            .startingTraining(sessionID: StableUUID(UUID()), now: now)
            .completingSession(now: now)
        let farFuture = appointment.endInstant(calendar: utc).addingTimeInterval(1_000_000)
        XCTAssertFalse(appointment.isOverdue(now: farFuture, calendar: utc))
    }

    // MARK: - State machine

    func testStartTrainingThenCompleteRequiresLinkedSession() throws {
        let scheduled = try makeAppointment(hour: 9, minute: 0, durationMinutes: 60)
        let sessionID = StableUUID(UUID())
        let inProgress = try scheduled.startingTraining(sessionID: sessionID, now: now)
        XCTAssertEqual(inProgress.status, .inProgress)
        XCTAssertEqual(inProgress.linkedSessionID, sessionID)

        let completed = try inProgress.completingSession(now: now)
        XCTAssertEqual(completed.status, .completed)
    }

    func testAbandoningEmptySessionReturnsToScheduled() throws {
        let scheduled = try makeAppointment(hour: 9, minute: 0, durationMinutes: 60)
        let inProgress = try scheduled.startingTraining(sessionID: StableUUID(UUID()), now: now)
        let backToScheduled = try inProgress.abandoningEmptySession(now: now)
        XCTAssertEqual(backToScheduled.status, .scheduled)
        XCTAssertNil(backToScheduled.linkedSessionID)
    }

    func testCancellingRequiresScheduledStatus() throws {
        let scheduled = try makeAppointment(hour: 9, minute: 0, durationMinutes: 60)
        let cancelled = try scheduled.cancelling(reason: nil, now: now)
        XCTAssertEqual(cancelled.status, .cancelled)

        let inProgress = try scheduled.startingTraining(sessionID: StableUUID(UUID()), now: now)
        XCTAssertThrowsError(try inProgress.cancelling(reason: nil, now: now))
    }

    func testMarkingAbsentRecordsCreditChoice() throws {
        let scheduled = try makeAppointment(hour: 9, minute: 0, durationMinutes: 60)
        let absent = try scheduled.markingAbsent(creditChoice: .notCharged, now: now)
        XCTAssertEqual(absent.status, .absent)
        XCTAssertEqual(absent.absentCreditChoice, .notCharged)
    }

    func testAppointmentDoesNotAutoTransitionOnConstructionWithAbsentCreditChoiceMismatch() {
        XCTAssertThrowsError(
            try Appointment(
                id: appointmentID,
                studentID: studentID,
                seriesID: nil,
                date: try LocalDate(year: 2026, month: 1, day: 5),
                startTime: try LocalTime(hour: 9, minute: 0),
                status: .scheduled,
                absentCreditChoice: .charged,
                createdAtUTC: now,
                updatedAtUTC: now
            )
        )
    }

    // MARK: - D-011 detached edit field scope

    func testDetachedEditOnlyChangesTimeAndReminderFields() throws {
        let scheduled = try makeAppointment(hour: 9, minute: 0, durationMinutes: 60)
        let edited = try scheduled.reschedulingDetached(
            startTime: try LocalTime(hour: 10, minute: 30),
            durationMinutes: 45,
            now: now
        )
        XCTAssertTrue(edited.isDetachedException)
        XCTAssertEqual(edited.startTime, try LocalTime(hour: 10, minute: 30))
        XCTAssertEqual(edited.durationMinutes, 45)
        XCTAssertEqual(edited.date, scheduled.date)
        XCTAssertEqual(edited.studentID, scheduled.studentID)
    }

    // MARK: - Deletion boundary

    func testOnlyNeverStartedFutureAppointmentCanBePermanentlyDeleted() throws {
        let farFuture = try makeAppointment(hour: 9, minute: 0, durationMinutes: 60, date: try LocalDate(year: 2099, month: 1, day: 1))
        XCTAssertTrue(farFuture.canPermanentlyDelete(now: now, calendar: utc))

        let started = try farFuture.startingTraining(sessionID: StableUUID(UUID()), now: now)
        XCTAssertFalse(started.canPermanentlyDelete(now: now, calendar: utc))
    }

    // MARK: - Helpers

    private func makeAppointment(
        hour: Int,
        minute: Int,
        durationMinutes: Int,
        date: LocalDate? = nil
    ) throws -> Appointment {
        try Appointment(
            id: appointmentID,
            studentID: studentID,
            seriesID: nil,
            date: try date ?? LocalDate(year: 2026, month: 1, day: 5),
            startTime: try LocalTime(hour: hour, minute: minute),
            durationMinutes: durationMinutes,
            createdAtUTC: now,
            updatedAtUTC: now
        )
    }
}
