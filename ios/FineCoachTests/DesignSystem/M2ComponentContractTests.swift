import FineCoach
import XCTest

/// M2 Phase 1 (T009): the "可自动" invariants of components.md §4.7, as pure
/// logic checks on the public component types and plain source scans of the
/// component files. No view rendering and no view inspection — layout, Dynamic
/// Type wrapping and the stacked-dialog look stay human walkthrough items
/// (components.md §1.4).
final class M2ComponentContractTests: XCTestCase {
    // MARK: - DS-PAGE-HEADER

    func testPageHeaderTitleIsAHeaderAndTrailingActionHasA44ptHitArea() throws {
        let source = try componentSource("FCPageHeader.swift")
        XCTAssertTrue(source.contains(".accessibilityAddTraits(.isHeader)"), "title must carry the header trait")
        XCTAssertTrue(source.contains(".frame(minWidth: 44, minHeight: 44)"), "trailing action needs a 44x44 hit area")
        XCTAssertTrue(source.contains("FCSemanticColors.textDisabled"), "disabled action uses text.disabled")
    }

    // MARK: - DS-HUB-ROW

    @MainActor
    func testHubRowOnlyActionModeIsTappable() {
        XCTAssertTrue(FCHubRow(icon: .symbol("bell"), title: "t", mode: .action {}).isTappable)
        XCTAssertFalse(FCHubRow(icon: .symbol("bell"), title: "t", mode: .informational).isTappable)
        XCTAssertFalse(FCHubRow(icon: .symbol("bell"), title: "t", mode: .unavailable(reason: "r")).isTappable)
    }

    func testHubRowSourceKeepsUnavailableActionFreeAndCombinesAccessibility() throws {
        let source = try componentSource("FCHubRow.swift")
        // Only the `.action` case builds a Button; the other modes render bare content.
        XCTAssertEqual(source.components(separatedBy: "Button(action:").count - 1, 1)
        XCTAssertTrue(source.contains("case .informational, .unavailable:\n            content"))
        XCTAssertTrue(source.contains(".accessibilityElement(children: .combine)"), "row must read as one element")
        XCTAssertTrue(source.contains("minHeight: 64"))
        // `›` only when tappable.
        XCTAssertTrue(source.contains("if isTappable {\n                FCSymbol(.forward)"))
    }

    // MARK: - DS-INLINE-RESULT

    func testInlineResultHasExactlyThreeVariantsEachWithAGlyph() {
        XCTAssertEqual(FCInlineResult.Variant.allCases.count, 3)
        let glyphs = FCInlineResult.Variant.allCases.map(\.symbolName)
        XCTAssertTrue(glyphs.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(glyphs).count, 3, "each variant needs its own glyph")
    }

    func testInlineResultSourceHidesBadgeCombinesTextAndKeepsRetrySeparate() throws {
        let result = try componentSource("FCInlineResult.swift")
        XCTAssertTrue(result.contains("FCStatusBadge(symbolName: variant.symbolName"))
        XCTAssertTrue(result.contains(".accessibilityElement(children: .combine)"))
        XCTAssertTrue(result.contains("FCLinkButton(title: retry.title"), "retry reuses the 44pt link button")
        // The retry button sits outside the combined title+message block.
        let combineIndex = try XCTUnwrap(result.range(of: ".accessibilityElement(children: .combine)")).lowerBound
        let retryIndex = try XCTUnwrap(result.range(of: "FCLinkButton(title: retry.title")).lowerBound
        XCTAssertLessThan(combineIndex, retryIndex)
        let status = try componentSource("FCStatusLabel.swift")
        let badge = try XCTUnwrap(status.range(of: "public struct FCStatusBadge"))
        XCTAssertTrue(status[badge.lowerBound...].contains(".accessibilityHidden(true)"), "badge is decorative")
    }

    // MARK: - DS-LIST-ROW

