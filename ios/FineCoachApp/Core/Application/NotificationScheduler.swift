import Foundation

/// Redacted notification copy (D-M1B-005, AC-015, SC-006): generic wording + time
/// only. MUST NOT reference the student's name, sex, or course-package balance/
/// validity -- a locked phone showing this text leaks nothing about who or what.
public enum AppointmentNotificationContentBuilder {
    public static func title() -> String {
        "训练提醒"
    }

    public static func body(startInstant: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: startInstant)) 有一节训练安排。"
    }
}

/// Coordinates Appointment state with the local notification system. Per plan
/// D-M1B-005 the Domain layer only ever describes intent (an Appointment's own
/// reminderEnabled/reminderLeadMinutes fields); this is the one place that turns
/// "should a reminder exist" into an actual scheduled/removed UNNotificationRequest,
/// so every appointment mutation that changes timing, cancels, or removes reminders
/// has exactly one place responsible for keeping the system notification in sync.
public struct NotificationScheduler: Sendable {
    private let notificationCenter: any LocalNotificationScheduling
    private let calendarProvider: any LocalCalendarProvider

    public init(
        notificationCenter: any LocalNotificationScheduling,
        calendarProvider: any LocalCalendarProvider
    ) {
        self.notificationCenter = notificationCenter
        self.calendarProvider = calendarProvider
    }

    /// Schedules or removes this appointment's reminder to match its current
    /// state. Requesting permission happens here, lazily, only when a reminder is
    /// actually about to be needed -- never blocks the caller's save on denial
    /// (D-004): `schedule` failing is swallowed, the appointment itself was
    /// already persisted by the caller before this runs.
    public func sync(appointment: Appointment) async {
        let identifier = AppointmentNotificationIdentifier.make(appointmentID: appointment.id)
        guard
            appointment.status == .scheduled,
            appointment.reminderEnabled,
            let leadMinutes = appointment.reminderLeadMinutes
        else {
            await notificationCenter.removePending(identifiers: [identifier])
            return
        }

        let calendar = calendarProvider.currentCalendar()
        let startInstant = appointment.startInstant(calendar: calendar)
        let fireDate = startInstant.addingTimeInterval(-Double(leadMinutes.rawValue * 60))

        await notificationCenter.requestAuthorizationIfNeeded()
        let descriptor = NotificationRequestDescriptor(
            identifier: identifier,
            title: AppointmentNotificationContentBuilder.title(),
            body: AppointmentNotificationContentBuilder.body(startInstant: startInstant, calendar: calendar),
            fireDate: fireDate
        )
        try? await notificationCenter.schedule(descriptor)
    }

    public func remove(appointmentID: StableUUID) async {
        await notificationCenter.removePending(
            identifiers: [AppointmentNotificationIdentifier.make(appointmentID: appointmentID)]
        )
    }

    public func remove(appointmentIDs: [StableUUID]) async {
        guard !appointmentIDs.isEmpty else {
            return
        }
        await notificationCenter.removePending(
            identifiers: appointmentIDs.map { AppointmentNotificationIdentifier.make(appointmentID: $0) }
        )
    }
}
