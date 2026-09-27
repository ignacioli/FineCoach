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
                FCSymbol(.forward)
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

/// The list group entry row (§8.1 "列表分组入口行": "已归档 · N ›" /
/// "已处理 · N ›", `sectionLabel` `text.secondary` + trailing `›`).
public struct FCGroupEntryRow: View {
    private let title: String
    private let count: Int
    private let action: () -> Void

    public init(title: String, count: Int, action: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: FCPrimitives.space2) {
                Text(verbatim: "\(title) · \(count)")
                    .fcFont(.sectionLabel)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                Spacer(minLength: FCPrimitives.space2)
                FCSymbol(.forward)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The label–value row (§8.1 "标签-值两栏行": label `callout` 400
/// `text.secondary` at x=16, value at x=112 (a 96pt label column), row
/// height 48–52, rows separated by `FCListRowDivider`). Used by the 02
/// redraw, student-detail profile section, and edit-profile page.
///
/// `value` is any view: plain `body` text, a control such as a `Toggle`
/// with `FCToggleStyle`, or text plus a trailing element. Pass `action` to
/// make the whole row tappable with a trailing `›`; pass
/// `showsDisclosure: true` without an action when the row is the label of
/// an enclosing `Menu`. Rows with a view-builder value keep their children
/// separately accessible (controls stay operable); plain-text rows read as
/// one element.
public struct FCLabelValueRow<Value: View>: View {
    private let label: String
    private let value: Value
    private let action: (() -> Void)?
    private let showsDisclosure: Bool
    private let combinesAccessibility: Bool

    private static var labelColumnWidth: CGFloat { 112 - FCPrimitives.space4 }

    public init(
        label: String,
        showsDisclosure: Bool? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder value: () -> Value
    ) {
        self.init(label: label, showsDisclosure: showsDisclosure, action: action, combinesAccessibility: false, value: value())
    }

    fileprivate init(
        label: String,
        showsDisclosure: Bool?,
        action: (() -> Void)?,
        combinesAccessibility: Bool,
        value: Value
    ) {
        self.label = label
        self.action = action
        self.showsDisclosure = showsDisclosure ?? (action != nil)
        self.combinesAccessibility = combinesAccessibility
        self.value = value
    }

    public var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else if combinesAccessibility {
            content
                .accessibilityElement(children: .combine)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            Text(label)
                .fcFont(.callout, weight: .regular)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .frame(width: Self.labelColumnWidth, alignment: .leading)
            value
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsDisclosure {
                FCSymbol(.forward)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
    }
}

public extension FCLabelValueRow where Value == FCLabelValueText {
    /// A row whose value is plain `body` `text.primary` text.
    init(label: String, value: String, showsDisclosure: Bool? = nil, action: (() -> Void)? = nil) {
        self.init(
            label: label,
            showsDisclosure: showsDisclosure,
            action: action,
            combinesAccessibility: true,
            value: FCLabelValueText(value)
        )
    }
}

/// The plain-text value of an `FCLabelValueRow` (`body`, `text.primary`).
public struct FCLabelValueText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .fcFont(.body)
            .foregroundStyle(FCSemanticColors.textPrimary)
    }
}
