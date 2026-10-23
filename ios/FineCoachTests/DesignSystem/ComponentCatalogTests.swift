import XCTest

/// L1 catalog gate (`design/design-system/components.md` §1.4): the component
/// index (§3) and the design-system code cannot drift apart silently.
/// - Every public `FC*` type under `ios/FineCoachApp/DesignSystem/` is listed
///   in the index's code column, and every listed type exists — so a new or
///   renamed component cannot ship without an anatomy entry.
/// - Every `DS-*` ID in the index has its own anatomy heading.
/// Plain source/doc scan; no view rendering.
final class ComponentCatalogTests: XCTestCase {
    private static let publicTypePattern = #"public\s+(?:struct|enum)\s+(FC[A-Za-z0-9]+)"#
    private static let codeTokenPattern = #"`(FC[A-Za-z0-9]+)`"#
    private static let componentIDPattern = #"`(DS-[A-Z0-9-]+)`"#

    func testIndexListsExactlyThePublicDesignSystemTypes() throws {
        let codeTypes = try publicDesignSystemTypes()
        let indexTypes = try indexRows().reduce(into: Set<String>()) { result, row in
            result.formUnion(Self.matches(Self.codeTokenPattern, in: row.codeColumn))
        }

        XCTAssertFalse(codeTypes.isEmpty, "found no public FC* types; scan path is wrong")
        XCTAssertEqual(
            codeTypes.subtracting(indexTypes).sorted(), [],
            "public design-system types missing from components.md §3; add an anatomy entry before shipping them"
        )
        XCTAssertEqual(
            indexTypes.subtracting(codeTypes).sorted(), [],
            "components.md §3 lists types that no longer exist in DesignSystem/"
        )
    }

    func testEveryIndexedComponentHasAnAnatomyHeading() throws {
        let doc = try componentsDoc()
        let headingIDs = doc.components(separatedBy: "\n")
            .filter { $0.hasPrefix("#") }
            .reduce(into: Set<String>()) { $0.formUnion(Self.matches(Self.componentIDPattern, in: $1)) }

        let rows = try indexRows()
        XCTAssertFalse(rows.isEmpty, "components.md §3 index table not found")
        for row in rows {
            XCTAssertTrue(headingIDs.contains(row.id), "\(row.id) is indexed in §3 but has no anatomy heading")
        }
    }

