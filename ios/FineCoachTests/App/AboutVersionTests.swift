import Foundation
import XCTest

@testable import FineCoach

/// 42「关于」/「源代码」: the version row reads the generated Info.plist values,
/// and the source-code row opens the public repository.
final class AboutVersionTests: XCTestCase {
    func testHostAppInfoPlistCarriesTheAgreedVersionAndBuild() {
        // The unit-test target is hosted by FineCoach.app, so `Bundle.main` is
        // the app bundle rather than the .xctest bundle.
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.finecoach.app")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, "0.2.0")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String, "1")
    }

    func testSourceCodeURLPointsAtThePublicRepository() {
        XCTAssertEqual(SettingsView.sourceCodeURL.absoluteString, "https://github.com/ignacioli/FineCoach")
    }
}
