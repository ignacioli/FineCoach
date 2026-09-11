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
public enum FCPrimitives {
    // FC Primitives: 9 colors, 2 spacing values, and 2 radii.
    public static let canvasHex = "#F7F4EE"
    public static let surfaceHex = "#FFFFFF"
    public static let inkHex = "#211F1B"
    public static let mutedInkHex = "#5C5A52"
    public static let dividerHex = "#ECE9E2"
    public static let destructiveHex = "#D9563E"
    public static let tintHex = "#EDE9E2"
    public static let warningHex = "#B45309"
    public static let brandHex = "#E08A5C"

    public static let canvas = Color(hex: canvasHex)
    public static let surface = Color(hex: surfaceHex)
    public static let ink = Color(hex: inkHex)
    public static let mutedInk = Color(hex: mutedInkHex)
    public static let divider = Color(hex: dividerHex)
    public static let destructive = Color(hex: destructiveHex)
    public static let tint = Color(hex: tintHex)
    public static let warning = Color(hex: warningHex)
    public static let brand = Color(hex: brandHex)

    public static let spacingSmall: CGFloat = 8
    public static let spacingMedium: CGFloat = 16
    public static let radiusSmall: CGFloat = 8
    public static let radiusMedium: CGFloat = 14
}

// FC Semantic Color: the nine semantic aliases used by SwiftUI views.
public enum FCSemanticColors {
    public static let background = FCPrimitives.canvas
    public static let elevatedSurface = FCPrimitives.surface
    public static let primaryText = FCPrimitives.ink
    public static let secondaryText = FCPrimitives.mutedInk
    public static let separator = FCPrimitives.divider
    public static let destructive = FCPrimitives.destructive
    public static let tint = FCPrimitives.tint
    public static let warning = FCPrimitives.warning
    public static let brand = FCPrimitives.brand
}
