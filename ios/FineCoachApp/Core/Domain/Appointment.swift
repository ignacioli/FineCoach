import Foundation

/// Persisted appointment status. Overdue is deliberately NOT a case here -- it is
/// a derived presentation state (`Appointment.isOverdue`), never stored, and the
/// domain layer MUST NOT transition an appointment to completed/cancelled on its
/// own just because time has passed (M1B-FR-002, plan D-M1B-001).
public enum AppointmentStatus: String, Codable, Sendable {
    case scheduled
    case inProgress
    case completed
    case cancelled
    case absent
}

public enum AbsentCreditChoice: String, Codable, Sendable {
    case charged
    case notCharged
}

/// A one-on-one training appointment (data-model §2.2). Distinct from `Session`:
/// an Appointment is a time slot, a Session is the record of training that
/// actually happened; at most one Session may ever be linked to an Appointment.
public struct Appointment: Hashable, Codable, Sendable, Identifiable {
    public let id: StableUUID
    public let studentID: StableUUID
    public let seriesID: StableUUID?
    public let date: LocalDate
    public let startTime: LocalTime
    public let durationMinutes: Int
    public let status: AppointmentStatus
    public let absentCreditChoice: AbsentCreditChoice?
    public let cancellationReason: ValidatedText?
    /// "仅本次" edit: this instance has detached from its series' shared rule and
    /// carries its own values going forward (D-011).
    public let isDetachedException: Bool
    public let reminderEnabled: Bool
    public let reminderLeadMinutes: ReminderLeadMinutes?
    public let linkedSessionID: StableUUID?
    public let createdAtUTC: Date
    public let updatedAtUTC: Date

    public init(
        id: StableUUID,
        studentID: StableUUID,
        seriesID: StableUUID?,
        date: LocalDate,
        startTime: LocalTime,
        durationMinutes: Int = 60,
        status: AppointmentStatus = .scheduled,
        absentCreditChoice: AbsentCreditChoice? = nil,
        cancellationReason: ValidatedText? = nil,
        isDetachedException: Bool = false,
        reminderEnabled: Bool = true,
        reminderLeadMinutes: ReminderLeadMinutes? = .sixty,
        linkedSessionID: StableUUID? = nil,
        createdAtUTC: Date,
        updatedAtUTC: Date
    ) throws {
        guard durationMinutes > 0 else {
            throw DomainError.invalidNumber
        }
        if reminderEnabled {
            guard reminderLeadMinutes != nil else {
                throw DomainError.invalidState
            }
        }
        if status != .absent, absentCreditChoice != nil {
            throw DomainError.invalidState
        }
        self.id = id
        self.studentID = studentID
        self.seriesID = seriesID
        self.date = date
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.status = status
        self.absentCreditChoice = absentCreditChoice
        self.cancellationReason = cancellationReason
        self.isDetachedException = isDetachedException
        self.reminderEnabled = reminderEnabled
        self.reminderLeadMinutes = reminderLeadMinutes
        self.linkedSessionID = linkedSessionID
        self.createdAtUTC = createdAtUTC
        self.updatedAtUTC = updatedAtUTC
    }

    public func startInstant(calendar: Calendar) -> Date {
        localInstant(date: date, time: startTime, calendar: calendar)
    }

