import XCTest

/// T1 (design-system README §13): deterministic static scan of user-visible
/// number formats in the zh-Hans values of `Localizable.xcstrings` and the
/// string literals of `ios/FineCoachApp/**/*.swift`. The violation count is
/// the experience scorecard's dimension-11 "文案语气一致" metric; the gate is
/// zero.
///
/// Rules (regex-based on purpose, same stance as `DesignValueScanTests`):
/// - `N1`: a number, format specifier or interpolation directly followed by
///   a Latin unit (`120kg`, `%@kg`, `\(x)km`).
/// - `N3`: the same directly followed by a Chinese measure word
///   (`12组`, `\(m)分`, `%d课时`).
/// - `N4`: a weight × reps set that still ends in 「次」 (`× 8次`, `× %@ 次`).
/// - `N7`: a package balance counted in 「次」 instead of 「课时」.
///
/// Debug seed files hold fictional coach-typed notes, which are shown as
/// typed (README §13), so they are not scanned. Comment lines are skipped.
final class NumberFormatScanTests: XCTestCase {
    private struct Rule {
        let name: String
        let regex: NSRegularExpression

        init(_ name: String, _ pattern: String) {
            self.name = name
            // swiftlint:disable:next force_try
            self.regex = try! NSRegularExpression(pattern: pattern)
        }
    }

    /// A number, a format specifier (`%d`, `%@`, `%1$@`, `%lld`) or the end
    /// of a Swift interpolation `\(...)`.
    private static let numberEnd = #"(?:\d|%(?:\d+\$)?(?:@|d|lld|ld)|\\\([^()]*(?:\([^()]*\))?[^()]*\))"#

    private static let rules: [Rule] = [
        Rule("N1", numberEnd + #"(?:kg|lb|km|cm)(?![A-Za-z])"#),
        Rule("N3", numberEnd + #"(?:组|次|分钟|分|秒|课时|天|个|节)"#),
        Rule("N4", #"×\s*"# + numberEnd + #"\s*次"#),
        Rule("N7", #"剩余\s*"# + numberEnd + #"\s*次"#),
    ]

    func testUserVisibleNumbersFollowTheFormatRules() throws {
        let violations = try scanStrings() + scanSwiftSource()
        for violation in violations {
            print("NumberFormatScanTests: \(violation)")
        }
        XCTAssertEqual(
            violations.count, 0,
            "number formats violate design-system README §13 (see the printed list)"
        )
    }

    func testRulesCatchKnownViolationsAndAcceptTheRightForms() {
        let bad = ["120kg × 8", "120 kg × 8次", "%1$@ kg × %2$@ 次", "\\(m)分\\(s)秒", "课包剩余 %d 次", "%@km"]
        let good = ["120 kg × 8", "左 8 kg / 右 9 kg × 10", "20 次", "5 分 30 秒", "剩余 8 课时", "18%", "5m30s"]
        for text in bad {
            XCTAssertFalse(Self.violatedRules(in: text).isEmpty, "should flag: \(text)")
        }
        for text in good {
            XCTAssertEqual(Self.violatedRules(in: text), [], "should accept: \(text)")
        }
    }

    // MARK: - Scanning

    private static func violatedRules(in text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return rules.filter { $0.regex.firstMatch(in: text, range: range) != nil }.map(\.name)
    }

    private func scanStrings() throws -> [String] {
        let url = try appDirectory().appendingPathComponent("Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let catalog = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        var violations: [String] = []
        for (key, entry) in strings.sorted(by: { $0.key < $1.key }) {
            guard let entry = entry as? [String: Any],
                let localizations = entry["localizations"] as? [String: Any],
                let zh = localizations["zh-Hans"] as? [String: Any],
                let unit = zh["stringUnit"] as? [String: Any],
                let value = unit["value"] as? String
            else {
                continue
            }
            for rule in Self.violatedRules(in: value) {
                violations.append("Localizable.xcstrings \(key): \(rule): \(value)")
            }
        }
        return violations
    }

    private func scanSwiftSource() throws -> [String] {
        let appDir = try appDirectory()
        guard
            let enumerator = FileManager.default.enumerator(
                at: appDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }
        var violations: [String] = []
        for case let fileURL as URL in enumerator
        where fileURL.pathExtension == "swift" && !fileURL.lastPathComponent.contains("DebugSeed") {
            let lines = try String(contentsOf: fileURL, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                for rule in Self.violatedRules(in: line) {
                    violations.append("\(fileURL.lastPathComponent):\(index + 1): \(rule): \(trimmed)")
                }
            }
        }
        return violations
    }

    /// `ios/FineCoachApp`, resolved from this file's `#filePath` like
    /// `DesignValueScanTests`.
    private func appDirectory() throws -> URL {
        let appDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DesignSystem/
            .deletingLastPathComponent()  // FineCoachTests/
            .deletingLastPathComponent()  // ios/
            .appendingPathComponent("FineCoachApp")
        guard FileManager.default.fileExists(atPath: appDir.path) else {
            throw XCTSkip("cannot resolve ios/FineCoachApp from #filePath: \(appDir.path)")
        }
        return appDir
    }
}
