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
            .deletingLastPathComponent()  // Privacy/
            .deletingLastPathComponent()  // FineCoachTests/
            .deletingLastPathComponent()  // ios/
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
        for branch in ["ArchiveViewerRoot(", "RootNavigation("] {
            let branchIndex = try XCTUnwrap(root.range(of: branch), branch).lowerBound
            XCTAssertLessThan(branchIndex, coverIndex, "\(branch) must sit below the cover layer")
        }
    }

    func testBranchViewsAppearOnlyAsChildrenOfTheAppRootLayer() throws {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil))
        var constructors: [String: [String]] = [:]
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for branch in ["ArchiveViewerRoot(", "RootNavigation(", "AppRoot()"]
            where text.contains(branch) && !text.contains("struct \(branch.dropLast())") {
                constructors[branch, default: []].append(url.lastPathComponent)
            }
        }
        XCTAssertEqual(constructors["ArchiveViewerRoot("], ["AppRoot.swift"])
        XCTAssertEqual(constructors["RootNavigation("], ["AppRoot.swift"])
        XCTAssertEqual(constructors["AppRoot()"], ["FineCoachApp.swift"])
    }

    func testRootNavigationNoLongerCarriesTheDuplicateCover() throws {
        let navigation = try source("App/RootNavigation.swift")
        XCTAssertFalse(navigation.contains("if privacyCoordinator.isCovered"))
        XCTAssertFalse(navigation.contains("PrivacyCover()"))
    }

    /// The viewer receives only the archive services: no Coach environment, store handle or
    /// Coach use case anywhere in its folder (plan §5). It does read through
    /// `ArchiveViewerUseCases`, which is why "UseCases" as a word is no longer banned.
    func testViewerBranchHoldsNoCoachEnvironmentOrWriteUseCases() throws {
        let dir = appRoot.appendingPathComponent("Features/ArchiveViewer")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let forbidden = [
            "AppEnvironment", "@EnvironmentObject", "HistoryUseCases", "ExerciseLibraryUseCases", "StudentUseCases",
            "BodyDataUseCases", "ActiveSessionUseCases", "TemplateUseCases", "AppointmentUseCases",
            "CreditLedgerUseCases", "Repository", "PersistenceWriter",
        ]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for word in forbidden {
                XCTAssertFalse(text.contains(word), "\(file.lastPathComponent) must not reference \(word)")
            }
        }
        let root = try source("Features/ArchiveViewer/ArchiveViewerRoot.swift")
        XCTAssertTrue(root.contains("init(services: ArchiveServices)"))
    }

    func testEveryScenePhaseCoversExceptActive() throws {
        let app = try source("FineCoachApp.swift")
        XCTAssertTrue(app.contains("case .active:"))
        XCTAssertTrue(app.contains("privacyCoordinator.sceneDidBecomeActive()"))
        XCTAssertTrue(app.contains("case .inactive:"))
        XCTAssertTrue(app.contains("case .background:"))
        XCTAssertTrue(app.contains("@unknown default:"))
        XCTAssertGreaterThanOrEqual(
            app.components(separatedBy: "privacyCoordinator.sceneWillResignActive()").count - 1, 3)
    }

    func testEveryFeatureFileThatPresentsAModalCoversItsContent() throws {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: appRoot.appendingPathComponent("Features"), includingPropertiesForKeys: nil)
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
