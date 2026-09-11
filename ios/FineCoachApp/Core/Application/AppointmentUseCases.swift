import Foundation

/// A conflicting appointment surfaced to the coach before an explicit override
/// (M1B-FR-006): the coach sees the other Student's display name and the
/// conflicting time window, not just "conflict" -- so this carries a resolved
/// display name rather than only `studentID`.
public struct AppointmentConflict: Equatable, Sendable {
    public let conflictingAppointmentID: StableUUID
    public let conflictingStudentID: StableUUID
    public let conflictingStudentDisplayName: String
    public let conflictingStartInstant: Date
    public let conflictingEndInstant: Date
}

public struct RecurringAppointmentDraft: Sendable {
    public var weekdays: Set<Weekday>
    public var termination: RecurrenceTermination
    public var firstOccurrenceDate: LocalDate
    public var startTime: LocalTime
    public var durationMinutes: Int
    public var reminderEnabled: Bool
    public var reminderLeadMinutes: ReminderLeadMinutes?

    public init(
        weekdays: Set<Weekday>,
        termination: RecurrenceTermination,
        firstOccurrenceDate: LocalDate,
        startTime: LocalTime,
        durationMinutes: Int = 60,
        reminderEnabled: Bool = true,
        reminderLeadMinutes: ReminderLeadMinutes? = .sixty
    ) {
        self.weekdays = weekdays
        self.termination = termination
        self.firstOccurrenceDate = firstOccurrenceDate
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.reminderEnabled = reminderEnabled
        self.reminderLeadMinutes = reminderLeadMinutes
    }
}

/// Whether a recurring edit applies to just the tapped instance or to it and
/// every future instance of the series (spec: 仅本次/本次及以后).
public enum RecurringEditScope: Sendable {
    case thisInstanceOnly
    case thisAndFuture
}

public struct AppointmentUseCases: Sendable {
    private let appointmentRepository: CoreDataAppointmentRepository
    private let studentRepository: CoreDataStudentRepository
    private let activeSession: ActiveSessionUseCases
    private let notifications: NotificationScheduler
    private let clock: any Clock
    private let calendarProvider: any LocalCalendarProvider
    private let ids: any IDGenerator

    public init(
        appointmentRepository: CoreDataAppointmentRepository,
        studentRepository: CoreDataStudentRepository,
        activeSession: ActiveSessionUseCases,
        notifications: NotificationScheduler,
        clock: any Clock,
        calendarProvider: any LocalCalendarProvider,
        ids: any IDGenerator
    ) {
        self.appointmentRepository = appointmentRepository
        self.studentRepository = studentRepository
        self.activeSession = activeSession
        self.notifications = notifications
        self.clock = clock
        self.calendarProvider = calendarProvider
        self.ids = ids
    }

    // MARK: - Conflict detection (M1B-FR-006)

    /// Coach-wide half-open-interval overlap against every scheduled/in-progress
    /// appointment (any student), excluding `excludingAppointmentID` (the one
    /// being edited, if any).
    public func detectConflicts(
        date: LocalDate,
        startTime: LocalTime,
        durationMinutes: Int,
        excludingAppointmentID: StableUUID?
    ) async throws -> [AppointmentConflict] {
        let calendar = calendarProvider.currentCalendar()
        let candidate = try Appointment(
            id: excludingAppointmentID ?? StableUUID(ids.makeID()),
            studentID: StableUUID(UUID()),
            seriesID: nil,
            date: date,
            startTime: startTime,
            durationMinutes: durationMinutes,
            createdAtUTC: clock.nowUTC(),
            updatedAtUTC: clock.nowUTC()
        )
        let active = try await appointmentRepository.activeAppointments(excluding: excludingAppointmentID)
        return try await conflicts(for: candidate, against: active, calendar: calendar)
    }

    private func conflicts(
        for candidate: Appointment,
        against active: [Appointment],
        calendar: Calendar
    ) async throws -> [AppointmentConflict] {
        var results: [AppointmentConflict] = []
        for other in active where other.overlaps(candidate, calendar: calendar) {
            let displayName = (try? await studentRepository.student(id: other.studentID))?.displayName.value ?? ""
            results.append(
                AppointmentConflict(
                    conflictingAppointmentID: other.id,
                    conflictingStudentID: other.studentID,
                    conflictingStudentDisplayName: displayName,
                    conflictingStartInstant: other.startInstant(calendar: calendar),
                    conflictingEndInstant: other.endInstant(calendar: calendar)
                )
            )
        }
        return results
    }

    // MARK: - Create

