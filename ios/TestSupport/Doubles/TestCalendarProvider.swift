import FineCoach
import Foundation

public final class TestCalendarProvider: LocalCalendarProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var calendar: Calendar

    public init(timeZone: TimeZone = TimeZone(identifier: "UTC")!) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public func currentCalendar() -> Calendar {
        lock.lock()
        defer { lock.unlock() }
        return calendar
    }

    public func setTimeZone(_ timeZone: TimeZone) {
        lock.lock()
        calendar.timeZone = timeZone
        lock.unlock()
    }
}
