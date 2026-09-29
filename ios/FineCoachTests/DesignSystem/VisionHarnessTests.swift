import FineCoach
import XCTest

/// Deterministic Vision Validation Harness (plan Sec9): token value assertions plus a
/// reusable WCAG contrast-ratio calculator derived from token hex strings, so UI/UX
/// acceptance is code-computed evidence rather than manual screenshot review.
enum WCAGContrast {
    /// Relative luminance per WCAG 2.x, computed from a 6-digit RGB hex string.
    static func relativeLuminance(hex: String) -> Double {
        let (r, g, b) = channels(hex: hex)
        func linearize(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    /// Contrast ratio between two hex colors, always >= 1.
    static func contrastRatio(_ hexA: String, _ hexB: String) -> Double {
        let lA = relativeLuminance(hex: hexA)
        let lB = relativeLuminance(hex: hexB)
        let lighter = max(lA, lB)
        let darker = min(lA, lB)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func channels(hex: String) -> (Double, Double, Double) {
        var sanitized = hex
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        return (r, g, b)
    }
}

/// T060: exact-value assertions for every color/spacing/radius token introduced by
/// T054–T057, pinned against `design/design-system/README.md` §2/§4/§5 so any drift in
/// `Tokens.swift` fails a test instead of silently reaching a feature screen.
final class VisionHarnessTests: XCTestCase {
    // MARK: §2.1 FC Primitives — color

    func testPrimitiveColorHexValues() {
        XCTAssertEqual(FCPrimitives.brandPrimaryHex, "#2A2822")
        XCTAssertEqual(FCPrimitives.brandPressedHex, "#1F1E1B")
        XCTAssertEqual(FCPrimitives.brandSubtleHex, "#EDE9E2")
        XCTAssertEqual(FCPrimitives.brandOnHex, "#FFFFFF")

        XCTAssertEqual(FCPrimitives.neutral0Hex, "#FFFFFF")
        XCTAssertEqual(FCPrimitives.neutral50Hex, "#F7F4EE")
        XCTAssertEqual(FCPrimitives.neutral100Hex, "#F0EEE9")
        XCTAssertEqual(FCPrimitives.neutral200Hex, "#ECE9E2")
        XCTAssertEqual(FCPrimitives.neutral400Hex, "#A8A39A")
        XCTAssertEqual(FCPrimitives.neutral500Hex, "#8E897F")
        XCTAssertEqual(FCPrimitives.neutral600Hex, "#5C5A52")
        XCTAssertEqual(FCPrimitives.neutral900Hex, "#211F1B")

        XCTAssertEqual(FCPrimitives.green600Hex, "#2A2822")
        XCTAssertEqual(FCPrimitives.amber700Hex, "#B45309")
        // §10 O1: dimmed from the original #D9563E (3.92:1) to #D4442A (4.51:1).
        XCTAssertEqual(FCPrimitives.red700Hex, "#D4442A")
    }

    // MARK: §2.2 FC Semantic Color — each MUST resolve to its documented §2.2 value

    func testSemanticColorHexValues() {
        XCTAssertEqual(FCSemanticColors.actionPrimaryHex, "#2A2822")
        XCTAssertEqual(FCSemanticColors.actionPressedHex, "#1F1E1B")
        XCTAssertEqual(FCSemanticColors.actionOnHex, "#FFFFFF")
        XCTAssertEqual(FCSemanticColors.surfacePageHex, "#FFFFFF")
        XCTAssertEqual(FCSemanticColors.surfaceElevatedHex, "#FFFFFF")
        XCTAssertEqual(FCSemanticColors.surfaceCanvasHex, "#F7F4EE")
        XCTAssertEqual(FCSemanticColors.surfaceSubtleHex, "#F0EEE9")
        XCTAssertEqual(FCSemanticColors.surfaceDividerHex, "#ECE9E2")
        XCTAssertEqual(FCSemanticColors.surfaceSelectedHex, "#EDE9E2")
        XCTAssertEqual(FCSemanticColors.borderControlHex, "#8E897F")
        XCTAssertEqual(FCSemanticColors.textPrimaryHex, "#211F1B")
        XCTAssertEqual(FCSemanticColors.textSecondaryHex, "#5C5A52")
        XCTAssertEqual(FCSemanticColors.textDisabledHex, "#A8A39A")
        // §10 C9: backfilled from the artwork, no primitive of its own.
        XCTAssertEqual(FCSemanticColors.textOnActionSecondaryHex, "#B0ABA2")
        XCTAssertEqual(FCSemanticColors.statusSuccessHex, "#2A2822")
        XCTAssertEqual(FCSemanticColors.statusWarningHex, "#B45309")
        // §10 O1: dimmed from the original #D9563E (3.92:1) to #D4442A (4.51:1).
        XCTAssertEqual(FCSemanticColors.statusDestructiveHex, "#D4442A")
    }

    // §2.2 `overlay.scrim` (T078, approved 2026-09-26): text.primary at 40%.
    func testOverlayScrimValue() {
        XCTAssertEqual(FCSemanticColors.overlayScrimHex, "#211F1B")
        XCTAssertEqual(FCSemanticColors.overlayScrimHex, FCSemanticColors.textPrimaryHex)
        XCTAssertEqual(FCSemanticColors.overlayScrimOpacity, 0.4)
    }

    // MARK: §4 spacing (only these six values are permitted)

    func testSpacingTokenValues() {
        XCTAssertEqual(FCPrimitives.space1, 4)
        XCTAssertEqual(FCPrimitives.space2, 8)
        XCTAssertEqual(FCPrimitives.space3, 12)
        XCTAssertEqual(FCPrimitives.space4, 16)
        XCTAssertEqual(FCPrimitives.space6, 24)
        XCTAssertEqual(FCPrimitives.space8, 32)
    }

    // MARK: §5 radii

    func testRadiusTokenValues() {
        XCTAssertEqual(FCPrimitives.radiusSm, 8)
        XCTAssertEqual(FCPrimitives.radiusMd, 12)
        XCTAssertEqual(FCPrimitives.radiusLg, 16)
        XCTAssertEqual(FCPrimitives.radiusXl, 20)
        // §10 C8: off the 8/12/16/20 scale but consistently used in the
        // approved artwork for the 36pt confirmation-dialog action buttons.
        XCTAssertEqual(FCPrimitives.radiusDialogAction, 10)
    }

    // MARK: Contrast utility self-checks (full §11 palette contrast assertions: T045)

    func testContrastRatioOfIdenticalColorsIsOne() {
        XCTAssertEqual(WCAGContrast.contrastRatio("#FFFFFF", "#FFFFFF"), 1.0, accuracy: 0.0001)
    }

    func testContrastRatioOfBlackOnWhiteIsMaximal() {
        XCTAssertEqual(WCAGContrast.contrastRatio("#000000", "#FFFFFF"), 21.0, accuracy: 0.01)
    }

    func testContrastRatioIsSymmetric() {
        let a = WCAGContrast.contrastRatio(FCSemanticColors.textPrimaryHex, FCSemanticColors.surfaceCanvasHex)
        let b = WCAGContrast.contrastRatio(FCSemanticColors.surfaceCanvasHex, FCSemanticColors.textPrimaryHex)
        XCTAssertEqual(a, b, accuracy: 0.0001)
    }
}
