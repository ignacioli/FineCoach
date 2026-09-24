import FineCoach
import XCTest

/// Cheap, non-structural coverage for T047a's later assertions (spec §2.4 /
/// T047a): every documented status carries non-empty text and a non-empty
/// icon, and the case count matches the 5 named statuses this design system
/// version documents (逾期/冲突/课包异常/不可比较/权限拒绝). Does not render or
/// inspect any view.
final class FCStatusTests: XCTestCase {
    func testExactlyFiveStatuses() {
        XCTAssertEqual(FCStatus.allCases.count, 5)
    }

    func testEveryStatusHasNonEmptyTextAndSymbol() {
        for status in FCStatus.allCases {
            XCTAssertFalse(status.text.isEmpty, "\(status) must have display text")
            XCTAssertFalse(status.symbolName.isEmpty, "\(status) must have an SF Symbol name")
        }
    }
}
