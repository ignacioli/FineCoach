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

    func testStoryboardUsesApprovedResourcesAndSuperviewLayoutWithoutText() throws {
        let source = try source(at: "FineCoachApp/Resources/LaunchScreen.storyboard")
        let parser = XMLParser(data: Data(source.utf8))
        XCTAssertTrue(parser.parse(), parser.parserError?.localizedDescription ?? "")
        XCTAssertTrue(source.contains("launchScreen=\"YES\""))
        XCTAssertTrue(source.contains("userInterfaceStyle=\"light\""))
        XCTAssertTrue(source.contains("<color key=\"backgroundColor\" name=\"LaunchBackground\""))
        XCTAssertTrue(source.contains("image=\"launch-mascot\""))
        XCTAssertTrue(source.contains("contentMode=\"scaleAspectFit\""))
        XCTAssertEqual(source.components(separatedBy: "<imageView ").count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: "<view ").count - 1, 1)
        XCTAssertFalse(source.contains("<label"))
        for attribute in ["leading", "trailing", "bottom"] {
            XCTAssertTrue(source.contains("secondItem=\"launch-view\" secondAttribute=\"\(attribute)\""))
        }
        XCTAssertTrue(
            source.contains("firstAttribute=\"height\" secondItem=\"launch-image\" secondAttribute=\"width\""))
        XCTAssertFalse(source.contains("safeArea\""))
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
        for (name, value) in ["red": 0xF8, "green": 0xF0, "blue": 0xE3] {
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

    func testLaunchMascotIsUnmodifiedApprovedAsset() throws {
        let json = try assetJSON("launch-mascot.imageset")
        let images = try XCTUnwrap(json["images"] as? [[String: Any]])
        XCTAssertEqual(images.count, 1)
        let entry = try XCTUnwrap(images.first)
        XCTAssertEqual(entry["idiom"] as? String, "universal")
        let filename = try XCTUnwrap(entry["filename"] as? String)
        let copy = try Data(contentsOf: assetsRoot.appendingPathComponent("launch-mascot.imageset/\(filename)"))
        let original = try Data(
            contentsOf: iosRoot.deletingLastPathComponent().appendingPathComponent(
                "design/design-system/assets/app-icon-light.png"))
        XCTAssertEqual(copy, original)
    }

    func testOverlayIsDecorativeFullWidthAndDoesNotAccessData() throws {
        let source = try source(at: "FineCoachApp/App/LaunchOverlay.swift")
        for required in [
            "FCSemanticColors.surfaceLaunch", "Image(\"launch-mascot\")", ".resizable()", ".scaledToFit()",
            "ZStack(alignment: .bottom)", ".frame(width: geometry.size.width, height: geometry.size.width)",
            ".ignoresSafeArea()", ".accessibilityHidden(true)", ".allowsHitTesting(false)",
        ] {
            XCTAssertTrue(source.contains(required), required)
        }
        for forbidden in ["@EnvironmentObject", "CoreData", "FileManager", "UserDefaults", "Button(", ".task"] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    func testRootSkipsReducedMotionAndUsesOneProcessLaunchAboveContentBelowPrivacyCover() throws {
        let source = try source(at: "FineCoachApp/App/AppRoot.swift")
        for required in [
            "@Environment(\\.accessibilityReduceMotion)", "private static var hasPresentedLaunch = false",
            "@State private var showsLaunchOverlay = !Self.hasPresentedLaunch",
            "if showsLaunchOverlay && !reduceMotion {", "guard !Self.hasPresentedLaunch else",
            "Self.hasPresentedLaunch = true", "guard !reduceMotion else { return }",
            "Task.sleep(for: .seconds(0.3))", "FCMotion.curveStandard(duration: FCMotion.durationFast)",
            "launchOpacity = 0", "defer { showsLaunchOverlay = false }",
        ] {
            XCTAssertTrue(source.contains(required), required)
        }
        let content = try XCTUnwrap(source.range(of: "systemOpenLayer(request, services: archiveServices)"))
        let overlay = try XCTUnwrap(source.range(of: "LaunchOverlay()"))
        let privacy = try XCTUnwrap(source.range(of: "PrivacyCover()"))
        XCTAssertLessThan(content.lowerBound, overlay.lowerBound)
        XCTAssertLessThan(overlay.lowerBound, privacy.lowerBound)
        let delay = try XCTUnwrap(source.range(of: ".task {"))
        let install = try XCTUnwrap(source.range(of: "guard installState == nil"))
        XCTAssertFalse(source[delay.lowerBound..<install.lowerBound].contains("resolveInstallState"))
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
