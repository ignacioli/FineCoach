import FineCoach
import XCTest

final class DurationTextParserTests: XCTestCase {
    // MARK: - parseSeconds: valid formats

    func testParsesFullChineseFormat() {
        XCTAssertEqual(DurationTextParser.parseSeconds("5分30秒"), "330")
    }

    func testParsesFullLatinFormat() {
        XCTAssertEqual(DurationTextParser.parseSeconds("5m30s"), "330")
    }

    func testParsesFullLatinFormatUppercase() {
        XCTAssertEqual(DurationTextParser.parseSeconds("5M30S"), "330")
    }

    func testParsesSecondsOnlyChinese() {
        XCTAssertEqual(DurationTextParser.parseSeconds("30秒"), "30")
    }

    func testParsesSecondsOnlyLatin() {
        XCTAssertEqual(DurationTextParser.parseSeconds("30s"), "30")
    }

    func testParsesMinutesOnlyChinese() {
        XCTAssertEqual(DurationTextParser.parseSeconds("5分"), "300")
    }

    func testParsesMinutesOnlyLatin() {
        XCTAssertEqual(DurationTextParser.parseSeconds("5m"), "300")
    }

    func testParsesBareNumberAsSecondsForBackwardCompatibility() {
        XCTAssertEqual(DurationTextParser.parseSeconds("45"), "45")
    }

    func testParsesBareDecimalNumberAsSecondsForBackwardCompatibility() {
        XCTAssertEqual(DurationTextParser.parseSeconds("45.5"), "45.5")
    }

    func testToleratesWhitespaceAroundUnitMarkersAndOverallTrim() {
        XCTAssertEqual(DurationTextParser.parseSeconds("  5 分 30 秒  "), "330")
    }

    func testZeroMinutesWithSecondsStillParsesAsFullFormat() {
        XCTAssertEqual(DurationTextParser.parseSeconds("0分45秒"), "45")
    }

    func testSecondsPartNotClampedTo59IsSummedLiterally() {
        // Lenient by design: "5分90秒" is unconventional but unambiguous math.
        XCTAssertEqual(DurationTextParser.parseSeconds("5分90秒"), "390")
    }

    // MARK: - parseSeconds: invalid formats

    func testEmptyStringIsInvalid() {
        XCTAssertNil(DurationTextParser.parseSeconds(""))
    }

    func testWhitespaceOnlyIsInvalid() {
        XCTAssertNil(DurationTextParser.parseSeconds("   "))
    }

    func testMixedUnitMarkersAreInvalid() {
        XCTAssertNil(DurationTextParser.parseSeconds("5分30s"))
        XCTAssertNil(DurationTextParser.parseSeconds("5m30秒"))
    }

    func testMissingSecondsUnitAfterMinutesIsInvalid() {
        XCTAssertNil(DurationTextParser.parseSeconds("5分30"))
    }

    func testReversedOrderIsInvalid() {
        XCTAssertNil(DurationTextParser.parseSeconds("30秒5分"))
    }

    func testNegativeNumberIsInvalid() {
        XCTAssertNil(DurationTextParser.parseSeconds("-5分"))
    }

    func testNonNumericTextIsInvalid() {
        XCTAssertNil(DurationTextParser.parseSeconds("五分三十秒"))
        XCTAssertNil(DurationTextParser.parseSeconds("abc"))
    }

    func testTrailingGarbageAfterValidFormatIsInvalid() {
        XCTAssertNil(DurationTextParser.parseSeconds("5分30秒!"))
    }

    // MARK: - formatForEditing

    func testFormatForEditingCombinesMinutesAndSeconds() {
        XCTAssertEqual(DurationTextParser.formatForEditing(secondsText: "330"), "5分30秒")
    }

    func testFormatForEditingWholeMinutesOmitsSeconds() {
        XCTAssertEqual(DurationTextParser.formatForEditing(secondsText: "300"), "5分")
    }

    func testFormatForEditingUnderAMinuteShowsSecondsOnly() {
        XCTAssertEqual(DurationTextParser.formatForEditing(secondsText: "45"), "45秒")
    }

    func testFormatForEditingZeroShowsZeroSeconds() {
        XCTAssertEqual(DurationTextParser.formatForEditing(secondsText: "0"), "0秒")
    }

    func testFormatForEditingNilOrInvalidReturnsEmptyString() {
        XCTAssertEqual(DurationTextParser.formatForEditing(secondsText: nil), "")
    }

    // MARK: - round-trip

    func testRoundTripParseThenFormatIsStable() {
        let seconds = DurationTextParser.parseSeconds("5分30秒")
        XCTAssertEqual(seconds, "330")
        XCTAssertEqual(DurationTextParser.formatForEditing(secondsText: seconds), "5分30秒")
    }
}
