import Foundation

/// How long before an appointment its local reminder fires (D-003).
public enum ReminderLeadMinutes: Int, CaseIterable, Hashable, Codable, Sendable {
    case fifteen = 15
    case thirty = 30
    case sixty = 60
    case oneTwenty = 120
}

public enum RecurrenceSeriesStatus: String, Codable, Sendable {
    case active
    case ended
}

/// Exactly one termination condition (spec: "恰好一个终止条件") -- modeled as an
/// enum rather than two optional fields so "neither set" / "both set" are
/// unrepresentable rather than runtime-validated.
public enum RecurrenceTermination: Hashable, Codable, Sendable {
    case endDate(LocalDate)
    case repeatCount(Int)
}

/// A weekly recurrence rule for one-on-one appointments (D-002/D-003, data-model §2.1).
/// No every-two-weeks/monthly variants. Materialization is bounded (D-012): at most
/// 366 instances, equivalently an endDate at most 366 days after the first occurrence.
public struct RecurrenceSeries: Hashable, Codable, Sendable, Identifiable {
    /// Hard cap on materialized instances for a single series (D-012).
    public static let maximumMaterializedInstances = 366

    public let id: StableUUID
    public let studentID: StableUUID
    public let weekdays: Set<Weekday>
    public let termination: RecurrenceTermination
    public let defaultStartTime: LocalTime
    public let defaultDurationMinutes: Int
    public let defaultReminderEnabled: Bool
    public let defaultReminderLeadMinutes: ReminderLeadMinutes?
    public let status: RecurrenceSeriesStatus
    public let createdAtUTC: Date
    public let updatedAtUTC: Date

    public init(
        id: StableUUID,
        studentID: StableUUID,
        weekdays: Set<Weekday>,
        termination: RecurrenceTermination,
        defaultStartTime: LocalTime,
        defaultDurationMinutes: Int = 60,
        defaultReminderEnabled: Bool = true,
        defaultReminderLeadMinutes: ReminderLeadMinutes? = .sixty,
        status: RecurrenceSeriesStatus = .active,
        createdAtUTC: Date,
        updatedAtUTC: Date
    ) throws {
        guard !weekdays.isEmpty else {
            throw DomainError.invalidState
        }
        guard defaultDurationMinutes > 0 else {
            throw DomainError.invalidNumber
        }
        if defaultReminderEnabled {
            guard defaultReminderLeadMinutes != nil else {
                throw DomainError.invalidState
            }
        }
        if case .repeatCount(let count) = termination {
            guard count > 0 else {
                throw DomainError.invalidNumber
            }
        }
        self.id = id
        self.studentID = studentID
        self.weekdays = weekdays
        self.termination = termination
        self.defaultStartTime = defaultStartTime
        self.defaultDurationMinutes = defaultDurationMinutes
        self.defaultReminderEnabled = defaultReminderEnabled
        self.defaultReminderLeadMinutes = defaultReminderLeadMinutes
        self.status = status
        self.createdAtUTC = createdAtUTC
        self.updatedAtUTC = updatedAtUTC
    }

    /// "本次及以后" truncation: the current series stops producing new instances
    /// as of this edit; a NEW series (built by the caller) carries the changed rule
    /// forward. Past materialized instances are untouched (spec D-011). Fields were
    /// already validated at construction and are unchanged here, so this cannot fail.
    public func ended(now: Date) -> RecurrenceSeries {
        RecurrenceSeries(
            id: id,
            studentID: studentID,
            weekdays: weekdays,
            termination: termination,
            defaultStartTime: defaultStartTime,
            defaultDurationMinutes: defaultDurationMinutes,
            defaultReminderEnabled: defaultReminderEnabled,
            defaultReminderLeadMinutes: defaultReminderLeadMinutes,
            status: .ended,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: now,
            skipValidation: ()
        )
    }

    private init(
        id: StableUUID,
        studentID: StableUUID,
        weekdays: Set<Weekday>,
        termination: RecurrenceTermination,
        defaultStartTime: LocalTime,
        defaultDurationMinutes: Int,
        defaultReminderEnabled: Bool,
        defaultReminderLeadMinutes: ReminderLeadMinutes?,
        status: RecurrenceSeriesStatus,
        createdAtUTC: Date,
        updatedAtUTC: Date,
        skipValidation: Void
    ) {
        self.id = id
        self.studentID = studentID
        self.weekdays = weekdays
        self.termination = termination
        self.defaultStartTime = defaultStartTime
        self.defaultDurationMinutes = defaultDurationMinutes
        self.defaultReminderEnabled = defaultReminderEnabled
        self.defaultReminderLeadMinutes = defaultReminderLeadMinutes
        self.status = status
        self.createdAtUTC = createdAtUTC
        self.updatedAtUTC = updatedAtUTC
    }

    /// D-012: validates that materializing from `firstOccurrenceDate` under
    /// `termination` would not exceed the 366-instance cap, WITHOUT generating
    /// the full date list (cheap, save-time check).
    public static func validateMaterializationBound(
        termination: RecurrenceTermination,
        firstOccurrenceDate: LocalDate,
        calendar: Calendar
    ) throws {
        switch termination {
        case .repeatCount(let count):
            guard count > 0, count <= maximumMaterializedInstances else {
                throw DomainError.recurrenceLimitExceeded
            }
        case .endDate(let endDate):
            guard endDate >= firstOccurrenceDate else {
                throw DomainError.invalidState
            }
            let span = endDate.daysSince(firstOccurrenceDate, calendar: calendar)
            guard span <= maximumMaterializedInstances else {
                throw DomainError.recurrenceLimitExceeded
            }
        }
    }

    /// Pure materialization: every LocalDate matching `weekdays`, starting at
    /// `firstOccurrenceDate`, until `termination` is satisfied. Always bounded by
    /// `maximumMaterializedInstances` regardless of input, as a defense-in-depth
    /// backstop alongside `validateMaterializationBound`.
    public static func materializedDates(
        weekdays: Set<Weekday>,
        firstOccurrenceDate: LocalDate,
        termination: RecurrenceTermination,
        calendar: Calendar
    ) -> [LocalDate] {
        guard !weekdays.isEmpty else {
            return []
        }
        var dates: [LocalDate] = []
        var cursor = firstOccurrenceDate

        switch termination {
        case .repeatCount(let count):
            let target = min(max(count, 0), maximumMaterializedInstances)
            var daysScanned = 0
            let scanLimit = maximumMaterializedInstances * 7 + 7
            while dates.count < target, daysScanned < scanLimit {
                if weekdays.contains(cursor.weekday(calendar: calendar)) {
                    dates.append(cursor)
                }
                cursor = cursor.addingDays(1, calendar: calendar)
                daysScanned += 1
            }
        case .endDate(let endDate):
            while cursor <= endDate, dates.count < maximumMaterializedInstances {
                if weekdays.contains(cursor.weekday(calendar: calendar)) {
                    dates.append(cursor)
                }
                cursor = cursor.addingDays(1, calendar: calendar)
            }
        }
        return dates
    }
}
