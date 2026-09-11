import Foundation

public struct SystemLocalCalendarProvider: LocalCalendarProvider, Sendable {
    private let calendarBuilder: @Sendable () -> Calendar

    public init(calendarBuilder: @escaping @Sendable () -> Calendar = { Calendar.current }) {
        self.calendarBuilder = calendarBuilder
    }

    public func currentCalendar() -> Calendar {
        calendarBuilder()
    }
}
