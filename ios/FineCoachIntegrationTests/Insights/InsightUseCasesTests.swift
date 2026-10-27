#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    final class InsightUseCasesTests: XCTestCase {
        private let now = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z")!

        private var calendar: Calendar {
            var value = Calendar(identifier: .gregorian)
            value.timeZone = TimeZone(secondsFromGMT: 0)!
            return value
        }

        private struct Environment {
            let root: TemporaryProtectedDirectory
            let controller: PersistenceController
            let clock: TestClock
            let students: StudentUseCases
            let sessions: ActiveSessionUseCases
            let history: HistoryUseCases
            let appointments: AppointmentUseCases
            let credits: CreditLedgerUseCases
            let exercises: ExerciseLibraryUseCases
            let insights: InsightUseCases
        }

        private func makeEnvironment(root: TemporaryProtectedDirectory? = nil) throws -> Environment {
            let root = try root ?? TemporaryProtectedDirectory()
            let controller = try PersistenceController(
                storeURL: root.url.appendingPathComponent("generation/FineCoach.sqlite"))
            let clock = TestClock(utcDate: now)
            let ids = SystemIDGenerator()
            let studentRepository = CoreDataStudentRepository(writer: controller.writer)
            let sessionRepository = CoreDataSessionRepository(writer: controller.writer)
            let exerciseRepository = CoreDataExerciseRepository(writer: controller.writer)
            let calendarProvider = TestCalendarProvider(timeZone: TimeZone(secondsFromGMT: 0)!)
            let students = StudentUseCases(repository: studentRepository, clock: clock, ids: ids)
            let history = HistoryUseCases(sessionRepository: sessionRepository, clock: clock, ids: ids)
            let sessions = ActiveSessionUseCases(
                sessionRepository: sessionRepository, studentRepository: studentRepository,
                exerciseRepository: exerciseRepository,
                sectionRepository: CoreDataSessionSectionRepository(writer: controller.writer),
                recoveryStore: ActiveSessionRecoveryStore(
                    url: root.url.appendingPathComponent("active-session-recovery-v1.json"),
                    protectedFileStore: ProtectedFileStore()),
                storeGenerationUUID: UUID(uuidString: "cccccccc-3333-4333-8333-333333333333")!, clock: clock, ids: ids)
            let appointments = AppointmentUseCases(
                appointmentRepository: CoreDataAppointmentRepository(writer: controller.writer),
                studentRepository: studentRepository, activeSession: sessions,
                notifications: NotificationScheduler(
                    notificationCenter: FakeNotificationScheduling(), calendarProvider: calendarProvider),
                clock: clock, calendarProvider: calendarProvider, ids: ids)
            let credits = CreditLedgerUseCases(
                repository: CoreDataCoursePackageRepository(writer: controller.writer), clock: clock, ids: ids)
            let exercises = ExerciseLibraryUseCases(repository: exerciseRepository, clock: clock, ids: ids)
            let insights = InsightUseCases(
                students: students, history: history, appointments: appointments, credits: credits,
                exercises: exercises,
                snoozes: InsightSnoozeStore(directory: root.url), calendarProvider: calendarProvider)
            return Environment(
                root: root, controller: controller, clock: clock, students: students, sessions: sessions,
                history: history, appointments: appointments, credits: credits, exercises: exercises, insights: insights
            )
        }

        private func student(_ env: Environment, age: Int, name: String) async throws -> Student {
            env.clock.setUTC(calendar.date(byAdding: .day, value: -age, to: now)!)
            let student = try await env.students.create(draft: StudentDraft(displayName: name, sex: .undisclosed))
            env.clock.setUTC(now)
            return student
        }

        @discardableResult
        private func book(_ env: Environment, studentID: StableUUID) async throws -> Appointment {
            try await env.appointments.createSingle(
                studentID: studentID, date: LocalDate(date: now, calendar: calendar).addingDays(1, calendar: calendar),
                startTime: LocalTime(hour: 12, minute: 0), reminderEnabled: false, reminderLeadMinutes: nil,
                overrideConflict: true)
        }

        private func complete(_ env: Environment, studentID: StableUUID, daysAgo: Int) async throws {
            env.clock.setUTC(calendar.date(byAdding: .day, value: -daysAgo, to: now)!)
            let session = try await env.sessions.startOrOpen(studentID: studentID)
            let withExercise = try await env.sessions.addSessionOnlyExercise(
                sessionID: session.id, displayName: "虚构计次动作", recordMode: .reps)
            let exercise = try XCTUnwrap(withExercise.exercises.first)
            let withSet = try await env.sessions.addSet(
                sessionID: session.id, exerciseID: exercise.id,
                input: TrainingSetInput(recordMode: .reps, repetitionCount: "8", unit: .repetitions))
            let set = try XCTUnwrap(withSet.exercises.first?.sets.first)
            _ = try await env.sessions.confirmSet(sessionID: session.id, setID: set.id)
            env.clock.advance(seconds: 60)
            _ = try await env.sessions.finish(sessionID: session.id)
            env.clock.setUTC(now)
        }

        func testLoadLedgerExpiryInactivityAutomaticDisappearanceAndStoreRebuild() async throws {
            let env = try makeEnvironment()
            let low = try await student(env, age: 0, name: "虚构课包甲")
            let inactive = try await student(env, age: 60, name: "虚构缺课乙")
            let booked = try await student(env, age: 21, name: "虚构预约丙")
            let archived = try await student(env, age: 21, name: "虚构归档丁")
            let expired = try await student(env, age: 0, name: "虚构过期戊")
            let package = try await env.credits.createActivePackage(
                studentID: low.id, name: nil, totalCredits: 3, startDate: nil, endDate: nil)
            _ = try await env.credits.debitOnSessionComplete(packageID: package.id, sessionID: StableUUID(UUID()))
            _ = try await env.credits.createActivePackage(
                studentID: archived.id, name: nil, totalCredits: 2, startDate: nil, endDate: nil)
            let expiredPackage = try await env.credits.createActivePackage(
                studentID: expired.id, name: nil, totalCredits: 8, startDate: nil,
                endDate: LocalDate(date: now, calendar: calendar).addingDays(-1, calendar: calendar))
            let activeExpired = try await env.credits.activePackage(studentID: expired.id)
            XCTAssertEqual(activeExpired?.id, expiredPackage.id)
            _ = try await env.students.archive(id: archived.id)
            try await complete(env, studentID: inactive.id, daysAgo: 21)
            _ = try await book(env, studentID: booked.id)
            let output = try await env.insights.load(now: now)
            XCTAssertEqual(output.count, 3)
            XCTAssertEqual(output.first { $0.studentID == low.id }?.balance, 2)
            XCTAssertEqual(output.first { $0.studentID == expired.id }?.kind, .packageExpired)
            XCTAssertEqual(output.first { $0.studentID == inactive.id }?.daysInactive, 21)
            XCTAssertEqual(output.first { $0.studentID == inactive.id }?.hasNeverTrained, false)
            XCTAssertFalse(output.contains { $0.studentID == archived.id || $0.studentID == booked.id })
            let own = try await env.insights.studentInsights(studentID: low.id, now: now)
            XCTAssertEqual(own, output.filter { $0.studentID == low.id })
            let archivedInsights = try await env.insights.studentInsights(studentID: archived.id, now: now)
            XCTAssertTrue(archivedInsights.isEmpty)
            try await env.controller.shutdownForTesting()
            let reopened = try makeEnvironment(root: env.root)
            let rebuilt = try await reopened.insights.load(now: now)
            XCTAssertEqual(rebuilt, output)
            _ = try await reopened.credits.endPackage(packageID: package.id)
            _ = try await reopened.credits.createActivePackage(
                studentID: low.id, name: nil, totalCredits: 10, startDate: nil, endDate: nil)
            _ = try await book(reopened, studentID: inactive.id)
            let refreshed = try await reopened.insights.load(now: now)
            XCTAssertEqual(refreshed.map(\.kind), [.packageExpired])
            try await reopened.controller.shutdownForTesting()
        }

        func testSnoozeIsScopedDurableAndExpiresAfterFourteenLocalDays() async throws {
            let env = try makeEnvironment()
            let student = try await student(env, age: 21, name: "虚构暂停己")
            _ = try await env.credits.createActivePackage(
                studentID: student.id, name: nil, totalCredits: 2, startDate: nil, endDate: nil)
            let initial = try await env.insights.load(now: now)
            XCTAssertEqual(initial.map(\.kind), [.packageLow, .inactive])
            try await env.insights.snooze(try XCTUnwrap(initial.first), now: now)
            let filtered = try await env.insights.load(now: now)
            XCTAssertEqual(filtered.map(\.kind), [.inactive])
            try await env.controller.shutdownForTesting()
            let reopened = try makeEnvironment(root: env.root)
            let afterRestart = try await reopened.insights.load(now: now)
            XCTAssertEqual(afterRestart, filtered)
            let boundary = LocalDate(date: now, calendar: calendar).addingDays(14, calendar: calendar).startOfDay(
                calendar: calendar)
            let afterExpiry = try await reopened.insights.studentInsights(studentID: student.id, now: boundary)
            XCTAssertEqual(afterExpiry.map(\.kind), [.packageLow, .inactive])
            try await reopened.controller.shutdownForTesting()
        }

        func testUnsnoozeRestoresInsightAcrossSourcesAndUseCaseRecreation() async throws {
            let env = try makeEnvironment()
            let person = try await student(env, age: 21, name: "虚构撤销学员")
            _ = try await env.credits.createActivePackage(
                studentID: person.id, name: nil, totalCredits: 2, startDate: nil, endDate: nil)
            let initial = try await env.insights.load(now: now)
            let target = try XCTUnwrap(initial.first { $0.kind == .packageLow })
            try await env.insights.snooze(target, now: now)
            let snoozed = try await env.insights.load(now: now)
            XCTAssertFalse(snoozed.contains(target))
            try await env.insights.unsnooze(target)
            let restored = try await env.insights.load(now: now)
            let detail = try await env.insights.studentInsights(studentID: person.id, now: now)
            XCTAssertEqual(restored, initial)
            XCTAssertEqual(detail, initial)
            try await env.controller.shutdownForTesting()
            let reopened = try makeEnvironment(root: env.root)
            let rebuilt = try await reopened.insights.load(now: now)
            XCTAssertEqual(rebuilt, initial)
            try await reopened.controller.shutdownForTesting()
        }

        func testLoadReadsCurrentAssistedPreferenceIncludingHiddenExercises() async throws {
            let env = try makeEnvironment()
            let student = try await student(env, age: 60, name: "虚构辅助庚")
            let item = try await env.exercises.createCustom(name: "虚构辅助动作", recordMode: .weightReps)
            try await env.exercises.setAssisted(id: item.id, isAssisted: true)
            for day in [-40, -3, -2, -1] {
                env.clock.setUTC(calendar.date(byAdding: .day, value: day, to: now)!)
                let session = try await env.sessions.startOrOpen(studentID: student.id)
                let withExercise = try await env.sessions.addCatalogExercise(sessionID: session.id, itemID: item.id)
                let exercise = try XCTUnwrap(withExercise.exercises.first)
                let withSet = try await env.sessions.addSet(
                    sessionID: session.id, exerciseID: exercise.id,
                    input: TrainingSetInput(
                        recordMode: .weightReps, weightValue: day == -40 ? "20" : "30", repetitionCount: "5",
                        unit: .kilograms))
                let set = try XCTUnwrap(withSet.exercises.first?.sets.first)
                _ = try await env.sessions.confirmSet(sessionID: session.id, setID: set.id)
                env.clock.advance(seconds: 60)
                _ = try await env.sessions.finish(sessionID: session.id)
            }
            env.clock.setUTC(now)
            try await env.exercises.setHidden(id: item.id, isHidden: true)
            let assisted = try await env.insights.load(now: now)
            XCTAssertEqual(assisted.count, 1)
            XCTAssertEqual(assisted.first?.baselineMetric, .lowestAssistance)
            XCTAssertEqual(assisted.first?.baselineBest, try DecimalValue("20"))
            try await env.exercises.setAssisted(id: item.id, isAssisted: false)
            let ordinary = try await env.insights.load(now: now)
            XCTAssertTrue(ordinary.isEmpty)
            try await env.controller.shutdownForTesting()
        }

        func testSnoozeRemovesSameInsightFromTodayAndStudentDetailSources() async throws {
            let env = try makeEnvironment()
            let person = try await student(env, age: 21, name: "虚构跨页学员")
            _ = try await env.credits.createActivePackage(
                studentID: person.id, name: nil, totalCredits: 2, startDate: nil, endDate: nil)
            let todayBefore = try await env.insights.load(now: now)
            let detailBefore = try await env.insights.studentInsights(studentID: person.id, now: now)
            let target = try XCTUnwrap(todayBefore.first(where: { $0.kind == .packageLow }))
            XCTAssertTrue(detailBefore.contains(target))
            try await env.insights.snooze(target, now: now)
            let todayAfter = try await env.insights.load(now: now)
            let detailAfter = try await env.insights.studentInsights(studentID: person.id, now: now)
            XCTAssertFalse(todayAfter.contains(where: { $0.id == target.id }))
            XCTAssertFalse(detailAfter.contains(where: { $0.id == target.id }))
            XCTAssertEqual(todayAfter.map(\.kind), [.inactive])
            XCTAssertEqual(detailAfter, todayAfter)
            try await env.controller.shutdownForTesting()
        }

        @MainActor
        func testBackupExportExcludesSnoozeDocumentAndItsOpaqueIDs() async throws {
            let root = try TemporaryProtectedDirectory()
            let destination = try TemporaryProtectedDirectory()
            let environment = try AppEnvironment(
                rootURL: root.url, clock: TestClock(utcDate: now),
                notificationCenter: FakeNotificationScheduling())
            // These IDs intentionally belong only to the snooze file, not to business records.
            let studentID = StableUUID(UUID(uuidString: "aaaaaaaa-1111-4111-8111-111111111111")!)
            let exerciseID = try StableExerciseID("bbbbbbbb-2222-4222-8222-222222222222")
            let store = InsightSnoozeStore(directory: root.url)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let insight = Insight(kind: .stagnant, studentID: studentID, exerciseID: exerciseID)
            try await store.snooze(insight, now: now, calendar: calendar)
            let keys = await store.activeKeys(now: now, calendar: calendar)
            XCTAssertEqual(keys, [insight.snoozeKey])
            let password = try BackupPassword(creating: "虚构备份口令甲乙丙丁")
            let result = try await environment.requireBackupCoordinator().exportInventory(
                BackupExportRequest(password: password, destinationDirectory: destination.url))
            let plaintext = try BackupContainerCodec.decrypt(
                container: Data(contentsOf: result.fileURL), password: password)
            XCTAssertFalse(plaintext.isEmpty)
            let content = String(decoding: plaintext, as: UTF8.self).lowercased()
            XCTAssertFalse(content.contains("snoozes"))
            XCTAssertFalse(content.contains(studentID.rawValue.uuidString.lowercased()))
            XCTAssertFalse(content.contains(exerciseID.rawValue.lowercased()))
        }
    }
#endif
