import Foundation

public struct WidgetTodaySnapshot: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public struct Entry: Codable, Equatable, Sendable {
        public let startAtUTC: Date
        public let studentDisplayName: String
        public let appointmentID: String

        public init(startAtUTC: Date, studentDisplayName: String, appointmentID: String) {
            self.startAtUTC = startAtUTC
            self.studentDisplayName = studentDisplayName
            self.appointmentID = appointmentID
        }
    }

    public let formatVersion: Int
    public let localDate: String
    public let generatedAtUTC: Date
    public let entries: [Entry]
    public let finishedCount: Int

    public init(
        formatVersion: Int = currentFormatVersion, localDate: String, generatedAtUTC: Date,
        entries: [Entry], finishedCount: Int
    ) {
        self.formatVersion = formatVersion
        self.localDate = localDate
        self.generatedAtUTC = generatedAtUTC
        self.entries = entries
        self.finishedCount = finishedCount
    }

    public enum DisplayState: Equatable, Sendable {
        case placeholder
        case noClasses
        case allFinished
        case classes
    }

    public static func dateKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public func displayState(at now: Date, calendar: Calendar) -> DisplayState {
        guard formatVersion == Self.currentFormatVersion, localDate == Self.dateKey(now, calendar: calendar) else {
            return .placeholder
        }
        if entries.isEmpty { return finishedCount > 0 ? .allFinished : .noClasses }
        return .classes
    }

    public func remainingCount(at now: Date, calendar: Calendar) -> Int {
        displayState(at: now, calendar: calendar) == .classes ? entries.count : 0
    }

    public func nextEntry(at now: Date, calendar: Calendar) -> Entry? {
        guard displayState(at: now, calendar: calendar) == .classes else { return nil }
        return entries.first { $0.startAtUTC >= now } ?? entries.first
    }

    public func mediumEntries(at now: Date, calendar: Calendar) -> [Entry] {
        guard displayState(at: now, calendar: calendar) == .classes else { return [] }
        return Array(entries.prefix(3))
    }

    public static func timelineDates(snapshot: Self?, now: Date, calendar: Calendar) -> [Date] {
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        // An exact start still counts as upcoming; advance again immediately after it.
        let starts =
            snapshot?.displayState(at: now, calendar: calendar) == .classes
            ? snapshot!.entries.flatMap { [$0.startAtUTC, $0.startAtUTC.addingTimeInterval(1)] }
                .filter { $0 > now && $0 < midnight } : []
        return Array(Set([now, midnight] + starts)).sorted()
    }
}

#if !FINECOACH_WIDGET_EXTENSION
    extension WidgetTodaySnapshot {
        public static func build(
            appointments: [Appointment], studentDisplayName: (StableUUID) -> String,
            now: Date, calendar: Calendar
        ) -> Self {
            let today = LocalDate(date: now, calendar: calendar)
            let todays = appointments.filter { $0.date == today }
            let entries = todays.filter { $0.status == .scheduled || $0.status == .inProgress }
                .sorted {
                    let left = $0.startInstant(calendar: calendar)
                    let right = $1.startInstant(calendar: calendar)
                    return left == right ? $0.id.rawValue.uuidString < $1.id.rawValue.uuidString : left < right
                }
                .map {
                    Entry(
                        startAtUTC: $0.startInstant(calendar: calendar),
                        studentDisplayName: studentDisplayName($0.studentID),
                        appointmentID: $0.id.rawValue.uuidString)
                }
            return Self(
                localDate: today.canonicalString, generatedAtUTC: now, entries: entries,
                finishedCount: todays.filter { $0.status == .completed || $0.status == .absent }.count)
        }
    }
#endif
