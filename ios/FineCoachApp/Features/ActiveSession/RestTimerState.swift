import Foundation

/// The between-sets rest countdown (experience P0-D3: starts after a set is
/// confirmed, 120 s). In-memory display aid only: nothing is persisted, no
/// notification is scheduled, and killing the app simply drops it.
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
