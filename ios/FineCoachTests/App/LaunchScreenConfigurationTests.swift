import Foundation
import XCTest

final class LaunchScreenConfigurationTests: XCTestCase {
    func testAppDebugAndReleaseUseLaunchStoryboard() throws {
        let data = try Data(contentsOf: iosRoot.appendingPathComponent("FineCoach.xcodeproj/project.pbxproj"))
        let project = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        let objects = try XCTUnwrap(project["objects"] as? [String: [String: Any]])
        let app = try XCTUnwrap(
            objects.values.first {
                ($0["isa"] as? String) == "PBXNativeTarget" && ($0["name"] as? String) == "FineCoach"
            })
        let list = try XCTUnwrap(objects[try XCTUnwrap(app["buildConfigurationList"] as? String)])
        let ids = try XCTUnwrap(list["buildConfigurations"] as? [String])
        var names: [String] = []
        for id in ids {
            let configuration = try XCTUnwrap(objects[id])
            names.append(try XCTUnwrap(configuration["name"] as? String))
            let settings = try XCTUnwrap(configuration["buildSettings"] as? [String: Any])
            XCTAssertEqual(settings["INFOPLIST_KEY_UILaunchStoryboardName"] as? String, "LaunchScreen")
            XCTAssertNil(settings["INFOPLIST_KEY_UILaunchScreen_Generation"])
        }
        XCTAssertEqual(names.sorted(), ["Debug", "Release"])
    }

    func testStoryboardIsLightWhiteBackgroundWithoutImageOrText() throws {
        let source = try source(at: "FineCoachApp/Resources/LaunchScreen.storyboard")
        let parser = XMLParser(data: Data(source.utf8))
        XCTAssertTrue(parser.parse(), parser.parserError?.localizedDescription ?? "")
        XCTAssertTrue(source.contains("launchScreen=\"YES\""))
        XCTAssertTrue(source.contains("userInterfaceStyle=\"light\""))
        XCTAssertTrue(source.contains("<color key=\"backgroundColor\" name=\"LaunchBackground\""))
        XCTAssertFalse(source.contains("<imageView"))
        XCTAssertFalse(source.contains("<label"))
        XCTAssertEqual(source.components(separatedBy: "<view ").count - 1, 1)
    }

    func testLaunchBackgroundIsUniversalSRGBWithoutDarkAppearance() throws {
        let json = try assetJSON("LaunchBackground.colorset")
        let colors = try XCTUnwrap(json["colors"] as? [[String: Any]])
        XCTAssertEqual(colors.count, 1)
        let entry = try XCTUnwrap(colors.first)
        XCTAssertEqual(entry["idiom"] as? String, "universal")
        XCTAssertNil(entry["appearances"])
        let color = try XCTUnwrap(entry["color"] as? [String: Any])
        XCTAssertEqual(color["color-space"] as? String, "srgb")
        let components = try XCTUnwrap(color["components"] as? [String: String])
        for (name, value) in ["red": 0xFF, "green": 0xFF, "blue": 0xFF] {
            let component = try XCTUnwrap(components[name])
            let actual: Double
            if component.hasPrefix("0x") {
                actual = Double(try XCTUnwrap(Int(component.dropFirst(2), radix: 16))) / 255
            } else {
                actual = try XCTUnwrap(Double(component))
            }
            XCTAssertEqual(actual, Double(value) / 255, accuracy: 0.000001)
        }
        XCTAssertEqual(try XCTUnwrap(Double(try XCTUnwrap(components["alpha"]))), 1)
    }

    func testLaunchOverlayAndIconAreRemoved() throws {
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: assetsRoot.appendingPathComponent("launch-icon.imageset").path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: iosRoot.appendingPathComponent("FineCoachApp/App/LaunchOverlay.swift").path))
        let root = try source(at: "FineCoachApp/App/AppRoot.swift")
        XCTAssertFalse(root.contains("LaunchOverlay"))
        XCTAssertFalse(root.contains("hasPresentedLaunch"))
        XCTAssertFalse(root.contains("launchOpacity"))
        XCTAssertTrue(root.contains("PrivacyCover()"))
        XCTAssertTrue(root.contains("systemOpenLayer(request, services: archiveServices)"))
    }

    private var iosRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var assetsRoot: URL {
        iosRoot.appendingPathComponent("FineCoachApp/Resources/Assets.xcassets")
    }

    private func source(at path: String) throws -> String {
        try String(contentsOf: iosRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private func assetJSON(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: assetsRoot.appendingPathComponent("\(path)/Contents.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
