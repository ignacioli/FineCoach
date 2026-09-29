@testable import FineCoach
import XCTest

/// T069l: `FCStepper`'s step rule — ±1, clamped to the range, so the
/// disabled side can never push the value out of bounds.
final class FCStepperTests: XCTestCase {
    func testStepsByOneInsideTheRange() {
        XCTAssertEqual(FCStepper.stepped(20, by: 1, in: 1...999), 21)
        XCTAssertEqual(FCStepper.stepped(20, by: -1, in: 1...999), 19)
    }

    func testClampsAtBothEnds() {
        XCTAssertEqual(FCStepper.stepped(1, by: -1, in: 1...999), 1)
        XCTAssertEqual(FCStepper.stepped(999, by: 1, in: 1...999), 999)
    }
}
