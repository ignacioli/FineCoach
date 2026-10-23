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

/// The invisible routing payload on a rest-end notification (Revision 1.3).
/// The copy may name the exercise (never the Student); the identifiers are how
/// a tap finds the same in-progress Session without any visible identity.
enum RestNotificationPayload {
    static let kindKey = "kind"
    static let kindRestEnded = "restEnded"
    static let studentIDKey = "studentID"
    static let sessionIDKey = "sessionID"

    static func restEnded(studentID: StableUUID, sessionID: StableUUID) -> [String: String] {
        [
            kindKey: kindRestEnded,
            studentIDKey: studentID.rawValue.uuidString.lowercased(),
            sessionIDKey: sessionID.rawValue.uuidString.lowercased(),
        ]
    }
}

/// One pending "rest ended" notification per Session (P0-D5). The body may name
/// the exercise that just finished (Revision 1.3); it still must not show a
/// Student name, weight, reps, or set number. The per-Session identifier keeps
/// two Sessions' rests from cancelling each other.
enum RestEndNotification {
    /// The shared prefix; the no-Session case keeps this exact identifier.
    static let identifier = "active-session.rest-ended"

    static func notificationIdentifier(for sessionID: StableUUID?) -> String {
        guard let sessionID else {
            return identifier
        }
        return "\(identifier).\(sessionID.rawValue.uuidString.lowercased())"
    }

    static func body(exerciseName: String?) -> String {
        guard let exerciseName, !exerciseName.isEmpty else {
            return String(localized: "session.rest.notificationBody")
        }
        return String(
            format: String(localized: "session.rest.notificationBodyExercise"),
            exerciseName
        )
    }

    enum Plan: Equatable {
        /// The identifier to remove is carried with the plan: removal must
        /// target this Session's own request, never the shared prefix.
        case remove(identifier: String)
        case schedule(NotificationRequestDescriptor)
    }

    /// Remove when there is no future end. Otherwise schedule at `endsAt`.
    /// `exerciseName` is the exercise that owned the just-confirmed set and is
    /// kept across ±15 s reschedules by the caller.
    static func plan(
        endsAt: Date?,
        now: Date,
        sessionID: StableUUID? = nil,
        studentID: StableUUID? = nil,
        exerciseName: String? = nil
    ) -> Plan {
        let identifier = notificationIdentifier(for: sessionID)
        guard let endsAt, endsAt > now else {
            return .remove(identifier: identifier)
        }
        let userInfo: [String: String] =
            if let sessionID, let studentID {
                RestNotificationPayload.restEnded(studentID: studentID, sessionID: sessionID)
            } else {
                [:]
            }
        return .schedule(
            NotificationRequestDescriptor(
                identifier: identifier,
                title: String(localized: "session.rest.notificationTitle"),
                body: body(exerciseName: exerciseName),
                fireDate: endsAt,
                userInfo: userInfo,
                threadIdentifier: sessionID == nil ? nil : identifier
            )
        )
    }

    static func apply(_ plan: Plan, with notifications: any LocalNotificationScheduling) async {
        switch plan {
        case .remove(let identifier):
            await notifications.removePending(identifiers: [identifier])
        case .schedule(let descriptor):
            await notifications.requestAuthorizationIfNeeded()
            // Replace only this Session's previous request before scheduling.
            await notifications.removePending(identifiers: [descriptor.identifier])
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
