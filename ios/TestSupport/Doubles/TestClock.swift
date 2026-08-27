import FineCoach
import Foundation

public final class TestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var utcDate: Date
    private var monotonicNanoseconds: UInt64

    public init(
        utcDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
        monotonicNanoseconds: UInt64 = 0
    ) {
        self.utcDate = utcDate
        self.monotonicNanoseconds = monotonicNanoseconds
    }

    public func nowUTC() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return utcDate
    }

    public func nowMonotonic() -> MonotonicInstant {
        lock.lock()
        defer { lock.unlock() }
        return MonotonicInstant(nanoseconds: monotonicNanoseconds)
    }

    public func advance(seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        let positiveSeconds = max(0, seconds)
        let nanoseconds: UInt64
        if positiveSeconds >= TimeInterval(UInt64.max) / 1_000_000_000 {
            nanoseconds = .max
        } else {
            nanoseconds = UInt64(positiveSeconds * 1_000_000_000)
        }
        lock.lock()
        utcDate.addTimeInterval(seconds)
        let (advanced, overflow) = monotonicNanoseconds.addingReportingOverflow(nanoseconds)
        monotonicNanoseconds = overflow ? .max : advanced
        lock.unlock()
    }

    public func setUTC(_ date: Date) {
        lock.lock()
        utcDate = date
        lock.unlock()
    }
}
