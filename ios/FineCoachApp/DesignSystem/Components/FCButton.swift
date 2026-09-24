import SwiftUI

/// The primary (filled) button (`design/design-system/README.md` §8: "主按钮（页面底部）",
/// 358×52, `radius.md`, `action.primary` bg, pressed `action.pressed`, `headline` white text).
/// Fills available width — the 358pt figure is the artwork's page content width
/// (page margin `space.4` either side of a 390pt screen), not a fixed constant.
public struct FCButton: View {
    public enum State: Equatable, Sendable {
        case `default`
        case disabled
    }

    private let title: String
    private let state: State
    private let action: () -> Void

    public init(
        title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.state = isEnabled ? .default : .disabled
        self.action = action
    }

    public init(
        title: String,
        state: State,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.state = state
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .fcFont(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(FCButtonStyle(state: state))
        .disabled(state == .disabled)
        .accessibilityLabel(Text(title))
    }
}

private struct FCButtonStyle: ButtonStyle {
    let state: FCButton.State

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusMd))
    }

    private var foregroundColor: Color {
        switch state {
        case .default:
            return FCSemanticColors.actionOn
        case .disabled:
            // Disabled token choice: `text.secondary` (#5C5A52), not
            // `text.disabled` (#A8A39A) — the latter is WCAG-exempt (§11,
            // 2.51:1 on white) and would be close to unreadable set against
            // `surface.divider`; `text.secondary` keeps the label legible
            // while `surface.divider` (vs. `action.primary`) still reads as
            // visually inactive.
            return FCSemanticColors.textSecondary
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch state {
        case .default:
            // No opacity trick for the pressed state — swap to the
            // dedicated `action.pressed` token instead (§8).
            return isPressed ? FCSemanticColors.actionPressed : FCSemanticColors.actionPrimary
        case .disabled:
            return FCSemanticColors.surfaceDivider
        }
    }
}

/// The secondary (outline) button (§8 Foundations swatch: white bg, 1.5pt
/// `action.primary` stroke, `radius.md`, `headline` `action.primary` text).
public struct FCSecondaryButton: View {
    private let title: String
    private let isEnabled: Bool
    private let action: () -> Void

    public init(
        title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .fcFont(.headline)
                .foregroundStyle(isEnabled ? FCSemanticColors.actionPrimary : FCSemanticColors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: FCPrimitives.radiusMd)
                        .strokeBorder(
                            isEnabled ? FCSemanticColors.actionPrimary : FCSemanticColors.textSecondary,
                            lineWidth: 1.5
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(title))
    }
}

/// The link-style (no background) button (§8: "链接式按钮", `callout` 600
/// `action.primary`, e.g. "＋ 添加动作" / "重试").
public struct FCLinkButton: View {
    private let title: String
    private let isEnabled: Bool
    private let action: () -> Void

    public init(
        title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .fcFont(.callout, weight: .semibold)
                .foregroundStyle(isEnabled ? FCSemanticColors.actionPrimary : FCSemanticColors.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(title))
    }
}
