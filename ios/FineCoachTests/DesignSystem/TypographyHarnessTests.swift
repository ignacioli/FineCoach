import CoreText
import XCTest

@testable import FineCoach

/// T061: proves the bundled variable font actually drives every documented weight
/// (not a silent system-font fallback), and pins all 14 `FCTextStyle` cases against a
/// literal copy of `design/design-system/README.md` §3.2/§3.3 — typed out here rather
/// than derived from `FCTextStyle` itself, so a value that's wrong in both the enum and
/// a careless test copy can't slip through.
final class TypographyHarnessTests: XCTestCase {
    /// The OpenType `wght` axis tag (`'wght'`, big-endian four-char code
    /// `0x77676874`), read back via `CTFontCopyVariation` to prove the axis actually
    /// moved. Declared independently of `FCFont`'s private copy of the same constant
    /// so this test isn't just checking the production code against itself.
    private static let weightAxisTag = NSNumber(value: 0x7767_6874 as UInt32)

    // MARK: (a) Font registration and per-weight axis resolution

    func testFontFamilyIsRegistered() {
        XCTAssertTrue(
            FCFont.isFamilyRegistered,
            "NotoSansSC-VF.otf must be registered via UIAppFonts; if this is false the "
                + "weight-axis assertions below are meaningless (the app would be silently "
                + "falling back to a system font) and MUST NOT be allowed to pass."
        )
    }

    func testEveryDocumentedWeightResolvesToTheRegisteredFontAndExactAxisValue() {
        // Deliberately no isFamilyRegistered guard/skip here: if the font failed to
        // register, FCFont.uiFont falls back to a system font, and the family-name
        // assertion below then fails hard (not a skip, not a silent pass) -- which is
        // exactly the required behavior.
        for weight: CGFloat in [400, 500, 600, 700] {
            let font = FCFont.uiFont(size: 17, weight: weight)

            XCTAssertEqual(
                font.familyName, "Noto Sans SC",
                "weight \(weight) resolved to family '\(font.familyName)', expected 'Noto Sans SC' "
                    + "(a system-font fallback would fail this)"
            )

            let ctFont = font as CTFont
            let variation = CTFontCopyVariation(ctFont) as? [NSNumber: Double]
            let resolvedWeight = variation?[Self.weightAxisTag]
            XCTAssertEqual(
                resolvedWeight, Double(weight),
                "requested wght \(weight) resolved to axis value \(String(describing: resolvedWeight))"
            )
        }
    }

    // MARK: (b) All 14 styles against a literal §3.2/§3.3 table

    private struct ExpectedStyle {
        let style: FCTextStyle
        let size: CGFloat
        let weight: CGFloat
        let lineHeight: CGFloat
        let scalingBase: UIFont.TextStyle
    }

    /// Typed out literally from §3.2 (7-step ladder) and §3.3 (7 named exceptions).
    /// Every one of `FCTextStyle`'s 14 cases MUST appear here exactly once. A function
    /// (not a `static let`) so Swift 6 strict concurrency has no shared mutable state
    /// to complain about — each call just builds a fresh, local array.
    private func expectedStyles() -> [ExpectedStyle] {
        [
            // §3.2 ladder
            ExpectedStyle(style: .display, size: 34, weight: 700, lineHeight: 1.2, scalingBase: .largeTitle),
            ExpectedStyle(style: .titleLarge, size: 28, weight: 700, lineHeight: 1.3, scalingBase: .title1),
            ExpectedStyle(style: .title, size: 22, weight: 600, lineHeight: 1.3, scalingBase: .title2),
            ExpectedStyle(style: .headline, size: 17, weight: 600, lineHeight: 1.4, scalingBase: .headline),
            ExpectedStyle(style: .body, size: 17, weight: 400, lineHeight: 1.4, scalingBase: .body),
            ExpectedStyle(style: .callout, size: 15, weight: 500, lineHeight: 1.4, scalingBase: .callout),
            ExpectedStyle(style: .caption, size: 13, weight: 400, lineHeight: 1.3, scalingBase: .footnote),
            // §3.3 named exceptions
            ExpectedStyle(style: .numeralHero, size: 44, weight: 700, lineHeight: 1.1, scalingBase: .largeTitle),
            ExpectedStyle(style: .numeralLarge, size: 24, weight: 600, lineHeight: 1.2, scalingBase: .title2),
            ExpectedStyle(style: .titleEmphasis, size: 22, weight: 700, lineHeight: 1.3, scalingBase: .title2),
            ExpectedStyle(style: .exerciseTitle, size: 20, weight: 700, lineHeight: 1.3, scalingBase: .title3),
            ExpectedStyle(style: .sectionLabel, size: 13, weight: 600, lineHeight: 1.3, scalingBase: .footnote),
            ExpectedStyle(style: .compact, size: 14, weight: 400, lineHeight: 1.2, scalingBase: .subheadline),
            ExpectedStyle(style: .chipLabel, size: 14, weight: 500, lineHeight: 1.3, scalingBase: .subheadline),
        ]
    }

    func testExactlyFourteenStyles() {
        XCTAssertEqual(expectedStyles().count, 14, "the literal table itself must list all 14 styles")
        XCTAssertEqual(FCTextStyle.allCases.count, 14)
    }

    func testEveryStyleMatchesTheLiteralDesignSystemTable() {
        for expected in expectedStyles() {
            XCTAssertEqual(expected.style.size, expected.size, "\(expected.style) size")
            XCTAssertEqual(expected.style.weight, expected.weight, "\(expected.style) weight")
            XCTAssertEqual(expected.style.lineHeight, expected.lineHeight, "\(expected.style) lineHeight")
            XCTAssertEqual(expected.style.scalingBase, expected.scalingBase, "\(expected.style) scalingBase")
        }
    }
}
