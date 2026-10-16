import FineCoach
import XCTest

/// T050a (NFR-002): the OSLog surface carries only fixed event / operation /
/// error-category identifiers. `AppLogger` accepts nothing but those enums, so
/// a name, body measurement or schedule cannot reach the log through it; this
/// test pins the identifier shape and that nothing else in the app writes to
/// a log or console. Not a runtime capture of the unified log.
final class LogSurfaceTests: XCTestCase {
    func testEveryLogIdentifierIsAFixedToken() throws {
        let identifiers =
            AppLogEvent.allCases.map(\.rawValue)
            + AppLogOperation.allCases.map(\.rawValue)
            + AppLogErrorCategory.allCases.map(\.rawValue)
        XCTAssertFalse(identifiers.isEmpty)
        let token = try NSRegularExpression(pattern: "^[A-Za-z][A-Za-z0-9_]*(\\.[a-z][a-z0-9_]*)?$")
        for identifier in identifiers {
            let range = NSRange(identifier.startIndex..., in: identifier)
            XCTAssertNotNil(
                token.firstMatch(in: identifier, range: range), "\(identifier) is not a fixed identifier token")
        }
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "log identifiers must be unique")
    }

    func testOnlyAppLoggerAndTheT116HarnessWriteToLogsOrConsole() throws {
        // `T116PerformanceHarness` prints synthetic-data timing lines from an
        // isolated store (its own file header); the T052 finding about
        // shipping it in Release is tracked separately.
        let allowed: Set<String> = ["AppLogger.swift", "T116PerformanceHarness.swift"]
        let sinks = ["Logger(", "os_log", "NSLog", "print(", "debugPrint(", "dump(", "fputs(", "standardError"]
        let appRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Privacy/
            .deletingLastPathComponent()  // FineCoachTests/
            .deletingLastPathComponent()  // ios/
            .appendingPathComponent("FineCoachApp")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil))
        var violations: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard !allowed.contains(url.lastPathComponent) else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            for sink in sinks where source.contains(sink) {
                violations.append("\(url.lastPathComponent): \(sink)")
            }
        }
        XCTAssertTrue(violations.isEmpty, "log/console sinks outside AppLogger: \(violations.sorted())")
    }

    func testAppLoggerMessagesInterpolateOnlyPublicFixedTokens() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FineCoachApp/Core/Platform/AppLogger.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let interpolations = source.components(separatedBy: "\\(").dropFirst()
        XCTAssertFalse(interpolations.isEmpty)
        for piece in interpolations {
            let expression = piece.prefix { $0 != ")" }
            XCTAssertTrue(
                expression.hasSuffix("rawValue, privacy: .public")
                    || expression.hasSuffix(".rawValue, privacy: .public"),
                "AppLogger interpolates something other than an enum rawValue: \(expression)"
            )
        }
    }
}