    public func endInstant(calendar: Calendar) -> Date {
        startInstant(calendar: calendar).addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    /// Half-open interval overlap: [start, end) intersects [other.start, other.end).
    public func overlaps(_ other: Appointment, calendar: Calendar) -> Bool {
        startInstant(calendar: calendar) < other.endInstant(calendar: calendar)
            && other.startInstant(calendar: calendar) < endInstant(calendar: calendar)
    }

    /// Derived presentation state (M1B-FR-002): scheduled, time window has fully
    /// elapsed, and the coach has not yet acted on it.
    public func isOverdue(now: Date, calendar: Calendar) -> Bool {
        status == .scheduled && endInstant(calendar: calendar) <= now
    }

    /// Permanent deletion is limited to "从未开始的未来误建" (M1B-FR-008): still
    /// scheduled, no Session ever linked, and its start time has not yet arrived.
    public func canPermanentlyDelete(now: Date, calendar: Calendar) -> Bool {
        status == .scheduled && linkedSessionID == nil && startInstant(calendar: calendar) > now
    }

    public func startingTraining(sessionID: StableUUID, now: Date) throws -> Appointment {
        guard status == .scheduled, linkedSessionID == nil else {
            throw DomainError.invalidState
        }
        return replacing(status: .inProgress, linkedSessionID: .some(sessionID), updatedAtUTC: now)
    }

    /// Abandoning an empty Session returns the appointment to `scheduled` without
    /// leaving a dangling Session link (mirrors M1A-FR-018 abandon-empty).
    public func abandoningEmptySession(now: Date) throws -> Appointment {
        guard status == .inProgress else {
            throw DomainError.invalidState
        }
        return replacing(status: .scheduled, linkedSessionID: .some(nil), updatedAtUTC: now)
    }

    public func completingSession(now: Date) throws -> Appointment {
        guard status == .inProgress, linkedSessionID != nil else {
            throw DomainError.invalidState
        }
        return replacing(status: .completed, updatedAtUTC: now)
    }

    public func cancelling(reason: ValidatedText?, now: Date) throws -> Appointment {
        guard status == .scheduled else {
            throw DomainError.invalidState
        }
        return replacing(status: .cancelled, cancellationReason: .some(reason), updatedAtUTC: now)
    }

    public func markingAbsent(creditChoice: AbsentCreditChoice, now: Date) throws -> Appointment {
        guard status == .scheduled else {
            throw DomainError.invalidState
        }
        return replacing(status: .absent, absentCreditChoice: .some(creditChoice), updatedAtUTC: now)
    }

    /// D-011: "仅本次"/"本次及以后" edits are limited to start time, duration, and
    /// reminder lead time. Changing weekdays is modeled as a new series by the
    /// Application layer, never as a mutation here.
    public func reschedulingDetached(
        date: LocalDate? = nil,
        startTime: LocalTime? = nil,
        durationMinutes: Int? = nil,
        reminderEnabled: Bool? = nil,
        reminderLeadMinutes: ReminderLeadMinutes? = nil,
        now: Date
    ) throws -> Appointment {
        guard status == .scheduled else {
            throw DomainError.invalidState
        }
        let resolvedDuration = durationMinutes ?? self.durationMinutes
        guard resolvedDuration > 0 else {
            throw DomainError.invalidNumber
        }
        let resolvedReminderEnabled = reminderEnabled ?? self.reminderEnabled
        let resolvedLeadMinutes = reminderLeadMinutes ?? self.reminderLeadMinutes
        if resolvedReminderEnabled {
            guard resolvedLeadMinutes != nil else {
                throw DomainError.invalidState
            }
        }
        return replacing(
            date: date,
            startTime: startTime,
            durationMinutes: resolvedDuration,
            isDetachedException: true,
            reminderEnabled: resolvedReminderEnabled,
            reminderLeadMinutes: .some(resolvedLeadMinutes),
            updatedAtUTC: now
        )
    }

    private func replacing(
        date: LocalDate? = nil,
        startTime: LocalTime? = nil,
        durationMinutes: Int? = nil,
        status: AppointmentStatus? = nil,
        absentCreditChoice: AbsentCreditChoice?? = nil,
        cancellationReason: ValidatedText?? = nil,
        isDetachedException: Bool? = nil,
        reminderEnabled: Bool? = nil,
        reminderLeadMinutes: ReminderLeadMinutes?? = nil,
        linkedSessionID: StableUUID?? = nil,
        updatedAtUTC: Date
    ) -> Appointment {
        // All inputs were already validated by the calling transition method
        // against a previously-valid instance, so this bypasses re-validation
        // rather than force-trying the throwing public initializer.
        Appointment(
            id: id,
            studentID: studentID,
            seriesID: seriesID,
            date: date ?? self.date,
            startTime: startTime ?? self.startTime,
            durationMinutes: durationMinutes ?? self.durationMinutes,
            status: status ?? self.status,
            absentCreditChoice: absentCreditChoice ?? self.absentCreditChoice,
            cancellationReason: cancellationReason ?? self.cancellationReason,
            isDetachedException: isDetachedException ?? self.isDetachedException,
            reminderEnabled: reminderEnabled ?? self.reminderEnabled,
            reminderLeadMinutes: reminderLeadMinutes ?? self.reminderLeadMinutes,
            linkedSessionID: linkedSessionID ?? self.linkedSessionID,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC,
            skipValidation: ()
        )
    }

    private init(
        id: StableUUID,
        studentID: StableUUID,
        seriesID: StableUUID?,
        date: LocalDate,
        startTime: LocalTime,
        durationMinutes: Int,
        status: AppointmentStatus,
        absentCreditChoice: AbsentCreditChoice?,
        cancellationReason: ValidatedText?,
        isDetachedException: Bool,
        reminderEnabled: Bool,
        reminderLeadMinutes: ReminderLeadMinutes?,
        linkedSessionID: StableUUID?,
        createdAtUTC: Date,
        updatedAtUTC: Date,
        skipValidation: Void
    ) {
        self.id = id
        self.studentID = studentID
        self.seriesID = seriesID
        self.date = date
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.status = status
        self.absentCreditChoice = absentCreditChoice
        self.cancellationReason = cancellationReason
        self.isDetachedException = isDetachedException
        self.reminderEnabled = reminderEnabled
        self.reminderLeadMinutes = reminderLeadMinutes
        self.linkedSessionID = linkedSessionID
        self.createdAtUTC = createdAtUTC
        self.updatedAtUTC = updatedAtUTC
    }
}
