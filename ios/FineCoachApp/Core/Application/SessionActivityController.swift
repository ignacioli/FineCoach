import ActivityKit
import Foundation

public protocol SessionActivityControlling: Sendable {
    func start(sessionID: String, content: SessionActivityAttributes.ContentState) async
    func update(sessionID: String, content: SessionActivityAttributes.ContentState) async
    func end(sessionID: String) async
    func cleanupStale(activeSessionIDs: Set<String>) async
}

public struct NoopSessionActivityController: SessionActivityControlling {
    public init() {}
    public func start(sessionID: String, content: SessionActivityAttributes.ContentState) async {}
    public func update(sessionID: String, content: SessionActivityAttributes.ContentState) async {}
    public func end(sessionID: String) async {}
    public func cleanupStale(activeSessionIDs: Set<String>) async {}
}

/// Serializes ActivityKit operations, including across actor suspension points.
public actor SessionActivityController: SessionActivityControlling {
    private let logger: any AppLogging
    private var pending: Task<Void, Never>?

    public init(logger: any AppLogging = AppLogger.standard) { self.logger = logger }

    public func start(sessionID: String, content: SessionActivityAttributes.ContentState) async {
        await enqueue { await self.startActivity(sessionID: sessionID, content: content) }
    }

    public func update(sessionID: String, content: SessionActivityAttributes.ContentState) async {
        await enqueue {
            for activity in Activity<SessionActivityAttributes>.activities
            where activity.attributes.sessionID == sessionID {
                await activity.update(ActivityContent(state: content, staleDate: content.restEndsAt))
            }
        }
    }

    public func end(sessionID: String) async {
        await enqueue {
            for activity in Activity<SessionActivityAttributes>.activities
            where activity.attributes.sessionID == sessionID {
                await activity.end(nil, dismissalPolicy: .immediate)
                self.logger.info(.systemEntryActivityEnded, operation: .systemEntry)
            }
        }
    }

    public func cleanupStale(activeSessionIDs: Set<String>) async {
        await enqueue {
            for activity in Activity<SessionActivityAttributes>.activities
            where !activeSessionIDs.contains(activity.attributes.sessionID) {
                await activity.end(nil, dismissalPolicy: .immediate)
                self.logger.info(.systemEntryActivityEnded, operation: .systemEntry)
            }
        }
    }

    private func enqueue(_ operation: @escaping @Sendable () async -> Void) async {
        let previous = pending
        let next = Task {
            await previous?.value
            await operation()
        }
        pending = next
        await next.value
    }

    private func startActivity(sessionID: String, content: SessionActivityAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info(.systemEntryActivityUnavailable, operation: .systemEntry)
            return
        }
        let value = ActivityContent(state: content, staleDate: content.restEndsAt)
        if let existing = Activity<SessionActivityAttributes>.activities.first(where: {
            $0.attributes.sessionID == sessionID
        }) {
            await existing.update(value)
            return
        }
        do {
            _ = try Activity.request(
                attributes: SessionActivityAttributes(sessionID: sessionID), content: value, pushType: nil)
            logger.info(.systemEntryActivityStarted, operation: .systemEntry)
        } catch {
            logger.info(.systemEntryActivityUnavailable, operation: .systemEntry)
        }
    }
}

#if DEBUG
    public actor FakeSessionActivityController: SessionActivityControlling {
        public enum Call: Equatable, Sendable {
            case start(String, SessionActivityAttributes.ContentState)
            case update(String, SessionActivityAttributes.ContentState)
            case end(String)
            case cleanup(Set<String>)
        }
        public private(set) var calls: [Call] = []
        public private(set) var activities: [String: SessionActivityAttributes.ContentState] = [:]
        public init() {}
        public func start(sessionID: String, content: SessionActivityAttributes.ContentState) async {
            calls.append(.start(sessionID, content))
            activities[sessionID] = content
        }
        public func update(sessionID: String, content: SessionActivityAttributes.ContentState) async {
            calls.append(.update(sessionID, content))
            if activities[sessionID] != nil { activities[sessionID] = content }
        }
        public func end(sessionID: String) async {
            calls.append(.end(sessionID))
            activities[sessionID] = nil
        }
        public func cleanupStale(activeSessionIDs: Set<String>) async {
            calls.append(.cleanup(activeSessionIDs))
            activities = activities.filter { activeSessionIDs.contains($0.key) }
        }
    }
#endif
