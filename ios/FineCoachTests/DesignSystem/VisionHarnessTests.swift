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
    // MARK: Token value assertions (pin exact G5 "暖炭黑素雅" palette hex values)

    func testCanvasTokenValue() {
        XCTAssertEqual(FCPrimitives.canvasHex, "#F7F4EE")
    }

    func testSurfaceTokenValue() {
        XCTAssertEqual(FCPrimitives.surfaceHex, "#FFFFFF")
    }

    func testPrimaryTextTokenValue() {
        XCTAssertEqual(FCPrimitives.inkHex, "#211F1B")
    }

    func testSecondaryTextTokenValue() {
        XCTAssertEqual(FCPrimitives.mutedInkHex, "#5C5A52")
    }

    func testSeparatorTokenValue() {
        XCTAssertEqual(FCPrimitives.dividerHex, "#ECE9E2")
    }

    func testDestructiveTokenValue() {
        XCTAssertEqual(FCPrimitives.destructiveHex, "#D9563E")
    }

    func testTintTokenValue() {
        XCTAssertEqual(FCPrimitives.tintHex, "#EDE9E2")
    }

    func testWarningTokenValue() {
        XCTAssertEqual(FCPrimitives.warningHex, "#B45309")
    }

    func testBrandTokenValue() {
        XCTAssertEqual(FCPrimitives.brandHex, "#E08A5C")
    }

    func testSpacingTokenValues() {
        XCTAssertEqual(FCPrimitives.spacingSmall, 8)
        XCTAssertEqual(FCPrimitives.spacingMedium, 16)
    }

    func testRadiusTokenValues() {
        XCTAssertEqual(FCPrimitives.radiusSmall, 8)
        XCTAssertEqual(FCPrimitives.radiusMedium, 14)
    }

    // MARK: Contrast utility self-checks (full palette contrast assertions land in T045)

    func testContrastRatioOfIdenticalColorsIsOne() {
        XCTAssertEqual(WCAGContrast.contrastRatio("#FFFFFF", "#FFFFFF"), 1.0, accuracy: 0.0001)
    }

    func testContrastRatioOfBlackOnWhiteIsMaximal() {
        XCTAssertEqual(WCAGContrast.contrastRatio("#000000", "#FFFFFF"), 21.0, accuracy: 0.01)
    }

    func testContrastRatioIsSymmetric() {
        let a = WCAGContrast.contrastRatio(FCPrimitives.inkHex, FCPrimitives.canvasHex)
        let b = WCAGContrast.contrastRatio(FCPrimitives.canvasHex, FCPrimitives.inkHex)
        XCTAssertEqual(a, b, accuracy: 0.0001)
    }
}
