import XCTest

@testable import FineCoach

/// Revision 1.3: a rest-end notification tap routes to the Student's
/// in-progress Session only. These are pure-decision tests plus the
/// consume-once router; the system delegate itself needs a device.
@MainActor
final class RestNotificationRoutingTests: XCTestCase {
    private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    private let otherStudentID = StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
    private let sessionID = StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
    private let otherSessionID = StableUUID(UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Delegate source guard

    func testDelegateUsesExplicitCompletionInsteadOfAsyncBridge() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FineCoachApp/App/RestNotificationRouting.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertNil(
            source.range(
                of: #"nonisolated\s+func\s+userNotificationCenter\s*\([^)]*\)\s*async"#,
                options: .regularExpression
            )
        )
        XCTAssertNil(
            source.range(
                of: #"didReceive\s+response:\s*UNNotificationResponse\s*\)\s*async"#,
                options: .regularExpression
            )
        )
        XCTAssertTrue(source.contains("withCompletionHandler completionHandler:"))
    }

    // MARK: - Payload parsing

    func testPayloadParsesKindAndBothIdentifiers() throws {
        let request = try XCTUnwrap(
            RestNotificationRouteRequest(
                userInfo: RestNotificationPayload.restEnded(studentID: studentID, sessionID: sessionID)
            )
        )
        XCTAssertEqual(request.studentID, studentID)
        XCTAssertEqual(request.sessionID, sessionID)
    }

    func testPayloadRequiresRestEndedKindAndCanonicalUUIDs() {
        XCTAssertNil(RestNotificationRouteRequest(userInfo: [:]))
        XCTAssertNil(
            RestNotificationRouteRequest(
                userInfo: [
                    RestNotificationPayload.kindKey: "appointmentReminder",
                    RestNotificationPayload.studentIDKey: studentID.rawValue.uuidString,
                    RestNotificationPayload.sessionIDKey: sessionID.rawValue.uuidString,
                ]
            )
        )
        XCTAssertNil(
            RestNotificationRouteRequest(
                userInfo: [
                    RestNotificationPayload.kindKey: RestNotificationPayload.kindRestEnded,
                    RestNotificationPayload.studentIDKey: "not-a-uuid",
                    RestNotificationPayload.sessionIDKey: sessionID.rawValue.uuidString,
                ]
            )
        )
        XCTAssertNil(
            RestNotificationRouteRequest(
                userInfo: [
                    RestNotificationPayload.kindKey: RestNotificationPayload.kindRestEnded,
                    RestNotificationPayload.studentIDKey: studentID.rawValue.uuidString,
                ]
            )
        )
    }

    // MARK: - Pure route decision

    func testRoutesOnlyWhenTheSameInProgressSessionStillExists() {
        let request = RestNotificationRouteRequest(studentID: studentID, sessionID: sessionID)
        let decision = RestNotificationRouting.decide(
            request: request,
            conditions: RestNotificationRouteConditions(),
            studentExists: true,
            activeSession: makeSession(id: sessionID, studentID: studentID)
        )
        XCTAssertEqual(decision, .route(request))
    }

    func testIgnoresNonCoachStorageOnboardingAndNotReadyRoot() {
        let request = RestNotificationRouteRequest(studentID: studentID, sessionID: sessionID)
        let session = makeSession(id: sessionID, studentID: studentID)
        let blockedConditions = [
            RestNotificationRouteConditions(isCoachMode: false),
            RestNotificationRouteConditions(isStorageAvailable: false),
            RestNotificationRouteConditions(isOnboardingCompleted: false),
            RestNotificationRouteConditions(isRootNavigationReady: false),
        ]
        for conditions in blockedConditions {
            XCTAssertEqual(
                RestNotificationRouting.decide(
                    request: request,
                    conditions: conditions,
                    studentExists: true,
                    activeSession: session
                ),
                .ignore
            )
        }
    }

    func testIgnoresMissingRequestOrStudentOrSession() {
        let request = RestNotificationRouteRequest(studentID: studentID, sessionID: sessionID)
        XCTAssertEqual(
            RestNotificationRouting.decide(
                request: nil,
                conditions: RestNotificationRouteConditions(),
                studentExists: true,
                activeSession: makeSession(id: sessionID, studentID: studentID)
            ),
            .ignore
        )
        XCTAssertEqual(
            RestNotificationRouting.decide(
                request: request,
                conditions: RestNotificationRouteConditions(),
                studentExists: false,
                activeSession: makeSession(id: sessionID, studentID: studentID)
            ),
            .ignore
        )
        XCTAssertEqual(
            RestNotificationRouting.decide(
                request: request,
                conditions: RestNotificationRouteConditions(),
                studentExists: true,
                activeSession: nil
            ),
            .ignore
        )
    }

    func testIgnoresFinishedAbandonedOrMismatchedSessions() {
        let request = RestNotificationRouteRequest(studentID: studentID, sessionID: sessionID)
        let mismatched = [
            makeSession(id: sessionID, studentID: studentID, state: .completed),
            makeSession(id: sessionID, studentID: studentID, state: .abandonedEmpty),
            makeSession(id: otherSessionID, studentID: studentID),
            makeSession(id: sessionID, studentID: otherStudentID),
        ]
        for session in mismatched {
            XCTAssertEqual(
                RestNotificationRouting.decide(
                    request: request,
                    conditions: RestNotificationRouteConditions(),
                    studentExists: true,
                    activeSession: session
                ),
                .ignore,
                "must not route to \(session.state) / mismatched Session"
            )
        }
    }

    // MARK: - Consume-once router