    func testNewRecordBadgeUsesLocalizedTextAndDelegatesAccessibilityToItsRow() throws {
        let url = repositoryRoot().appendingPathComponent(
            "ios/FineCoachApp/DesignSystem/Components/FCNewRecordBadge.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("String(localized: \"session.set.newRecord\")"))
        XCTAssertTrue(source.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(source.contains(".fcFont(.sectionLabel)"))
        XCTAssertTrue(source.contains("FCSemanticColors.surfaceSelected, in: Capsule()"))
        XCTAssertTrue(source.contains("FCSemanticColors.actionPrimary"))
    }

    func testNewRecordRowKeepsBadgeAndConfirmationHapticHasOneStableSource() throws {
        let row = try source("ios/FineCoachApp/DesignSystem/Components/FCSetRow.swift")
        XCTAssertTrue(row.contains("self.isNewRecord = isNewRecord && state == .completed"))
        XCTAssertTrue(row.contains(".accessibilityLabel(Text(accessibilityText))"))
        XCTAssertTrue(row.contains("String(localized: \"session.set.newRecord\")"))
        XCTAssertTrue(row.contains("ViewThatFits(in: .horizontal)"))
        // The row must not own confirmation feedback: the primary confirm path
        // inserts an already-completed row, so a row-state trigger never fires.
        XCTAssertFalse(row.contains("sensoryFeedback"))
        XCTAssertFalse(row.contains("isRecordImprovement"))

        let session = try source("ios/FineCoachApp/Features/ActiveSession/ActiveSessionView.swift")
        XCTAssertTrue(session.contains(".sensoryFeedback(trigger: viewModel.confirmationFeedback)"))
        XCTAssertTrue(session.contains("guard let feedback else { return nil }"))
        XCTAssertTrue(session.contains("feedback.isRecordImprovement ? .impact(weight: .heavy) : .success"))
        XCTAssertEqual(
            session.components(separatedBy: ".sensoryFeedback(trigger: viewModel.confirmationFeedback)").count - 1, 1,
            "the training page must have exactly one confirmation haptic source")

        let editor = try source("ios/FineCoachApp/Features/ActiveSession/SetEditor.swift")
        XCTAssertFalse(editor.contains("sensoryFeedback"))
    }

    // MARK: - DS-HERO-CARD multi-row (W-08, approved 2026-10-22)

    func testHeroCardMultiRowBuildsOneIdentifiedButtonPerRow() throws {
        let source = try source("ios/FineCoachApp/DesignSystem/Components/FCHeroCard.swift")
        let start = try XCTUnwrap(source.range(of: "private func multiRowCard"))
        let multi = String(source[start.lowerBound...])
        XCTAssertTrue(multi.contains("ForEach(rows)"))
        XCTAssertEqual(
            multi.components(separatedBy: "Button {").count - 1, 1,
            "the multi-row variant must create exactly one Button per row, not one card-level Button")
        XCTAssertTrue(multi.contains(".accessibilityIdentifier(row.accessibilityIdentifier)"))
        XCTAssertTrue(multi.contains("minHeight: 44"))
    }

    func testHeroCardMultiRowCountFollowsRowsAndEmptyIsSuppressed() throws {
        let hero = try source("ios/FineCoachApp/DesignSystem/Components/FCHeroCard.swift")
        XCTAssertTrue(hero.contains("if isMultiRow"))
        XCTAssertTrue(hero.contains("if rows.isEmpty"))
        XCTAssertTrue(hero.contains("EmptyView()"))
        let start = try XCTUnwrap(hero.range(of: "private func multiRowCard"))
        let multi = String(hero[start.lowerBound...])
        XCTAssertTrue(multi.contains("ForEach(rows)"))
        XCTAssertTrue(multi.contains("if row.id != rows.first?.id"))

        let today = try source("ios/FineCoachApp/Features/Today/TodayView.swift")
        XCTAssertTrue(today.contains("if !viewModel.inProgress.isEmpty"))
        XCTAssertTrue(today.contains("summaries.map { summary in"))
        XCTAssertTrue(today.contains("summaries.count == 1, let summary = summaries.first"))
    }

    // MARK: - Sources

    private struct IndexRow {
        let id: String
        let codeColumn: String
    }

    /// Rows of the §3 table: `| \`DS-…\` | code | source | consumers | status |`.
    private func indexRows() throws -> [IndexRow] {
        let lines = try componentsDoc().components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.hasPrefix("## 3.") }) else { return [] }
        let end = lines[(start + 1)...].firstIndex(where: { $0.hasPrefix("## ") }) ?? lines.endIndex
        return lines[start..<end].compactMap { line in
            let columns = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard line.hasPrefix("| `DS-"), columns.count > 2,
                let id = Self.matches(Self.componentIDPattern, in: columns[1]).first
            else { return nil }
            return IndexRow(id: id, codeColumn: columns[2])
        }
    }

    private func publicDesignSystemTypes() throws -> Set<String> {
        let directory = repositoryRoot().appendingPathComponent("ios/FineCoachApp/DesignSystem")
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw XCTSkip("cannot enumerate \(directory.path)")
        }
        var types = Set<String>()
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            types.formUnion(Self.matches(Self.publicTypePattern, in: source))
        }
        return types
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func componentsDoc() throws -> String {
        let url = repositoryRoot().appendingPathComponent("design/design-system/components.md")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("cannot resolve components.md from #filePath in this environment: \(url.path)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// This file lives at `ios/FineCoachTests/DesignSystem/`; the simulator
    /// can read the host filesystem (same approach as `DesignValueScanTests`).
    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DesignSystem/
            .deletingLastPathComponent()  // FineCoachTests/
            .deletingLastPathComponent()  // ios/
            .deletingLastPathComponent()  // repository root
    }

    private static func matches(_ pattern: String, in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(
            regex.matches(in: text, range: range).compactMap { match in
                Range(match.range(at: 1), in: text).map { String(text[$0]) }
            })
    }
}
