import XCTest

@testable import FineCoach

@MainActor
final class SystemEntryRoutingTests: XCTestCase {
    private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    private let sessionID = StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
    private let otherSessionID = StableUUID(UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)

    func testParsesOnlyTodayAndSessionURLShapes() throws {
        XCTAssertEqual(SystemEntryRouteRequest(url: try url("finecoach://today")), .today)
        XCTAssertEqual(
            SystemEntryRouteRequest(url: try url("finecoach://session/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")),
            .session(sessionID)
        )
    }

    func testMalformedURLsAreIgnored() throws {
        for value in [
            "Finecoach://today", "finecoach://Today", "finecoach://SESSION/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            "finecoach://session/AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
            "finecoach://today/", "finecoach://today/extra", "finecoach://today?", "finecoach://today#",
            "finecoach://today?value=1", "finecoach://today#fragment", "finecoach://session",
            "finecoach://session/", "finecoach://session/not-a-uuid",
            "finecoach://session/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/extra",
            "finecoach://session/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa?value=1",
            "finecoach://session/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa#fragment",
            "finecoach://session/%61aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            "finecoach://session/aaaaaaaaaaaa4aaa8aaaaaaaaaaaaaaa",
            "finecoach://user@today", "finecoach://today:80", "finecoach:///today",
            "https://today", "file:///today", "finecoach://continueTraining",
        ] {
            XCTAssertNil(SystemEntryRouteRequest(url: try url(value)), value)
        }
    }

    func testTodaySelectsTodayAndClearsNavigationStack() {
        let decision = decide(.today)
        XCTAssertEqual(decision, .today)
        XCTAssertEqual(SystemEntryNavigation.path(current: [.settings], decision: decision), [])
    }

    func testActiveSessionRoutesToItsStudent() {
        XCTAssertEqual(decide(.session(sessionID), session: makeSession()), .activeSession(studentID))
    }

    func testFinishedAbandonedMissingAndMismatchedSessionsOnlyOpenApp() {
        for session in [
            nil, makeSession(state: .completed), makeSession(state: .abandonedEmpty),
            makeSession(id: otherSessionID),
        ] {
            let decision = decide(.session(sessionID), session: session)
            XCTAssertEqual(decision, .ignore)
            XCTAssertEqual(SystemEntryNavigation.path(current: [.settings], decision: decision), [.settings])
        }
    }

    func testContinueTrainingWithZeroSessionsOpensToday() {
        XCTAssertEqual(decide(.continueTraining), .today)
    }

    func testContinueTrainingWithOneSessionOpensTraining() {
        XCTAssertEqual(decide(.continueTraining, activeSessions: [makeSession()]), .activeSession(studentID))
    }

    func testContinueTrainingWithTwoSessionsOpensToday() {
        XCTAssertEqual(
            decide(.continueTraining, activeSessions: [makeSession(), makeSession(id: otherSessionID)]), .today)
    }

    func testContinueTrainingCountsOnlyInProgressSessions() {
        XCTAssertEqual(
            decide(.continueTraining, activeSessions: [makeSession(state: .completed)]), .today)
        XCTAssertEqual(
            decide(
                .continueTraining, activeSessions: [makeSession(), makeSession(id: otherSessionID, state: .completed)]),
            .activeSession(studentID)
        )
    }

    func testShortcutPageMappingStartsTrainingOnToday() {
        XCTAssertEqual(SystemEntryPage.today.request, .today)
        XCTAssertEqual(SystemEntryPage.startTraining.request, .today)
        XCTAssertEqual(SystemEntryPage.continueTraining.request, .continueTraining)
    }

    func testBlockedConditionsDoNotRouteAndRetainRequestUntilConsumedOnce() {
        let router = SystemEntryRouter()
        let request = SystemEntryRouteRequest.session(sessionID)
        router.receive(request)
        for conditions in [
            SystemEntryRouteConditions(isCoachMode: false),
            SystemEntryRouteConditions(isStorageAvailable: false),
            SystemEntryRouteConditions(isOnboardingCompleted: false),
            SystemEntryRouteConditions(isRootNavigationReady: false),
        ] {
            let ready =
                conditions.isCoachMode && conditions.isStorageAvailable
                && conditions.isOnboardingCompleted && conditions.isRootNavigationReady
            XCTAssertNil(router.takePendingRequest(ifReady: ready))
            XCTAssertEqual(router.pendingRequest, request)
            for blockedRequest in [request, .today, .continueTraining] {
                XCTAssertEqual(
                    SystemEntryRouting.decide(
                        request: blockedRequest, conditions: conditions, session: makeSession(),
                        activeSessions: [makeSession()]), .ignore)
            }
        }
        XCTAssertEqual(router.takePendingRequest(ifReady: true), request)
        XCTAssertNil(router.pendingRequest)
        XCTAssertNil(router.takePendingRequest(ifReady: true))
    }

    func testViewerDiscardsDeferredRequestWithoutReplay() {
        let router = SystemEntryRouter()
        router.receive(.continueTraining)
        XCTAssertNil(router.takePendingRequest(ifReady: false))
        router.discardPendingRequest()
        XCTAssertNil(router.pendingRequest)
        XCTAssertNil(router.takePendingRequest())
    }

    func testWarmRequestConsumesOnceAndMalformedURLDoesNotReplaceIt() throws {
        let router = SystemEntryRouter()
        router.receive(url: try url("finecoach://today"))
        router.receive(url: try url("finecoach://today/extra"))
        XCTAssertEqual(router.takePendingRequest(), .today)
        XCTAssertNil(router.takePendingRequest())
        XCTAssertEqual(decide(nil), .ignore)
    }

    func testTrainingNavigationDoesNotDuplicateTopPage() {
        let destination = RootDestination.activeSession(studentID.rawValue)
        let decision = SystemEntryRouteDecision.activeSession(studentID)
        XCTAssertEqual(SystemEntryNavigation.path(current: [.settings], decision: decision), [destination])
        let current = [RootDestination.studentDetail(studentID.rawValue), destination]
        XCTAssertEqual(SystemEntryNavigation.path(current: current, decision: decision), current)
    }

    func testAcceptedNonFileURLsCannotDiscardAnInboxCopy() throws {
        for value in ["finecoach://today", "finecoach://session/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"] {
            XCTAssertFalse(ArchiveImportUseCases.discardInboxCopy(at: try url(value)))
        }
    }

    private func url(_ value: String) throws -> URL {
        try XCTUnwrap(URL(string: value))
    }

    private func decide(
        _ request: SystemEntryRouteRequest?, session: Session? = nil, activeSessions: [Session] = []
    ) -> SystemEntryRouteDecision {
        SystemEntryRouting.decide(
            request: request, conditions: SystemEntryRouteConditions(), session: session, activeSessions: activeSessions
        )
    }

    private func makeSession(id: StableUUID? = nil, state: SessionState = .inProgress) -> Session {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Session(
            id: id ?? sessionID, studentID: studentID, state: state,
            startedAtUTC: now, lastCheckpointUTC: now, elapsedSeconds: .zero,
            interruptionStartedAtUTC: nil, durationNeedsReview: false, coachAdjustedDurationSeconds: nil,
            trainingFocus: [], studentFacingSummary: nil, privateCoachNote: nil, revision: 1,
            createdAtUTC: now, updatedAtUTC: now, completedAtUTC: state == .completed ? now : nil, exercises: []
        )
    }
}
