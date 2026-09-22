import XCTest

@testable import FineCoach

@MainActor
final class TrendsViewPointLabelTests: XCTestCase {
    func testWholeNumberDropsTrailingDecimal() {
        XCTAssertEqual(TrendsView.pointLabel(40, unit: "kg"), "40kg")
    }

    func testFractionalValueKeepsOneDecimalPlace() {
        XCTAssertEqual(TrendsView.pointLabel(40.5, unit: "kg"), "40.5kg")
    }

    func testRoundsToOneDecimalPlace() {
        XCTAssertEqual(TrendsView.pointLabel(40.27, unit: "kg"), "40.3kg")
        XCTAssertEqual(TrendsView.pointLabel(40.24, unit: "kg"), "40.2kg")
    }

    func testRoundingUpToWholeNumberDropsTrailingDecimal() {
        // 40.96 rounds to 41.0, which must render as "41", not "41.0".
        XCTAssertEqual(TrendsView.pointLabel(40.96, unit: "kg"), "41kg")
    }

    func testZeroDropsTrailingDecimal() {
        XCTAssertEqual(TrendsView.pointLabel(0, unit: "次"), "0次")
    }
}