    public func createSingle(
        studentID: StableUUID,
        date: LocalDate,
        startTime: LocalTime,
        durationMinutes: Int = 60,
        reminderEnabled: Bool = true,
        reminderLeadMinutes: ReminderLeadMinutes? = .sixty,
        overrideConflict: Bool
    ) async throws -> Appointment {
        let student = try await studentRepository.student(id: studentID)
        guard student.canStartSession() else {
            throw DomainError.invalidState
        }
        let now = clock.nowUTC()
        let draft = try Appointment(
            id: StableUUID(ids.makeID()),
            studentID: studentID,
            seriesID: nil,
            date: date,
            startTime: startTime,
            durationMinutes: durationMinutes,
            reminderEnabled: reminderEnabled,
            reminderLeadMinutes: reminderLeadMinutes,
            createdAtUTC: now,
            updatedAtUTC: now
        )
        try await ensureNoConflict(draft, overrideConflict: overrideConflict, excludingAppointmentID: nil)
        let created = try await appointmentRepository.create(draft)
        await notifications.sync(appointment: created)
        return created
    }

    public func createRecurring(
        studentID: StableUUID,
        draft: RecurringAppointmentDraft,
        overrideConflict: Bool
    ) async throws -> [Appointment] {
        let student = try await studentRepository.student(id: studentID)
        guard student.canStartSession() else {
            throw DomainError.invalidState
        }
        let calendar = calendarProvider.currentCalendar()
        try RecurrenceSeries.validateMaterializationBound(
            termination: draft.termination,
            firstOccurrenceDate: draft.firstOccurrenceDate,
            calendar: calendar
        )
        let now = clock.nowUTC()
        let series = try RecurrenceSeries(
            id: StableUUID(ids.makeID()),
            studentID: studentID,
            weekdays: draft.weekdays,
            termination: draft.termination,
            defaultStartTime: draft.startTime,
            defaultDurationMinutes: draft.durationMinutes,
            defaultReminderEnabled: draft.reminderEnabled,
            defaultReminderLeadMinutes: draft.reminderLeadMinutes,
            createdAtUTC: now,
            updatedAtUTC: now
        )
        let appointments = try materializedAppointments(
            for: series,
            weekdays: draft.weekdays,
            firstOccurrenceDate: draft.firstOccurrenceDate,
            termination: draft.termination,
            startTime: draft.startTime,
            durationMinutes: draft.durationMinutes,
            reminderEnabled: draft.reminderEnabled,
            reminderLeadMinutes: draft.reminderLeadMinutes,
            studentID: studentID,
            calendar: calendar,
            now: now
        )
        if !overrideConflict {
            let active = try await appointmentRepository.activeAppointments(excluding: nil)
            var allConflicts: [AppointmentConflict] = []
            for appointment in appointments {
                allConflicts.append(contentsOf: try await conflicts(for: appointment, against: active, calendar: calendar))
            }
            guard allConflicts.isEmpty else {
                throw DomainError.conflict
            }
        }
        try await appointmentRepository.createSeries(series: series, appointments: appointments)
        for appointment in appointments {
            await notifications.sync(appointment: appointment)
        }
        return appointments
    }

    private func materializedAppointments(
        for series: RecurrenceSeries,
        weekdays: Set<Weekday>,
        firstOccurrenceDate: LocalDate,
        termination: RecurrenceTermination,
        startTime: LocalTime,
        durationMinutes: Int,
        reminderEnabled: Bool,
        reminderLeadMinutes: ReminderLeadMinutes?,
        studentID: StableUUID,
        calendar: Calendar,
        now: Date
    ) throws -> [Appointment] {
        let dates = RecurrenceSeries.materializedDates(
            weekdays: weekdays,
            firstOccurrenceDate: firstOccurrenceDate,
            termination: termination,
            calendar: calendar
        )
        return try dates.map { date in
            try Appointment(
                id: StableUUID(ids.makeID()),
                studentID: studentID,
                seriesID: series.id,
                date: date,
                startTime: startTime,
                durationMinutes: durationMinutes,
                reminderEnabled: reminderEnabled,
                reminderLeadMinutes: reminderLeadMinutes,
                createdAtUTC: now,
                updatedAtUTC: now
            )
        }
    }

    private func ensureNoConflict(
        _ candidate: Appointment,
        overrideConflict: Bool,
        excludingAppointmentID: StableUUID?
    ) async throws {
        guard !overrideConflict else {
            return
        }
        let active = try await appointmentRepository.activeAppointments(excluding: excludingAppointmentID)
        let calendar = calendarProvider.currentCalendar()
        guard try await conflicts(for: candidate, against: active, calendar: calendar).isEmpty else {
            throw DomainError.conflict
        }
    }

    // MARK: - Reschedule / detached edit (D-011)

