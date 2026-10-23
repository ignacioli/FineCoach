import Combine
import Foundation
import UIKit
import UserNotifications

/// The invisible routing request carried by a rest-end notification
/// (Revision 1.3). Only technical identifiers are parsed; the visible body
/// never contains a Student name or other sensitive field.
struct RestNotificationRouteRequest: Equatable, Sendable {
    let studentID: StableUUID
    let sessionID: StableUUID

    init(studentID: StableUUID, sessionID: StableUUID) {
        self.studentID = studentID
        self.sessionID = sessionID
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard
            let kind = userInfo[RestNotificationPayload.kindKey] as? String,
            kind == RestNotificationPayload.kindRestEnded,
            let studentValue = userInfo[RestNotificationPayload.studentIDKey] as? String,
            let sessionValue = userInfo[RestNotificationPayload.sessionIDKey] as? String,
            let studentUUID = UUID(uuidString: studentValue),
            let sessionUUID = UUID(uuidString: sessionValue)
        else {
            return nil
        }
        self.studentID = StableUUID(studentUUID)
        self.sessionID = StableUUID(sessionUUID)
    }
}

/// Everything the notification route depends on besides the read-only
/// Session lookup. `isRootNavigationReady` is the cold-start gate: a tap that
/// arrives before onboarding/root navigation exist waits for the next consume.
struct RestNotificationRouteConditions: Equatable, Sendable {
    let isCoachMode: Bool
    let isStorageAvailable: Bool
    let isOnboardingCompleted: Bool
    let isRootNavigationReady: Bool

    init(
        isCoachMode: Bool = true,
        isStorageAvailable: Bool = true,
        isOnboardingCompleted: Bool = true,
        isRootNavigationReady: Bool = true
    ) {
        self.isCoachMode = isCoachMode
        self.isStorageAvailable = isStorageAvailable
        self.isOnboardingCompleted = isOnboardingCompleted
        self.isRootNavigationReady = isRootNavigationReady
    }
}

enum RestNotificationRouteDecision: Equatable, Sendable {
    case route(RestNotificationRouteRequest)
    case ignore
}

/// Pure routing decision: no notification center, no persistence, no writes.
/// The caller supplies the results of read-only lookups.
enum RestNotificationRouting {
    static func decide(
        request: RestNotificationRouteRequest?,
        conditions: RestNotificationRouteConditions,
        studentExists: Bool,
        activeSession: Session?
    ) -> RestNotificationRouteDecision {
        guard
            let request,
            conditions.isCoachMode,
            conditions.isStorageAvailable,
            conditions.isOnboardingCompleted,
            conditions.isRootNavigationReady,
            studentExists,
            let activeSession,
            activeSession.state == .inProgress,
            activeSession.id == request.sessionID,
            activeSession.studentID == request.studentID
        else {
            return .ignore
        }
        return .route(request)
    }
}

/// Push semantics for the routed tap: replace the stack with the Student's
/// training page, but leave it untouched when that exact page is on top.
enum RestNotificationNavigation {
    static func path(
        current: [RootDestination],
        studentID: StableUUID
    ) -> [RootDestination] {
        let destination = RootDestination.activeSession(studentID.rawValue)
        return current.last == destination ? current : [destination]
    }
}

/// Holds at most one tap request until the coach root is ready. Taking the
/// request clears it, so a cold-start request can never be replayed.
@MainActor
final class RestNotificationRouter: ObservableObject {
    static let shared = RestNotificationRouter()

    @Published private(set) var pendingRequest: RestNotificationRouteRequest?

    init() {}

    func receive(userInfo: [AnyHashable: Any]) {
        guard let request = RestNotificationRouteRequest(userInfo: userInfo) else {
            // Appointment reminders and unknown payloads keep their old
            // behavior: opening the app only, no route.
            return
        }
        receive(request)
    }

    func receive(_ request: RestNotificationRouteRequest) {
        pendingRequest = request
    }

    func takePendingRequest() -> RestNotificationRouteRequest? {
        defer { pendingRequest = nil }
        return pendingRequest
    }

    func discardPendingRequest() {
        pendingRequest = nil
    }
}

/// Sets the notification-center delegate at launch. Only the response hook is
/// implemented: `willPresent` is deliberately absent so a foreground
/// notification still produces no banner (P0-D5).
@MainActor
final class RestNotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard
            let request = RestNotificationRouteRequest(
                userInfo: response.notification.request.content.userInfo
            )
        else {
            return
        }
        await RestNotificationRouter.shared.receive(request)
    }
}