    func testColdStartRequestWaitsForMountedRootAndIsConsumedOnce() {
        let router = RestNotificationRouter()
        let request = RestNotificationRouteRequest(studentID: studentID, sessionID: sessionID)
        router.receive(request)

        // Loading onboarding can complete before NavigationStack is mounted.
        XCTAssertNil(router.takePendingRequest(ifReady: false))
        XCTAssertEqual(router.pendingRequest, request)
        XCTAssertNil(router.takePendingRequest(ifReady: false))
        XCTAssertEqual(router.pendingRequest, request, "failed readiness guards must retain the tap")

        let consumed = router.takePendingRequest(ifReady: true)
        XCTAssertEqual(consumed, request)
        XCTAssertEqual(
            RestNotificationRouting.decide(
                request: consumed,
                conditions: RestNotificationRouteConditions(),
                studentExists: true,
                activeSession: makeSession(id: sessionID, studentID: studentID)
            ),
            .route(request)
        )
        XCTAssertNil(router.pendingRequest)
        XCTAssertNil(router.takePendingRequest(ifReady: true), "later observers must not replay the tap")
    }

    func testRequestArrivingAfterRootIsReadyIsConsumedOnce() {
        let router = RestNotificationRouter()
        XCTAssertNil(router.takePendingRequest(ifReady: true))
        let request = RestNotificationRouteRequest(studentID: studentID, sessionID: sessionID)
        router.receive(request)

        XCTAssertEqual(router.takePendingRequest(ifReady: true), request)
        XCTAssertNil(router.takePendingRequest(ifReady: true))
    }

    func testViewerDiscardsADeferredRequestWithoutReplay() {
        let router = RestNotificationRouter()
        router.receive(RestNotificationRouteRequest(studentID: studentID, sessionID: sessionID))
        XCTAssertNil(router.takePendingRequest(ifReady: false))

        router.discardPendingRequest()

        XCTAssertNil(router.pendingRequest)
        XCTAssertNil(router.takePendingRequest(ifReady: true))
    }

    func testRouterConsumesARequestOnceAndCanBeDiscarded() throws {
        let router = RestNotificationRouter()
        let request = RestNotificationRouteRequest(studentID: studentID, sessionID: sessionID)

        router.receive(
            userInfo: RestNotificationPayload.restEnded(studentID: studentID, sessionID: sessionID)
        )
        XCTAssertEqual(router.takePendingRequest(), request)
        XCTAssertNil(router.takePendingRequest(), "a consumed request must not replay")

        router.receive(request)
        router.discardPendingRequest()
        XCTAssertNil(router.takePendingRequest())
    }

    func testAppointmentOrUnknownTapCreatesNoRouteRequest() {
        let router = RestNotificationRouter()
        router.receive(userInfo: [:])
        XCTAssertNil(router.takePendingRequest())

        router.receive(
            userInfo: [
                RestNotificationPayload.kindKey: "appointmentReminder",
                RestNotificationPayload.studentIDKey: studentID.rawValue.uuidString,
            ]
        )
        XCTAssertNil(router.takePendingRequest())
    }

    // MARK: - Navigation stack

    func testRouteReplacesTheStackButDoesNotDuplicateTheSameTrainingPage() {
        let destination = RootDestination.activeSession(studentID.rawValue)
        XCTAssertEqual(
            RestNotificationNavigation.path(current: [], studentID: studentID),
            [destination]
        )
        XCTAssertEqual(
            RestNotificationNavigation.path(current: [.settings], studentID: studentID),
            [destination]
        )
        XCTAssertEqual(
            RestNotificationNavigation.path(current: [destination], studentID: studentID),
            [destination]
        )
        XCTAssertEqual(
            RestNotificationNavigation.path(
                current: [.studentDetail(studentID.rawValue), destination],
                studentID: studentID
            ),
            [.studentDetail(studentID.rawValue), destination],
            "the same training page must not be pushed twice"
        )
        XCTAssertEqual(
            RestNotificationNavigation.path(
                current: [.activeSession(otherStudentID.rawValue)],
                studentID: studentID
            ),
            [destination]
        )
    }

    // MARK: - Appointment reminders stay plain

    func testAppointmentReminderDescriptorHasNoRoutingUserInfo() async throws {
        let center = FakeNotificationScheduling()
        let scheduler = NotificationScheduler(
            notificationCenter: center,
            calendarProvider: TestCalendarProvider(timeZone: TimeZone(identifier: "UTC")!)
        )
        let appointment = try Appointment(
            id: StableUUID(UUID(uuidString: "33333333-3333-4333-8333-333333333333")!),
            studentID: studentID,
            seriesID: nil,
            date: try LocalDate(year: 2026, month: 1, day: 5),
            startTime: try LocalTime(hour: 9, minute: 0),
            createdAtUTC: now,
            updatedAtUTC: now
        )
        await scheduler.sync(appointment: appointment)

        let scheduled = await center.scheduled
        let descriptor = try XCTUnwrap(scheduled.values.first)
        XCTAssertTrue(descriptor.userInfo.isEmpty)
        XCTAssertNil(RestNotificationRouteRequest(userInfo: descriptor.userInfo))
    }

    // MARK: - Helpers

    private func makeSession(
        id: StableUUID,
        studentID: StableUUID,
        state: SessionState = .inProgress
    ) -> Session {
        Session(
            id: id,
            studentID: studentID,
            state: state,
            startedAtUTC: now,
            lastCheckpointUTC: now,
            elapsedSeconds: .zero,
            interruptionStartedAtUTC: nil,
            durationNeedsReview: false,
            coachAdjustedDurationSeconds: nil,
            trainingFocus: [],
            studentFacingSummary: nil,
            privateCoachNote: nil,
            revision: 1,
            createdAtUTC: now,
            updatedAtUTC: now,
            completedAtUTC: state == .completed ? now : nil,
            exercises: []
        )
    }
}
