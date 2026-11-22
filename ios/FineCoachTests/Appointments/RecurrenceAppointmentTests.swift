import CoreData
import XCTest

@testable import FineCoach

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
        let farFuture = try makeAppointment(
            hour: 9, minute: 0, durationMinutes: 60, date: try LocalDate(year: 2099, month: 1, day: 1))
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

#if DEBUG
    // S2-D22: fictional fixtures persisted through the real Core Data writer.
    final class AppointmentFutureEditTests: XCTestCase {
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        private actor WidgetRefreshSpy: WidgetSnapshotPublishing {
            private(set) var refreshCount = 0

            func refresh() async {
                refreshCount += 1
            }
        }

        private struct Fixture {
            let directory: TemporaryProtectedDirectory
            let controller: PersistenceController
            let repository: CoreDataAppointmentRepository
            let cases: AppointmentUseCases
            let notifications: FakeNotificationScheduling
            let widgets: WidgetRefreshSpy
            let studentID: StableUUID
        }

        private func withFixture(_ run: (Fixture) async throws -> Void) async throws {
            let directory = try TemporaryProtectedDirectory()
            let controller = try PersistenceController(storeURL: directory.url.appendingPathComponent("future.sqlite"))
            do {
                let ids = TestIDGenerator(ids: (0..<100).map { _ in UUID() })
                let clock = TestClock(utcDate: now)
                let students = CoreDataStudentRepository(writer: controller.writer)
                let student = try await StudentUseCases(repository: students, clock: clock, ids: ids).create(
                    draft: StudentDraft(displayName: "虚构排课", sex: .female))
                let active = ActiveSessionUseCases(
                    sessionRepository: CoreDataSessionRepository(writer: controller.writer),
                    studentRepository: students,
                    exerciseRepository: CoreDataExerciseRepository(writer: controller.writer),
                    sectionRepository: CoreDataSessionSectionRepository(writer: controller.writer),
                    recoveryStore: ActiveSessionRecoveryStore(
                        url: directory.url.appendingPathComponent("recovery.json")),
                    storeGenerationUUID: ids.makeID(), clock: clock, ids: ids)
                let repository = CoreDataAppointmentRepository(writer: controller.writer)
                let notifications = FakeNotificationScheduling()
                let widgets = WidgetRefreshSpy()
                let provider = TestCalendarProvider(timeZone: TimeZone(secondsFromGMT: 0)!)
                let cases = AppointmentUseCases(
                    appointmentRepository: repository, studentRepository: students, activeSession: active,
                    notifications: NotificationScheduler(notificationCenter: notifications, calendarProvider: provider),
                    clock: clock, calendarProvider: provider, ids: ids, widgetSnapshots: widgets)
                try await run(
                    Fixture(
                        directory: directory, controller: controller, repository: repository, cases: cases,
                        notifications: notifications, widgets: widgets, studentID: student.id))
                try await controller.shutdownForTesting()
            } catch {
                try? await controller.shutdownForTesting()
                throw error
            }
        }

        private func series(
            _ f: Fixture, termination: RecurrenceTermination = .repeatCount(10)
        ) async throws -> [Appointment] {
            try await f.cases.createRecurring(
                studentID: f.studentID,
                draft: RecurringAppointmentDraft(
                    intervalDays: .everyOtherDay, termination: termination,
                    firstOccurrenceDate: LocalDate(year: 2026, month: 3, day: 7),
                    startTime: LocalTime(hour: 9, minute: 0), trainingFocus: [.chest]),
                overrideConflict: false)
        }

        private func edit(
            _ f: Fixture, boundary: Appointment, overrideConflict: Bool = false
        ) async throws -> [Appointment] {
            try await f.cases.applyThisAndFuture(
                seriesID: XCTUnwrap(boundary.seriesID), boundaryDate: boundary.date,
                startTime: LocalTime(hour: 11, minute: 30), overrideConflict: overrideConflict)
        }

        private func storedSeries(_ f: Fixture) async throws -> Set<RecurrenceSeries> {
            try await f.controller.writer.read { context in
                let request = NSFetchRequest<NSManagedObject>(
                    entityName: RecurrenceSeriesManagedObjectMapping.entityName)
                return try Set(
                    context.fetch(request).map { try RecurrenceSeriesManagedObjectMapping.makeSeries(from: $0) })
            }
        }

        private func assertRejectedWithoutChanges(
            _ f: Fixture, seriesID: StableUUID, boundaryDate: LocalDate,
            intervalDays: RecurrenceInterval? = nil, expectedError: DomainError = .incompatibleInput
        ) async throws {
            let rows = try await f.repository.appointments(studentID: f.studentID)
            let series = try await storedSeries(f)
            let reminders = await f.notifications.scheduled
            let refreshCount = await f.widgets.refreshCount
            do {
                _ = try await f.cases.applyThisAndFuture(
                    seriesID: seriesID, boundaryDate: boundaryDate, intervalDays: intervalDays,
                    startTime: LocalTime(hour: 11, minute: 30), overrideConflict: true)
                XCTFail("Expected input rejection")
            } catch let error as DomainError {
                XCTAssertTrue(error == expectedError)
            }
            let savedRows = try await f.repository.appointments(studentID: f.studentID)
            let savedSeries = try await storedSeries(f)
            let savedReminders = await f.notifications.scheduled
            let savedRefreshCount = await f.widgets.refreshCount
            XCTAssertTrue(savedRows == rows)
            XCTAssertTrue(savedSeries == series)
            XCTAssertTrue(savedReminders == reminders)
            XCTAssertTrue(savedRefreshCount == refreshCount)
        }

        func testNilAndOriginalIntervalAreAcceptedWithoutChangingIntervalOrDates() async throws {
            let intervals: [RecurrenceInterval?] = [nil, .everyOtherDay]
            for interval in intervals {
                try await withFixture { f in
                    let initial = try await series(f)
                    let changed = try await f.cases.applyThisAndFuture(
                        seriesID: XCTUnwrap(initial[0].seriesID), boundaryDate: initial[4].date,
                        intervalDays: interval, startTime: LocalTime(hour: 11, minute: 30), overrideConflict: false)
                    let replacement = try await f.cases.series(id: XCTUnwrap(changed.first?.seriesID))
                    XCTAssertTrue(replacement.intervalDays == .everyOtherDay)
                    XCTAssertTrue(replacement.termination == .repeatCount(6))
                    XCTAssertTrue(changed.map(\.date) == initial.dropFirst(4).map(\.date))
                }
            }
        }

        func testDifferentIntervalIsRejectedWithoutChangingStoreRemindersOrWidget() async throws {
            try await withFixture { f in
                let initial = try await series(f)
                try await assertRejectedWithoutChanges(
                    f, seriesID: XCTUnwrap(initial[0].seriesID), boundaryDate: initial[4].date,
                    intervalDays: .everyWeek, expectedError: .incompatibleInput)
            }
        }

        func testEndedSeriesIsRejectedWithoutChangingStoreRemindersOrWidget() async throws {
            try await withFixture { f in
                let initial = try await series(f)
                let current = try await f.cases.series(id: XCTUnwrap(initial[0].seriesID))
                _ = try await f.repository.updateSeries(current.ended(now: now))
                try await assertRejectedWithoutChanges(f, seriesID: current.id, boundaryDate: initial[4].date)
            }
        }

        func testMissingBoundaryIsRejectedEvenWhenLaterScheduledRowsExist() async throws {
            try await withFixture { f in
                let initial = try await series(f)
                try await f.cases.deleteNeverStartedFutureAppointment(appointmentID: initial[4].id)
                try await assertRejectedWithoutChanges(
                    f, seriesID: XCTUnwrap(initial[0].seriesID), boundaryDate: initial[4].date)
            }
        }

        func testResolvedBoundariesAreRejectedEvenWhenLaterScheduledRowsExist() async throws {
            for status in [AppointmentStatus.cancelled, .absent, .inProgress, .completed] {
                try await withFixture { f in
                    let initial = try await series(f)
                    let boundary = initial[4]
                    switch status {
                    case .cancelled:
                        _ = try await f.cases.cancel(appointmentID: boundary.id, reason: nil)
                    case .absent:
                        _ = try await f.cases.markAbsent(appointmentID: boundary.id, creditChoice: .notCharged)
                    case .inProgress, .completed:
                        let started = try boundary.startingTraining(sessionID: StableUUID(UUID()), now: now)
                        let row: Appointment
                        if status == .completed {
                            row = try started.completingSession(now: now)
                        } else {
                            row = started
                        }
                        _ = try await f.repository.update(row)
                    case .scheduled:
                        XCTFail("Expected a resolved boundary fixture")
                    }
                    try await assertRejectedWithoutChanges(
                        f, seriesID: XCTUnwrap(boundary.seriesID), boundaryDate: boundary.date)
                }
            }
        }

        func testDetachedScheduledBoundaryPreservesDetachedRowAndReplacesLaterScheduledRows() async throws {
            try await withFixture { f in
                let initial = try await series(f)
                let boundary = initial[4]
                let detached = try await f.cases.rescheduleSingle(
                    appointmentID: boundary.id, startTime: LocalTime(hour: 15, minute: 0),
                    overrideConflict: false)
                XCTAssertTrue(detached.status == .scheduled && detached.isDetachedException)
                let changed = try await edit(f, boundary: detached)
                let rows = try await f.repository.appointments(studentID: f.studentID)
                let replacement = try await f.cases.series(id: XCTUnwrap(changed.first?.seriesID))
                let old = try await f.cases.series(id: XCTUnwrap(boundary.seriesID))
                let expectedTime = try LocalTime(hour: 11, minute: 30)
                XCTAssertTrue(changed.map(\.date) == initial.dropFirst(5).map(\.date))
                XCTAssertTrue(changed.allSatisfy { $0.seriesID == replacement.id && $0.status == .scheduled })
                XCTAssertTrue(changed.allSatisfy { $0.startTime == expectedTime })
                XCTAssertTrue(replacement.termination == .repeatCount(5))
                XCTAssertTrue(old.status == .ended)
                XCTAssertTrue(rows.first { $0.id == detached.id } == detached)
                XCTAssertTrue(rows.filter { $0.date == boundary.date } == [detached])
                XCTAssertTrue(rows.filter { $0.date < boundary.date } == Array(initial.prefix(4)))
                XCTAssertTrue(rows.count == initial.count)
                XCTAssertTrue(rows.map(\.date).sorted() == initial.map(\.date))
            }
        }

        func testEmptySupersededIsRejectedForBothTerminationsWithoutSideEffects() async throws {
            let terminations: [RecurrenceTermination] = [
                .repeatCount(1), .endDate(try LocalDate(year: 2026, month: 3, day: 7)),
            ]
            for termination in terminations {
                try await withFixture { f in
                    let initial = try await series(f, termination: termination)
                    let detached = try await f.cases.rescheduleSingle(
                        appointmentID: initial[0].id, startTime: LocalTime(hour: 15, minute: 0),
                        overrideConflict: false)
                    XCTAssertTrue(detached.status == .scheduled && detached.isDetachedException)
                    let existing = try await f.repository.appointments(seriesID: XCTUnwrap(detached.seriesID))
                    XCTAssertTrue(existing.count == 1 && existing[0] == detached)
                    try await assertRejectedWithoutChanges(
                        f, seriesID: XCTUnwrap(initial[0].seriesID), boundaryDate: initial[0].date)
                }
            }
        }

        func testRepeatCountKeepsOriginalDatesAndStoresRemainingCount() async throws {
            try await withFixture { f in
                let initial = try await series(f)
                let changed = try await edit(f, boundary: initial[4])
                let rows = try await f.repository.appointments(studentID: f.studentID)
                let replacement = try await f.cases.series(id: XCTUnwrap(changed.first?.seriesID))
                let old = try await f.cases.series(id: XCTUnwrap(initial.first?.seriesID))
                XCTAssertTrue(rows.count == initial.count)
                XCTAssertTrue(rows.map(\.date).sorted() == initial.map(\.date))
                XCTAssertTrue(changed.map(\.date) == initial.dropFirst(4).map(\.date))
                XCTAssertTrue(replacement.termination == .repeatCount(6))
                XCTAssertTrue(replacement.intervalDays == .everyOtherDay)
                XCTAssertTrue(old.status == .ended)
                XCTAssertTrue(rows.filter { $0.date < initial[4].date } == Array(initial.prefix(4)))
            }
        }

        func testCancelledAbsentAndDetachedRowsStayUnchangedWithoutReplacements() async throws {
            try await withFixture { f in
                let initial = try await series(f)
                let cancelled = try await f.cases.cancel(appointmentID: initial[5].id, reason: nil)
                let absent = try await f.cases.markAbsent(appointmentID: initial[6].id, creditChoice: .notCharged)
                let detached = try await f.cases.rescheduleSingle(
                    appointmentID: initial[7].id, startTime: LocalTime(hour: 15, minute: 0), overrideConflict: false)
                let changed = try await edit(f, boundary: initial[4])
                let rows = try await f.repository.appointments(studentID: f.studentID)
                for kept in [cancelled, absent, detached] {
                    let saved = try await f.cases.appointment(id: kept.id)
                    XCTAssertTrue(saved == kept)
                    XCTAssertTrue(rows.filter { $0.date == kept.date } == [kept])
                }
                XCTAssertTrue(changed.map(\.date) == [initial[4].date, initial[8].date, initial[9].date])
                XCTAssertTrue(rows.count == initial.count)
            }
        }

        func testCompletedAndInProgressRowsStayUnchangedWithoutReplacements() async throws {
            try await withFixture { f in
                let initial = try await series(f)
                // Build persisted status fixtures via domain transitions; no Session workflow is under test.
                let completed = try await f.repository.update(
                    initial[5].startingTraining(sessionID: StableUUID(UUID()), now: now).completingSession(now: now))
                let inProgress = try await f.repository.update(
                    initial[6].startingTraining(sessionID: StableUUID(UUID()), now: now))
                _ = try await edit(f, boundary: initial[4], overrideConflict: true)
                let rows = try await f.repository.appointments(studentID: f.studentID)
                for kept in [completed, inProgress] {
                    let saved = try await f.cases.appointment(id: kept.id)
                    XCTAssertTrue(saved == kept)
                    XCTAssertTrue(rows.filter { $0.date == kept.date } == [kept])
                }
                XCTAssertTrue(rows.count == initial.count)
            }
        }

        func testPreviouslyDeletedFutureDateDoesNotReturn() async throws {
            try await withFixture { f in
                let initial = try await series(f)
                try await f.cases.deleteNeverStartedFutureAppointment(appointmentID: initial[6].id)
                _ = try await edit(f, boundary: initial[4])
                let rows = try await f.repository.appointments(studentID: f.studentID)
                XCTAssertTrue(rows.allSatisfy { $0.date != initial[6].date })
                XCTAssertTrue(rows.map(\.date).sorted() == initial.filter { $0.id != initial[6].id }.map(\.date))
            }
        }

        func testEndDateKeepsTerminationAndOnlySupersededDates() async throws {
            try await withFixture { f in
                let termination = RecurrenceTermination.endDate(try LocalDate(year: 2026, month: 3, day: 25))
                let initial = try await series(f, termination: termination)
                _ = try await f.cases.cancel(appointmentID: initial[5].id, reason: nil)
                try await f.cases.deleteNeverStartedFutureAppointment(appointmentID: initial[6].id)
                let before = try await f.repository.appointments(studentID: f.studentID)
                let expected = before.filter { $0.date >= initial[4].date && $0.status == .scheduled }
                let changed = try await edit(f, boundary: initial[4])
                let replacement = try await f.cases.series(id: XCTUnwrap(changed.first?.seriesID))
                let rows = try await f.repository.appointments(studentID: f.studentID)
                XCTAssertTrue(replacement.termination == termination)
                XCTAssertTrue(changed.map(\.date) == expected.map(\.date))
                XCTAssertTrue(rows.map(\.date).sorted() == before.map(\.date).sorted())
            }
        }

        func testConsecutiveFutureEditsDoNotGrowOrDuplicateDates() async throws {
            try await withFixture { f in
                let initial = try await series(f)
                let first = try await edit(f, boundary: initial[4])
                let eighth = try XCTUnwrap(first.first { $0.date == initial[7].date })
                let second = try await edit(f, boundary: eighth)
                let rows = try await f.repository.appointments(studentID: f.studentID)
                let replacement = try await f.cases.series(id: XCTUnwrap(second.first?.seriesID))
                XCTAssertTrue(rows.map(\.date).sorted() == initial.map(\.date))
                XCTAssertTrue(Set(rows.map(\.date)).count == rows.count)
                XCTAssertTrue(second.map(\.date) == initial.suffix(3).map(\.date))
                XCTAssertTrue(replacement.termination == .repeatCount(3))
            }
        }

        func testConflictLeavesRowsSeriesAndRemindersUnchangedAndOverrideSucceeds() async throws {
            try await withFixture { f in
                let initial = try await series(f)
                let blocker = try await f.cases.createSingle(
                    studentID: f.studentID, date: initial[4].date,
                    startTime: LocalTime(hour: 11, minute: 30), overrideConflict: false)
                let before = try await f.repository.appointments(studentID: f.studentID)
                let old = try await f.cases.series(id: XCTUnwrap(initial[0].seriesID))
                let reminders = await f.notifications.scheduled
                do {
                    _ = try await edit(f, boundary: initial[4])
                    XCTFail("Expected conflict")
                } catch DomainError.conflict {}
                let after = try await f.repository.appointments(studentID: f.studentID)
                let savedSeries = try await f.cases.series(id: old.id)
                let savedReminders = await f.notifications.scheduled
                XCTAssertTrue(after == before)
                XCTAssertTrue(savedSeries == old)
                XCTAssertTrue(savedReminders == reminders)
                let changed = try await edit(f, boundary: initial[4], overrideConflict: true)
                let savedBlocker = try await f.cases.appointment(id: blocker.id)
                let rows = try await f.repository.appointments(studentID: f.studentID)
                XCTAssertTrue(savedBlocker == blocker)
                XCTAssertTrue(changed.map(\.date) == initial.dropFirst(4).map(\.date))
                XCTAssertTrue(rows.filter { $0.seriesID != nil }.map(\.date).sorted() == initial.map(\.date))
            }
        }

        func testRemindersReplaceOnlySupersededAndUseNewSettings() async throws {
            try await withFixture { f in
                let initial = try await series(f)
                _ = try await f.cases.cancel(appointmentID: initial[5].id, reason: nil)
                _ = try await f.cases.markAbsent(appointmentID: initial[6].id, creditChoice: .notCharged)
                let detached = try await f.cases.rescheduleSingle(
                    appointmentID: initial[7].id, startTime: LocalTime(hour: 15, minute: 0), overrideConflict: false)
                let beforeRows = try await f.repository.appointments(studentID: f.studentID)
                let superseded = beforeRows.filter {
                    $0.date >= initial[4].date && $0.status == .scheduled && !$0.isDetachedException
                }
                let reminders = await f.notifications.scheduled
                let changed = try await f.cases.applyThisAndFuture(
                    seriesID: XCTUnwrap(initial[0].seriesID), boundaryDate: initial[4].date,
                    startTime: LocalTime(hour: 11, minute: 30), durationMinutes: 45,
                    reminderEnabled: true, reminderLeadMinutes: .thirty, overrideConflict: false)
                let after = await f.notifications.scheduled
                for old in superseded {
                    XCTAssertTrue(after[AppointmentNotificationIdentifier.make(appointmentID: old.id)] == nil)
                }
                for kept in [initial[0], initial[5], initial[6], detached] {
                    let key = AppointmentNotificationIdentifier.make(appointmentID: kept.id)
                    XCTAssertTrue(after[key] == reminders[key])
                }
                let calendar = TestCalendarProvider(timeZone: TimeZone(secondsFromGMT: 0)!).currentCalendar()
                for row in changed {
                    let descriptor = try XCTUnwrap(after[AppointmentNotificationIdentifier.make(appointmentID: row.id)])
                    XCTAssertTrue(
                        row.durationMinutes == 45 && row.reminderLeadMinutes == .thirty && row.reminderEnabled)
                    XCTAssertTrue(
                        descriptor.fireDate == row.startInstant(calendar: calendar).addingTimeInterval(-30 * 60))
                }
                let untouched = reminders.filter { key, _ in
                    !superseded.contains { AppointmentNotificationIdentifier.make(appointmentID: $0.id) == key }
                }
                XCTAssertTrue(after.count == untouched.count + changed.count)

                let disabled = try await f.cases.applyThisAndFuture(
                    seriesID: XCTUnwrap(changed.first?.seriesID), boundaryDate: changed[0].date,
                    reminderEnabled: false, overrideConflict: false)
                let disabledReminders = await f.notifications.scheduled
                XCTAssertTrue(disabled.allSatisfy { !$0.reminderEnabled })
                XCTAssertTrue(disabledReminders == untouched)
            }
        }

        func testBoundaryFocusOverridesOnlyBoundaryAndLaterFocusIsInherited() async throws {
            try await withFixture { f in
                let initial = try await series(f)
                _ = try await f.cases.updateTrainingFocus(appointmentID: initial[5].id, trainingFocus: [.back])
                _ = try await f.cases.updateTrainingFocus(appointmentID: initial[6].id, trainingFocus: [])
                let before = try await f.repository.appointments(studentID: f.studentID)
                let changed = try await f.cases.applyThisAndFuture(
                    seriesID: XCTUnwrap(initial[0].seriesID), boundaryDate: initial[4].date,
                    boundaryTrainingFocus: [.thighs], overrideConflict: false)
                XCTAssertTrue(changed.first?.trainingFocus == [.thighs])
                for row in changed.dropFirst() {
                    let original = try XCTUnwrap(before.first { $0.date == row.date })
                    XCTAssertTrue(row.trainingFocus == original.trainingFocus)
                }
                XCTAssertTrue(changed.map(\.date) == initial.dropFirst(4).map(\.date))
            }
        }
    }
#endif
