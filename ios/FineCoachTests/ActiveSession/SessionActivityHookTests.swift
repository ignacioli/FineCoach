#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    @MainActor
    final class SessionActivityHookTests: XCTestCase {
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        func testStartReopenAndTwoFictitiousStudentsKeepOneActivityPerSession() async throws {
            let fixture = try makeFixture()
            let first = try await fixture.student("虚构学员甲")
            let second = try await fixture.student("虚构学员乙")
            let a = try await fixture.sessions.startOrOpen(studentID: first.id)
            let reopened = try await fixture.sessions.startOrOpen(studentID: first.id)
            let b = try await fixture.sessions.startOrOpen(studentID: second.id)
            XCTAssertEqual(reopened.id, a.id)
            let calls = await fixture.activities.calls
            XCTAssertEqual(calls.count, 3)
            let activities = await fixture.activities.activities
            XCTAssertEqual(Set(activities.keys), [id(a), id(b)])
            _ = try await fixture.sessions.abandonEmpty(sessionID: a.id)
            let remaining = await fixture.activities.activities
            XCTAssertEqual(Set(remaining.keys), [id(b)])
            let ended = await fixture.activities.calls.filter { $0 == .end(id(a)) }
            XCTAssertEqual(ended.count, 1)
            try await fixture.persistence.shutdownForTesting()
        }

        func testConfirmAdjustBothDirectionsAndDismissEachPublishOnceWithoutChangingNotifications() async throws {
            let fixture = try makeFixture()
            let vm = try await makeViewModel(fixture)
            let baseline = await fixture.activities.calls.count
            vm.weight = "60"
            vm.reps = "8"
            await vm.confirmActiveDraftSet()
            await vm.sessionActivityTask?.value
            var calls = await fixture.activities.calls
            XCTAssertEqual(calls.count, baseline + 1)
            let session = try XCTUnwrap(vm.session)
            let end = now.addingTimeInterval(120)
            XCTAssertEqual(calls.last, .update(id(session), content("深蹲", count: 1, end: end)))
            vm.adjustRest(by: 15)
            await vm.sessionActivityTask?.value
            calls = await fixture.activities.calls
            XCTAssertEqual(calls.count, baseline + 2)
            XCTAssertEqual(calls.last, .update(id(session), content("深蹲", count: 1, end: end.addingTimeInterval(15))))
            vm.adjustRest(by: -15)
            await vm.sessionActivityTask?.value
            calls = await fixture.activities.calls
            XCTAssertEqual(calls.count, baseline + 3)
            XCTAssertEqual(calls.last, .update(id(session), content("深蹲", count: 1, end: end)))
            vm.dismissRest()
            await vm.sessionActivityTask?.value
            calls = await fixture.activities.calls
            XCTAssertEqual(calls.count, baseline + 4)
            XCTAssertEqual(calls.last, .update(id(session), content("深蹲", count: 1, end: nil)))
            try await fixture.persistence.shutdownForTesting()
        }

        func testExplicitDraftConfirmationPublishesOnce() async throws {
            let fixture = try makeFixture()
            let vm = try await makeViewModel(fixture)
            vm.weight = "60"
            vm.reps = "8"
            await vm.addDraftSet()
            let set = try XCTUnwrap(vm.currentExercise?.sets.last)
            let baseline = await fixture.activities.calls.count
            await vm.confirmSet(setID: set.id)
            await vm.sessionActivityTask?.value
            let calls = await fixture.activities.calls
            XCTAssertEqual(calls.count, baseline + 1)
            XCTAssertEqual(
                calls.last,
                .update(id(try XCTUnwrap(vm.session)), content("深蹲", count: 1, end: now.addingTimeInterval(120))))
            try await fixture.persistence.shutdownForTesting()
        }

        func testExerciseSwitchUsesSelectedExerciseCountAndRestRestorePublishesWithoutNotificationReplay() async throws
        {
            let fixture = try makeFixture()
            let store = RestTimerStore()
            let vm = try await makeViewModel(fixture, store: store)
            let firstExercise = try XCTUnwrap(vm.currentExercise)
            vm.weight = "60"
            vm.reps = "8"
            await vm.confirmActiveDraftSet()
            await vm.sessionActivityTask?.value
            let sessionID = try XCTUnwrap(vm.session?.id)
            _ = try await fixture.sessions.addSessionOnlyExercise(
                sessionID: sessionID, displayName: "卧推", recordMode: .weightReps)
            let notifications = FakeNotificationScheduling()
            let restored = ActiveSessionViewModel(
                studentID: vm.studentID, useCases: fixture.sessions, notifications: notifications,
                restTimerStore: store, now: { [now] in now })
            let baseline = await fixture.activities.calls.count
            await restored.load()
            await restored.sessionActivityTask?.value
            var calls = await fixture.activities.calls
            XCTAssertEqual(calls.count, baseline + 2, "ensure existence plus one restored-content update")
            XCTAssertEqual(
                calls.last,
                .update(
                    sessionID.rawValue.uuidString.lowercased(),
                    content("卧推", count: 0, end: now.addingTimeInterval(120))))
            let scheduled = await notifications.scheduled
            XCTAssertTrue(scheduled.isEmpty)
            restored.selectExercise(firstExercise.id)
            await restored.sessionActivityTask?.value
            calls = await fixture.activities.calls
            XCTAssertEqual(calls.count, baseline + 3)
            XCTAssertEqual(
                calls.last,
                .update(
                    sessionID.rawValue.uuidString.lowercased(),
                    content("深蹲", count: 1, end: now.addingTimeInterval(120))))
            try await fixture.persistence.shutdownForTesting()
        }

        func testFinishEndsOnceAfterDurableSaveAndDoesNotUpdateTerminatedActivity() async throws {
            let fixture = try makeFixture()
            let vm = try await makeViewModel(fixture)
            vm.weight = "60"
            vm.reps = "8"
            await vm.confirmActiveDraftSet()
            await vm.sessionActivityTask?.value
            let session = try XCTUnwrap(vm.session)
            let baseline = await fixture.activities.calls.count
            await vm.finishNow()
            await vm.sessionActivityTask?.value
            let calls = await fixture.activities.calls
            XCTAssertEqual(calls.count, baseline + 1)
            XCTAssertEqual(calls.last, .end(id(session)))
            let active = try await fixture.sessions.loadActive(sessionID: session.id)
            XCTAssertNil(active)
            try await fixture.persistence.shutdownForTesting()
        }

        func testFailedStartDoesNotCreateActivity() async throws {
            let fixture = try makeFixture()
            let student = try await fixture.student("虚构学员甲")
            fixture.faults.setFailure(at: .persistenceWriterSave, enabled: true)
            do {
                _ = try await fixture.sessions.startOrOpen(studentID: student.id)
                XCTFail("Expected save failure")
            } catch FaultInjectionError.injected(.persistenceWriterSave) {}
            _ = try await fixture.sessions.startOrOpen(studentID: student.id)
            let calls = await fixture.activities.calls
            XCTAssertTrue(calls.isEmpty)
            try await fixture.persistence.shutdownForTesting()
        }

        func testFailedConfirmationDoesNotPublish() async throws {
            let fixture = try makeFixture()
            let vm = try await makeViewModel(fixture)
            vm.weight = "60"
            vm.reps = "8"
            await vm.addDraftSet()
            let set = try XCTUnwrap(vm.currentExercise?.sets.last)
            let baseline = await fixture.activities.calls.count
            fixture.faults.setFailure(at: .persistenceWriterSave, enabled: true)
            await vm.confirmSet(setID: set.id)
            await vm.sessionActivityTask?.value
            let count = await fixture.activities.calls.count
            XCTAssertEqual(count, baseline)
            XCTAssertNotNil(vm.errorMessage)
            try await fixture.persistence.shutdownForTesting()
        }

        func testFailedFinishDoesNotEndActivity() async throws {
            let fixture = try makeFixture()
            let vm = try await makeViewModel(fixture)
            vm.weight = "60"
            vm.reps = "8"
            await vm.confirmActiveDraftSet()
            await vm.sessionActivityTask?.value
            let baseline = await fixture.activities.calls.count
            fixture.faults.setFailure(at: .persistenceWriterSave, enabled: true)
            await vm.finishNow()
            let count = await fixture.activities.calls.count
            XCTAssertEqual(count, baseline)
            XCTAssertNotNil(vm.errorMessage)
            try await fixture.persistence.shutdownForTesting()
        }

        func testFailedAbandonDoesNotEndActivity() async throws {
            let fixture = try makeFixture()
            let student = try await fixture.student("虚构学员甲")
            let session = try await fixture.sessions.startOrOpen(studentID: student.id)
            fixture.faults.setFailure(at: .persistenceWriterSave, enabled: true)
            do {
                _ = try await fixture.sessions.abandonEmpty(sessionID: session.id)
                XCTFail("Expected save failure")
            } catch FaultInjectionError.injected(.persistenceWriterSave) {}
            let calls = await fixture.activities.calls
            XCTAssertEqual(calls.count, 1)
            let activities = await fixture.activities.activities
            XCTAssertNotNil(activities[id(session)])
            try await fixture.persistence.shutdownForTesting()
        }

        func testLaunchCleanupReceivesOnlyPersistedActiveSessionIDs() async throws {
            let directory = try TemporaryProtectedDirectory()
            let fake = FakeSessionActivityController()
            let environment = try AppEnvironment(
                rootURL: directory.url, notificationCenter: FakeNotificationScheduling(),
                widgetSnapshotPublisher: NoopWidgetSnapshotPublisher(), sessionActivityController: fake)
            let students = try XCTUnwrap(environment.studentUseCases)
            let sessions = try XCTUnwrap(environment.sessionUseCases)
            let student = try await students.create(draft: StudentDraft(displayName: "虚构学员甲", sex: .female))
            let session = try await sessions.startOrOpen(studentID: student.id)
            let orphan = UUID().uuidString.lowercased()
            await fake.start(sessionID: orphan, content: content("深蹲", count: 0, end: nil))
            await AppLifecycleCoordinator().sceneDidBecomeActive(environment: environment)
            let calls = await fake.calls
            XCTAssertEqual(calls.last, .cleanup([id(session)]))
            let activities = await fake.activities
            XCTAssertEqual(Set(activities.keys), [id(session)])
        }

        private func id(_ session: Session) -> String { session.id.rawValue.uuidString.lowercased() }
        private func content(_ name: String, count: Int, end: Date?) -> SessionActivityAttributes.ContentState {
            .init(exerciseName: name, completedSetCount: count, restEndsAt: end)
        }

        private struct Fixture {
            let directory: TemporaryProtectedDirectory
            let persistence: PersistenceController
            let faults: TestFaultInjector
            let activities: FakeSessionActivityController
            let students: StudentUseCases
            let sessions: ActiveSessionUseCases

            func student(_ name: String) async throws -> Student {
                try await students.create(draft: StudentDraft(displayName: name, sex: .female))
            }
        }

        private func makeFixture() throws -> Fixture {
            let directory = try TemporaryProtectedDirectory()
            let faults = TestFaultInjector()
            let persistence = try PersistenceController(
                storeURL: directory.url.appendingPathComponent("store.sqlite"),
                faultInjectionBoundary: FaultInjectionBoundary(injector: faults))
            let activities = FakeSessionActivityController()
            let students = CoreDataStudentRepository(writer: persistence.writer)
            let clock = TestClock(utcDate: now)
            let ids = SystemIDGenerator()
            return Fixture(
                directory: directory, persistence: persistence, faults: faults, activities: activities,
                students: StudentUseCases(repository: students, clock: clock, ids: ids),
                sessions: ActiveSessionUseCases(
                    sessionRepository: CoreDataSessionRepository(writer: persistence.writer),
                    studentRepository: students,
                    exerciseRepository: CoreDataExerciseRepository(writer: persistence.writer),
                    sectionRepository: CoreDataSessionSectionRepository(writer: persistence.writer),
                    recoveryStore: ActiveSessionRecoveryStore(
                        url: directory.url.appendingPathComponent("recovery.json")),
                    storeGenerationUUID: UUID(), clock: clock, ids: ids, sessionActivities: activities))
        }

        private func makeViewModel(_ fixture: Fixture, store: RestTimerStore = RestTimerStore()) async throws
            -> ActiveSessionViewModel
        {
            let student = try await fixture.student("虚构学员甲")
            let session = try await fixture.sessions.startOrOpen(studentID: student.id)
            _ = try await fixture.sessions.addSessionOnlyExercise(
                sessionID: session.id, displayName: "深蹲", recordMode: .weightReps)
            let vm = ActiveSessionViewModel(
                studentID: student.id, useCases: fixture.sessions, restTimerStore: store, now: { [now] in now })
            await vm.load()
            await vm.sessionActivityTask?.value
            return vm
        }
    }
#endif
