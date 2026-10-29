#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    @MainActor
    final class ActiveSessionOpenExistingTests: XCTestCase {
        private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        func testRestNotificationRouteThenAbandonBeforeLoadDoesNotCreateSession() async throws {
            try await assertRouteThenAbandon(systemEntry: false)
        }

        func testSystemEntryRouteThenAbandonBeforeLoadDoesNotCreateSession() async throws {
            try await assertRouteThenAbandon(systemEntry: true)
        }

        func testOpenExistingLoadsTheSameSessionAndReloadNeverStartsAnother() async throws {
            let environment = try makeEnvironment()
            try await createStudent(environment)
            let started = try await environment.sessionUseCases.startOrOpen(studentID: studentID)
            let viewModel = makeViewModel(environment)
            await viewModel.load()
            XCTAssertEqual(viewModel.session?.id, started.id)
            XCTAssertFalse(viewModel.sessionUnavailable)
            XCTAssertNil(viewModel.errorMessage)
            let count = try await countSessions(environment)
            XCTAssertEqual(count, 1)

            _ = try await environment.sessionUseCases.abandonEmpty(sessionID: started.id)
            await viewModel.load()
            try await assertUnavailable(viewModel, environment: environment, expectedCount: count)
            try await environment.controller.shutdownForTesting()
        }

        func testOpenExistingWithoutActiveSessionReturnsNilAndDoesNotWrite() async throws {
            let environment = try makeEnvironment()
            try await createStudent(environment)
            let before = try await countSessions(environment)
            let beforeFiles = try recoveryFiles(environment)
            let opened = try await environment.sessionUseCases.openExisting(studentID: studentID)
            XCTAssertNil(opened)
            let after = try await countSessions(environment)
            XCTAssertEqual(after, before)
            XCTAssertEqual(try recoveryFiles(environment), beforeFiles)
            let active = try await environment.sessionUseCases.loadAllActive()
            XCTAssertTrue(active.isEmpty)
            try await environment.controller.shutdownForTesting()
        }

        private func assertRouteThenAbandon(systemEntry: Bool) async throws {
            let environment = try makeEnvironment()
            try await createStudent(environment)
            let started = try await environment.sessionUseCases.startOrOpen(studentID: studentID)
            let active = try await environment.sessionUseCases.loadActive(sessionID: started.id)
            let route: [RootDestination]
            if systemEntry {
                let decision = SystemEntryRouting.decide(
                    request: .session(started.id), conditions: SystemEntryRouteConditions(), session: active)
                XCTAssertEqual(decision, .activeSession(studentID))
                route = SystemEntryNavigation.path(current: [], decision: decision)
            } else {
                let request = RestNotificationRouteRequest(studentID: studentID, sessionID: started.id)
                let decision = RestNotificationRouting.decide(
                    request: request, conditions: RestNotificationRouteConditions(), studentExists: true,
                    activeSession: active)
                XCTAssertEqual(decision, .route(request))
                route = RestNotificationNavigation.path(current: [], studentID: studentID)
            }
            XCTAssertEqual(route, [.existingSession(studentID.rawValue)])
            let before = try await countSessions(environment)
            _ = try await environment.sessionUseCases.abandonEmpty(sessionID: started.id)
            let viewModel = makeViewModel(environment)
            await viewModel.load()
            try await assertUnavailable(viewModel, environment: environment, expectedCount: before)
            try await environment.controller.shutdownForTesting()
        }

        private func assertUnavailable(
            _ viewModel: ActiveSessionViewModel, environment: Environment, expectedCount: Int
        ) async throws {
            let active = try await environment.sessionUseCases.loadAllActive()
            XCTAssertTrue(active.isEmpty)
            let count = try await countSessions(environment)
            XCTAssertEqual(count, expectedCount)
            XCTAssertNil(viewModel.session)
            XCTAssertTrue(viewModel.sessionUnavailable)
            XCTAssertNil(viewModel.errorMessage)
        }

        private func makeViewModel(_ environment: Environment) -> ActiveSessionViewModel {
            ActiveSessionViewModel(
                studentID: studentID, useCases: environment.sessionUseCases, entryMode: .openExisting,
                restTimerStore: RestTimerStore(), now: { [now] in now })
        }

        private func createStudent(_ environment: Environment) async throws {
            _ = try await environment.studentUseCases.create(
                draft: StudentDraft(displayName: "虚构学员", sex: .female))
        }

        private func countSessions(_ environment: Environment) async throws -> Int {
            try await environment.controller.writer.read { context in
                try context.count(for: NSFetchRequest<NSManagedObject>(entityName: "SessionMO"))
            }
        }

        private func recoveryFiles(_ environment: Environment) throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: environment.directory.url.path)
                .filter { $0.hasPrefix("active-session-recovery-v1") }.sorted()
        }

        private struct Environment {
            let directory: TemporaryProtectedDirectory
            let controller: PersistenceController
            let studentUseCases: StudentUseCases
            let sessionUseCases: ActiveSessionUseCases
        }

        private func makeEnvironment() throws -> Environment {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let controller = try PersistenceController(storeURL: storeURL)
            let clock = TestClock(utcDate: now)
            let ids = TestIDGenerator(ids: [studentID.rawValue] + (0..<40).map { _ in UUID() })
            let studentRepository = CoreDataStudentRepository(writer: controller.writer)
            return Environment(
                directory: directory,
                controller: controller,
                studentUseCases: StudentUseCases(repository: studentRepository, clock: clock, ids: ids),
                sessionUseCases: ActiveSessionUseCases(
                    sessionRepository: CoreDataSessionRepository(writer: controller.writer),
                    studentRepository: studentRepository,
                    exerciseRepository: CoreDataExerciseRepository(writer: controller.writer),
                    sectionRepository: CoreDataSessionSectionRepository(writer: controller.writer),
                    recoveryStore: ActiveSessionRecoveryStore(
                        url: directory.url.appendingPathComponent("active-session-recovery-v1.json"),
                        protectedFileStore: ProtectedFileStore()
                    ),
                    storeGenerationUUID: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
                    clock: clock,
                    ids: ids
                )
            )
        }

    }
#endif
