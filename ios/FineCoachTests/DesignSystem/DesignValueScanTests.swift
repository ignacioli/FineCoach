import XCTest

/// T062: deterministic static scan over `ios/FineCoachApp/**/*.swift`, excluding
/// `DesignSystem/` (which legitimately defines these raw values) but including shell
/// files like `App/RootNavigation.swift`, for source that bypasses the design-system
/// tokens (plan §9-8).
///
/// Rule set (kept intentionally small and regex-based, not a full Swift parser):
/// - `colorLiteral`: `Color(red:…)`, `Color(hex:…)`, `UIColor(…)`, a SwiftUI system
///   color used as a `Color` static member (`Color.red`/`.secondary`/`.primary`/…), or
///   that same system color passed to `.foregroundStyle`/`.foregroundColor`.
/// - `systemFont`: `.font(.something)` — any SwiftUI built-in `Font` static member
///   (`.body`, `.headline`, `.system(...)`, …) used instead of `.fcFont(_:)`.
/// - `spacingLiteral`: a bare non-zero numeric literal passed to `.padding(...)`
///   (single- or edge+value form) or to a `spacing:` parameter (`HStack(spacing: 8)`,
///   …). A literal `0` means "no gap" rather than a design value, so it is exempt
///   (design system §4, owner decision 2026-09-28 in T068).
/// - `cornerRadiusLiteral`: a bare numeric literal passed to `cornerRadius:` (e.g.
///   `RoundedRectangle(cornerRadius: 14)`) or `.cornerRadius(...)`.
///
/// Hard gate since T068: feature source MUST have zero violations (the T062 baseline
/// of 131 was migrated onto T054–T059's tokens/components in T068).
final class DesignValueScanTests: XCTestCase {
    private struct Violation: Comparable {
        let relativePath: String
        let line: Int
        let rule: String
        let text: String

        static func < (lhs: Violation, rhs: Violation) -> Bool {
            if lhs.relativePath != rhs.relativePath { return lhs.relativePath < rhs.relativePath }
            if lhs.line != rhs.line { return lhs.line < rhs.line }
            return lhs.rule < rhs.rule
        }
    }

    private struct ScanRule {
        let name: String
        let regex: NSRegularExpression

        init(name: String, pattern: String) {
            self.name = name
            // swiftlint:disable:next force_try
            self.regex = try! NSRegularExpression(pattern: pattern)
        }
    }

    private static let rules: [ScanRule] = [
        ScanRule(
            name: "colorLiteral",
            pattern:
                #"Color\(red:|Color\(hex:|UIColor\(|Color\.(red|blue|green|gray|yellow|orange|purple|pink|black|white|secondary|primary|accentColor)\b|\.foregroundStyle\(\.(secondary|primary|red|blue|green|gray|yellow|orange|purple|pink|black|white)\)|\.foregroundColor\(\.(secondary|primary|red|blue|green|gray|yellow|orange|purple|pink|black|white)\)"#
        ),
        ScanRule(
            name: "systemFont",
            pattern: #"\.font\(\.\w"#
        ),
        ScanRule(
            name: "spacingLiteral",
            pattern: #"\.padding\(\s*(?!0(?![.\d]))\d|\.padding\(\.\w+,\s*(?!0(?![.\d]))\d|spacing:\s*(?!0(?![.\d]))\d"#
        ),
        ScanRule(
            name: "cornerRadiusLiteral",
            pattern: #"cornerRadius:\s*\d|\.cornerRadius\(\s*\d"#
        ),
    ]

    func testFeatureSourceHasNoDesignValueViolations() throws {
        let violations = try scanFeatureSource()

        var byRule: [String: Int] = [:]
        for v in violations { byRule[v.rule, default: 0] += 1 }
        var byFile: [String: Int] = [:]
        for v in violations { byFile[v.relativePath, default: 0] += 1 }
        let topFiles = byFile.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(5)

        print("DesignValueScanTests: \(violations.count) violation(s)")
        print("DesignValueScanTests: by rule -> \(byRule.sorted { $0.key < $1.key })")
        print("DesignValueScanTests: top files -> \(Array(topFiles))")
        for v in violations {
            print("\(v.relativePath):\(v.line): \(v.rule): \(v.text)")
        }

        XCTAssertEqual(
            violations.count, 0,
            "feature source bypasses design-system tokens; use FCPrimitives / "
                + "FCSemanticColors / .fcFont(_:) instead (see the printed list)"
        )
    }

    // MARK: - Scanning

    private func scanFeatureSource() throws -> [Violation] {
        let appDir = try featureAppDirectory()
        let swiftFiles = try enumerateSwiftFiles(under: appDir)
            .filter { !$0.path.contains("/DesignSystem/") }

        var violations: [Violation] = []
        for fileURL in swiftFiles {
            let relativePath = String(fileURL.path.dropFirst(appDir.deletingLastPathComponent().path.count + 1))
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = contents.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
                for rule in Self.rules {
                    if rule.regex.firstMatch(in: line, range: nsRange) != nil {
                        violations.append(
                            Violation(relativePath: relativePath, line: index + 1, rule: rule.name, text: trimmed)
                        )
                    }
                }
            }
        }
        return violations.sorted()
    }

    /// Locates `ios/FineCoachApp` from this test file's own `#filePath` (this file
    /// lives at `ios/FineCoachTests/DesignSystem/`, three path components below
    /// `ios/`) — the simulator process can read the host filesystem directly (it is
    /// not a separate VM), and this repo already relies on that (see
    /// `BodyMeasurementComparisonTests.codeLines(of:)`).
    private func featureAppDirectory() throws -> URL {
        let iosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DesignSystem/
            .deletingLastPathComponent()  // FineCoachTests/
            .deletingLastPathComponent()  // ios/
        let appDir = iosRoot.appendingPathComponent("FineCoachApp")
        guard FileManager.default.fileExists(atPath: appDir.path) else {
            throw XCTSkip("cannot resolve ios/FineCoachApp from #filePath in this environment: \(appDir.path)")
        }
        return appDir
    }

    private func enumerateSwiftFiles(under directory: URL) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }
        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            result.append(url)
        }
        return result
    }
}
