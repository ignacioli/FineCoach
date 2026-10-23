import Foundation
import UIKit
import UserNotifications

/// Stable request identifiers derived from appointment identity (plan D-M1B-005):
/// scheduling the same appointment twice, or removing a stale reminder, always
/// targets the same UNNotificationRequest id -- no separate ID bookkeeping needed.
public enum AppointmentNotificationIdentifier {
    public static func make(appointmentID: StableUUID) -> String {
        "appointment-reminder:\(appointmentID.rawValue.uuidString)"
    }
}

public struct NotificationRequestDescriptor: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let body: String
    public let fireDate: Date
    /// Invisible routing data (Revision 1.3). Appointment reminders leave this
    /// empty, so their tap behavior stays unchanged.
    public let userInfo: [String: String]

    public init(
        identifier: String,
        title: String,
        body: String,
        fireDate: Date,
        userInfo: [String: String] = [:]
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.userInfo = userInfo
    }
}

/// Everything the Application layer (NotificationScheduler, T013) needs from the
/// system notification center, narrowed to a protocol so it can be faked in tests
/// without touching real device permissions.
public protocol LocalNotificationScheduling: Sendable {
    /// Requests permission only the FIRST time it is actually needed (an appointment
    /// with reminders enabled is being saved) and only if not yet determined; MUST
    /// NOT block or fail the save on denial (D-004).
    func requestAuthorizationIfNeeded() async
    func schedule(_ descriptor: NotificationRequestDescriptor) async throws
    func removePending(identifiers: [String]) async
}

/// UNUserNotificationCenter itself is not Sendable, but Apple documents it as safe
/// to call from any thread/queue.
public struct SystemNotificationAdapter: LocalNotificationScheduling, NotificationAuthorizationProvider,
    @unchecked Sendable
{
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func currentStatus() async -> NotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        @unknown default:
            return .notDetermined
        }
    }

    public func requestAuthorizationIfNeeded() async {
        guard await currentStatus() == .notDetermined else {
            return
        }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    public func schedule(_ descriptor: NotificationRequestDescriptor) async throws {
        let content = UNMutableNotificationContent()
        content.title = descriptor.title
        content.body = descriptor.body
        content.sound = .default
        content.userInfo = descriptor.userInfo

        let interval = descriptor.fireDate.timeIntervalSinceNow
        guard interval > 0 else {
            return
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: descriptor.identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    public func removePending(identifiers: [String]) async {
        guard !identifiers.isEmpty else {
            return
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// D-004's "system settings exit": Feature UI surfaces this when reminders are
/// denied, rather than leaving the coach stuck with no path to re-enable them.
public enum SystemSettingsLink {
    @MainActor
    public static func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}
