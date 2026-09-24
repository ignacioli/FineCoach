import SwiftUI

/// The 5 named coach-facing status conditions that MUST be conveyed by both
/// text and an icon, never color alone (§2.4 "状态必须同时用文字和图标表达，不能只靠颜色",
/// spec T047a). Each case carries its own display text and SF Symbol so
/// nothing can reference a status without both.
public enum FCStatus: CaseIterable, Sendable {
    case overdue
    case conflict
    case coursePackageInvalid
    case notComparable
    case permissionDenied

    public var text: String {
        switch self {
        case .overdue: return String(localized: "status.overdue")
        case .conflict: return String(localized: "status.conflict")
        case .coursePackageInvalid: return String(localized: "status.coursePackageInvalid")
        case .notComparable: return String(localized: "status.notComparable")
        case .permissionDenied: return String(localized: "status.permissionDenied")
        }
    }

    /// SF Symbol name for the badge glyph. §7.2 only documents two glyph
    /// shapes for this badge pattern — `!` (caution) and `i` (informational)
    /// — so every status maps to one of those two, never an invented symbol.
    public var symbolName: String {
        switch self {
        case .overdue, .conflict, .coursePackageInvalid:
            return "exclamationmark"
        case .notComparable, .permissionDenied:
            return "info"
        }
    }

    /// Badge background. §7.2 documents exactly two allowed backgrounds for
    /// this 22×22 icon-circle pattern — `status.warning` or `action.primary`
    /// — never `status.destructive` (there is no destructive variant of this
    /// component in the design system). `overdue`/`conflict` are explicitly
    /// grouped under `amber.700` in §2.1's own token comment ("逾期、时间冲突图标
    /// 底"); `coursePackageInvalid` is treated the same way, as a
    /// data-needs-attention condition. `notComparable`/`permissionDenied` are
    /// purely informational (a UI limitation under the current state, not
    /// something wrong to fix), so they take the neutral `action.primary`
    /// badge instead — this pairing (which named status gets which of the
    /// two allowed treatments) is an implementation decision the design
    /// system does not spell out per status; flagged in the T059 report.
    public var badgeColor: Color {
        switch self {
        case .overdue, .conflict, .coursePackageInvalid:
            return FCSemanticColors.statusWarning
        case .notComparable, .permissionDenied:
            return FCSemanticColors.actionPrimary
        }
    }
}

/// A status label (§7.2 icon-circle badge + text, §2.4). Initializers make it
/// impossible to construct without both non-optional text and an icon: the
/// `FCStatus`-backed initializer supplies both from the enum, and the
/// free-form initializer requires both `text` and `symbolName` directly —
/// there is no initializer that accepts only one.
public struct FCStatusLabel: View {
    private let text: String
    private let symbolName: String
    private let badgeColor: Color

    /// The primary initializer — one of the 5 documented `FCStatus` cases.
    public init(_ status: FCStatus) {
        self.text = status.text
        self.symbolName = status.symbolName
        self.badgeColor = status.badgeColor
    }

    /// For status text not covered by `FCStatus`. Both `text` and
    /// `symbolName` are required (non-optional) — it is impossible to build
    /// a status label with only one of the two.
    public init(text: String, symbolName: String, badgeColor: Color = FCSemanticColors.statusWarning) {
        self.text = text
        self.symbolName = symbolName
        self.badgeColor = badgeColor
    }

    public var body: some View {
        Label {
            Text(text)
                .fcFont(.caption)
        } icon: {
            ZStack {
                Circle().fill(badgeColor)
                Image(systemName: symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FCSemanticColors.actionOn)
            }
            .frame(width: 22, height: 22)
        }
        .foregroundStyle(FCSemanticColors.textSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
    }
}
