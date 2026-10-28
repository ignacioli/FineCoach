import XCTest

final class SystemEntryConfigurationTests: XCTestCase {
    func testAppAndWidgetEntitlementsContainOnlyTheApprovedAppGroup() throws {
        for path in [
            "FineCoachApp/FineCoach.entitlements",
            "FineCoachWidgets/FineCoachWidgets.entitlements",
        ] {
            let entitlements = try dictionary(at: path)
            let groups = try XCTUnwrap(entitlements["com.apple.security.application-groups"] as? [String], path)
            XCTAssertEqual(groups, ["group.com.finecoach.app"], path)
        }
    }

    func testAppDebugAndReleaseSupportLiveActivities() throws {
        let project = try dictionary(at: "FineCoach.xcodeproj/project.pbxproj")
        let objects = try XCTUnwrap(project["objects"] as? [String: [String: Any]])
        let app = try XCTUnwrap(
            objects.values.first {
                ($0["isa"] as? String) == "PBXNativeTarget" && ($0["name"] as? String) == "FineCoach"
            }
        )
        let listID = try XCTUnwrap(app["buildConfigurationList"] as? String)
        let list = try XCTUnwrap(objects[listID])
        let configurationIDs = try XCTUnwrap(list["buildConfigurations"] as? [String])
        var names: [String] = []
        for id in configurationIDs {
            let configuration = try XCTUnwrap(objects[id])
            names.append(try XCTUnwrap(configuration["name"] as? String))
            let settings = try XCTUnwrap(configuration["buildSettings"] as? [String: Any])
            XCTAssertEqual(settings["INFOPLIST_KEY_NSSupportsLiveActivities"] as? String, "YES")
        }
        XCTAssertEqual(names.sorted(), ["Debug", "Release"])
    }

    func testWidgetShellDoesNotAccessBusinessData() throws {
        let directory = iosRoot.appendingPathComponent("FineCoachWidgets")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil,
                errorHandler: { url, error in
                    XCTFail("Cannot enumerate \(url.lastPathComponent): \(error)")
                    return false
                }
            )
        )
        var count = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            count += 1
            let source = try String(contentsOf: url, encoding: .utf8)
            for forbidden in ["FileManager", "UserDefaults", "containerURL", "NSPersistentContainer", "CoreData"] {
                XCTAssertFalse(source.contains(forbidden), "\(url.lastPathComponent): \(forbidden)")
            }
        }
        XCTAssertGreaterThan(count, 0)
    }

    func testWidgetStudentNameRenderingIsPrivacySensitiveAndLockScreenFamiliesOmitNames() throws {
        let source = try String(
            contentsOf: iosRoot.appendingPathComponent("FineCoachWidgets/TodayWidget.swift"), encoding: .utf8)
        let nameLines = source.components(separatedBy: .newlines).filter {
            $0.contains("Text(") && $0.contains("studentDisplayName")
        }
        XCTAssertEqual(nameLines.count, 2)
        XCTAssertTrue(nameLines.allSatisfy { $0.contains(".privacySensitive()") })
        let inline = try XCTUnwrap(source.range(of: "private struct InlineTodayView"))
        let end = try XCTUnwrap(source.range(of: "private struct RectangularTodayView"))
        XCTAssertFalse(source[inline.lowerBound..<end.lowerBound].contains("studentDisplayName"))
        // R1 device evidence 2026-10-28: the locked lock screen did not redact the name.
        let home = try XCTUnwrap(source.range(of: "private struct HomeTodayView"))
        XCTAssertFalse(source[end.lowerBound..<home.lowerBound].contains("studentDisplayName"))
        // StandBy (no container background) did not redact either: names render only on the home screen.
        XCTAssertTrue(source.contains("@Environment(\\.showsWidgetContainerBackground) private var showsNames"))
        let homeSource = source[home.lowerBound...]
        XCTAssertEqual(homeSource.components(separatedBy: "if showsNames {").count - 1, 2)
    }

    func testWidgetsHaveOnlyReadOnlyWholeWidgetNavigation() throws {
        let directory = iosRoot.appendingPathComponent("FineCoachWidgets")
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for forbidden in ["Button(", "Link(", "AppIntent"] {
                XCTAssertFalse(source.contains(forbidden), url.lastPathComponent)
            }
        }
        let source = try String(contentsOf: directory.appendingPathComponent("TodayWidget.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains(".widgetURL(URL(string: \"finecoach://today\"))"))
    }

    private var iosRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SystemEntry/
            .deletingLastPathComponent()  // FineCoachTests/
            .deletingLastPathComponent()  // ios/
    }

    private func dictionary(at path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: iosRoot.appendingPathComponent(path))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any], path
        )
    }
}
