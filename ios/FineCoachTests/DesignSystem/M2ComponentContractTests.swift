@testable import FineCoach
import CoreText
import SwiftUI
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

    func testPageHeaderBackIsAnInlineGlyphWith44ptHitAreaAndLabel() throws {
        let source = try componentSource("FCPageHeader.swift")
        XCTAssertTrue(source.contains("FCSymbol(.pageBack)"), "the back glyph is the Noto ‹ at 22/400")
        XCTAssertTrue(source.contains("Color.clear\n                        .frame(width: 44, height: 44)"), "back needs a 44x44 hit area")
        XCTAssertTrue(source.contains(".accessibilityLabel(Text(\"common.back\"))"))
        XCTAssertTrue(source.contains("HStack(alignment: .firstTextBaseline"), "back and title share the first line")
        XCTAssertEqual(FCPageHeader.backLayoutWidth, 16, "title starts at page margin (16) + 16 = x 32")
        XCTAssertTrue(source.contains("interactivePopGestureRecognizer"), "hiding the bar must not lose the edge swipe-back")
    }

    /// Every secondary page hides the system bar through `fcSecondaryPage` and draws the inline
    /// back; none keeps the `.toolbarRole(.editor)` system back row (owner walkthrough 2026-10-10).
    /// Left on the system bar on purpose: ActiveSessionView (the artwork 11/30 draws no back and a
    /// 22pt title; owner decision pending) and the nav-title pages whose title sits in the bar.
    func testEverySecondaryPageUsesTheInlineBack() throws {
        let features = appRoot().appendingPathComponent("Features")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: features, includingPropertiesForKeys: nil))
        let systemBackAllowed: Set<String> = ["ActiveSessionView.swift"]
        var secondaryPages = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let name = url.lastPathComponent
            let source = try String(contentsOf: url, encoding: .utf8)
            if source.contains(".toolbarRole(.editor)") {
                XCTAssertTrue(systemBackAllowed.contains(name), "\(name) still uses the system back row")
            }
            if source.contains(".fcSecondaryPage(") {
                secondaryPages += 1
                XCTAssertTrue(source.contains("FCPageHeader("), "\(name) hides the bar but has no FCPageHeader")
                XCTAssertTrue(source.contains("back:"), "\(name) hides the bar but draws no inline back")
            }
        }
        XCTAssertGreaterThanOrEqual(secondaryPages, 17, "found too few secondary pages; the scan is broken")
    }

    @MainActor
    func testSymbolGlyphsAreNotoSansSCAtTheDocumentedSizes() throws {
        let cases: [(FCSymbol.Kind, String, CGFloat, CGFloat)] = [
            (.pageBack, "\u{2039}", 22, 400), (.back, "\u{2039}", 20, 400), (.forward, "\u{203A}", 20, 400),
            (.check, "\u{2713}", 15, 600), (.checkOnFill, "\u{2713}", 13, 600),
        ]
        for (kind, glyph, size, _) in cases {
            XCTAssertTrue(FCSymbol.rendersAsNotoGlyph(kind))
            let font = FCSymbol.glyphFont(kind, .large)
            XCTAssertEqual(font.familyName, "Noto Sans SC")
            XCTAssertEqual(font.pointSize, size, accuracy: 0.6, "\(kind) size at the default Dynamic Type")
            var glyphs = [CGGlyph](repeating: 0, count: 1)
            let characters = Array(glyph.utf16)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(font, characters, &glyphs, 1), "\(kind): bundled font lacks \(glyph)")
            XCTAssertGreaterThan(FCSymbol.glyphFont(kind, .accessibility3).pointSize, font.pointSize, "scales with Dynamic Type")
        }
        for kind in [FCSymbol.Kind.minus, .plus, .collapse] {
            XCTAssertFalse(FCSymbol.rendersAsNotoGlyph(kind), "−, + and ▾ stay SF Symbols")
        }
        let source = try componentSource("FCSymbol.swift")
        XCTAssertTrue(source.contains("FCFont.uiFont"))
        XCTAssertFalse(source.contains("\"chevron.left\"") || source.contains("\"chevron.right\"") || source.contains("\"checkmark\""))
        // The other ✓ users inherit it instead of drawing an SF checkmark.
        XCTAssertFalse(try componentSource("FCSetStateCircle.swift").contains("systemName: \"checkmark\""))
        XCTAssertTrue(try componentSource("FCStatusLabel.swift").contains("FCSymbol(.checkOnFill)"))
    }

    /// Hosts a SwiftUI `NavigationStack` (a real `UINavigationController` underneath) with a
    /// pushed page using `fcSecondaryPage`, and checks the edge-swipe recognizer is allowed to
    /// begin there with the bar hidden, is switched off for a flow's step-back page, and is
    /// restored when the page goes away.
    @MainActor
    func testSecondaryPageKeepsTheEdgeSwipeBackWorking() async throws {
        for (enabled, expectsBegin) in [(true, true), (false, false)] {
            let host = UIHostingController(rootView: SwipeBackHarness(swipeBackEnabled: enabled))
            // A window in the app's scene: a scene-less UIWindow never lays out the stack.
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 600_000_000)
            let navigation = try XCTUnwrap(Self.findNavigationController(in: host), "no UINavigationController under NavigationStack")
            XCTAssertEqual(navigation.viewControllers.count, 2, "harness page not pushed")
            let pop = try XCTUnwrap(navigation.interactivePopGestureRecognizer)
            let begins = pop.delegate?.gestureRecognizerShouldBegin?(pop) ?? false
            XCTAssertEqual(pop.isEnabled && begins, expectsBegin, "swipeBackEnabled: \(enabled)")
            if enabled {
                XCTAssertTrue(navigation.isNavigationBarHidden || navigation.navigationBar.isHidden, "system bar is hidden")
            }
            navigation.popViewController(animated: false)
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertTrue(navigation.interactivePopGestureRecognizer?.isEnabled ?? false, "state restored after leaving the page")
            window.isHidden = true
        }
    }

    private struct SwipeBackHarness: View {
        let swipeBackEnabled: Bool
        @State private var path = [1]

        var body: some View {
            NavigationStack(path: $path) {
                Color.clear
                    .navigationDestination(for: Int.self) { _ in
                        Color.clear.fcSecondaryPage(swipeBackEnabled: swipeBackEnabled)
                    }
            }
        }
    }

    @MainActor
    private static func findNavigationController(in controller: UIViewController) -> UINavigationController? {
        func search(_ view: UIView) -> UINavigationController? {
            if let navigation = view.next as? UINavigationController { return navigation }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        return search(controller.view)
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

    func testListRowGeometryMatchesTheArtwork() throws {
        // Measured from M2-02a/02b/03: 52pt rows + 1pt divider = 53pt pitch; child indent 16;
        // titles at the divider's x (no extra leading inset inside the page margin).
        XCTAssertEqual(FCListRowGeometry.minHeight, 52)
        XCTAssertEqual(FCListRowGeometry.indent, 16)
        let source = try componentSource("FCListRow.swift")
        XCTAssertFalse(source.contains(".padding(.leading, FCPrimitives.space4)\n                .frame(maxWidth: .infinity, minHeight"))
        XCTAssertTrue(source.contains(".padding(.leading, isIndented ? FCListRowGeometry.indent : 0)"))
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
