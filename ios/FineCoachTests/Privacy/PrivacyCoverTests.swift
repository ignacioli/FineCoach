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

    /// The cover is one layer in `AppRoot`, drawn after (above) every branch, so it covers the
    /// viewer, Coach and first-launch branches alike (T022, adversarial review #1).
    func testRootCoverIsShownWhileTheSceneIsCovered() throws {
        let root = try source("App/AppRoot.swift")
        XCTAssertTrue(root.contains("if privacyCoordinator.isCovered"))
        XCTAssertTrue(root.contains("PrivacyCover()"))
        XCTAssertEqual(root.components(separatedBy: "PrivacyCover()").count - 1, 1)
        let coverIndex = try XCTUnwrap(root.range(of: "if privacyCoordinator.isCovered")).lowerBound
        for branch in ["ArchiveViewerRoot()", "RootNavigation()"] {
            let branchIndex = try XCTUnwrap(root.range(of: branch), branch).lowerBound
            XCTAssertLessThan(branchIndex, coverIndex, "\(branch) must sit below the cover layer")
        }
    }

    func testBranchViewsAppearOnlyAsChildrenOfTheAppRootLayer() throws {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil))
        var constructors: [String: [String]] = [:]
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for branch in ["ArchiveViewerRoot()", "RootNavigation()", "AppRoot()"] where text.contains(branch) {
                constructors[branch, default: []].append(url.lastPathComponent)
            }
        }
        XCTAssertEqual(constructors["ArchiveViewerRoot()"], ["AppRoot.swift"])
        XCTAssertEqual(constructors["RootNavigation()"], ["AppRoot.swift"])
        XCTAssertEqual(constructors["AppRoot()"], ["FineCoachApp.swift"])
    }

    func testRootNavigationNoLongerCarriesTheDuplicateCover() throws {
        let navigation = try source("App/RootNavigation.swift")
        XCTAssertFalse(navigation.contains("if privacyCoordinator.isCovered"))
        XCTAssertFalse(navigation.contains("PrivacyCover()"))
    }

    func testViewerBranchHoldsNoCoachEnvironmentOrWriteUseCases() throws {
        let viewer = try source("Features/ArchiveViewer/ArchiveViewerRoot.swift")
        for forbidden in ["AppEnvironment", "environment", "UseCases", "Repository", "PersistenceWriter"] {
            XCTAssertFalse(viewer.contains(forbidden), "viewer root must not reference \(forbidden)")
        }
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
