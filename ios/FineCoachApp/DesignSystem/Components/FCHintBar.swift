import SwiftUI

/// The hint bar (§8 "提示条": 358×44, `radius.md`, `surface.selected` bg,
/// `caption` `action.primary` text). Fills available width — see
/// `FCButton`'s width note.
public struct FCHintBar: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .fcFont(.caption)
            .foregroundStyle(FCSemanticColors.actionPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, FCPrimitives.space4)
            .background(FCSemanticColors.surfaceSelected)
            .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusMd))
    }
}

/// The in-training bar (§8.1 "训练中提示条", `21-student-list-v2`): hint-bar
/// styling (`surface.selected` bg, `radius.md`, `caption` `action.primary`
/// text) with a trailing "继续训练" in `callout` 600 `action.primary`. The
/// whole bar is one tap target that resumes the session.
public struct FCActiveSessionBar: View {
    private let text: String
    private let actionTitle: String
    private let action: () -> Void

    public init(text: String, actionTitle: String, action: @escaping () -> Void) {
        self.text = text
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: FCPrimitives.space2) {
                Text(text)
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.actionPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(actionTitle)
                    .fcFont(.callout, weight: .semibold)
                    .foregroundStyle(FCSemanticColors.actionPrimary)
            }
            .padding(.horizontal, FCPrimitives.space4)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(FCSemanticColors.surfaceSelected)
            .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusMd))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
