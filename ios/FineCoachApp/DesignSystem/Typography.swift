import CoreText
import SwiftUI
import UIKit

/// Loads the approved Noto Sans SC variable font (T055, `design/design-system/README.md`
/// §3.1) and exposes it as scalable `UIFont`s driven by the font's `wght` axis.
///
/// SwiftUI's `.fontWeight()` / `Font.weight()` modifiers are **not** guaranteed to hit a
/// custom variable font's registered axis — verified directly against the bundled font
/// (`NotoSansSC-VF.otf`, single `wght` axis, range 100–900, default 100): building a
/// `Font` from a `UIFontDescriptor`/`UIFont` and asking SwiftUI to reweight it does not
/// reliably move the axis. Instead every weight is produced by driving the `wght`
/// variation axis explicitly through Core Text (`kCTFontVariationAttribute`), confirmed
/// against the built font to resolve to the correct named instances (100→Thin,
/// 400→Regular, 500→Medium, 700→Bold; 600 has no named instance in this font but the
/// axis value is still honored — verified via `CTFontCopyVariation` and by comparing
/// glyph bounding boxes at 400 vs. 700).
public enum FCFont {
    /// The font family name as recorded in the font's own `name` table (nameID 1),
    /// read directly from the compiled font rather than assumed.
    public static let familyName = "Noto Sans SC"

    /// The OpenType `wght` axis tag (`'wght'` as a big-endian four-char code,
    /// `0x77676874`), the sole variation axis on this font.
    private static let weightAxisIdentifier = NSNumber(value: 0x7767_6874 as UInt32)

    /// Whether the bundled font actually registered with the system font database
    /// (via `UIAppFonts` in `FineCoach-Info.plist`). Exposed so tests (T061) can
    /// assert the app is really using Noto Sans SC instead of a silent system-font
    /// fallback going undetected.
    public static var isFamilyRegistered: Bool {
        UIFont.familyNames.contains(familyName)
    }

    /// Builds a `UIFont` for the family at `size`, with the `wght` variation axis
    /// driven to `weight` (expected range 100–900; design tokens only ever use
    /// 400/500/600/700). Falls back to the closest system weight if the family
    /// failed to register, so a missing font degrades to a legible font rather
    /// than crashing — but `isFamilyRegistered` lets tests catch that condition.
    static func uiFont(size: CGFloat, weight: CGFloat) -> UIFont {
        guard isFamilyRegistered else {
            return .systemFont(ofSize: size, weight: systemWeight(for: weight))
        }
        let baseDescriptor = CTFontDescriptorCreateWithAttributes(
            [kCTFontFamilyNameAttribute: familyName as CFString] as CFDictionary
        )
        let variationAttributes: [String: Any] = [
            kCTFontVariationAttribute as String: [weightAxisIdentifier: Double(weight)]
        ]
        let variedDescriptor = CTFontDescriptorCreateCopyWithAttributes(
            baseDescriptor, variationAttributes as CFDictionary
        )
        let ctFont = CTFontCreateWithFontDescriptor(variedDescriptor, size, nil)
        return ctFont as UIFont
    }

    private static func systemWeight(for weight: CGFloat) -> UIFont.Weight {
        switch weight {
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        default: return .bold
        }
    }
}

/// A documented alternate weight for the small set of ladder/named styles that the
/// design system explicitly permits a variant on (§3.2 `callout`, §3.3 `compact`).
/// This intentionally does not add new `FCTextStyle` cases — see T056 scope note.
public enum FCFontWeightVariant {
    /// 400 — the default weight for the affected styles.
    case regular
    /// 600 — `callout`'s time/link/dialog-button variant; `compact`'s
    /// selected/today variant.
    case semibold

    fileprivate var weightValue: CGFloat {
        switch self {
        case .regular: return 400
        case .semibold: return 600
        }
    }
}

/// The 7-step type ladder (§3.2) plus the 7 named exceptions (§3.3) from
/// `design/design-system/README.md`. This case list is closed by design — do not add
/// cases for one-off sizes; fold them into the nearest documented style instead (§3.3
/// "零散用法的归并").
public enum FCTextStyle: CaseIterable {
    // Ladder (§3.2)
    case display
    case titleLarge
    case title
    case headline
    case body
    case callout
    case caption

    // Named exceptions (§3.3)
    case numeralHero
    case numeralLarge
    case titleEmphasis
    case exerciseTitle
    case sectionLabel
    case compact
    case chipLabel

    fileprivate struct Spec {
        let size: CGFloat
        let weight: CGFloat
        let lineHeight: CGFloat
        let scalingBase: UIFont.TextStyle
        let allowedVariants: Set<FCFontWeightVariant>
    }

