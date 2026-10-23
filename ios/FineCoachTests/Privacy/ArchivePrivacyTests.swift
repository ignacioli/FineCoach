import XCTest

@testable import FineCoach

/// T065 privacy self-check for M2 (NFR-001, NFR-002, NFR-005, AC-004, M2-FR-017). Static source
/// scans of the archive code plus one on-disk assertion; nothing is rendered. Each scan first
/// asserts that it found files, so an empty or moved folder cannot pass by default.
final class ArchivePrivacyTests: XCTestCase {
    private var appRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Privacy/
            .deletingLastPathComponent()  // FineCoachTests/
            .deletingLastPathComponent()  // ios/
            .appendingPathComponent("FineCoachApp")
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// `Core/Archive`, `Core/Application/Archive` and every `Features/Archive*` folder.
    private func archiveSources() throws -> [(name: String, text: String)] {
        var directories = [
            appRoot.appendingPathComponent("Core/Archive"),
            appRoot.appendingPathComponent("Core/Application/Archive"),
        ]
        let features = appRoot.appendingPathComponent("Features")
        directories += try FileManager.default.contentsOfDirectory(at: features, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Archive") }
        var sources: [(String, String)] = []
        for directory in directories {
            let files = try swiftFiles(in: directory)
            XCTAssertFalse(files.isEmpty, "\(directory.lastPathComponent) holds no Swift files")
            for file in files {
                sources.append(
                    (
                        "\(directory.lastPathComponent)/\(file.lastPathComponent)",
                        try String(contentsOf: file, encoding: .utf8)
                    ))
            }
        }
        return sources
    }

    private func featureSources(_ names: [String]) throws -> [(name: String, text: String)] {
        var sources: [(String, String)] = []
        for name in names {
            let files = try swiftFiles(in: appRoot.appendingPathComponent("Features/\(name)"))
            XCTAssertFalse(files.isEmpty, name)
            for file in files {
                sources.append(("\(name)/\(file.lastPathComponent)", try String(contentsOf: file, encoding: .utf8)))
            }
        }
        return sources
    }

    // MARK: NFR-001 no network

    func testArchiveSourcesUseNoNetworkAPI() throws {
        let sources = try archiveSources()
        XCTAssertGreaterThan(sources.count, 20)
        let forbidden = [
            "URLSession", "URLRequest", "URLConnection", "NSURLSession", "URLSessionConfiguration",
            "import Network", "NWConnection", "NWPathMonitor", "NWBrowser", "CFNetwork", "CFHTTP", "CFSocket",
            "SCNetworkReachability", "WKWebView", "import WebKit", "SFSafariViewController", "import SafariServices",
            "CloudKit", "MultipeerConnectivity", "NSNetService", "import Firebase", "Data(contentsOf: URL(string",
            "String(contentsOf: URL(string",
        ]
        for (name, text) in sources {
            for word in forbidden {
                XCTAssertFalse(text.contains(word), "\(name) must not use \(word)")
            }
        }
    }

    /// The only web address in the archive code is the fixed Creative Commons page shown under
    /// the attribution (M2-17), opened by the system on the user's tap.
    func testTheOnlyWebAddressInArchiveSourcesIsTheFixedLicensePage() throws {
        let pattern = try NSRegularExpression(pattern: "https?://[^\"\\s)]+")
        var found: [String] = []
        for (_, text) in try archiveSources() {
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                found.append(String(text[Range(match.range, in: text)!]))
            }
        }
        XCTAssertEqual(Set(found), ["https://creativecommons.org/licenses/by-sa/"])
    }

    // MARK: NFR-002 logs carry fixed event IDs only

    func testArchiveLogEventIdentifiersAreFixedArchiveTokens() {
        let events = AppLogEvent.allCases
        let archiveEvents = events.filter { String(describing: $0).hasPrefix("archive") }
        XCTAssertGreaterThanOrEqual(archiveEvents.count, 15)
        for event in archiveEvents {
            XCTAssertTrue(event.rawValue.hasPrefix("archive."), "\(event) must log as archive.*")
        }
        for event in events where event.rawValue.hasPrefix("archive.") {
            XCTAssertTrue(String(describing: event).hasPrefix("archive"), "\(event.rawValue)")
        }
    }

