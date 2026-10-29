import AppIntents
import XCTest

@testable import FineCoach

@MainActor
final class SystemEntryIntentsTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        SystemEntryRouter.shared.discardPendingRequest()
    }

    override func tearDown() async throws {
        SystemEntryRouter.shared.discardPendingRequest()
        try await super.tearDown()
    }

    func testAllIntentsRequireAuthenticationAndOpenApp() {
        XCTAssertEqual(TodayIntent.authenticationPolicy, .requiresAuthentication)
        XCTAssertEqual(StartTrainingIntent.authenticationPolicy, .requiresAuthentication)
        XCTAssertEqual(ContinueTrainingIntent.authenticationPolicy, .requiresAuthentication)
        XCTAssertTrue(TodayIntent.openAppWhenRun)
        XCTAssertTrue(StartTrainingIntent.openAppWhenRun)
        XCTAssertTrue(ContinueTrainingIntent.openAppWhenRun)
    }

    func testTodayIntentQueuesTodayUntilNavigationIsReady() async throws {
        _ = try await TodayIntent().perform()
        assertPending(.today)
    }

    func testStartTrainingIntentQueuesTodayWithoutStartingTraining() async throws {
        _ = try await StartTrainingIntent().perform()
        assertPending(.startTraining)
    }

    func testContinueTrainingIntentQueuesContinueTraining() async throws {
        _ = try await ContinueTrainingIntent().perform()
        assertPending(.continueTraining)
    }

    func testContinueTrainingIntentResolvesZeroOneAndTwoActiveSessions() async throws {
        let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func session() -> Session {
            Session(
                id: StableUUID(UUID()), studentID: studentID, state: .inProgress,
                startedAtUTC: now, lastCheckpointUTC: now, elapsedSeconds: .zero,
                interruptionStartedAtUTC: nil, durationNeedsReview: false, coachAdjustedDurationSeconds: nil,
                trainingFocus: [], studentFacingSummary: nil, privateCoachNote: nil, revision: 1,
                createdAtUTC: now, updatedAtUTC: now, completedAtUTC: nil, exercises: [])
        }
        for count in 0...2 {
            _ = try await ContinueTrainingIntent().perform()
            let decision = SystemEntryRouting.decide(
                request: SystemEntryRouter.shared.takePendingRequest(), conditions: SystemEntryRouteConditions(),
                activeSessions: (0..<count).map { _ in session() })
            XCTAssertEqual(decision, count == 1 ? .activeSession(studentID) : .today)
            XCTAssertEqual(
                SystemEntryNavigation.path(current: [.settings], decision: decision),
                count == 1 ? [.activeSession(studentID.rawValue)] : [])
            XCTAssertNil(SystemEntryRouter.shared.takePendingRequest())
        }
    }

    func testProviderHasExactlyThreeShortcutsWithApplicationNameInEveryPhrase() throws {
        XCTAssertEqual(FineCoachShortcuts.appShortcuts.count, 3)
        let source = try String(contentsOf: intentsURL, encoding: .utf8)
        let phrases = source.components(separatedBy: .newlines).filter { $0.contains("phrases:") }
        XCTAssertEqual(phrases.count, 3)
        XCTAssertTrue(phrases.allSatisfy { $0.contains("\\(.applicationName)") })
        let catalog = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: iosRoot.appendingPathComponent("FineCoachApp/Resources/AppShortcuts.xcstrings")))
                as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        XCTAssertEqual(
            Set(strings.keys), ["${applicationName} 今日", "${applicationName} 开始训练", "${applicationName} 继续训练"])
    }

    #if DEBUG
        func testPerformDoesNotCallRepositoryWriter() async throws {
            let directory = try TemporaryProtectedDirectory()
            let spy = RepositoryWriteSpy()
            let persistence = try PersistenceController(
                storeURL: directory.url.appendingPathComponent("store.sqlite"),
                faultInjectionBoundary: FaultInjectionBoundary(injector: spy))
            let students = StudentUseCases(
                repository: CoreDataStudentRepository(writer: persistence.writer),
                clock: TestClock(utcDate: Date(timeIntervalSince1970: 1_700_000_000)), ids: SystemIDGenerator())
            // A real repository write proves the spy observes the writer's save boundary.
            _ = try await students.create(draft: StudentDraft(displayName: "虚构学员甲", sex: .female))
            XCTAssertGreaterThan(spy.writeCount, 0)
            spy.reset()
            _ = try await TodayIntent().perform()
            XCTAssertEqual(spy.writeCount, 0)
            _ = try await StartTrainingIntent().perform()
            XCTAssertEqual(spy.writeCount, 0)
            _ = try await ContinueTrainingIntent().perform()
            XCTAssertEqual(spy.writeCount, 0)
            // The entire Intent source has no way to obtain a repository or use case.
            let source = try String(contentsOf: intentsURL, encoding: .utf8)
            for forbidden in ["Repository", "UseCases", "AppEnvironment", "Persistence", "FileManager", "UserDefaults"]
            {
                XCTAssertFalse(source.contains(forbidden), forbidden)
            }
            try await persistence.shutdownForTesting()
        }

        private final class RepositoryWriteSpy: FaultInjector, @unchecked Sendable {
            private let lock = NSLock()
            private var count = 0

            var writeCount: Int { lock.withLock { count } }

            func check(_ point: FaultInjectionPoint) throws {
                if point == .persistenceWriterSave { lock.withLock { count += 1 } }
            }

            func reset() { lock.withLock { count = 0 } }
        }
    #endif

    private var iosRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var intentsURL: URL { iosRoot.appendingPathComponent("FineCoachApp/App/SystemEntryIntents.swift") }

    private func assertPending(_ page: SystemEntryPage) {
        let router = SystemEntryRouter.shared
        XCTAssertEqual(router.pendingRequest, page.request)
        XCTAssertNil(router.takePendingRequest(ifReady: false))
        XCTAssertEqual(router.pendingRequest, page.request)
        XCTAssertEqual(router.takePendingRequest(), page.request)
        XCTAssertNil(router.takePendingRequest())
    }
}
