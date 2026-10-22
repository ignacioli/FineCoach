import Foundation

/// The between-sets rest countdown (experience P0-D3: starts after a set is
/// confirmed, 120 s). The countdown itself is not persisted. The generic
/// end notification (P0-D5) is a separate pending request and can still
/// fire if the process is killed.
struct RestTimerState: Equatable {
    static let defaultDuration: TimeInterval = 120
    static let adjustmentStep: TimeInterval = 15
    /// How long the ended state stays up before the bar dismisses itself (P0-b).
    static let finishedHold: TimeInterval = 3

    private(set) var endsAt: Date

    init(startedAt: Date, duration: TimeInterval = Self.defaultDuration) {
        endsAt = startedAt.addingTimeInterval(duration)
    }

    /// Whole seconds left, rounded up so "0:00" only shows once finished.
    func remainingSeconds(at now: Date) -> Int {
        max(0, Int(ceil(endsAt.timeIntervalSince(now))))
    }

    func isFinished(at now: Date) -> Bool {
        remainingSeconds(at: now) == 0
    }

    /// ±15 s; never moves the end before `now`.
    mutating func adjust(by seconds: TimeInterval, now: Date) {
        endsAt = max(now, endsAt.addingTimeInterval(seconds))
    }

    /// "1:45" / "0:07".
    static func text(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Seconds from `now` until the bar should dismiss: the time still left,
    /// plus `finishedHold` after `endsAt`. Already past the hold returns 0.
    func autoDismissDelay(at now: Date) -> TimeInterval {
        max(0, endsAt.addingTimeInterval(Self.finishedHold).timeIntervalSince(now))
    }
}

/// One pending "rest ended" notification per Session (P0-D5). Copy is generic
/// on purpose: a locked phone must not show a student name, exercise, or
/// weight. The per-Session identifier keeps two Sessions' rests from cancelling
/// each other.
enum RestEndNotification {
    /// The shared prefix; the no-Session overload keeps this exact identifier
    /// for the single-Session tests and backwards compatibility.
    static let identifier = "active-session.rest-ended"

    static func notificationIdentifier(for sessionID: StableUUID?) -> String {
        guard let sessionID else {
            return identifier
        }
        return "\(identifier).\(sessionID.rawValue.uuidString.lowercased())"
    }

    enum Plan: Equatable {
        case remove
        case schedule(NotificationRequestDescriptor)
    }

    /// Remove when there is no future end. Otherwise schedule at `endsAt`.
    static func plan(endsAt: Date?, now: Date, sessionID: StableUUID? = nil) -> Plan {
        guard let endsAt, endsAt > now else {
            return .remove
        }
        return .schedule(
            NotificationRequestDescriptor(
                identifier: notificationIdentifier(for: sessionID),
                title: String(localized: "session.rest.notificationTitle"),
                body: String(localized: "session.rest.notificationBody"),
                fireDate: endsAt
            )
        )
    }

    static func apply(_ plan: Plan, with notifications: any LocalNotificationScheduling) async {
        switch plan {
        case .remove:
            await notifications.removePending(identifiers: [identifier])
        case .schedule(let descriptor):
            await notifications.requestAuthorizationIfNeeded()
            await notifications.removePending(identifiers: [identifier])
            try? await notifications.schedule(descriptor)
        }
    }

    /// UI tests must not raise the system permission alert. Production uses
    /// the same adapter as appointment reminders.
    static func scheduler(arguments: [String] = ProcessInfo.processInfo.arguments) -> (any LocalNotificationScheduling)?
    {
        arguments.contains("-FineCoachUITesting") ? nil : SystemNotificationAdapter()
    }
}
