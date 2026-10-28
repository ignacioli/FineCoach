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
    public var intervalDays: RecurrenceInterval
    public var termination: RecurrenceTermination
    public var firstOccurrenceDate: LocalDate
    public var startTime: LocalTime
    public var durationMinutes: Int
    public var reminderEnabled: Bool
    public var reminderLeadMinutes: ReminderLeadMinutes?
    /// M1B-FR-033: copied onto every materialized instance.
    public var trainingFocus: Set<BodyPart>

    public init(
        intervalDays: RecurrenceInterval,
        termination: RecurrenceTermination,
        firstOccurrenceDate: LocalDate,
        startTime: LocalTime,
        durationMinutes: Int = 60,
        reminderEnabled: Bool = true,
        reminderLeadMinutes: ReminderLeadMinutes? = .sixty,
        trainingFocus: Set<BodyPart> = []
    ) {
        self.trainingFocus = trainingFocus
        self.intervalDays = intervalDays
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
    private let widgetSnapshots: any WidgetSnapshotPublishing
    private let ids: any IDGenerator

    public init(
        appointmentRepository: CoreDataAppointmentRepository,
        studentRepository: CoreDataStudentRepository,
        activeSession: ActiveSessionUseCases,
        notifications: NotificationScheduler,
        clock: any Clock,
        calendarProvider: any LocalCalendarProvider,
        ids: any IDGenerator,
        widgetSnapshots: any WidgetSnapshotPublishing = NoopWidgetSnapshotPublisher()
    ) {
        self.appointmentRepository = appointmentRepository
        self.studentRepository = studentRepository
        self.activeSession = activeSession
        self.notifications = notifications
        self.clock = clock
        self.calendarProvider = calendarProvider
        self.ids = ids
        self.widgetSnapshots = widgetSnapshots
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
        trainingFocus: Set<BodyPart> = [],
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
            trainingFocus: trainingFocus,
            createdAtUTC: now,
            updatedAtUTC: now
        )
        try await ensureNoConflict(draft, overrideConflict: overrideConflict, excludingAppointmentID: nil)
        let created = try await appointmentRepository.create(draft)
        await notifications.sync(appointment: created)
        await widgetSnapshots.refresh()
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
            intervalDays: draft.intervalDays,
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
            intervalDays: draft.intervalDays,
            firstOccurrenceDate: draft.firstOccurrenceDate,
            termination: draft.termination,
            startTime: draft.startTime,
            durationMinutes: draft.durationMinutes,
            reminderEnabled: draft.reminderEnabled,
            reminderLeadMinutes: draft.reminderLeadMinutes,
            trainingFocus: { _ in draft.trainingFocus },
            studentID: studentID,
            calendar: calendar,
            now: now
        )
        if !overrideConflict {
            let active = try await appointmentRepository.activeAppointments(excluding: nil)
            var allConflicts: [AppointmentConflict] = []
            for appointment in appointments {
                allConflicts.append(
                    contentsOf: try await conflicts(for: appointment, against: active, calendar: calendar))
            }
            guard allConflicts.isEmpty else {
                throw DomainError.conflict
            }
        }
        try await appointmentRepository.createSeries(series: series, appointments: appointments)
        for appointment in appointments {
            await notifications.sync(appointment: appointment)
        }
        await widgetSnapshots.refresh()
        return appointments
    }

    private func materializedAppointments(
        for series: RecurrenceSeries,
        intervalDays: RecurrenceInterval,
        firstOccurrenceDate: LocalDate,
        termination: RecurrenceTermination,
        startTime: LocalTime,
        durationMinutes: Int,
        reminderEnabled: Bool,
        reminderLeadMinutes: ReminderLeadMinutes?,
        trainingFocus: (LocalDate) -> Set<BodyPart>,
        studentID: StableUUID,
        calendar: Calendar,
        now: Date
    ) throws -> [Appointment] {
        let dates = RecurrenceSeries.materializedDates(
            intervalDays: intervalDays,
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
                trainingFocus: trainingFocus(date),
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
        trainingFocus: Set<BodyPart>? = nil,
        overrideConflict: Bool
    ) async throws -> Appointment {
        let current = try await appointmentRepository.appointment(id: appointmentID)
        let now = clock.nowUTC()
        var updated = try current.reschedulingDetached(
            date: date,
            startTime: startTime,
            durationMinutes: durationMinutes,
            reminderEnabled: reminderEnabled,
            reminderLeadMinutes: reminderLeadMinutes,
            now: now
        )
        if let trainingFocus {
            updated = try updated.updatingTrainingFocus(trainingFocus, now: now)
        }
        try await ensureNoConflict(updated, overrideConflict: overrideConflict, excludingAppointmentID: appointmentID)
        let saved = try await appointmentRepository.update(updated)
        await notifications.sync(appointment: saved)
        await widgetSnapshots.refresh()
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
        intervalDays: RecurrenceInterval? = nil,
        startTime: LocalTime? = nil,
        durationMinutes: Int? = nil,
        reminderEnabled: Bool? = nil,
        reminderLeadMinutes: ReminderLeadMinutes? = nil,
        boundaryTrainingFocus: Set<BodyPart>? = nil,
        overrideConflict: Bool
    ) async throws -> [Appointment] {
        let calendar = calendarProvider.currentCalendar()
        let now = clock.nowUTC()
        let currentSeries = try await appointmentRepository.series(id: seriesID)
        let existing = try await appointmentRepository.appointments(seriesID: seriesID)

        let superseded = existing.filter { appointment in
            appointment.date >= boundaryDate && appointment.status == .scheduled && !appointment.isDetachedException
        }

        // Training focus is per instance and outside D-011's this-and-future
        // fields: each re-materialized date keeps the focus of the instance
        // it supersedes; only the boundary instance may take an edited focus.
        var focusByDate: [LocalDate: Set<BodyPart>] = [:]
        for appointment in superseded {
            focusByDate[appointment.date] = appointment.trainingFocus
        }
        if let boundaryTrainingFocus {
            focusByDate[boundaryDate] = boundaryTrainingFocus
        }

        let resolvedIntervalDays = intervalDays ?? currentSeries.intervalDays
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
            intervalDays: resolvedIntervalDays,
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
            intervalDays: resolvedIntervalDays,
            firstOccurrenceDate: boundaryDate,
            termination: currentSeries.termination,
            startTime: resolvedStartTime,
            durationMinutes: resolvedDuration,
            reminderEnabled: resolvedReminderEnabled,
            reminderLeadMinutes: resolvedReminderLeadMinutes,
            trainingFocus: { focusByDate[$0] ?? [] },
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
        await widgetSnapshots.refresh()
        return newAppointments
    }

    // MARK: - Cancel / absent / start / abandon / complete

    public func cancel(appointmentID: StableUUID, reason: String?) async throws -> Appointment {
        let current = try await appointmentRepository.appointment(id: appointmentID)
        let reasonText = try reason.map { try ValidatedText($0, allowEmpty: true) }
        let updated = try current.cancelling(reason: reasonText, now: clock.nowUTC())
        let saved = try await appointmentRepository.update(updated)
        await notifications.remove(appointmentID: appointmentID)
        await widgetSnapshots.refresh()
        return saved
    }

    public func updateTrainingFocus(appointmentID: StableUUID, trainingFocus: Set<BodyPart>) async throws -> Appointment
    {
        let current = try await appointmentRepository.appointment(id: appointmentID)
        let updated = try current.updatingTrainingFocus(trainingFocus, now: clock.nowUTC())
        return try await appointmentRepository.update(updated)
    }

    public func markAbsent(appointmentID: StableUUID, creditChoice: AbsentCreditChoice) async throws -> Appointment {
        let current = try await appointmentRepository.appointment(id: appointmentID)
        let updated = try current.markingAbsent(creditChoice: creditChoice, now: clock.nowUTC())
        let saved = try await appointmentRepository.update(updated)
        await notifications.remove(appointmentID: appointmentID)
        await widgetSnapshots.refresh()
        return saved
    }

    /// "开始训练" (M1B-FR-007, revised 2026-10-22): `ActiveSessionUseCases`
    /// owns the per-Student invariant -- at most one in-progress Session for
    /// THIS appointment's Student, and re-starting returns that Student's
    /// existing one. Another Student's in-progress Session neither blocks this
    /// start nor gets linked to this appointment.
    public func startTraining(appointmentID: StableUUID) async throws -> Session {
        let appointment = try await appointmentRepository.appointment(id: appointmentID)
        guard appointment.status == .scheduled else {
            throw DomainError.invalidState
        }
        // M1B-FR-033/D-013: prefill the new/reused Session's training focus
        // from this appointment's own selection; the Coach may change it on
        // the Session afterward.
        let session = try await activeSession.startOrOpen(
            studentID: appointment.studentID,
            trainingFocus: appointment.trainingFocus
        )
        guard session.studentID == appointment.studentID, appointment.linkedSessionID == nil else {
            return session
        }
        let updated = try appointment.startingTraining(sessionID: session.id, now: clock.nowUTC())
        _ = try await appointmentRepository.update(updated)
        await notifications.remove(appointmentID: appointmentID)
        await widgetSnapshots.refresh()
        return session
    }

    public func abandonEmptySession(appointmentID: StableUUID) async throws -> Appointment {
        let current = try await appointmentRepository.appointment(id: appointmentID)
        let updated = try current.abandoningEmptySession(now: clock.nowUTC())
        let saved = try await appointmentRepository.update(updated)
        await notifications.sync(appointment: saved)
        await widgetSnapshots.refresh()
        return saved
    }

    public func completeSession(appointmentID: StableUUID) async throws -> Appointment {
        let current = try await appointmentRepository.appointment(id: appointmentID)
        let updated = try current.completingSession(now: clock.nowUTC())
        let saved = try await appointmentRepository.update(updated)
        await notifications.remove(appointmentID: appointmentID)
        await widgetSnapshots.refresh()
        return saved
    }

    // MARK: - Delete (M1B-FR-008: never-started future misclick only)

    public func deleteNeverStartedFutureAppointment(appointmentID: StableUUID) async throws {
        let calendar = calendarProvider.currentCalendar()
        try await appointmentRepository.delete(id: appointmentID, now: clock.nowUTC(), calendar: calendar)
        await notifications.remove(appointmentID: appointmentID)
        await widgetSnapshots.refresh()
    }

    // MARK: - Queries

    public func appointment(id: StableUUID) async throws -> Appointment {
        try await appointmentRepository.appointment(id: id)
    }

    /// Appointments whose training was started and not yet settled (any
    /// Student) -- input to `SessionCreditSettlement`'s launch repair.
    public func inProgressLinkedAppointments() async throws -> [Appointment] {
        try await appointmentRepository.activeAppointments(excluding: nil)
            .filter { $0.status == .inProgress && $0.linkedSessionID != nil }
    }

    public func appointments(studentID: StableUUID) async throws -> [Appointment] {
        try await appointmentRepository.appointments(studentID: studentID)
    }

    public func series(id: StableUUID) async throws -> RecurrenceSeries {
        try await appointmentRepository.series(id: id)
    }

    /// The instances "本次及以后" from `boundaryDate` would re-materialize:
    /// same selection rule as `applyThisAndFuture` (scheduled, not a
    /// detached exception, on or after the boundary). For the scope-sheet
    /// count shown before the coach commits.
    public func thisAndFutureAffectedCount(seriesID: StableUUID, boundaryDate: LocalDate) async throws -> Int {
        try await appointmentRepository.appointments(seriesID: seriesID).filter { appointment in
            appointment.date >= boundaryDate && appointment.status == .scheduled && !appointment.isDetachedException
        }.count
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
