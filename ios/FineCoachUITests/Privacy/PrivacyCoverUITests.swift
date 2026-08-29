import XCTest

@MainActor
final class PrivacyCoverUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPrivacyCoverIsAbsentWhileActiveAndClearsAfterBackground() {
        let app = RecoveryProcessDriver.launchIsolatedApp()
        RecoveryProcessDriver.skipOnboardingIfPresented(in: app)
        XCTAssertTrue(
            app.buttons["studentList.add"].waitForExistence(timeout: 8)
                || app.staticTexts["还没有学员"].waitForExistence(timeout: 2)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["privacy.cover"].exists,
            "opaque cover must not remain after the scene is active"
        )

        XCUIDevice.shared.press(.home)
        _ = app.wait(for: .runningBackground, timeout: 4)
        app.activate()
        XCTAssertTrue(
            app.buttons["studentList.add"].waitForExistence(timeout: 8)
                || app.staticTexts["还没有学员"].waitForExistence(timeout: 2)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["privacy.cover"].waitForExistence(timeout: 2),
            "cover must be removed when the scene returns to active"
        )
    }
}
