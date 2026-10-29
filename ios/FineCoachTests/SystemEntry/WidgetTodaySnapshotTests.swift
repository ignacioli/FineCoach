import XCTest

@testable import FineCoach

final class WidgetTodaySnapshotTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 9))! }
    private let studentID = StableUUID(UUID())

    private func appointment(hour: Int, status: AppointmentStatus = .scheduled, day: Int = 28) throws -> Appointment {
        try Appointment(
            id: StableUUID(UUID()), studentID: studentID, seriesID: nil,
            date: LocalDate(year: 2026, month: 10, day: day), startTime: LocalTime(hour: hour, minute: 0),
            status: status, createdAtUTC: now, updatedAtUTC: now)
    }

    func testSnapshotAndEntryJSONKeysExactlyMatchAllowlistAndExcludeSensitiveFixtureValues() throws {
        let student = try StudentDraft(
            displayName: "虚构学员甲", sex: .female, trainingGoal: "虚构训练目标",
            injuryNotes: "虚构伤病说明", privateCoachNote: "虚构私密备注"
        ).makeStudent(id: studentID, now: now)
        let package = try CoursePackage(
            id: StableUUID(UUID()), studentID: studentID, name: ValidatedText("虚构课包甲"),
            totalCredits: 12, createdAtUTC: now, updatedAtUTC: now)
        let body = try BodyMeasurement(
            id: StableUUID(UUID()), studentID: studentID, metricID: StableUUID(UUID()),
            localCalendarDay: LocalDate(date: now, calendar: calendar), value: DecimalValue("987.654"),
            enteredUnit: "虚构身体指标", createdAtUTC: now, updatedAtUTC: now)
        let associated = [
            package.name!.value, body.value.canonicalString, body.enteredUnit, student.sex.rawValue,
            student.injuryNotes!.value, student.privateCoachNote!.value, student.trainingGoal!.value,
        ]
        let fixture = (student: student, package: package, body: body)
        let snapshot = WidgetTodaySnapshot.build(
            appointments: [try appointment(hour: 10)], studentDisplayName: { _ in fixture.student.displayName.value },
            now: now, calendar: calendar)
        let data = try JSONEncoder().encode(snapshot)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["formatVersion", "localDate", "generatedAtUTC", "entries", "finishedCount"])
        let entry = try XCTUnwrap((json["entries"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(entry.keys), ["startAtUTC", "studentDisplayName", "appointmentID"])
        XCTAssertEqual(entry["studentDisplayName"] as? String, student.displayName.value)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        for value in associated { XCTAssertFalse(encoded.contains(value), value) }
        XCTAssertEqual(try JSONDecoder().decode(WidgetTodaySnapshot.self, from: data), snapshot)
    }

    func testFiltersSortsAndCountsOnlyCompletedAndAbsentToday() throws {
        let snapshot = WidgetTodaySnapshot.build(
            appointments: [
                try appointment(hour: 14), try appointment(hour: 8, status: .inProgress),
                try appointment(hour: 7, status: .completed), try appointment(hour: 6, status: .absent),
                try appointment(hour: 5, status: .cancelled), try appointment(hour: 10, day: 29),
            ], studentDisplayName: { _ in "虚构学员甲" }, now: now, calendar: calendar)
        XCTAssertEqual(snapshot.entries.map { calendar.component(.hour, from: $0.startAtUTC) }, [8, 14])
        XCTAssertEqual(snapshot.finishedCount, 2)
        XCTAssertEqual(snapshot.remainingCount(at: now, calendar: calendar), 2)
    }

    func testNextEntryChoosesUpcomingThenFallsBackToFirstWhenAllPast() throws {
        let snapshot = WidgetTodaySnapshot.build(
            appointments: [try appointment(hour: 8), try appointment(hour: 10)],
            studentDisplayName: { _ in "虚构学员甲" }, now: now, calendar: calendar)
        XCTAssertEqual(snapshot.nextEntry(at: now, calendar: calendar), snapshot.entries[1])
        XCTAssertEqual(snapshot.nextEntry(at: snapshot.entries[1].startAtUTC, calendar: calendar), snapshot.entries[1])
        XCTAssertEqual(snapshot.nextEntry(at: now.addingTimeInterval(7200), calendar: calendar), snapshot.entries[0])
    }

    func testNoClassesAndAllFinishedHaveDistinctEmptyStates() {
        for finished in [0, 2] {
            let snapshot = WidgetTodaySnapshot(
                localDate: "2026-10-28", generatedAtUTC: now, entries: [], finishedCount: finished)
            XCTAssertEqual(
                snapshot.displayState(at: now, calendar: calendar), finished == 0 ? .noClasses : .allFinished)
            XCTAssertNil(snapshot.nextEntry(at: now, calendar: calendar))
            XCTAssertEqual(snapshot.remainingCount(at: now, calendar: calendar), 0)
        }
    }

    func testMidnightAndUnsupportedVersionHideAllOldNames() throws {
        let snapshot = WidgetTodaySnapshot.build(
            appointments: [try appointment(hour: 10)], studentDisplayName: { _ in "虚构学员甲" },
            now: now, calendar: calendar)
        for candidate in [
            snapshot,
            WidgetTodaySnapshot(
                formatVersion: 99, localDate: snapshot.localDate, generatedAtUTC: now,
                entries: snapshot.entries, finishedCount: 0),
        ] {
            let date = candidate.formatVersion == 99 ? now : now.addingTimeInterval(86400)
            XCTAssertEqual(candidate.displayState(at: date, calendar: calendar), .placeholder)
            XCTAssertNil(candidate.nextEntry(at: date, calendar: calendar))
            XCTAssertTrue(candidate.mediumEntries(at: date, calendar: calendar).isEmpty)
            XCTAssertEqual(candidate.remainingCount(at: date, calendar: calendar), 0)
        }
    }

    func testLocalDateAndStartTimeUseInjectedTimeZone() throws {
        var tokyo = calendar
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let lateUTC = now.addingTimeInterval(15 * 3600 - 1)
        let snapshot = WidgetTodaySnapshot.build(
            appointments: [try appointment(hour: 10, day: 29), try appointment(hour: 10)],
            studentDisplayName: { _ in "虚构学员甲" }, now: lateUTC, calendar: tokyo)
        XCTAssertEqual(snapshot.localDate, "2026-10-29")
        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertEqual(tokyo.component(.hour, from: snapshot.entries[0].startAtUTC), 10)
        XCTAssertEqual(snapshot.displayState(at: lateUTC, calendar: calendar), .placeholder)
    }

    func testMediumListsAtMostThreeRemainingEntries() throws {
        for count in 1...5 {
            let snapshot = WidgetTodaySnapshot.build(
                appointments: try (10..<(10 + count)).map { try appointment(hour: $0) },
                studentDisplayName: { _ in "虚构学员甲" }, now: now, calendar: calendar)
            XCTAssertEqual(snapshot.mediumEntries(at: now, calendar: calendar).count, min(3, count))
        }
    }

    func testTimelineCoversNowFutureStartsAndNextLocalMidnightAcrossDST() throws {
        var la = calendar
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = la.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let nextMidnight = la.date(byAdding: .day, value: 1, to: start)!
        let snapshot = WidgetTodaySnapshot(
            localDate: WidgetTodaySnapshot.dateKey(start, calendar: la), generatedAtUTC: start,
            entries: [
                .init(startAtUTC: start.addingTimeInterval(7200), studentDisplayName: "虚构学员甲", appointmentID: "opaque")
            ],
            finishedCount: 0)
        XCTAssertEqual(
            WidgetTodaySnapshot.timelineDates(snapshot: snapshot, now: start, calendar: la),
            [start, start.addingTimeInterval(7200), start.addingTimeInterval(7201), nextMidnight])
        XCTAssertEqual(nextMidnight.timeIntervalSince(start), 25 * 3600)
        XCTAssertEqual(snapshot.displayState(at: nextMidnight, calendar: la), .placeholder)
        XCTAssertEqual(
            WidgetTodaySnapshot.timelineDates(snapshot: nil, now: start, calendar: la), [start, nextMidnight])
    }
}

