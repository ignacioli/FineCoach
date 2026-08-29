import FineCoach
import XCTest

@MainActor
final class ScenePrivacyCoordinatorTests: XCTestCase {
    func testResigningActiveCoversSynchronouslyAndBecomeActiveClears() {
        let coordinator = ScenePrivacyCoordinator()
        XCTAssertFalse(coordinator.isCovered)

        coordinator.sceneWillResignActive()
        XCTAssertTrue(
            coordinator.isCovered,
            "cover must appear synchronously on inactive/background, before system snapshot"
        )

        coordinator.sceneDidBecomeActive()
        XCTAssertFalse(coordinator.isCovered)
    }
}
