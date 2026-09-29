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

/// The title-row icon button (§8.1 "标题行图标按钮": sits on the large
/// title's line, right side; a 22×20 line icon in `text.secondary`, stroke
/// 1.5; no fill or shadow; hit area ≥ 44×44 — the calendar entry on 今日 and
/// the resource-hub entry on 学员). `systemImage` is an SF Symbol name;
/// `accessibilityLabel` is required because the button has no visible text.
public struct FCTitleIconButton: View {
    private let systemImage: String
    private let accessibilityLabel: String
    private let action: () -> Void

    public init(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .resizable()
                .scaledToFit()
                .fontWeight(.light)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .frame(width: 22, height: 20)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

/// 标题行「＋」主入口 (D15a): a bare `action.primary` plus, heavier than the
/// grey line icons beside it, tap target ≥ 44×44. Only the 今日 title row
/// uses it, and it always means 新建预约.
public struct FCTitleAddButton: View {
    private let accessibilityLabel: String
    private let action: () -> Void

    public init(accessibilityLabel: String, action: @escaping () -> Void) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .foregroundStyle(FCSemanticColors.actionPrimary)
                .frame(width: 22, height: 22)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}