#if DEBUG
    @MainActor
    final class WidgetSnapshotRefreshHookTests: XCTestCase {
        private struct Fixture {
            let directory: TemporaryProtectedDirectory
            let controller: PersistenceController
            let faults: TestFaultInjector
            let publisher: FakeWidgetSnapshotPublisher
            let students: StudentUseCases
            let sessions: ActiveSessionUseCases
            let appointments: AppointmentUseCases
            let studentID: StableUUID
            let today: LocalDate
        }

        private func fixture() async throws -> Fixture {
            let directory = try TemporaryProtectedDirectory()
            let faults = TestFaultInjector()
            let controller = try PersistenceController(
                storeURL: directory.url.appendingPathComponent("store/FineCoach.sqlite"),
                faultInjectionBoundary: FaultInjectionBoundary(injector: faults))
            let now = Calendar.current.startOfDay(for: Date())
            let clock = TestClock(utcDate: now)
            let publisher = FakeWidgetSnapshotPublisher()
            let repository = CoreDataStudentRepository(writer: controller.writer)
            let students = StudentUseCases(
                repository: repository, clock: clock, ids: SystemIDGenerator(), widgetSnapshots: publisher)
            let student = try await students.create(draft: StudentDraft(displayName: "虚构学员甲", sex: .undisclosed))
            let sessions = ActiveSessionUseCases(
                sessionRepository: CoreDataSessionRepository(writer: controller.writer), studentRepository: repository,
                exerciseRepository: CoreDataExerciseRepository(writer: controller.writer),
                sectionRepository: CoreDataSessionSectionRepository(writer: controller.writer),
                recoveryStore: ActiveSessionRecoveryStore(url: directory.url.appendingPathComponent("recovery.json")),
                storeGenerationUUID: UUID(), clock: clock, ids: SystemIDGenerator(), widgetSnapshots: publisher)
            let appointments = AppointmentUseCases(
                appointmentRepository: CoreDataAppointmentRepository(writer: controller.writer),
                studentRepository: repository,
                activeSession: sessions,
                notifications: NotificationScheduler(
                    notificationCenter: FakeNotificationScheduling(), calendarProvider: SystemLocalCalendarProvider()),
                clock: clock, calendarProvider: SystemLocalCalendarProvider(), ids: SystemIDGenerator(),
                widgetSnapshots: publisher)
            return Fixture(
                directory: directory, controller: controller, faults: faults, publisher: publisher,
                students: students, sessions: sessions, appointments: appointments, studentID: student.id,
                today: LocalDate(date: now, calendar: .current))
        }

        private func create(_ f: Fixture) async throws -> Appointment {
            try await f.appointments.createSingle(
                studentID: f.studentID, date: f.today,
                startTime: LocalTime(hour: 12, minute: 0), overrideConflict: true)
        }

        private func assertOne(_ publisher: FakeWidgetSnapshotPublisher, action: () async throws -> Void) async throws {
            let before = await publisher.refreshCount
            try await action()
            let after = await publisher.refreshCount
            XCTAssertEqual(after, before + 1)
        }

        func testAppointmentCreateRescheduleCancelAbsentDeleteStartCompleteAndAbandonRefreshOnce() async throws {
            let f = try await fixture()
            try await assertOne(f.publisher) { _ = try await create(f) }
            let a = try await create(f)
            try await assertOne(f.publisher) {
                _ = try await f.appointments.rescheduleSingle(
                    appointmentID: a.id, startTime: LocalTime(hour: 13, minute: 0), overrideConflict: true)
            }
            try await assertOne(f.publisher) { _ = try await f.appointments.cancel(appointmentID: a.id, reason: nil) }
            let absent = try await create(f)
            try await assertOne(f.publisher) {
                _ = try await f.appointments.markAbsent(appointmentID: absent.id, creditChoice: .notCharged)
            }
            let deleted = try await create(f)
            try await assertOne(f.publisher) {
                try await f.appointments.deleteNeverStartedFutureAppointment(appointmentID: deleted.id)
            }
            let started = try await create(f)
            try await assertOne(f.publisher) { _ = try await f.appointments.startTraining(appointmentID: started.id) }
            try await assertOne(f.publisher) {
                _ = try await f.appointments.abandonEmptySession(appointmentID: started.id)
            }
            _ = try await f.appointments.startTraining(appointmentID: started.id)
            try await assertOne(f.publisher) { _ = try await f.appointments.completeSession(appointmentID: started.id) }
            try await f.controller.shutdownForTesting()
        }

        func testRecurringCreateAndThisAndFutureRefreshOncePerOperation() async throws {
            let f = try await fixture()
            let before = await f.publisher.refreshCount
            let series = try await f.appointments.createRecurring(
                studentID: f.studentID,
                draft: RecurringAppointmentDraft(
                    intervalDays: .everyWeek, termination: .repeatCount(3),
                    firstOccurrenceDate: f.today, startTime: LocalTime(hour: 12, minute: 0)), overrideConflict: true)
            let after = await f.publisher.refreshCount
            XCTAssertEqual(after, before + 1)
            try await assertOne(f.publisher) {
                _ = try await f.appointments.applyThisAndFuture(
                    seriesID: XCTUnwrap(series.first?.seriesID),
                    boundaryDate: f.today, startTime: LocalTime(hour: 13, minute: 0), overrideConflict: true)
            }
            try await f.controller.shutdownForTesting()
        }

        func testStudentRenameAndArchiveRefreshOnceAndUnchangedNameDoesNotRefresh() async throws {
            let f = try await fixture()
            let initial = await f.publisher.refreshCount
            _ = try await f.students.update(
                id: f.studentID, draft: StudentDraft(displayName: "虚构学员甲", sex: .undisclosed))
            let unchanged = await f.publisher.refreshCount
            XCTAssertEqual(unchanged, initial)
            try await assertOne(f.publisher) {
                _ = try await f.students.update(
                    id: f.studentID, draft: StudentDraft(displayName: "虚构学员乙", sex: .undisclosed))
            }
            try await assertOne(f.publisher) { _ = try await f.students.archive(id: f.studentID) }
            try await f.controller.shutdownForTesting()
        }

        func testActiveSessionAbandonAndFinishRefreshOnce() async throws {
            let f = try await fixture()
            _ = try await f.sessions.startOrOpen(studentID: f.studentID)
            try await assertOne(f.publisher) { _ = try await f.sessions.abandonEmpty() }
            _ = try await f.sessions.startOrOpen(studentID: f.studentID)
            let session = try await f.sessions.addSessionOnlyExercise(displayName: "虚构计次动作", recordMode: .reps)
            let exercise = try XCTUnwrap(session.exercises.first)
            let withSet = try await f.sessions.addSet(
                exerciseID: exercise.id,
                input: TrainingSetInput(recordMode: .reps, repetitionCount: "5", unit: .repetitions))
            _ = try await f.sessions.confirmSet(setID: XCTUnwrap(withSet.exercises.first?.sets.first?.id))
            try await assertOne(f.publisher) { _ = try await f.sessions.finish() }
            try await f.controller.shutdownForTesting()
        }

        func testFailedBusinessWritesNeverRequestRefresh() async throws {
            let f = try await fixture()
            let a = try await create(f)
            let initial = await f.publisher.refreshCount
            f.faults.setFailure(at: .persistenceWriterSave, enabled: true)
            let actions: [() async throws -> Void] = [
                { _ = try await self.create(f) },
                {
                    _ = try await f.appointments.rescheduleSingle(
                        appointmentID: a.id, startTime: LocalTime(hour: 13, minute: 0), overrideConflict: true)
                },
                { _ = try await f.appointments.cancel(appointmentID: a.id, reason: nil) },
                { _ = try await f.appointments.markAbsent(appointmentID: a.id, creditChoice: .notCharged) },
                { try await f.appointments.deleteNeverStartedFutureAppointment(appointmentID: a.id) },
                { _ = try await f.appointments.startTraining(appointmentID: a.id) },
                {
                    _ = try await f.students.update(
                        id: f.studentID, draft: StudentDraft(displayName: "虚构学员乙", sex: .undisclosed))
                },
                { _ = try await f.students.archive(id: f.studentID) },
            ]
            for action in actions {
                do {
                    try await action()
                    XCTFail("Expected injected write failure")
                } catch {}
                let count = await f.publisher.refreshCount
                XCTAssertEqual(count, initial)
            }
            f.faults.setFailure(at: .persistenceWriterSave, enabled: false)
            try await f.controller.shutdownForTesting()
        }

        func testFailedRecurringAndThisAndFutureWritesDoNotRefresh() async throws {
            let f = try await fixture()
            let draft = try RecurringAppointmentDraft(
                intervalDays: .everyWeek, termination: .repeatCount(3),
                firstOccurrenceDate: f.today, startTime: LocalTime(hour: 12, minute: 0))
            let series = try await f.appointments.createRecurring(
                studentID: f.studentID, draft: draft, overrideConflict: true)
            let initial = await f.publisher.refreshCount
            f.faults.setFailure(at: .persistenceWriterSave, enabled: true)
            do {
                _ = try await f.appointments.createRecurring(
                    studentID: f.studentID, draft: draft, overrideConflict: true)
                XCTFail("Expected injected recurring write failure")
            } catch {}
            do {
                _ = try await f.appointments.applyThisAndFuture(
                    seriesID: XCTUnwrap(series.first?.seriesID),
                    boundaryDate: f.today, overrideConflict: true)
                XCTFail("Expected injected series replacement failure")
            } catch {}
            let count = await f.publisher.refreshCount
            XCTAssertEqual(count, initial)
            f.faults.setFailure(at: .persistenceWriterSave, enabled: false)
            try await f.controller.shutdownForTesting()
        }

        func testFailedAppointmentCompleteAndAbandonWritesDoNotRefresh() async throws {
            let f = try await fixture()
            let a = try await create(f)
            _ = try await f.appointments.startTraining(appointmentID: a.id)
            let initial = await f.publisher.refreshCount
            f.faults.setFailure(at: .persistenceWriterSave, enabled: true)
            do {
                _ = try await f.appointments.completeSession(appointmentID: a.id)
                XCTFail("Expected injected completion failure")
            } catch {}
            do {
                _ = try await f.appointments.abandonEmptySession(appointmentID: a.id)
                XCTFail("Expected injected abandon failure")
            } catch {}
            let count = await f.publisher.refreshCount
            XCTAssertEqual(count, initial)
            f.faults.setFailure(at: .persistenceWriterSave, enabled: false)
            try await f.controller.shutdownForTesting()
        }

        func testFailedActiveSessionFinishAndAbandonWritesDoNotRefresh() async throws {
            for finishing in [false, true] {
                let f = try await fixture()
                _ = try await f.sessions.startOrOpen(studentID: f.studentID)
                if finishing {
                    let session = try await f.sessions.addSessionOnlyExercise(displayName: "虚构计次动作", recordMode: .reps)
                    let exercise = try XCTUnwrap(session.exercises.first)
                    let withSet = try await f.sessions.addSet(
                        exerciseID: exercise.id,
                        input: TrainingSetInput(recordMode: .reps, repetitionCount: "5", unit: .repetitions))
                    _ = try await f.sessions.confirmSet(setID: XCTUnwrap(withSet.exercises.first?.sets.first?.id))
                }
                let initial = await f.publisher.refreshCount
                f.faults.setFailure(at: .persistenceWriterSave, enabled: true)
                do {
                    if finishing { _ = try await f.sessions.finish() } else { _ = try await f.sessions.abandonEmpty() }
                    XCTFail("Expected injected session write failure")
                } catch {}
                let count = await f.publisher.refreshCount
                XCTAssertEqual(count, initial)
                f.faults.setFailure(at: .persistenceWriterSave, enabled: false)
                try await f.controller.shutdownForTesting()
            }
        }

        func testForegroundRefreshUsesInjectedPublisher() async throws {
            let directory = try TemporaryProtectedDirectory()
            let publisher = FakeWidgetSnapshotPublisher()
            let environment = try AppEnvironment(
                rootURL: directory.url, notificationCenter: FakeNotificationScheduling(),
                widgetSnapshotPublisher: publisher, sessionActivityController: NoopSessionActivityController())
            await AppLifecycleCoordinator().sceneDidBecomeActive(environment: environment)
            let count = await publisher.refreshCount
            XCTAssertEqual(count, 1)
        }
    }
#endif
