import SwiftUI

/// The 15 approved Penpot tokens, grouped by their source token set.
///
/// Keep this list closed: feature views should consume these tokens rather
/// than introducing feature-specific colors, spacing, or radii.
public enum FCPrimitives {
    // FC Primitives: 5 colors, 2 spacing values, and 2 radii.
    public static let canvas = Color(red: 0.97, green: 0.97, blue: 0.96)
    public static let surface = Color.white
    public static let ink = Color(red: 0.10, green: 0.10, blue: 0.10)
    public static let mutedInk = Color(red: 0.38, green: 0.38, blue: 0.36)
    public static let divider = Color(red: 0.84, green: 0.84, blue: 0.82)
    public static let spacingSmall: CGFloat = 8
    public static let spacingMedium: CGFloat = 16
    public static let radiusSmall: CGFloat = 8
    public static let radiusMedium: CGFloat = 14
}

// FC Semantic Color: the six semantic aliases used by SwiftUI views.
public enum FCSemanticColors {
    public static let background = FCPrimitives.canvas
    public static let elevatedSurface = FCPrimitives.surface
    public static let primaryText = FCPrimitives.ink
    public static let secondaryText = FCPrimitives.mutedInk
    public static let separator = FCPrimitives.divider
    public static let destructive = Color(red: 0.70, green: 0.12, blue: 0.12)
}
