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

final class VisionHarnessTests: XCTestCase {
    // MARK: Token value assertions (pin exact G5 "暖炭黑素雅" palette hex values, §2/§4/§5)

    func testSurfacePageTokenValue() {
        XCTAssertEqual(FCSemanticColors.surfacePageHex, "#FFFFFF")
    }

    func testSurfaceCanvasTokenValue() {
        XCTAssertEqual(FCSemanticColors.surfaceCanvasHex, "#F7F4EE")
    }

    func testTextPrimaryTokenValue() {
        XCTAssertEqual(FCSemanticColors.textPrimaryHex, "#211F1B")
    }

    func testTextSecondaryTokenValue() {
        XCTAssertEqual(FCSemanticColors.textSecondaryHex, "#5C5A52")
    }

    func testSurfaceDividerTokenValue() {
        XCTAssertEqual(FCSemanticColors.surfaceDividerHex, "#ECE9E2")
    }

    func testStatusDestructiveTokenValue() {
        // §10 O1: dimmed from #D9563E to #D4442A to clear 4.5:1 text contrast.
        XCTAssertEqual(FCSemanticColors.statusDestructiveHex, "#D4442A")
    }

    func testSurfaceSelectedTokenValue() {
        XCTAssertEqual(FCSemanticColors.surfaceSelectedHex, "#EDE9E2")
    }

    func testStatusWarningTokenValue() {
        XCTAssertEqual(FCSemanticColors.statusWarningHex, "#B45309")
    }

    func testActionPrimaryTokenValue() {
        XCTAssertEqual(FCSemanticColors.actionPrimaryHex, "#2A2822")
    }

    func testBorderControlTokenValue() {
        XCTAssertEqual(FCSemanticColors.borderControlHex, "#8E897F")
    }

    func testTextOnActionSecondaryTokenValue() {
        XCTAssertEqual(FCSemanticColors.textOnActionSecondaryHex, "#B0ABA2")
    }

    func testSpacingTokenValues() {
        XCTAssertEqual(FCPrimitives.space1, 4)
        XCTAssertEqual(FCPrimitives.space2, 8)
        XCTAssertEqual(FCPrimitives.space3, 12)
        XCTAssertEqual(FCPrimitives.space4, 16)
        XCTAssertEqual(FCPrimitives.space6, 24)
        XCTAssertEqual(FCPrimitives.space8, 32)
    }

    func testRadiusTokenValues() {
        XCTAssertEqual(FCPrimitives.radiusSm, 8)
        XCTAssertEqual(FCPrimitives.radiusMd, 12)
        XCTAssertEqual(FCPrimitives.radiusLg, 16)
        XCTAssertEqual(FCPrimitives.radiusXl, 20)
        XCTAssertEqual(FCPrimitives.radiusDialogAction, 10)
    }

    // MARK: Contrast utility self-checks (full palette contrast assertions land in T045)

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
