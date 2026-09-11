import Foundation

/// Which bucket a Today-surface row belongs to, in display order (M1B-FR-001).
/// A pure classification -- Feature UI renders this order verbatim and MUST NOT
/// re-sort (spec: "UI 不自行排序").
public enum TodayOrderingSection: Sendable, Equatable {
    case inProgress
    case overdue
    case nextUp
    case remainingToday
    /// Completed/cancelled/absent today -- folded/collapsed in the UI.
    case resolved
}

public struct TodayOrderedAppointment: Sendable, Equatable {
    public let appointment: Appointment
    public let section: TodayOrderingSection

    public init(appointment: Appointment, section: TodayOrderingSection) {
        self.appointment = appointment
        self.section = section
    }
}

/// Pure Today-surface ordering (M1B-FR-001, D-001): in-progress training, then
/// overdue-pending, then the single next class today (earliest remaining
/// scheduled slot only -- D-001), then the rest of today, with
/// completed/cancelled/absent folded at the end. Overdue is computed via the
/// injected clock/calendar (T007a), never wall-clock, so this stays
/// deterministic under test.
public enum TodayOrderingPolicy {
    public static func order(
        appointments: [Appointment],
        today: LocalDate,
        now: Date,
        calendar: Calendar
    ) -> [TodayOrderedAppointment] {
        let todays = appointments.filter { $0.date == today }

        var inProgress: [Appointment] = []
        var overdue: [Appointment] = []
        var pending: [Appointment] = []
        var resolved: [Appointment] = []

        for appointment in todays {
            switch appointment.status {
            case .inProgress:
                inProgress.append(appointment)
            case .completed, .cancelled, .absent:
                resolved.append(appointment)
            case .scheduled:
                if appointment.isOverdue(now: now, calendar: calendar) {
                    overdue.append(appointment)
                } else {
                    pending.append(appointment)
                }
            }
        }

        inProgress.sort { $0.startTime < $1.startTime }
        overdue.sort { $0.startTime < $1.startTime }
        pending.sort { $0.startTime < $1.startTime }
        resolved.sort { $0.startTime < $1.startTime }

        var result: [TodayOrderedAppointment] = []
        result += inProgress.map { TodayOrderedAppointment(appointment: $0, section: .inProgress) }
        result += overdue.map { TodayOrderedAppointment(appointment: $0, section: .overdue) }
        if let next = pending.first {
            result.append(TodayOrderedAppointment(appointment: next, section: .nextUp))
            result += pending.dropFirst().map { TodayOrderedAppointment(appointment: $0, section: .remainingToday) }
        }
        result += resolved.map { TodayOrderedAppointment(appointment: $0, section: .resolved) }
        return result
    }
}