    func testGroupSelectionStateIsDerivedFromChildren() {
        typealias State = FCListGroupRow.SelectionState
        XCTAssertEqual(State(childSelections: []), .noneSelected)
        XCTAssertEqual(State(childSelections: [false, false]), .noneSelected)
        XCTAssertEqual(State(childSelections: [true, true, true]), .allSelected)
        XCTAssertEqual(State(childSelections: [true, false]), .partiallySelected)
        XCTAssertEqual(State(childSelections: [false, true, false]), .partiallySelected)
    }

    func testGroupRowSelectionStateIsComputedNotSettable() throws {
        let source = try componentSource("FCListRow.swift")
        let groupStart = try XCTUnwrap(source.range(of: "public struct FCListGroupRow"))
        let group = String(source[groupStart.lowerBound...])
        XCTAssertTrue(group.contains("public var selectionState: SelectionState {"), "state is a computed property")
        let initStart = try XCTUnwrap(group.range(of: "    public init(\n        title: String,"))
        let initEnd = try XCTUnwrap(group.range(of: ") {", range: initStart.upperBound..<group.endIndex))
        let initSignature = group[initStart.lowerBound..<initEnd.lowerBound]
        XCTAssertFalse(initSignature.contains("SelectionState"), "the initializer must not accept a state")
        XCTAssertTrue(initSignature.contains("childSelections: [Bool]"))
    }

    func testListRowUsesIsSelectedAndUnavailableHasNoAction() throws {
        let source = try componentSource("FCListRow.swift")
        XCTAssertTrue(source.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
        // Unavailable renders bare content: no Button, no circle, no `›`.
        XCTAssertTrue(source.contains("case .plain, .unavailable:\n            content"))
        XCTAssertTrue(source.contains("case .unavailable:\n            EmptyView()"))
        // `›` and the circle come from one `accessory` switch, so they are exclusive.
        XCTAssertEqual(source.components(separatedBy: "FCListSelectionCircle(isSelected").count - 1, 1)
    }

    // MARK: - DS-ACTION-ROW

    func testActionRowTrashIconIsDecorativeAndMatchesTitleColour() throws {
        let source = try componentSource("FCBottomSheet.swift")
        let iconStart = try XCTUnwrap(source.range(of: "Image(systemName: \"trash\")"))
        let iconEnd = try XCTUnwrap(source.range(of: "VStack(alignment: .leading", range: iconStart.upperBound..<source.endIndex))
        let icon = source[iconStart.lowerBound..<iconEnd.lowerBound]
        XCTAssertTrue(icon.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(icon.contains(".foregroundStyle(titleColor)"))
        XCTAssertTrue(icon.contains(".frame(width: 24, height: 24)"))
        XCTAssertTrue(source.contains("showsTrashIcon: Bool = false"), "default keeps the 10 existing consumers unchanged")
    }

    // MARK: - DS-CONFIRM-DIALOG

    func testConfirmationDialogOwnsItsSizeAndCallersPassNone() throws {
        let dialog = try componentSource("FCConfirmationDialog.swift")
        XCTAssertFalse(dialog.contains(".frame(width: 300)"), "width is a maximum, not a fixed frame")
        XCTAssertTrue(dialog.contains(".frame(maxWidth: 300)"))
        XCTAssertTrue(dialog.contains("ViewThatFits"))
        XCTAssertGreaterThanOrEqual(dialog.components(separatedBy: "minHeight: 44").count - 1, 1)

        let features = appRoot().appendingPathComponent("Features")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: features, includingPropertiesForKeys: nil))
        var callers = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            guard source.contains("FCConfirmationDialog(") || source.contains(".fcConfirmationDialog(") else { continue }
            callers += 1
            XCTAssertFalse(source.contains(".frame(width:"), "\(url.lastPathComponent) must not size the dialog")
        }
        XCTAssertGreaterThan(callers, 0, "found no dialog callers; scan path is wrong")
    }

    // MARK: - Sources

    private func appRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // DesignSystem/
            .deletingLastPathComponent() // FineCoachTests/
            .deletingLastPathComponent() // ios/
            .appendingPathComponent("FineCoachApp")
    }

    private func componentSource(_ name: String) throws -> String {
        let url = appRoot().appendingPathComponent("DesignSystem/Components/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
