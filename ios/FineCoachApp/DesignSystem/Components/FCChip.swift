import SwiftUI

/// The filter chip (§8 "筛选胶囊（07）": height 30 capsule; unselected
/// `surface.selected` bg + `chipLabel` `text.primary`; selected
/// `action.primary` bg + white text).
public struct FCFilterChip: View {
    private let title: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .fcFont(.chipLabel)
                .foregroundStyle(isSelected ? FCSemanticColors.actionOn : FCSemanticColors.textPrimary)
                .padding(.horizontal, FCPrimitives.space3)
                .frame(minHeight: 30)
                .background(
                    Capsule().fill(isSelected ? FCSemanticColors.actionPrimary : FCSemanticColors.surfaceSelected)
                )
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The weekday multi-select chip (§8 "星期多选（02）": 64×28 capsule, same
/// color scheme as the filter chip).
public struct FCWeekdayChip: View {
    private let title: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .fcFont(.chipLabel)
                .foregroundStyle(isSelected ? FCSemanticColors.actionOn : FCSemanticColors.textPrimary)
                .frame(width: 64, height: 28)
                .background(
                    Capsule().fill(isSelected ? FCSemanticColors.actionPrimary : FCSemanticColors.surfaceSelected)
                )
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
