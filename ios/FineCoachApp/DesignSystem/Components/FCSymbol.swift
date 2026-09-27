import SwiftUI

/// The artwork's text-glyph icons as SF Symbols (§7.2), with the documented
/// size, weight, and color per use. Feature views use this instead of
/// typing `‹ › − + ✓ ▾` or sizing symbols themselves. Decorative by
/// default; a tappable use must sit in a ≥ 44×44 hit area and carry its own
/// accessibility label.
public struct FCSymbol: View {
    public enum Kind {
        /// `‹` 20/400 `text.secondary` — back, previous month.
        case back
        /// `›` 20/400 `text.secondary` — list-row disclosure, next month.
        case forward
        /// `−` 20/600 — credit debit record.
        case minus
        /// `+` 20/600 — credit return record.
        case plus
        /// `✓` 15/600 `action.primary` — completed / included (inline).
        case check
        /// `✓` 13/600 white — inside a filled circle.
        case checkOnFill
        /// `▾` 15/600 `action.primary` — section collapse.
        case collapse

        fileprivate var systemName: String {
            switch self {
            case .back: return "chevron.left"
            case .forward: return "chevron.right"
            case .minus: return "minus"
            case .plus: return "plus"
            case .check, .checkOnFill: return "checkmark"
            case .collapse: return "chevron.down"
            }
        }

        fileprivate var size: CGFloat {
            switch self {
            case .back, .forward, .minus, .plus: return 20
            case .check, .collapse: return 15
            case .checkOnFill: return 13
            }
        }

        fileprivate var weight: Font.Weight {
            switch self {
            case .back, .forward: return .regular
            case .minus, .plus, .check, .checkOnFill, .collapse: return .semibold
            }
        }

        fileprivate var defaultColor: Color {
            switch self {
            case .back, .forward: return FCSemanticColors.textSecondary
            case .minus, .plus: return FCSemanticColors.textPrimary
            case .check, .collapse: return FCSemanticColors.actionPrimary
            case .checkOnFill: return FCSemanticColors.actionOn
            }
        }
    }

    private let kind: Kind
    private let color: Color?

    /// - Parameter color: overrides the §7.2 default only where the artwork
    ///   gives the glyph a state color (e.g. a debit amount's sign).
    public init(_ kind: Kind, color: Color? = nil) {
        self.kind = kind
        self.color = color
    }

    public var body: some View {
        Image(systemName: kind.systemName)
            .font(.system(size: kind.size, weight: kind.weight))
            .foregroundStyle(color ?? kind.defaultColor)
            .accessibilityHidden(true)
    }
}
