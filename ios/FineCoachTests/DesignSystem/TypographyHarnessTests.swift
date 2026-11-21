import CoreText
import XCTest
import os

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

    /// Each documented style, plus the callout/compact weight variants, keeps the
    /// same family and `wght` axis, and a second request does not build another font.
    func testEveryStyleAndAllowedVariantReusesOneCachedFont() {
        for style in FCTextStyle.allCases {
            assertCachedFont(size: style.size, weight: style.weight)
        }
        assertCachedFont(size: FCTextStyle.callout.size, weight: 400)
        assertCachedFont(size: FCTextStyle.callout.size, weight: 600)
        assertCachedFont(size: FCTextStyle.compact.size, weight: 600)
    }

    /// Sizes outside the design ladder, so this test is the first builder of the pair
    /// even when other tests have already filled the cache.
    func testSameSizeAndWeightBuildsTheFontOnce() {
        assertCachedFont(size: 31, weight: 450)
        let builds = FCFont.creationCountForTesting(size: 31, weight: 450)
        XCTAssertEqual(builds, 1, "this pair must be constructed by this test and then reused")
        let other = FCFont.uiFont(size: 31, weight: 700)
        XCTAssertEqual(FCFont.creationCountForTesting(size: 31, weight: 700), 1)
        XCTAssertFalse(FCFont.uiFont(size: 31, weight: 450) === other)
    }

    /// Same weight, two sizes. A cache key that dropped `size` would return one
    /// font and the second point size would stay at the first request.
    func testCacheKeyKeepsSize() {
        let small = FCFont.uiFont(size: 11, weight: 400)
        let large = FCFont.uiFont(size: 29, weight: 400)
        XCTAssertEqual(small.pointSize, 11, accuracy: 0.01)
        XCTAssertEqual(large.pointSize, 29, accuracy: 0.01)
        XCTAssertFalse(small === large)
        XCTAssertEqual(FCFont.creationCountForTesting(size: 11, weight: 400), 1)
        XCTAssertEqual(FCFont.creationCountForTesting(size: 29, weight: 400), 1)
        XCTAssertEqual(FCFont.uiFont(size: 11, weight: 400).pointSize, 11, accuracy: 0.01)
        XCTAssertEqual(FCFont.uiFont(size: 29, weight: 400).pointSize, 29, accuracy: 0.01)
    }

    func testConcurrentRequestsObserveOneFontInstance() {
        let size: CGFloat = 41
        let weight: CGFloat = 550
        let threads = 24
        let tokens = OSAllocatedUnfairLock(initialState: [ObjectIdentifier]())
        let group = DispatchGroup()
        for _ in 0..<threads {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let font = FCFont.uiFont(size: size, weight: weight)
                tokens.withLock { $0.append(ObjectIdentifier(font)) }
                group.leave()
            }
        }
        let finished = group.wait(timeout: .now() + 5) == .success
        let seen = tokens.withLock { $0 }
        guard finished, let first = seen.first else {
            XCTFail("font requests did not finish; received \(seen.count) of \(threads)")
            return
        }
        XCTAssertEqual(seen.count, threads)
        XCTAssertEqual(Set(seen).count, 1, "concurrent callers must observe one cached UIFont")
        let builds = FCFont.creationCountForTesting(size: size, weight: weight)
        let again = FCFont.uiFont(size: size, weight: weight)
        XCTAssertEqual(ObjectIdentifier(again), first)
        XCTAssertEqual(
            FCFont.creationCountForTesting(size: size, weight: weight), builds,
            "a request after the cache is populated must not build again"
        )
    }

    private func assertCachedFont(
        size: CGFloat, weight: CGFloat, file: StaticString = #filePath, line: UInt = #line
    ) {
        let first = FCFont.uiFont(size: size, weight: weight)
        let builds = FCFont.creationCountForTesting(size: size, weight: weight)
        let second = FCFont.uiFont(size: size, weight: weight)
        XCTAssertTrue(first === second, "second request must return the cached UIFont", file: file, line: line)
        XCTAssertEqual(
            FCFont.creationCountForTesting(size: size, weight: weight), builds,
            "second request must not construct another font", file: file, line: line
        )
        XCTAssertEqual(first.familyName, FCFont.familyName, file: file, line: line)
        let variation = CTFontCopyVariation(first as CTFont) as? [NSNumber: Double]
        XCTAssertEqual(
            variation?[Self.weightAxisTag], Double(weight),
            "cached font lost the requested wght axis", file: file, line: line
        )
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