    /// Handles both a standalone appointment's plain reschedule and a
    /// recurring instance's "仅本次" edit -- for `.thisInstanceOnly` this is
    /// the entire operation. For `.thisAndFuture` on a series member, callers
    /// MUST route through `applyThisAndFuture` instead, since that scope
    /// requires ending the old series and materializing a new one.
    public func rescheduleSingle(
        appointmentID: StableUUID,
        date: LocalDate? = nil,
        startTime: LocalTime? = nil,
        durationMinutes: Int? = nil,
        reminderEnabled: Bool? = nil,
        reminderLeadMinutes: ReminderLeadMinutes? = nil,
        overrideConflict: Bool
    ) async throws -> Appointment {
        let current = try await appointmentRepository.appointment(id: appointmentID)
        let now = clock.nowUTC()
        let updated = try current.reschedulingDetached(
            date: date,
            startTime: startTime,
            durationMinutes: durationMinutes,
            reminderEnabled: reminderEnabled,
            reminderLeadMinutes: reminderLeadMinutes,
            now: now
        )
        try await ensureNoConflict(updated, overrideConflict: overrideConflict, excludingAppointmentID: appointmentID)
        let saved = try await appointmentRepository.update(updated)
        await notifications.sync(appointment: saved)
        return saved
    }

    /// "本次及以后" (D-011): ends the current series as of `boundaryDate`,
    /// deletes that series' own future not-yet-acted-on instances (they are
    /// superseded, never became real training records), and materializes a
    /// new series carrying the edited rule forward from `boundaryDate`. Past
    /// instances and any instance the coach already resolved individually
    /// (completed/cancelled/absent/detached) are left untouched.
    public func applyThisAndFuture(
        seriesID: StableUUID,
        boundaryDate: LocalDate,
        weekdays: Set<Weekday>? = nil,
        startTime: LocalTime? = nil,
        durationMinutes: Int? = nil,
        reminderEnabled: Bool? = nil,
        reminderLeadMinutes: ReminderLeadMinutes? = nil,
        overrideConflict: Bool
    ) async throws -> [Appointment] {
        let calendar = calendarProvider.currentCalendar()
        let now = clock.nowUTC()
        let currentSeries = try await appointmentRepository.series(id: seriesID)
        let existing = try await appointmentRepository.appointments(seriesID: seriesID)

        let superseded = existing.filter { appointment in
            appointment.date >= boundaryDate && appointment.status == .scheduled && !appointment.isDetachedException
        }

        let resolvedWeekdays = weekdays ?? currentSeries.weekdays
        let resolvedStartTime = startTime ?? currentSeries.defaultStartTime
        let resolvedDuration = durationMinutes ?? currentSeries.defaultDurationMinutes
        let resolvedReminderEnabled = reminderEnabled ?? currentSeries.defaultReminderEnabled
        let resolvedReminderLeadMinutes = reminderLeadMinutes ?? currentSeries.defaultReminderLeadMinutes

        try RecurrenceSeries.validateMaterializationBound(
            termination: currentSeries.termination,
            firstOccurrenceDate: boundaryDate,
            calendar: calendar
        )
        let newSeries = try RecurrenceSeries(
            id: StableUUID(ids.makeID()),
            studentID: currentSeries.studentID,
            weekdays: resolvedWeekdays,
            termination: currentSeries.termination,
            defaultStartTime: resolvedStartTime,
            defaultDurationMinutes: resolvedDuration,
            defaultReminderEnabled: resolvedReminderEnabled,
            defaultReminderLeadMinutes: resolvedReminderLeadMinutes,
            createdAtUTC: now,
            updatedAtUTC: now
        )
        let newAppointments = try materializedAppointments(
            for: newSeries,
            weekdays: resolvedWeekdays,
            firstOccurrenceDate: boundaryDate,
            termination: currentSeries.termination,
            startTime: resolvedStartTime,
            durationMinutes: resolvedDuration,
            reminderEnabled: resolvedReminderEnabled,
            reminderLeadMinutes: resolvedReminderLeadMinutes,
            studentID: currentSeries.studentID,
            calendar: calendar,
            now: now
        )

        if !overrideConflict {
            let supersededIDs = Set(superseded.map(\.id))
            let active = try await appointmentRepository.activeAppointments(excluding: nil)
                .filter { !supersededIDs.contains($0.id) }
            var allConflicts: [AppointmentConflict] = []
            for appointment in newAppointments {
                allConflicts.append(
                    contentsOf: try await conflicts(for: appointment, against: active, calendar: calendar)
                )
            }
            guard allConflicts.isEmpty else {
                throw DomainError.conflict
            }
        }

        let ended = currentSeries.ended(now: now)
        try await appointmentRepository.truncateAndReplaceSeries(
            endedSeries: ended,
            supersededAppointmentIDs: superseded.map(\.id),
            newSeries: newSeries,
            newAppointments: newAppointments
        )
        await notifications.remove(appointmentIDs: superseded.map(\.id))
        for appointment in newAppointments {
            await notifications.sync(appointment: appointment)
        }
        return newAppointments
    }

