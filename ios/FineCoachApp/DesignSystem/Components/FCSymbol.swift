import SwiftUI

/// The artwork's text-glyph icons (§7.2), with the documented size, weight,
/// and color per use. `‹ › ✓` render as the bundled Noto Sans SC glyph exactly
/// as the artwork draws them (owner decision 2026-10-10: the SF Symbol
/// checkmark/chevrons were rejected); `− + ▾` stay SF Symbols (the bundled
/// font has no `▾` glyph). Feature views use this instead of typing
/// `‹ › − + ✓ ▾` or sizing symbols themselves. Decorative by default; a
/// tappable use must sit in a ≥ 44×44 hit area and carry its own
/// accessibility label.
public struct FCSymbol: View {
    public enum Kind {
        /// `‹` 22/400 `text.secondary` — the inline page back (`FCPageHeader`).
        case pageBack
        /// `‹` 20/400 `text.secondary` — previous month.
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

        /// The Noto Sans SC character for glyph-rendered kinds; `nil` for SF Symbols.
        fileprivate var glyph: String? {
            switch self {
            case .pageBack, .back: return "\u{2039}"
            case .forward: return "\u{203A}"
            case .check, .checkOnFill: return "\u{2713}"
            case .minus, .plus, .collapse: return nil
            }
        }

        fileprivate var systemName: String {
            switch self {
            case .minus: return "minus"
            case .plus: return "plus"
            case .collapse: return "chevron.down"
            case .pageBack, .back, .forward, .check, .checkOnFill: return ""
            }
        }

        fileprivate var size: CGFloat {
            switch self {
            case .pageBack: return 22
            case .back, .forward, .minus, .plus: return 20
            case .check, .collapse: return 15
            case .checkOnFill: return 13
            }
        }

        fileprivate var weight: Font.Weight {
            switch self {
            case .pageBack, .back, .forward: return .regular
            case .minus, .plus, .check, .checkOnFill, .collapse: return .semibold
            }
        }

        fileprivate var defaultColor: Color {
            switch self {
            case .pageBack, .back, .forward: return FCSemanticColors.textSecondary
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public var body: some View {
        Group {
            if let glyph = kind.glyph {
                Text(verbatim: glyph)
                    .font(Font(Self.glyphFont(kind, dynamicTypeSize)))
                    .fixedSize()
            } else {
                Image(systemName: kind.systemName)
                    .font(.system(size: kind.size, weight: kind.weight))
            }
        }
        .foregroundStyle(color ?? kind.defaultColor)
        .accessibilityHidden(true)
    }

    /// The bundled Noto Sans SC font for a glyph kind, scaled with Dynamic
    /// Type like body text (`FCFont.uiFont` + `UIFontMetrics`).
    static func glyphFont(_ kind: Kind, _ size: DynamicTypeSize) -> UIFont {
        let weight: CGFloat = kind.weight == .semibold ? 600 : 400
        let base = FCFont.uiFont(size: kind.size, weight: weight)
        let traits = UITraitCollection(preferredContentSizeCategory: size.fcContentSizeCategory)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base, compatibleWith: traits)
    }

    /// Whether `kind` renders as a Noto Sans SC glyph (contract-test hook).
    static func rendersAsNotoGlyph(_ kind: Kind) -> Bool { kind.glyph != nil }
}

extension DynamicTypeSize {
    var fcContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}
