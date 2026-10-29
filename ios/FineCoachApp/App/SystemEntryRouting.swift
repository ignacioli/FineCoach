import Combine
import Foundation

enum SystemEntryPage: Equatable, Sendable {
    case today
    case startTraining
    case continueTraining

    var request: SystemEntryRouteRequest {
        switch self {
        case .today, .startTraining: return .today
        case .continueTraining: return .continueTraining
        }
    }
}

enum SystemEntryRouteRequest: Equatable, Sendable {
    case today
    case session(StableUUID)
    case continueTraining

    init?(url: URL) {
        let value = url.absoluteString
        if value == "finecoach://today" {
            self = .today
            return
        }
        let prefix = "finecoach://session/"
        guard value.hasPrefix(prefix) else { return nil }
        let identifier = String(value.dropFirst(prefix.count))
        guard let uuid = UUID(uuidString: identifier),
            identifier == uuid.uuidString.lowercased()
        else { return nil }
        self = .session(StableUUID(uuid))
    }
}

typealias SystemEntryRouteConditions = RestNotificationRouteConditions

enum SystemEntryRouteDecision: Equatable, Sendable {
    case today
    case activeSession(StableUUID)
    case ignore
}

/// All inputs are read-only values. Routing cannot start or mutate a Session.
enum SystemEntryRouting {
    static func decide(
        request: SystemEntryRouteRequest?,
        conditions: SystemEntryRouteConditions,
        session: Session? = nil,
        activeSessions: [Session] = []
    ) -> SystemEntryRouteDecision {
        guard let request,
            conditions.isCoachMode, conditions.isStorageAvailable,
            conditions.isOnboardingCompleted, conditions.isRootNavigationReady
        else { return .ignore }
        switch request {
        case .today:
            return .today
        case .session(let id):
            guard let session, session.id == id, session.state == .inProgress else { return .ignore }
            return .activeSession(session.studentID)
        case .continueTraining:
            let active = activeSessions.filter { $0.state == .inProgress }
            guard active.count == 1, let session = active.first else { return .today }
            return .activeSession(session.studentID)
        }
    }
}

enum SystemEntryNavigation {
    static func path(current: [RootDestination], decision: SystemEntryRouteDecision) -> [RootDestination] {
        switch decision {
        case .today: return []
        case .activeSession(let studentID):
            return RestNotificationNavigation.path(current: current, studentID: studentID)
        case .ignore: return current
        }
    }
}

@MainActor
final class SystemEntryRouter: ObservableObject {
    static let shared = SystemEntryRouter()

    @Published private(set) var pendingRequest: SystemEntryRouteRequest?

    func receive(_ request: SystemEntryRouteRequest) {
        pendingRequest = request
    }

    func receive(url: URL) {
        guard let request = SystemEntryRouteRequest(url: url) else { return }
        receive(request)
    }

    func takePendingRequest(ifReady isReady: Bool = true) -> SystemEntryRouteRequest? {
        guard isReady else { return nil }
        defer { pendingRequest = nil }
        return pendingRequest
    }

    func discardPendingRequest() {
        pendingRequest = nil
    }
}
