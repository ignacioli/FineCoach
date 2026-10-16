import Foundation

/// Day-of-week identity independent of locale/first-weekday settings, ISO-numbered
/// (Monday = 1 ... Sunday = 7). Domain code MUST use this rather than
/// Foundation 's Calendar.Component.weekday (which is Sunday-based and
/// locale-sensitive) so recurrence rules stay deterministic across time zones.
public enum Weekday: Int, CaseIterable, Hashable, Codable, Sendable, Comparable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Foundation's Calendar.Component.weekday is 1 = Sunday ... 7 = Saturday.
    init(foundationWeekday: Int) {
        self = Weekday(rawValue: foundationWeekday == 1 ? 7 : foundationWeekday - 1) ?? .monday
    }

    var foundationWeekday: Int {
        rawValue == 7 ? 1 : rawValue + 1
    }
}

/// A calendar day with no time-of-day or time-zone component, stored as a canonical
/// "yyyy-MM-dd" string (data-model modeling principle: canonical values, not
/// binary floating types). Comparisons and arithmetic MUST go through an injected
/// Calendar (LocalCalendarProvider, T007a) rather than Calendar.current, so
/// recurrence/overdue logic is deterministic in tests.
public struct LocalDate: Hashable, Codable, Sendable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        guard year > 0, (1...12).contains(month), (1...31).contains(day) else {
            throw DomainError.invalidNumber
        }
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year ?? 1970
        self.month = components.month ?? 1
        self.day = components.day ?? 1
    }

    public var canonicalString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public init(canonicalString: String) throws {
        let parts = canonicalString.split(separator: "-")
        guard parts.count == 3,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else {
            throw DomainError.invalidNumber
        }
        try self.init(year: year, month: month, day: day)
    }

    public func startOfDay(calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    public func weekday(calendar: Calendar) -> Weekday {
        let foundationWeekday = calendar.component(.weekday, from: startOfDay(calendar: calendar))
        return Weekday(foundationWeekday: foundationWeekday)
    }

    public func addingDays(_ days: Int, calendar: Calendar) -> LocalDate {
        let date =
            calendar.date(byAdding: .day, value: days, to: startOfDay(calendar: calendar))
            ?? startOfDay(calendar: calendar)
        return LocalDate(date: date, calendar: calendar)
    }

    /// Whole-day difference (self - earlier), MAY be negative.
    public func daysSince(_ earlier: LocalDate, calendar: Calendar) -> Int {
        calendar.dateComponents(
            [.day],
            from: earlier.startOfDay(calendar: calendar),
            to: startOfDay(calendar: calendar)
        ).day ?? 0
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// A wall-clock time with no date or time-zone component, stored as a canonical
/// "HH:mm" string.
public struct LocalTime: Hashable, Codable, Sendable, Comparable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw DomainError.invalidNumber
        }
        self.hour = hour
        self.minute = minute
    }

    public var canonicalString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public init(canonicalString: String) throws {
        let parts = canonicalString.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            throw DomainError.invalidNumber
        }
        try self.init(hour: hour, minute: minute)
    }

    public var minutesSinceMidnight: Int {
        hour * 60 + minute
    }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

/// Combines a LocalDate + LocalTime into a UTC instant via an injected Calendar,
/// the single conversion point recurrence/appointment overlap logic depends on.
public func localInstant(date: LocalDate, time: LocalTime, calendar: Calendar) -> Date {
    var components = calendar.dateComponents([.year, .month, .day], from: date.startOfDay(calendar: calendar))
    components.hour = time.hour
    components.minute = time.minute
    return calendar.date(from: components) ?? date.startOfDay(calendar: calendar)
}
