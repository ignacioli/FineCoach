import SwiftUI

extension Color {
    /// Creates a color from a 6-digit RGB hex string (no alpha), e.g. "#F7F4EE".
    init(hex: String) {
        var sanitized = hex
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

/// The approved Penpot tokens (G5 "暖炭黑素雅" palette), grouped by their source token set.
///
/// Keep this list closed: feature views should consume these tokens rather
/// than introducing feature-specific colors, spacing, or radii. Hex constants
/// are exposed alongside each Color so the Deterministic Vision Validation
/// Harness can compute WCAG contrast directly from the source hex values.
///
/// Source of truth: `design/design-system/README.md` §2 (colors), §4
/// (spacing), §5 (radii). Do not add or change a value here without an
/// entry in that document.
public enum FCPrimitives {
    // MARK: FC Primitives §2.1 — color

    public static let brandPrimaryHex = "#2A2822"
    public static let brandPressedHex = "#1F1E1B"
    public static let brandSubtleHex = "#EDE9E2"
    public static let brandOnHex = "#FFFFFF"

    public static let neutral0Hex = "#FFFFFF"
    public static let neutral50Hex = "#F7F4EE"
    public static let neutral100Hex = "#F0EEE9"
    public static let neutral200Hex = "#ECE9E2"
    public static let neutral400Hex = "#A8A39A"
    public static let neutral500Hex = "#8E897F"
    public static let neutral600Hex = "#5C5A52"
    public static let neutral900Hex = "#211F1B"

    public static let green600Hex = "#2A2822"
    public static let amber700Hex = "#B45309"
    /// §10 O1: dimmed from the original `#D9563E` (3.92:1) to `#D4442A`
    /// (4.51:1) to clear the WCAG AA text-contrast bar.
    public static let red700Hex = "#D4442A"

    public static let brandPrimary = Color(hex: brandPrimaryHex)
    public static let brandPressed = Color(hex: brandPressedHex)
    public static let brandSubtle = Color(hex: brandSubtleHex)
    public static let brandOn = Color(hex: brandOnHex)

    public static let neutral0 = Color(hex: neutral0Hex)
    public static let neutral50 = Color(hex: neutral50Hex)
    public static let neutral100 = Color(hex: neutral100Hex)
    public static let neutral200 = Color(hex: neutral200Hex)
    public static let neutral400 = Color(hex: neutral400Hex)
    public static let neutral500 = Color(hex: neutral500Hex)
    public static let neutral600 = Color(hex: neutral600Hex)
    public static let neutral900 = Color(hex: neutral900Hex)

    public static let green600 = Color(hex: green600Hex)
    public static let amber700 = Color(hex: amber700Hex)
    public static let red700 = Color(hex: red700Hex)

    // MARK: §4 — spacing (only these six values are permitted)

    public static let space1: CGFloat = 4
    public static let space2: CGFloat = 8
    public static let space3: CGFloat = 12
    public static let space4: CGFloat = 16
    public static let space6: CGFloat = 24
    public static let space8: CGFloat = 32

    // MARK: §5 — radii

    public static let radiusSm: CGFloat = 8
    public static let radiusMd: CGFloat = 12
    public static let radiusLg: CGFloat = 16
    public static let radiusXl: CGFloat = 20
    /// Confirmation-dialog action buttons (36pt tall); off the 8/12/16/20
    /// scale but consistently used in the approved artwork (§5, §10 C8).
    public static let radiusDialogAction: CGFloat = 10

    // MARK: Transitional aliases — remove in T068

    /// Transitional alias — remove in T068
    public static let spacingSmall: CGFloat = 8
    /// Transitional alias — remove in T068
    public static let spacingMedium: CGFloat = 16
    /// Transitional alias — remove in T068
    public static let radiusSmall: CGFloat = 8
    /// Transitional alias — remove in T068
    public static let radiusMedium: CGFloat = 14
}

/// FC Semantic Color: the design-system semantic aliases used by SwiftUI
/// views (§2.2). Each token also exposes its resolved hex so the Vision
/// Harness can compute WCAG contrast directly from source values.
public enum FCSemanticColors {
    public static let actionPrimaryHex = FCPrimitives.brandPrimaryHex
    public static let actionPressedHex = FCPrimitives.brandPressedHex
    public static let actionOnHex = FCPrimitives.brandOnHex
    public static let surfacePageHex = FCPrimitives.neutral0Hex
    public static let surfaceElevatedHex = FCPrimitives.neutral0Hex
    public static let surfaceCanvasHex = FCPrimitives.neutral50Hex
    public static let surfaceSubtleHex = FCPrimitives.neutral100Hex
    public static let surfaceDividerHex = FCPrimitives.neutral200Hex
    public static let surfaceSelectedHex = FCPrimitives.brandSubtleHex
    public static let borderControlHex = FCPrimitives.neutral500Hex
    public static let textPrimaryHex = FCPrimitives.neutral900Hex
    public static let textSecondaryHex = FCPrimitives.neutral600Hex
    public static let textDisabledHex = FCPrimitives.neutral400Hex
    /// §10 C9: not in the Penpot token set; backfilled from the artwork
    /// (dark hero-card secondary text, no primitive backing it).
    public static let textOnActionSecondaryHex = "#B0ABA2"
    public static let statusSuccessHex = FCPrimitives.green600Hex
    public static let statusWarningHex = FCPrimitives.amber700Hex
    public static let statusDestructiveHex = FCPrimitives.red700Hex

    public static let actionPrimary = Color(hex: actionPrimaryHex)
    public static let actionPressed = Color(hex: actionPressedHex)
    public static let actionOn = Color(hex: actionOnHex)
    public static let surfacePage = Color(hex: surfacePageHex)
    public static let surfaceElevated = Color(hex: surfaceElevatedHex)
    public static let surfaceCanvas = Color(hex: surfaceCanvasHex)
    public static let surfaceSubtle = Color(hex: surfaceSubtleHex)
    public static let surfaceDivider = Color(hex: surfaceDividerHex)
    public static let surfaceSelected = Color(hex: surfaceSelectedHex)
    public static let borderControl = Color(hex: borderControlHex)
    public static let textPrimary = Color(hex: textPrimaryHex)
    public static let textSecondary = Color(hex: textSecondaryHex)
    public static let textDisabled = Color(hex: textDisabledHex)
    public static let textOnActionSecondary = Color(hex: textOnActionSecondaryHex)
    public static let statusSuccess = Color(hex: statusSuccessHex)
    public static let statusWarning = Color(hex: statusWarningHex)
    public static let statusDestructive = Color(hex: statusDestructiveHex)

    // MARK: Transitional aliases — remove in T068

    /// Transitional alias — remove in T068
    public static let elevatedSurface = surfaceElevated
    /// Transitional alias — remove in T068
    public static let primaryText = textPrimary
    /// Transitional alias — remove in T068
    public static let secondaryText = textSecondary
    /// Transitional alias — remove in T068
    public static let separator = surfaceDivider
    /// Transitional alias — remove in T068
    public static let destructive = statusDestructive
    /// Transitional alias — remove in T068
    public static let tint = surfaceSelected
    /// Transitional alias — remove in T068
    public static let warning = statusWarning
}
