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

/// The fixed-interval recurrence step (Revision 1.2/D-014, replaces the old
/// per-weekday rule): every other day (2), every two days (3), or every week
/// (7). "不重复" (no repeat) is not a case here -- it means no
/// `RecurrenceSeries` is created at all; the Appointment is simply standalone
/// (`seriesID == nil`).
public enum RecurrenceInterval: Int, CaseIterable, Hashable, Codable, Sendable {
    case everyOtherDay = 2
    case everyTwoDays = 3
    case everyWeek = 7
}

/// A fixed-interval recurrence rule for one-on-one appointments (D-014,
/// data-model §2.1). No every-two-weeks/monthly variants. Materialization is
/// bounded (D-012): at most 366 instances, equivalently an endDate at most
/// 366 days after the first occurrence.
public struct RecurrenceSeries: Hashable, Codable, Sendable, Identifiable {
    /// Hard cap on materialized instances for a single series (D-012).
    public static let maximumMaterializedInstances = 366

    public let id: StableUUID
    public let studentID: StableUUID
    public let intervalDays: RecurrenceInterval
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
        intervalDays: RecurrenceInterval,
        termination: RecurrenceTermination,
        defaultStartTime: LocalTime,
        defaultDurationMinutes: Int = 60,
        defaultReminderEnabled: Bool = true,
        defaultReminderLeadMinutes: ReminderLeadMinutes? = .sixty,
        status: RecurrenceSeriesStatus = .active,
        createdAtUTC: Date,
        updatedAtUTC: Date
    ) throws {
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
        self.intervalDays = intervalDays
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
            intervalDays: intervalDays,
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
        intervalDays: RecurrenceInterval,
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
        self.intervalDays = intervalDays
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

    /// Pure materialization: every LocalDate starting at `firstOccurrenceDate`
    /// and stepping forward by `intervalDays.rawValue` days, until
    /// `termination` is satisfied. Always bounded by
    /// `maximumMaterializedInstances` regardless of input, as a defense-in-depth
    /// backstop alongside `validateMaterializationBound`.
    public static func materializedDates(
        intervalDays: RecurrenceInterval,
        firstOccurrenceDate: LocalDate,
        termination: RecurrenceTermination,
        calendar: Calendar
    ) -> [LocalDate] {
        var dates: [LocalDate] = []
        var cursor = firstOccurrenceDate

        switch termination {
        case .repeatCount(let count):
            let target = min(max(count, 0), maximumMaterializedInstances)
            while dates.count < target {
                dates.append(cursor)
                cursor = cursor.addingDays(intervalDays.rawValue, calendar: calendar)
            }
        case .endDate(let endDate):
            while cursor <= endDate, dates.count < maximumMaterializedInstances {
                dates.append(cursor)
                cursor = cursor.addingDays(intervalDays.rawValue, calendar: calendar)
            }
        }
        return dates
    }
}
