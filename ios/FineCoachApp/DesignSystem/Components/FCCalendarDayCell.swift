import SwiftUI

/// A month-calendar day cell (`25-calendar-v2`): the day number, a filled
/// `action.primary` circle when selected, and the §8.1 "月历有课圆点" — a 4pt
/// `action.primary` dot under the number on days with appointments, not
/// repeated inside the selected day's circle. The dot slot is always
/// reserved so rows keep one height whether or not a day has a dot.
public struct FCCalendarDayCell: View {
    private let day: Int
    private let isSelected: Bool
    private let hasAppointments: Bool
    private let action: () -> Void

    private static let selectedDiameter: CGFloat = 28
    private static let dotDiameter: CGFloat = 4

    public init(day: Int, isSelected: Bool, hasAppointments: Bool, action: @escaping () -> Void) {
        self.day = day
        self.isSelected = isSelected
        self.hasAppointments = hasAppointments
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: FCPrimitives.space1 / 2) {
                Text("\(day)")
                    .fcFont(.compact, weight: isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? FCSemanticColors.actionOn : FCSemanticColors.textPrimary)
                    .frame(width: Self.selectedDiameter, height: Self.selectedDiameter)
                    .background(
                        Circle().fill(isSelected ? FCSemanticColors.actionPrimary : Color.clear)
                    )
                Circle()
                    .fill(hasAppointments && !isSelected ? FCSemanticColors.actionPrimary : Color.clear)
                    .frame(width: Self.dotDiameter, height: Self.dotDiameter)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(hasAppointments ? Text("designSystem.calendar.hasAppointments") : Text(verbatim: ""))
    }
}