    // MARK: - Cancel / absent / start / abandon / complete

    public func cancel(appointmentID: StableUUID, reason: String?) async throws -> Appointment {
        let current = try await appointmentRepository.appointment(id: appointmentID)
        let reasonText = try reason.map { try ValidatedText($0, allowEmpty: true) }
        let updated = try current.cancelling(reason: reasonText, now: clock.nowUTC())
        let saved = try await appointmentRepository.update(updated)
        await notifications.remove(appointmentID: appointmentID)
        return saved
    }

    public func markAbsent(appointmentID: StableUUID, creditChoice: AbsentCreditChoice) async throws -> Appointment {
        let current = try await appointmentRepository.appointment(id: appointmentID)
        let updated = try current.markingAbsent(creditChoice: creditChoice, now: clock.nowUTC())
        let saved = try await appointmentRepository.update(updated)
        await notifications.remove(appointmentID: appointmentID)
        return saved
    }

    /// "开始训练" (M1B-FR-007): reuses the M1-A single-active-session pointer
    /// via `ActiveSessionUseCases.startOrOpen` so "at most one in-progress
    /// Session globally, re-starting reopens the existing one" holds without
    /// duplicating that invariant here. If a DIFFERENT student's session is
    /// already active, this appointment is left `scheduled` (not silently
    /// misattributed to a foreign session) and the existing session is
    /// returned so the coach lands back on their in-progress training.
    public func startTraining(appointmentID: StableUUID) async throws -> Session {
        let appointment = try await appointmentRepository.appointment(id: appointmentID)
        guard appointment.status == .scheduled else {
            throw DomainError.invalidState
        }
        let session = try await activeSession.startOrOpen(studentID: appointment.studentID)
        guard session.studentID == appointment.studentID, appointment.linkedSessionID == nil else {
            return session
        }
        let updated = try appointment.startingTraining(sessionID: session.id, now: clock.nowUTC())
        _ = try await appointmentRepository.update(updated)
        await notifications.remove(appointmentID: appointmentID)
        return session
    }

    public func abandonEmptySession(appointmentID: StableUUID) async throws -> Appointment {
        let current = try await appointmentRepository.appointment(id: appointmentID)
        let updated = try current.abandoningEmptySession(now: clock.nowUTC())
        let saved = try await appointmentRepository.update(updated)
        await notifications.sync(appointment: saved)
        return saved
    }

    public func completeSession(appointmentID: StableUUID) async throws -> Appointment {
        let current = try await appointmentRepository.appointment(id: appointmentID)
        let updated = try current.completingSession(now: clock.nowUTC())
        let saved = try await appointmentRepository.update(updated)
        await notifications.remove(appointmentID: appointmentID)
        return saved
    }

    // MARK: - Delete (M1B-FR-008: never-started future misclick only)

    public func deleteNeverStartedFutureAppointment(appointmentID: StableUUID) async throws {
        let calendar = calendarProvider.currentCalendar()
        try await appointmentRepository.delete(id: appointmentID, now: clock.nowUTC(), calendar: calendar)
        await notifications.remove(appointmentID: appointmentID)
    }

    // MARK: - Queries

    public func appointment(id: StableUUID) async throws -> Appointment {
        try await appointmentRepository.appointment(id: id)
    }

    public func appointments(studentID: StableUUID) async throws -> [Appointment] {
        try await appointmentRepository.appointments(studentID: studentID)
    }

    public func appointments(onLocalDates dates: [LocalDate]) async throws -> [Appointment] {
        try await appointmentRepository.appointments(localDates: dates)
    }

    /// Today's ordered rows (T014 TodayOrderingPolicy), computed from this use
    /// case's own injected clock/calendar -- so the Today Feature UI never needs
    /// its own copy of "what time is it" / "what day is today" (T014a).
    public func todayOrdering() async throws -> [TodayOrderedAppointment] {
        let calendar = calendarProvider.currentCalendar()
        let now = clock.nowUTC()
        let today = LocalDate(date: now, calendar: calendar)
        let appointments = try await appointments(onLocalDates: [today])
        return TodayOrderingPolicy.order(appointments: appointments, today: today, now: now, calendar: calendar)
    }

    public func todayLocalDate() -> LocalDate {
        LocalDate(date: clock.nowUTC(), calendar: calendarProvider.currentCalendar())
    }
}
