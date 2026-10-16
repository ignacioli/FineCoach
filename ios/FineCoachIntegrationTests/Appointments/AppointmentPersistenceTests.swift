#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    final class AppointmentPersistenceTests: XCTestCase {
        private let now = Date(timeIntervalSince1970: 1_700_000_000)
        private var utc: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            return calendar
        }

        private struct Environment {
            let directory: TemporaryProtectedDirectory
            let controller: PersistenceController
            let studentID: StableUUID
            let appointmentUseCases: AppointmentUseCases
        }

        private func makeEnvironment(
            ids: [UUID],
            studentIDs: [UUID] = []
        ) async throws -> Environment {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let controller = try PersistenceController(storeURL: storeURL)
            let clock = TestClock(utcDate: now)
            let idGenerator = TestIDGenerator(ids: ids)
            let studentRepository = CoreDataStudentRepository(writer: controller.writer)
            let calendarProvider = TestCalendarProvider(timeZone: TimeZone(identifier: "UTC")!)

            let firstStudentID = studentIDs.first ?? UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!
            let studentIDGen = TestIDGenerator(ids: [firstStudentID])
            let studentUseCases = StudentUseCases(repository: studentRepository, clock: clock, ids: studentIDGen)
            let student = try await studentUseCases.create(
                draft: StudentDraft(displayName: "林青", sex: .female)
            )

            let sessionUseCases = ActiveSessionUseCases(
                sessionRepository: CoreDataSessionRepository(writer: controller.writer),
                studentRepository: studentRepository,
                exerciseRepository: CoreDataExerciseRepository(writer: controller.writer),
                sectionRepository: CoreDataSessionSectionRepository(writer: controller.writer),
                recoveryStore: ActiveSessionRecoveryStore(
                    url: directory.url.appendingPathComponent("active-session-recovery-v1.json"),
                    protectedFileStore: ProtectedFileStore()
                ),
                storeGenerationUUID: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!,
                clock: clock,
                ids: idGenerator
            )

            let appointmentUseCases = AppointmentUseCases(
                appointmentRepository: CoreDataAppointmentRepository(writer: controller.writer),
                studentRepository: studentRepository,
                activeSession: sessionUseCases,
                notifications: NotificationScheduler(
                    notificationCenter: FakeNotificationScheduling(),
                    calendarProvider: calendarProvider
                ),
                clock: clock,
                calendarProvider: calendarProvider,
                ids: idGenerator
            )

            return Environment(
                directory: directory,
                controller: controller,
                studentID: student.id,
                appointmentUseCases: appointmentUseCases
            )
        }

        func testSingleAppointmentPersistsAndSurvivesRestart() async throws {
            let appointmentID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
            let env = try await makeEnvironment(ids: [appointmentID])
            let created = try await env.appointmentUseCases.createSingle(
                studentID: env.studentID,
                date: try LocalDate(year: 2026, month: 1, day: 5),
                startTime: try LocalTime(hour: 9, minute: 0),
                overrideConflict: false
            )
            XCTAssertEqual(created.id.rawValue, appointmentID)
            try await env.controller.shutdownForTesting()

            let reopened = try PersistenceController(
                storeURL: env.directory.url.appendingPathComponent("generation/FineCoach.sqlite"))
            let repository = CoreDataAppointmentRepository(writer: reopened.writer)
            let fetched = try await repository.appointment(id: StableUUID(appointmentID))
            XCTAssertEqual(fetched.status, .scheduled)
            XCTAssertEqual(fetched.date, created.date)
            try await reopened.shutdownForTesting()
        }

        func testRecurringSeriesMaterializesAndPersistsAllInstances() async throws {
            let seriesAppointmentIDs = (0..<4).map { UUID(uuidString: "22222222-2222-4222-8222-22222222222\($0)")! }
            let env = try await makeEnvironment(ids: seriesAppointmentIDs + [UUID()])
            // 2026-01-05 is a Monday.
            let first = try LocalDate(year: 2026, month: 1, day: 5)
            let draft = RecurringAppointmentDraft(
                intervalDays: .everyTwoDays,
                termination: .repeatCount(4),
                firstOccurrenceDate: first,
                startTime: try LocalTime(hour: 9, minute: 0)
            )
            let created = try await env.appointmentUseCases.createRecurring(
                studentID: env.studentID,
                draft: draft,
                overrideConflict: false
            )
            XCTAssertEqual(created.count, 4)
            let seriesID = try XCTUnwrap(created.first?.seriesID)
            XCTAssertTrue(created.allSatisfy { $0.seriesID == seriesID })

            try await env.controller.shutdownForTesting()
            let reopened = try PersistenceController(
                storeURL: env.directory.url.appendingPathComponent("generation/FineCoach.sqlite"))
            let repository = CoreDataAppointmentRepository(writer: reopened.writer)
            let persisted = try await repository.appointments(seriesID: seriesID)
            XCTAssertEqual(persisted.count, 4)
            try await reopened.shutdownForTesting()
        }

        func testConflictBlocksSilentSaveAndOverrideAllowsSave() async throws {
            let firstID = UUID(uuidString: "33333333-3333-4333-8333-333333333331")!
            let secondStudentID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000002")!
            let secondAppointmentID = UUID(uuidString: "33333333-3333-4333-8333-333333333332")!
            let env = try await makeEnvironment(ids: [firstID, secondAppointmentID, UUID()])

            let studentRepository = CoreDataStudentRepository(writer: env.controller.writer)
            let secondStudentIDGen = TestIDGenerator(ids: [secondStudentID])
            let secondStudentUseCases = StudentUseCases(
                repository: studentRepository,
                clock: TestClock(utcDate: now),
                ids: secondStudentIDGen
            )
            let secondStudent = try await secondStudentUseCases.create(
                draft: StudentDraft(displayName: "王强", sex: .male))

            _ = try await env.appointmentUseCases.createSingle(
                studentID: env.studentID,
                date: try LocalDate(year: 2026, month: 1, day: 5),
                startTime: try LocalTime(hour: 9, minute: 0),
                durationMinutes: 60,
                overrideConflict: false
            )

            do {
                _ = try await env.appointmentUseCases.createSingle(
                    studentID: secondStudent.id,
                    date: try LocalDate(year: 2026, month: 1, day: 5),
                    startTime: try LocalTime(hour: 9, minute: 30),
                    durationMinutes: 60,
                    overrideConflict: false
                )
                XCTFail("expected conflict to block silent save")
            } catch DomainError.conflict {
                // expected
            }

            let overridden = try await env.appointmentUseCases.createSingle(
                studentID: secondStudent.id,
                date: try LocalDate(year: 2026, month: 1, day: 5),
                startTime: try LocalTime(hour: 9, minute: 30),
                durationMinutes: 60,
                overrideConflict: true
            )
            XCTAssertEqual(overridden.status, .scheduled)

            let conflicts = try await env.appointmentUseCases.detectConflicts(
                date: try LocalDate(year: 2026, month: 1, day: 5),
                startTime: try LocalTime(hour: 9, minute: 15),
                durationMinutes: 30,
                excludingAppointmentID: nil
            )
            XCTAssertEqual(conflicts.count, 2)
            XCTAssertTrue(conflicts.contains { $0.conflictingStudentDisplayName == "林青" })
            XCTAssertTrue(conflicts.contains { $0.conflictingStudentDisplayName == "王强" })
        }

        func testDeleteOnlyAllowedForNeverStartedFutureAppointment() async throws {
            let futureID = UUID(uuidString: "44444444-4444-4444-8444-444444444441")!
            let pastID = UUID(uuidString: "44444444-4444-4444-8444-444444444442")!
            let env = try await makeEnvironment(ids: [futureID, pastID])

            let future = try await env.appointmentUseCases.createSingle(
                studentID: env.studentID,
                date: try LocalDate(year: 2099, month: 1, day: 1),
                startTime: try LocalTime(hour: 9, minute: 0),
                overrideConflict: false
            )
            try await env.appointmentUseCases.deleteNeverStartedFutureAppointment(appointmentID: future.id)

            let past = try await env.appointmentUseCases.createSingle(
                studentID: env.studentID,
                date: try LocalDate(year: 2020, month: 1, day: 1),
                startTime: try LocalTime(hour: 9, minute: 0),
                overrideConflict: false
            )
            do {
                try await env.appointmentUseCases.deleteNeverStartedFutureAppointment(appointmentID: past.id)
                XCTFail("expected deletion of a past appointment to be rejected")
            } catch DomainError.invalidState {
                // expected
            }
        }

        func testThisAndFutureTruncatesOldSeriesAndSurvivesRestart() async throws {
            let seriesAppointmentIDs = (0..<3).map { UUID(uuidString: "55555555-5555-4555-8555-55555555555\($0)")! }
            let env = try await makeEnvironment(
                ids: seriesAppointmentIDs + (0..<5).map { _ in UUID() }
            )
            let first = try LocalDate(year: 2026, month: 1, day: 5)
            let draft = RecurringAppointmentDraft(
                intervalDays: .everyWeek,
                termination: .repeatCount(3),
                firstOccurrenceDate: first,
                startTime: try LocalTime(hour: 9, minute: 0)
            )
            let created = try await env.appointmentUseCases.createRecurring(
                studentID: env.studentID,
                draft: draft,
                overrideConflict: false
            )
            let oldSeriesID = try XCTUnwrap(created.first?.seriesID)
            let boundaryDate = created[1].date

            let newStartTime = try LocalTime(hour: 10, minute: 0)
            let replaced = try await env.appointmentUseCases.applyThisAndFuture(
                seriesID: oldSeriesID,
                boundaryDate: boundaryDate,
                startTime: newStartTime,
                overrideConflict: false
            )
            XCTAssertFalse(replaced.isEmpty)
            XCTAssertTrue(replaced.allSatisfy { $0.startTime == newStartTime })

            try await env.controller.shutdownForTesting()
            let reopened = try PersistenceController(
                storeURL: env.directory.url.appendingPathComponent("generation/FineCoach.sqlite"))
            let repository = CoreDataAppointmentRepository(writer: reopened.writer)

            let oldSeries = try await repository.series(id: oldSeriesID)
            XCTAssertEqual(oldSeries.status, .ended)

            let stillOnOldSeries = try await repository.appointments(seriesID: oldSeriesID)
            XCTAssertEqual(stillOnOldSeries.count, 1)
            XCTAssertEqual(stillOnOldSeries.first?.date, created[0].date)

            let newSeriesID = try XCTUnwrap(replaced.first?.seriesID)
            let newInstances = try await repository.appointments(seriesID: newSeriesID)
            XCTAssertEqual(newInstances.count, replaced.count)
            try await reopened.shutdownForTesting()
        }

        // T077 / M1B-FR-033: a recurring draft's training focus lands on every
        // materialized instance and survives restart.
        func testRecurringDraftTrainingFocusIsCopiedToEveryInstance() async throws {
            let env = try await makeEnvironment(ids: (0..<4).map { _ in UUID() })
            let created = try await env.appointmentUseCases.createRecurring(
                studentID: env.studentID,
                draft: RecurringAppointmentDraft(
                    intervalDays: .everyOtherDay,
                    termination: .repeatCount(3),
                    firstOccurrenceDate: try LocalDate(year: 2026, month: 1, day: 5),
                    startTime: try LocalTime(hour: 9, minute: 0),
                    trainingFocus: [.thighs, .glutes]
                ),
                overrideConflict: false
            )
            XCTAssertTrue(created.allSatisfy { $0.trainingFocus == [.thighs, .glutes] })

            let seriesID = try XCTUnwrap(created.first?.seriesID)
            try await env.controller.shutdownForTesting()
            let reopened = try PersistenceController(
                storeURL: env.directory.url.appendingPathComponent("generation/FineCoach.sqlite"))
            let persisted = try await CoreDataAppointmentRepository(writer: reopened.writer).appointments(
                seriesID: seriesID)
            XCTAssertEqual(persisted.count, 3)
            XCTAssertTrue(persisted.allSatisfy { $0.trainingFocus == [.thighs, .glutes] })
            try await reopened.shutdownForTesting()
        }

        // T077 / D-011: "本次及以后" changes only start time / duration / reminder
        // for later instances; each re-materialized instance keeps its own
        // focus, and only the edited (boundary) instance takes the new focus.
        func testThisAndFutureKeepsPerInstanceFocusAndAppliesEditedFocusOnlyToBoundary() async throws {
            let env = try await makeEnvironment(ids: (0..<10).map { _ in UUID() })
            let created = try await env.appointmentUseCases.createRecurring(
                studentID: env.studentID,
                draft: RecurringAppointmentDraft(
                    intervalDays: .everyWeek,
                    termination: .repeatCount(3),
                    firstOccurrenceDate: try LocalDate(year: 2026, month: 1, day: 5),
                    startTime: try LocalTime(hour: 9, minute: 0),
                    trainingFocus: [.chest]
                ),
                overrideConflict: false
            )
            _ = try await env.appointmentUseCases.updateTrainingFocus(
                appointmentID: created[2].id, trainingFocus: [.back])

            let newStartTime = try LocalTime(hour: 10, minute: 0)
            let replaced = try await env.appointmentUseCases.applyThisAndFuture(
                seriesID: try XCTUnwrap(created[1].seriesID),
                boundaryDate: created[1].date,
                startTime: newStartTime,
                boundaryTrainingFocus: [.thighs],
                overrideConflict: false
            )

            let byDate = Dictionary(uniqueKeysWithValues: replaced.map { ($0.date, $0) })
            XCTAssertEqual(byDate[created[1].date]?.trainingFocus, [.thighs])
            XCTAssertEqual(byDate[created[2].date]?.trainingFocus, [.back])
            XCTAssertTrue(replaced.allSatisfy { $0.startTime == newStartTime })
            let untouched = try await env.appointmentUseCases.appointment(id: created[0].id)
            XCTAssertEqual(untouched.trainingFocus, [.chest])
        }

        // T069a: the Today hero card / in-training bar read the running
        // session's start time and focus from `inProgressTraining()`.
        func testInProgressSummaryCarriesStartTimeAndFocus() async throws {
            let env = try await makeEnvironment(ids: (0..<6).map { _ in UUID() })
            let appointment = try await env.appointmentUseCases.createSingle(
                studentID: env.studentID,
                date: try LocalDate(year: 2023, month: 11, day: 14),
                startTime: try LocalTime(hour: 22, minute: 0),
                trainingFocus: [.chest, .arms],
                overrideConflict: false
            )
            _ = try await env.appointmentUseCases.startTraining(appointmentID: appointment.id)

            let summary = try await CoreDataStudentRepository(writer: env.controller.writer).inProgressTraining()
            let unwrapped = try XCTUnwrap(summary)
            XCTAssertEqual(unwrapped.studentID, env.studentID)
            XCTAssertEqual(unwrapped.trainingFocus, [.chest, .arms])
            XCTAssertEqual(unwrapped.startedAtUTC, now)
            XCTAssertEqual(unwrapped.elapsedMinutes(now: now.addingTimeInterval(32 * 60 + 59)), 32)
            XCTAssertEqual(unwrapped.elapsedMinutes(now: now.addingTimeInterval(-60)), 0)
        }

        // T077: "仅本次" can change schedule and focus in one write; the
        // instance becomes a detached exception.
        // T019 / SC-002 (M1B-FR-004/005): both termination conditions survive a
        // restart, 仅本次 and 本次及以后 stay distinguishable, and instances
        // before the boundary are not touched.
        func testBothTerminationConditionsAndScopeSurviveRestartWithoutTouchingHistory() async throws {
            let env = try await makeEnvironment(ids: (0..<12).map { _ in UUID() })
            let byCount = try await env.appointmentUseCases.createRecurring(
                studentID: env.studentID,
                draft: RecurringAppointmentDraft(
                    intervalDays: .everyWeek,
                    termination: .repeatCount(3),
                    firstOccurrenceDate: try LocalDate(year: 2026, month: 1, day: 5),
                    startTime: try LocalTime(hour: 9, minute: 0)
                ),
                overrideConflict: false
            )
            let byEndDate = try await env.appointmentUseCases.createRecurring(
                studentID: env.studentID,
                draft: RecurringAppointmentDraft(
                    intervalDays: .everyWeek,
                    termination: .endDate(try LocalDate(year: 2026, month: 2, day: 2)),
                    firstOccurrenceDate: try LocalDate(year: 2026, month: 1, day: 6),
                    startTime: try LocalTime(hour: 14, minute: 0)
                ),
                overrideConflict: false
            )
            let countSeriesID = try XCTUnwrap(byCount.first?.seriesID)
            let endDateSeriesID = try XCTUnwrap(byEndDate.first?.seriesID)

            // 仅本次 on the count series' last instance; 本次及以后 on the end-date series.
            let single = try await env.appointmentUseCases.rescheduleSingle(
                appointmentID: byCount[2].id,
                startTime: try LocalTime(hour: 11, minute: 0),
                overrideConflict: false
            )
            XCTAssertTrue(single.isDetachedException)
            let boundary = byEndDate[2].date
            _ = try await env.appointmentUseCases.applyThisAndFuture(
                seriesID: endDateSeriesID,
                boundaryDate: boundary,
                startTime: try LocalTime(hour: 16, minute: 0),
                overrideConflict: false
            )

            try await env.controller.shutdownForTesting()
            let reopened = try PersistenceController(
                storeURL: env.directory.url.appendingPathComponent("generation/FineCoach.sqlite"))
            let repository = CoreDataAppointmentRepository(writer: reopened.writer)

            let countSeries = try await repository.series(id: countSeriesID)
            XCTAssertEqual(countSeries.termination, .repeatCount(3))
            XCTAssertEqual(countSeries.status, .active, "仅本次 must not end the series")
            let countInstances = try await repository.appointments(seriesID: countSeriesID)
            XCTAssertEqual(countInstances.filter(\.isDetachedException).count, 1)

            let endSeries = try await repository.series(id: endDateSeriesID)
            XCTAssertEqual(endSeries.termination, .endDate(try LocalDate(year: 2026, month: 2, day: 2)))
            XCTAssertEqual(endSeries.status, .ended, "本次及以后 ends the old series")

            // Instances before the boundary keep their original date and time.
            let history = try await repository.appointments(seriesID: endDateSeriesID)
            XCTAssertEqual(history.count, 2)
            for (original, kept) in zip(byEndDate.prefix(2), history.sorted { $0.date < $1.date }) {
                XCTAssertEqual(kept.date, original.date)
                XCTAssertEqual(kept.startTime, original.startTime)
            }
            try await reopened.shutdownForTesting()
        }

        func testRescheduleSingleAlsoUpdatesTrainingFocus() async throws {
            let env = try await makeEnvironment(ids: (0..<4).map { _ in UUID() })
            let created = try await env.appointmentUseCases.createRecurring(
                studentID: env.studentID,
                draft: RecurringAppointmentDraft(
                    intervalDays: .everyWeek,
                    termination: .repeatCount(2),
                    firstOccurrenceDate: try LocalDate(year: 2026, month: 1, day: 5),
                    startTime: try LocalTime(hour: 9, minute: 0),
                    trainingFocus: [.chest]
                ),
                overrideConflict: false
            )
            let updated = try await env.appointmentUseCases.rescheduleSingle(
                appointmentID: created[0].id,
                startTime: try LocalTime(hour: 11, minute: 0),
                trainingFocus: [.core],
                overrideConflict: false
            )
            XCTAssertTrue(updated.isDetachedException)
            XCTAssertEqual(updated.trainingFocus, [.core])
            let sibling = try await env.appointmentUseCases.appointment(id: created[1].id)
            XCTAssertEqual(sibling.trainingFocus, [.chest])
        }
    }
#else
    import XCTest

    final class AppointmentPersistenceTests: XCTestCase {
        func testReleaseBuildSkipsDebugOnlyIntegrationCoverage() {
            XCTAssertTrue(true)
        }
    }
#endif