    fileprivate var spec: Spec {
        switch self {
        case .display:
            return Spec(size: 34, weight: 700, lineHeight: 1.2, scalingBase: .largeTitle, allowedVariants: [])
        case .titleLarge:
            return Spec(size: 28, weight: 700, lineHeight: 1.3, scalingBase: .title1, allowedVariants: [])
        case .title:
            return Spec(size: 22, weight: 600, lineHeight: 1.3, scalingBase: .title2, allowedVariants: [])
        case .headline:
            return Spec(size: 17, weight: 600, lineHeight: 1.4, scalingBase: .headline, allowedVariants: [])
        case .body:
            return Spec(size: 17, weight: 400, lineHeight: 1.4, scalingBase: .body, allowedVariants: [])
        case .callout:
            return Spec(
                size: 15, weight: 500, lineHeight: 1.4, scalingBase: .callout,
                allowedVariants: [.regular, .semibold]
            )
        case .caption:
            return Spec(size: 13, weight: 400, lineHeight: 1.3, scalingBase: .footnote, allowedVariants: [])
        case .numeralHero:
            return Spec(size: 44, weight: 700, lineHeight: 1.1, scalingBase: .largeTitle, allowedVariants: [])
        case .numeralLarge:
            return Spec(size: 24, weight: 600, lineHeight: 1.2, scalingBase: .title2, allowedVariants: [])
        case .titleEmphasis:
            return Spec(size: 22, weight: 700, lineHeight: 1.3, scalingBase: .title2, allowedVariants: [])
        case .exerciseTitle:
            return Spec(size: 20, weight: 700, lineHeight: 1.3, scalingBase: .title3, allowedVariants: [])
        case .sectionLabel:
            return Spec(size: 13, weight: 600, lineHeight: 1.3, scalingBase: .footnote, allowedVariants: [])
        case .compact:
            return Spec(
                size: 14, weight: 400, lineHeight: 1.2, scalingBase: .subheadline,
                allowedVariants: [.regular, .semibold]
            )
        case .chipLabel:
            return Spec(size: 14, weight: 500, lineHeight: 1.3, scalingBase: .subheadline, allowedVariants: [])
        }
    }

    /// The unscaled design point size (§3.2/§3.3), before Dynamic Type scaling.
    public var size: CGFloat { spec.size }
    /// The numeric `wght` axis value (100–900 scale; design tokens use 400/500/600/700).
    public var weight: CGFloat { spec.weight }
    /// The line-height multiplier of `size` (§3.2/§3.3, e.g. `body` = 1.4).
    public var lineHeight: CGFloat { spec.lineHeight }
    /// The `UIFont.TextStyle` this style scales against for Dynamic Type (§3.1).
    public var scalingBase: UIFont.TextStyle { spec.scalingBase }

    /// Resolves the effective weight for an optional documented variant. Returns the
    /// style's default weight if `variant` is nil or not in the style's documented set
    /// (§3.2/§3.3 "允许的字重变体"); in DEBUG builds an unsupported variant asserts so
    /// misuse is caught during development rather than silently ignored in the UI.
    fileprivate func effectiveWeight(variant: FCFontWeightVariant?) -> CGFloat {
        guard let variant else { return spec.weight }
        guard spec.allowedVariants.contains(variant) else {
            assertionFailure("FCTextStyle.\(self) does not document a \(variant) weight variant (§3.2/§3.3).")
            return spec.weight
        }
        return variant.weightValue
    }
}

private extension DynamicTypeSize {
    /// Maps SwiftUI's Dynamic Type environment value to the `UIContentSizeCategory`
    /// `UIFontMetrics` needs, so the current view's `dynamicTypeSize` environment
    /// (which may be locally overridden, not just the system-wide setting) is honored.
    var uiContentSizeCategory: UIContentSizeCategory {
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

/// Applies an `FCTextStyle` to a view: builds the scaled `UIFont` (base weight, or a
/// documented variant), wraps it as a SwiftUI `Font`, and applies the design system's
/// line-height as line spacing. Reads `dynamicTypeSize` from the environment so the
/// view rebuilds — and rescales — whenever the user's preferred text size changes.
private struct FCFontModifier: ViewModifier {
    let style: FCTextStyle
    let variant: FCFontWeightVariant?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let weight = style.effectiveWeight(variant: variant)
        let baseFont = FCFont.uiFont(size: style.size, weight: weight)
        let traitCollection = UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory)
        let scaledFont = UIFontMetrics(forTextStyle: style.scalingBase)
            .scaledFont(for: baseFont, compatibleWith: traitCollection)

        // Desired total line height scales with the same ratio Dynamic Type applied
        // to the point size; line spacing is the remainder above the font's own
        // natural line height, never negative.
        let desiredLineHeight = scaledFont.pointSize * style.lineHeight
        let lineSpacing = max(0, desiredLineHeight - scaledFont.lineHeight)

        content
            .font(Font(scaledFont))
            .lineSpacing(lineSpacing)
    }
}

public extension View {
    /// Applies the design system's Noto Sans SC typography (`design/design-system/README.md`
    /// §3) for `style`, including Dynamic Type scaling and the documented line height.
    /// Letter spacing is always 0 (§3.1) — this modifier never sets tracking/kerning,
    /// which already defaults to 0.
    ///
    /// - Parameter weight: An optional documented weight variant. Only `callout` and
    ///   `compact` (§3.2/§3.3) have one; passing a variant for any other style asserts
    ///   in DEBUG and is ignored in release.
    func fcFont(_ style: FCTextStyle, weight: FCFontWeightVariant? = nil) -> some View {
        modifier(FCFontModifier(style: style, variant: weight))
    }
}

public extension Text {
    /// A `Text`-scoped variant of `View.fcFont(_:weight:)`, needed only where a SwiftUI
    /// API requires a `Text` value directly rather than an arbitrary `View` (e.g.
    /// `TextField`'s `prompt:` parameter). Because a `Text` is built outside a view's
    /// `body`, this cannot read the `dynamicTypeSize` environment value the way
    /// `View.fcFont` does — it scales against the system-wide preferred content size
    /// category instead of honoring a local `.dynamicTypeSize()` override — and it does
    /// not apply the style's line spacing (`Text` alone has no line-wrapping geometry to
    /// space). Prefer `View.fcFont` wherever the call site is not constrained to `Text`.
    func fcFont(_ style: FCTextStyle, weight: FCFontWeightVariant? = nil) -> Text {
        let resolvedWeight = style.effectiveWeight(variant: weight)
        let baseFont = FCFont.uiFont(size: style.size, weight: resolvedWeight)
        let scaledFont = UIFontMetrics(forTextStyle: style.scalingBase).scaledFont(for: baseFont)
        return self.font(Font(scaledFont))
    }
}
