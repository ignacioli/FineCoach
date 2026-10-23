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
        XCTAssertEqual(DurationTextParser.formatForEditing(secondsText: "330"), "5 分 30 秒")
    }

    func testFormatForEditingWholeMinutesOmitsSeconds() {
        XCTAssertEqual(DurationTextParser.formatForEditing(secondsText: "300"), "5 分")
    }

    func testFormatForEditingUnderAMinuteShowsSecondsOnly() {
        XCTAssertEqual(DurationTextParser.formatForEditing(secondsText: "45"), "45 秒")
    }

    func testFormatForEditingZeroShowsZeroSeconds() {
        XCTAssertEqual(DurationTextParser.formatForEditing(secondsText: "0"), "0 秒")
    }

    func testFormatForEditingNilOrInvalidReturnsEmptyString() {
        XCTAssertEqual(DurationTextParser.formatForEditing(secondsText: nil), "")
    }

    // MARK: - Session review (hours and minutes)

    func testParsesSessionDurationFormats() {
        let cases: [(String, String)] = [
            ("1h12m", "4320"),
            ("1小时12分", "4320"),
            ("1小时12分钟", "4320"),
            ("55分钟", "3300"),
            ("55分", "3300"),
            ("55m", "3300"),
            ("2h", "7200"),
            ("2小时", "7200"),
            ("12 小时 5 分", "43500"),
            ("1h 12m", "4320"),
            (" 1 H 12 M ", "4320"),
            ("55M", "3300"),
            ("2H", "7200"),
            ("1 小时 12 分钟", "4320"),
            ("55 分钟", "3300"),
            ("55 分", "3300"),
            ("55 m", "3300"),
            ("2 h", "7200"),
            ("2 小时", "7200"),
            ("90m", "5400"),
            ("1h90m", "9000"),
        ]
        for (text, seconds) in cases {
            XCTAssertEqual(DurationTextParser.parseSessionDurationSeconds(text), seconds, text)
        }
    }

    func testSessionBareIntegerMeansMinutes() {
        XCTAssertEqual(DurationTextParser.parseSessionDurationSeconds("90"), "5400")
        XCTAssertEqual(DurationTextParser.parseSessionDurationSeconds("0"), "0")
    }

    func testRejectsInvalidSessionDurationAndOverflow() {
        for text in ["abc", "1h2x", "", "   ", "-1", "1.5", "30s", "2m1h", "1h12", "1h2m!"] {
            XCTAssertNil(DurationTextParser.parseSessionDurationSeconds(text), text)
        }
        for text in ["\(Int.max)h", "\(Int.max)m", "\(Int.max)0", "2562047788015215h31m"] {
            XCTAssertNil(DurationTextParser.parseSessionDurationSeconds(text), text)
        }
    }

    func testFormatsSessionDurationRoundedToMinutes() {
        let cases: [(String, String)] = [
            ("0", "0 分"),
            ("29", "0 分"),
            ("30", "1 分"),
            ("59", "1 分"),
            ("3300", "55 分"),
            ("7200", "2 小时"),
            ("43500", "12 小时 5 分"),
            ("7180", "2 小时"),
        ]
        for (seconds, text) in cases {
            XCTAssertEqual(DurationTextParser.formatSessionDurationForEditing(seconds: seconds), text, seconds)
            XCTAssertNotNil(DurationTextParser.parseSessionDurationSeconds(text), text)
        }
    }

    // MARK: - round-trip

    func testRoundTripParseThenFormatIsStable() {
        let seconds = DurationTextParser.parseSeconds("5分30秒")
        XCTAssertEqual(seconds, "330")
        XCTAssertEqual(DurationTextParser.formatForEditing(secondsText: seconds), "5 分 30 秒")
        // README §13 N6: the spaced display text parses back to the same seconds.
        XCTAssertEqual(DurationTextParser.parseSeconds("5 分 30 秒"), "330")
        XCTAssertEqual(DurationTextParser.parseSeconds("5 分"), "300")
        XCTAssertEqual(DurationTextParser.parseSeconds("45 秒"), "45")
    }
}
