import SwiftUI

/// The entry row of a hub-style page (`DS-HUB-ROW`, components.md §4.7;
/// 19 资料库, 42/43 设置): 24pt line icon (`action.primary`, decorative) →
/// `headline` title with an optional subtitle (`caption` `text.secondary`, or
/// an `FCStatusLabel`) → flexible space → an optional trailing note (`caption`
/// `text.secondary`) or trailing action text (`callout` 600 `action.primary`)
/// → `›` when tappable. Minimum height 64, `space.4` between icon and text.
/// Rows are separated by the caller with `FCListRowDivider`.
///
/// `mode` carries the interaction, so an unavailable row cannot carry an
/// action or a `›` by construction. The whole row is one accessibility
/// element reading title, subtitle and trailing text. Attach an
/// `accessibilityIdentifier` to the row from the caller.
public struct FCHubRow: View {
    public enum Icon {
        /// An SF Symbol name, drawn 24×24.
        case symbol(String)
        /// One of the 21 equipment icons, drawn 24×24.
        case equipment(FCEquipmentIcon)
    }

    public enum Subtitle {
        case text(String)
        case status(FCStatus)
    }

    public enum Trailing {
        case none
        /// `caption` `text.secondary`, e.g. 「24 次」.
        case note(String)
        /// `callout` 600 `action.primary`, e.g. 43「前往设置」. Meaningful on a
        /// tappable row; ignored by the other modes.
        case actionText(String)
    }

    public enum Mode {
        /// Tappable: whole row is the button, `›` shown.
        case action(() -> Void)
        /// Not tappable, no `›` (e.g. 42「关于」).
        case informational
        /// Not available: icon and title `text.disabled`, `reason` as the
        /// trailing note, no `›`, no action.
        case unavailable(reason: String)
    }

    private let icon: Icon
    private let title: String
    private let subtitle: Subtitle?
    private let trailing: Trailing
    private let mode: Mode

    public init(
        icon: Icon,
        title: String,
        subtitle: Subtitle? = nil,
        trailing: Trailing = .none,
        mode: Mode
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.mode = mode
    }

    /// Whether the row has a tap action. `false` for `informational` and
    /// `unavailable`.
    public var isTappable: Bool {
        if case .action = mode { return true }
        return false
    }

    public var body: some View {
        switch mode {
        case .action(let action):
            Button(action: action) { content }
                .buttonStyle(.plain)
        case .informational, .unavailable:
            content
        }
    }

    private var isUnavailable: Bool {
        if case .unavailable = mode { return true }
        return false
    }

    private var content: some View {
        HStack(spacing: FCPrimitives.space4) {
            iconView
            VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                Text(title)
                    .fcFont(.headline)
                    .foregroundStyle(isUnavailable ? FCSemanticColors.textDisabled : FCSemanticColors.textPrimary)
                if let subtitle {
                    switch subtitle {
                    case .text(let text):
                        Text(text)
                            .fcFont(.caption)
                            .foregroundStyle(FCSemanticColors.textSecondary)
                    case .status(let status):
                        FCStatusLabel(status)
                    }
                }
            }
            Spacer(minLength: FCPrimitives.space2)
            trailingView
            if isTappable {
                FCSymbol(.forward)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var iconView: some View {
        let color = isUnavailable ? FCSemanticColors.textDisabled : FCSemanticColors.actionPrimary
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(color)
                .accessibilityHidden(true)
        case .equipment(let equipment):
            Image(equipment.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(color)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        if case .unavailable(let reason) = mode {
            Text(reason)
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
        } else {
            switch trailing {
            case .none:
                EmptyView()
            case .note(let note):
                Text(note)
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            case .actionText(let text):
                Text(text)
                    .fcFont(.callout, weight: .semibold)
                    .foregroundStyle(FCSemanticColors.actionPrimary)
            }
        }
    }
}

#if DEBUG
    #Preview("States") {
        VStack(spacing: 0) {
            FCListRowDivider()
            FCHubRow(
                icon: .equipment(.barbell),
                title: "动作库",
                subtitle: .text("内置 120 · 自建 3"),
                mode: .action {}
            )
            FCListRowDivider()
            FCHubRow(
                icon: .symbol("list.bullet.rectangle"),
                title: "训练模板",
                trailing: .note("24 次"),
                mode: .action {}
            )
            FCListRowDivider()
            FCHubRow(
                icon: .symbol("bell"),
                title: "通知",
                subtitle: .status(.permissionDenied),
                trailing: .actionText("前往设置"),
                mode: .action {}
            )
            FCListRowDivider()
            FCHubRow(
                icon: .symbol("info.circle"),
                title: "关于",
                subtitle: .text("版本 1.0 (1)"),
                mode: .informational
            )
            FCListRowDivider()
            FCHubRow(
                icon: .symbol("chart.xyaxis.line"),
                title: "训练趋势",
                mode: .unavailable(reason: "档案未包含")
            )
            FCListRowDivider()
        }
        .padding(.horizontal, FCPrimitives.space4)
    }
#endif
