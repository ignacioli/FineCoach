import XCTest

/// T050b (NFR-003): the task-switcher privacy cover exists at the app root,
/// is driven by every scene-phase change, and every Feature file that
/// presents a system modal (`fullScreenCover` / `sheet`) puts the cover on
/// that modal's content too, because modals sit above the root cover. The
/// coordinator's own behaviour is `ScenePrivacyCoordinatorTests`. The system
/// file picker cannot be covered; that limit is recorded in T051.
final class PrivacyCoverTests: XCTestCase {
    private var appRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Privacy/
            .deletingLastPathComponent() // FineCoachTests/
            .deletingLastPathComponent() // ios/
            .appendingPathComponent("FineCoachApp")
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: appRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testRootCoverIsShownWhileTheSceneIsCovered() throws {
        let root = try source("App/RootNavigation.swift")
        XCTAssertTrue(root.contains("if privacyCoordinator.isCovered"))
        XCTAssertTrue(root.contains("PrivacyCover()"))
    }

    func testEveryScenePhaseCoversExceptActive() throws {
        let app = try source("FineCoachApp.swift")
        XCTAssertTrue(app.contains("case .active:"))
        XCTAssertTrue(app.contains("privacyCoordinator.sceneDidBecomeActive()"))
        XCTAssertTrue(app.contains("case .inactive:"))
        XCTAssertTrue(app.contains("case .background:"))
        XCTAssertTrue(app.contains("@unknown default:"))
        XCTAssertGreaterThanOrEqual(app.components(separatedBy: "privacyCoordinator.sceneWillResignActive()").count - 1, 3)
    }

    func testEveryFeatureFileThatPresentsAModalCoversItsContent() throws {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: appRoot.appendingPathComponent("Features"), includingPropertiesForKeys: nil)
        )
        var uncovered: [String] = []
        var presenters = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard text.contains(".fullScreenCover(") || text.contains(".sheet(") else { continue }
            presenters += 1
            if !text.contains(".fcPrivacyCovered()") {
                uncovered.append(url.lastPathComponent)
            }
        }
        XCTAssertGreaterThan(presenters, 0, "scan found no modal presenters; the scan is broken")
        XCTAssertTrue(uncovered.isEmpty, "modal content without privacy cover: \(uncovered.sorted())")
    }
}
