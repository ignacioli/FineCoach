import XCTest

final class SetupSmokeUITests: XCTestCase {
    @MainActor
    func testApplicationTargetIsDiscoverable() {
        let application = XCUIApplication()
        XCTAssertNotNil(application)
    }
}
