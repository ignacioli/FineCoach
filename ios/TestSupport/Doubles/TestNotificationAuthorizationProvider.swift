import FineCoach
import Foundation

public actor TestNotificationAuthorizationProvider: NotificationAuthorizationProvider {
    private var status: NotificationAuthorizationStatus

    public init(status: NotificationAuthorizationStatus = .notDetermined) {
        self.status = status
    }

    public func currentStatus() async -> NotificationAuthorizationStatus {
        status
    }

    public func setStatus(_ status: NotificationAuthorizationStatus) {
        self.status = status
    }
}
