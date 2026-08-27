import Foundation

public struct SystemClock: Clock, Sendable {
    private let wallClock: @Sendable () -> Date
    private let monotonicClock: @Sendable () -> MonotonicInstant

    public init(wallClock: @escaping @Sendable () -> Date = { Date() }) {
        let continuousClock = ContinuousClock()
        let origin = continuousClock.now
        self.init(wallClock: wallClock) {
            let duration = origin.duration(to: continuousClock.now)
            let components = duration.components
            guard components.seconds >= 0, components.attoseconds >= 0 else {
                return .zero
            }

            let seconds = UInt64(components.seconds)
            let nanoseconds = UInt64(components.attoseconds / 1_000_000_000)
            let (wholeSeconds, secondsOverflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
            guard !secondsOverflow else {
                return MonotonicInstant(nanoseconds: .max)
            }
            let (total, nanosecondsOverflow) = wholeSeconds.addingReportingOverflow(nanoseconds)
            guard !nanosecondsOverflow else {
                return MonotonicInstant(nanoseconds: .max)
            }
            return MonotonicInstant(nanoseconds: total)
        }
    }

    public init(
        wallClock: @escaping @Sendable () -> Date,
        monotonicNow: @escaping @Sendable () -> MonotonicInstant
    ) {
        self.wallClock = wallClock
        self.monotonicClock = monotonicNow
    }

    public func nowUTC() -> Date {
        wallClock()
    }

    public func nowMonotonic() -> MonotonicInstant {
        monotonicClock()
    }
}

public struct SystemIDGenerator: IDGenerator, Sendable {
    public init() {}

    public func makeID() -> UUID {
        UUID()
    }
}
