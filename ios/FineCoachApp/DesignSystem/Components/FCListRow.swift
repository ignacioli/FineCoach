import SwiftUI

/// The standard list row (§8 "列表行": left margin 16; main text `headline` or
/// `body`; meta text `caption` `text.secondary`; trailing `›`; rows separated
/// by a 1pt divider).
public struct FCListRow: View {
    public enum TitleStyle {
        case headline
        case body
    }

    private let title: String
    private let titleStyle: TitleStyle
    private let subtitle: String?
    private let showsDisclosure: Bool
    private let action: (() -> Void)?

    public init(
        title: String,
        titleStyle: TitleStyle = .body,
        subtitle: String? = nil,
        showsDisclosure: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.titleStyle = titleStyle
        self.subtitle = subtitle
        self.showsDisclosure = showsDisclosure
        self.action = action
    }

    public var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content
                    .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: FCPrimitives.space2) {
            VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                Text(title)
                    .fcFont(titleStyle == .headline ? .headline : .body)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
            }
            Spacer(minLength: FCPrimitives.space2)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, FCPrimitives.space4)
        .frame(minHeight: 44)
    }
}

/// The 1pt divider between list rows (§6: "分割线：1pt，`surface.divider`").
/// A separate view rather than baked into `FCListRow` so callers composing
/// rows in a plain `VStack` (not a native `List`, which draws its own
/// separators) control exactly where dividers appear.
public struct FCListRowDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(FCSemanticColors.surfaceDivider)
            .frame(height: 1)
    }
}

/// The section label (§8 "区段标签": `sectionLabel`, `text.secondary`).
public struct FCSectionLabel: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .fcFont(.sectionLabel)
            .foregroundStyle(FCSemanticColors.textSecondary)
    }
}
