import XCTest

/// T050c (NFR-002 / NFR-007): the shipped capability manifests declare no
/// network, Contacts, Photos, camera, location or telemetry capability, and
/// no third-party package or networking API is linked. Static scan of
/// `FineCoach-Info.plist`, `FineCoach.entitlements`, `PrivacyInfo.xcprivacy`,
/// the project file and the app sources; it proves what is declared, not
/// runtime behaviour (that stays a device / binary check in T051).
final class CapabilityManifestTests: XCTestCase {
    private var iosRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Privacy/
            .deletingLastPathComponent() // FineCoachTests/
            .deletingLastPathComponent() // ios/
    }

    private func plist(_ name: String) throws -> [String: Any] {
        let url = iosRoot.appendingPathComponent("FineCoachApp").appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(object as? [String: Any], "\(name) must be a dictionary plist")
    }

    func testInfoPlistDeclaresNoNetworkOrPrivacySensitiveAccess() throws {
        let keys = try plist("FineCoach-Info.plist").keys
        let forbidden = keys.filter {
            $0.hasSuffix("UsageDescription")
                || $0.hasPrefix("NSAppTransportSecurity")
                || $0 == "NSBonjourServices"
                || $0 == "NSLocalNetworkUsageDescription"
                || $0 == "UIBackgroundModes"
        }
        XCTAssertTrue(forbidden.isEmpty, "Info.plist declares \(forbidden.sorted())")
    }

    func testEntitlementsDeclareNoCapabilities() throws {
        let entitlements = try plist("FineCoach.entitlements")
        XCTAssertTrue(entitlements.isEmpty, "entitlements declare \(entitlements.keys.sorted())")
    }

    func testPrivacyManifestDeclaresNoTrackingOrCollection() throws {
        let manifest = try plist("PrivacyInfo.xcprivacy")
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
    }

    func testProjectGeneratesNoUsageDescriptionsAndLinksNoPackages() throws {
        let project = try String(
            contentsOf: iosRoot.appendingPathComponent("FineCoach.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        XCTAssertFalse(project.contains("UsageDescription"), "project generates a usage description")
        XCTAssertFalse(project.contains("XCRemoteSwiftPackageReference"), "remote Swift package linked")
        XCTAssertFalse(project.contains("XCLocalSwiftPackageReference"), "local Swift package linked")
    }

    func testAppSourcesImportNoNetworkOrSensitiveFrameworks() throws {
        let forbiddenImports: Set<String> = [
            "Network", "NetworkExtension", "CFNetwork", "WebKit", "SafariServices",
            "EventKit", "EventKitUI", "Contacts", "ContactsUI", "Photos", "PhotosUI", "AVFoundation", "CoreLocation",
            "CloudKit", "MetricKit", "AdSupport", "AppTrackingTransparency", "StoreKit",
            "FirebaseCore", "FirebaseAnalytics", "FirebaseCrashlytics", "Sentry", "Amplitude", "Mixpanel",
        ]
        let forbiddenAPIs = ["URLSession", "NWConnection", "URLRequest"]
        let appRoot = iosRoot.appendingPathComponent("FineCoachApp")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil))
        var violations: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for line in source.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("import "), let module = trimmed.dropFirst(7).split(separator: " ").first,
                    forbiddenImports.contains(String(module))
                {
                    violations.append("\(url.lastPathComponent): import \(module)")
                }
            }
            for api in forbiddenAPIs where source.contains(api) {
                violations.append("\(url.lastPathComponent): \(api)")
            }
        }
        XCTAssertTrue(violations.isEmpty, "forbidden usage: \(violations.sorted())")
    }

    /// T019 / M1B-FR-003: the calendar is the app's own month view; there is no
    /// system calendar sync (no EventKit, checked above) and no week or day view.
    func testNoWeekOrDayViewScreens() throws {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: iosRoot.appendingPathComponent("FineCoachApp/Features"), includingPropertiesForKeys: nil))
        let screens = enumerator.compactMap { ($0 as? URL)?.lastPathComponent }
            .filter { $0.hasSuffix(".swift") && ($0.contains("WeekView") || $0.contains("DayView")) }
        XCTAssertTrue(screens.isEmpty, "week/day view screens are out of scope: \(screens)")
    }
}
