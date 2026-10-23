import Combine
import Foundation
import UIKit
import UserNotifications

/// Tap-routing phases for on-device diagnosis (C19), logged through
/// `AppLogger` as fixed event IDs: never a payload, identifier or name.
enum RestNotificationDiagnostics {
    enum Phase {
        case delegateInstalled, responseReceived, ignoredPayload, received, rootLoading, rootLoaded
        case stackReady, stackRemoved
        case deferredNotReady, consumed, ignoredNoRoute, routed, pathEmpty, pathNonempty
        case installCoach, installViewer, installUnselected, discarded

        var event: AppLogEvent {
            switch self {
            case .delegateInstalled: return .restNotificationDelegateInstalled
            case .responseReceived: return .restNotificationResponseReceived
            case .ignoredPayload: return .restNotificationIgnoredPayload
            case .received: return .restNotificationReceived
            case .rootLoading: return .restNotificationRootLoading
            case .rootLoaded: return .restNotificationRootLoaded
            case .stackReady: return .restNotificationStackReady
            case .stackRemoved: return .restNotificationStackRemoved
            case .deferredNotReady: return .restNotificationDeferredNotReady
            case .consumed: return .restNotificationConsumed
            case .ignoredNoRoute: return .restNotificationIgnoredNoRoute
            case .routed: return .restNotificationRouted
            case .pathEmpty: return .restNotificationPathEmpty
            case .pathNonempty: return .restNotificationPathNonempty
            case .installCoach: return .restNotificationInstallCoach
            case .installViewer: return .restNotificationInstallViewer
            case .installUnselected: return .restNotificationInstallUnselected
            case .discarded: return .restNotificationDiscarded
            }
        }
    }

    static func record(_ phase: Phase) {
        AppLogger.standard.info(phase.event, operation: .restNotification)
    }
}

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

/// Foreground rest reminders only interrupt when their Student is not on screen.
enum RestNotificationPresentation {
    static func options(
        for request: RestNotificationRouteRequest?,
        visibleStudentID: StableUUID?
    ) -> UNNotificationPresentationOptions {
        guard let request, request.studentID != visibleStudentID else {
            return []
        }
        return [.banner, .list, .sound]
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
    private(set) var visibleStudentID: StableUUID?

    init() {}

    func activeSessionDidAppear(studentID: StableUUID) {
        visibleStudentID = studentID
    }

    func activeSessionDidDisappear(studentID: StableUUID) {
        guard visibleStudentID == studentID else { return }
        visibleStudentID = nil
    }

    func receive(userInfo: [AnyHashable: Any]) {
        guard let request = RestNotificationRouteRequest(userInfo: userInfo) else {
            // Appointment reminders and unknown payloads keep their old
            // behavior: opening the app only, no route.
            return
        }
        receive(request)
    }

    func receive(_ request: RestNotificationRouteRequest) {
        RestNotificationDiagnostics.record(.received)
        pendingRequest = request
    }

    func takePendingRequest(ifReady isReady: Bool = true) -> RestNotificationRouteRequest? {
        guard isReady else {
            RestNotificationDiagnostics.record(.deferredNotReady)
            return nil
        }
        defer { pendingRequest = nil }
        if pendingRequest != nil {
            RestNotificationDiagnostics.record(.consumed)
        }
        return pendingRequest
    }

    func discardPendingRequest() {
        if pendingRequest != nil {
            RestNotificationDiagnostics.record(.discarded)
        }
        pendingRequest = nil
    }
}

/// Sets the notification-center delegate at launch. Foreground rest reminders
/// use the in-app bar for the visible Student and system alerts for others.
@MainActor
final class RestNotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        RestNotificationDiagnostics.record(.delegateInstalled)
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        let request = RestNotificationRouteRequest(userInfo: notification.request.content.userInfo)
        Task { @MainActor in
            completionHandler(
                RestNotificationPresentation.options(
                    for: request,
                    visibleStudentID: RestNotificationRouter.shared.visibleStudentID
                )
            )
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        RestNotificationDiagnostics.record(.responseReceived)
        let request = RestNotificationRouteRequest(
            userInfo: response.notification.request.content.userInfo
        )
        Task { @MainActor in
            // UIKit's cold-start restoration requires completion on the main thread.
            defer { completionHandler() }
            guard let request else {
                RestNotificationDiagnostics.record(.ignoredPayload)
                return
            }
            RestNotificationRouter.shared.receive(request)
        }
    }
}