    func testArchiveLogCallsPassOnlyFixedEventsAndNeverInterpolateData() throws {
        var calls = 0
        let events = Dictionary(uniqueKeysWithValues: AppLogEvent.allCases.map { (String(describing: $0), $0) })
        let operations = Set(AppLogOperation.allCases.map { String(describing: $0) })
        let categories = Set(AppLogErrorCategory.allCases.map { String(describing: $0) })
        for (name, text) in try archiveSources() {
            // Nothing else may write to a log or the console.
            for word in [
                "print(", "NSLog(", "os_log(", "debugPrint(", "dump(", "Logger(subsystem", "import OSLog", "import os",
            ] {
                XCTAssertFalse(text.contains(word), "\(name) must not use \(word)")
            }
            for call in Self.loggerCalls(in: text) {
                calls += 1
                XCTAssertTrue(["info", "failure"].contains(call.method), "\(name): logger.\(call.method)")
                XCTAssertFalse(
                    call.arguments.contains("\""), "\(name): a log call holds a string literal: \(call.arguments)")
                XCTAssertFalse(call.arguments.contains("\\("), "\(name): a log call interpolates: \(call.arguments)")
                let arguments = call.arguments
                    .split(separator: ",", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                // Every argument is a labelled or bare leading-dot case: `.archiveX`, `operation: .y`.
                for argument in arguments {
                    let value =
                        argument.split(separator: ":", maxSplits: 1).last.map {
                            $0.trimmingCharacters(in: .whitespaces)
                        } ?? ""
                    XCTAssertTrue(value.hasPrefix("."), "\(name): argument \(argument) is not a fixed case")
                    let caseName = String(value.dropFirst())
                    if argument.hasPrefix("operation:") {
                        XCTAssertTrue(operations.contains(caseName), "\(name): \(caseName)")
                    } else if argument.hasPrefix("category:") {
                        XCTAssertTrue(categories.contains(caseName), "\(name): \(caseName)")
                    } else {
                        XCTAssertTrue(
                            events[caseName]?.rawValue.hasPrefix("archive.") == true,
                            "\(name): \(caseName) is not an archive.* event")
                    }
                }
            }
        }
        XCTAssertGreaterThanOrEqual(calls, 20, "the scan found too few log calls to be meaningful")
    }

    /// Every `logger.<method>(...)` / `.logger.<method>(...)` call with its balanced argument text.
    private static func loggerCalls(in text: String) -> [(method: String, arguments: String)] {
        let pattern = try! NSRegularExpression(pattern: "logger\\.([A-Za-z]+)\\(")
        let range = NSRange(text.startIndex..., in: text)
        var results: [(String, String)] = []
        for match in pattern.matches(in: text, range: range) {
            let method = String(text[Range(match.range(at: 1), in: text)!])
            var index = Range(match.range, in: text)!.upperBound
            var depth = 1
            let start = index
            while index < text.endIndex, depth > 0 {
                if text[index] == "(" { depth += 1 }
                if text[index] == ")" { depth -= 1 }
                if depth > 0 { index = text.index(after: index) }
            }
            results.append((method, String(text[start..<index])))
        }
        return results
    }

    // MARK: Viewer storage is excluded from backup

    func testArchiveViewerDirectoryAndEveryFileInItAreExcludedFromBackup() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchivePrivacyTests-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent(ArchiveSnapshotStore.directoryName, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }

        let store = ArchiveSnapshotStore(rootURL: root)
        try store.commit(snapshot: ArchiveFixtures.fullSnapshot())
        try store.writeDisplaySettings(ArchiveDisplaySettings(weightUnit: .lb, lengthUnit: .inch, density: .compact))

        XCTAssertEqual(ArchiveSnapshotStore.directoryName, "ArchiveViewer")
        var urls = [root]
        urls += try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)).compactMap {
            $0 as? URL
        }
        XCTAssertGreaterThanOrEqual(
            urls.count, 6, "root, current.json, generations, one generation, snapshot.bin, settings")
        for url in urls {
            let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
            XCTAssertEqual(values.isExcludedFromBackup, true, "\(url.lastPathComponent) is not excluded from backup")
        }
    }

    // MARK: AC-004 / M2-FR-017 archive password fields

    func testArchivePasswordFieldsDeclareNoPasswordContentTypeAndTurnAutocorrectionOff() throws {
        let sources = try featureSources(["ArchiveExport", "ArchiveImport"])
        let fieldFile = "ArchiveExport/ArchivePasswordField.swift"
        var fieldUses = 0
        for (name, text) in sources {
            // A leading-dot content type (`.password`), not a property access like `model.password`.
            let contentType = try NSRegularExpression(
                pattern:
                    "(?<![A-Za-z0-9_])\\.(password|newPassword|oneTimeCode)\\b|UITextContentType\\.(password|newPassword|oneTimeCode)\\b|rawValue: \"(password|newPassword|oneTimeCode)\""
            )
            XCTAssertNil(
                contentType.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                "\(name) declares a password content type")
            if name != fieldFile {
                // A masked entry anywhere else would bypass the shared configuration.
                XCTAssertFalse(text.contains("SecureField"), "\(name) builds its own secure field")
                XCTAssertFalse(text.contains("isSecure: true"), "\(name) builds its own secure field")
                XCTAssertFalse(text.contains(".textContentType("), "\(name) sets its own content type")
                fieldUses += text.components(separatedBy: "ArchivePasswordField(").count - 1
            }
        }
        // M2-05 (two fields) and M2-08 / M2-19 (one each).
        XCTAssertEqual(fieldUses, 4)
        let field = try XCTUnwrap(sources.first { $0.name == fieldFile }).text
        XCTAssertTrue(field.contains("isSecure: true"))
        XCTAssertTrue(field.contains(".textContentType(UITextContentType(rawValue: \"\"))"))
        XCTAssertTrue(field.contains(".autocorrectionDisabled(true)"))
        XCTAssertTrue(field.contains(".textInputAutocapitalization(.never)"))
        XCTAssertTrue(field.contains(".archivePasswordEntry()"))
    }

    // MARK: NFR-005 status is never colour alone

    /// Status colours reach the screen only through `FCStatusLabel`, `FCInlineResult` or the
    /// `M2-FACT-ROW` (`ArchiveFactRow`, which passes the colour to a badge that also carries a
    /// symbol and the text). No archive view colours text with a status colour or a raw system
    /// colour on its own.
    func testArchiveStatusIsPresentedOnlyThroughTheSharedStatusComponents() throws {
        let viewFolders = ["ArchiveExport/", "ArchiveImport/", "ArchiveViewer/"]
        let views = try archiveSources().filter { source in
            viewFolders.contains { source.name.hasPrefix($0) }
        }
        XCTAssertGreaterThan(views.count, 15)
        let factRowFile = "ArchiveExport/ArchiveDeliveryWarningView.swift"
        for (name, text) in views {
            for word in [
                ".foregroundStyle(.red", ".foregroundStyle(.orange", ".foregroundStyle(.yellow",
                ".foregroundStyle(.green", ".foregroundColor(", "Color.red", "Color.orange", "Color.green",
                "Color.yellow",
                "Color(.system", "UIColor.system",
            ] {
                XCTAssertFalse(text.contains(word), "\(name) hand-colours with \(word)")
            }
            if name != factRowFile {
                XCTAssertFalse(text.contains("FCSemanticColors.status"), "\(name) uses a status colour directly")
                XCTAssertFalse(text.contains("FCStatusBadge("), "\(name) draws its own status badge")
            }
        }
        let factRow = try XCTUnwrap(views.first { $0.name == factRowFile }).text
        XCTAssertTrue(factRow.contains("struct ArchiveFactRow"))
        XCTAssertTrue(factRow.contains("FCStatusBadge("), "the fact row pairs the colour with a symbol")
        // The component itself pairs every colour with an icon and text.
        let statusLabel = try String(
            contentsOf: appRoot.appendingPathComponent("DesignSystem/Components/FCStatusLabel.swift"), encoding: .utf8)
        XCTAssertTrue(statusLabel.contains("public init(text: String, symbolName: String"))
    }
}
