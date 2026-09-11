import FineCoach
import Foundation

public actor FakeNotificationScheduling: LocalNotificationScheduling {
    public private(set) var authorizationRequested = false
    public private(set) var scheduled: [String: NotificationRequestDescriptor] = [:]
    private let scheduleShouldFail: Bool

    public init(scheduleShouldFail: Bool = false) {
        self.scheduleShouldFail = scheduleShouldFail
    }

    public func requestAuthorizationIfNeeded() async {
        authorizationRequested = true
    }

    public func schedule(_ descriptor: NotificationRequestDescriptor) async throws {
        guard !scheduleShouldFail else {
            throw DomainError.invalidState
        }
        scheduled[descriptor.identifier] = descriptor
    }

    public func removePending(identifiers: [String]) async {
        for identifier in identifiers {
            scheduled.removeValue(forKey: identifier)
        }
    }
}
