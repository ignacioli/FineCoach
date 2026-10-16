import XCTest

@testable import FineCoach

/// T047 (NFR-004): every interactive design-system component declares a
/// ≥ 44 × 44 pt hit area. The rule is enforced where the controls are built,
/// so Feature screens inherit it; this scan pins it at the component. It does
/// not measure rendered screens: layout and text at large Dynamic Type sizes
/// stay a human walkthrough item (T070, CLAUDE.md), not a UI automation gate.
final class TouchTargetComponentTests: XCTestCase {
    func testInteractiveComponentsDeclareA44ptHitArea() throws {
        let components = [
            "FCButton.swift", "FCChip.swift", "FCListRow.swift", "FCSegmentedSwitch.swift",
            "FCToggleStyle.swift", "FCBodyPartChip.swift", "FCStepper.swift", "FCSetRow.swift",
            "FCCalendarDayCell.swift",
        ]
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DesignSystem/
            .deletingLastPathComponent()  // FineCoachTests/
            .deletingLastPathComponent()  // ios/
            .appendingPathComponent("FineCoachApp/DesignSystem/Components")
        for name in components {
            let source = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            XCTAssertTrue(
                source.contains("minHeight: 44") || source.contains("height: 44"),
                "\(name) must declare a 44pt hit area"
            )
        }
    }

    func testTitleRowButtonsDeclareA44x44HitArea() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FineCoachApp/DesignSystem/Components/FCButton.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        // FCLinkButton, FCTitleIconButton, FCTitleAddButton: today's calendar,
        // settings, resource-hub and 新建预约 entries.
        XCTAssertGreaterThanOrEqual(source.components(separatedBy: ".frame(minWidth: 44, minHeight: 44)").count - 1, 3)
    }

    /// M2 Phase 1 (T009): the hit areas added by the §4.7 components.
    func testM2ComponentsDeclareTheirHitAreas() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DesignSystem/
            .deletingLastPathComponent()  // FineCoachTests/
            .deletingLastPathComponent()  // ios/
            .appendingPathComponent("FineCoachApp/DesignSystem/Components")
        func source(_ name: String) throws -> String {
            try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
        }

        // Page header trailing action: 44x44.
        XCTAssertTrue(try source("FCPageHeader.swift").contains(".frame(minWidth: 44, minHeight: 44)"))
        // Hub row: whole row, min height 64 (>= 44).
        XCTAssertTrue(try source("FCHubRow.swift").contains("minHeight: 64"))
        // Inline result retry reuses FCLinkButton (44x44, asserted above).
        XCTAssertTrue(try source("FCInlineResult.swift").contains("FCLinkButton("))
        // Group row: the selection circle is its own 44x44 target; the rest of the row is >= 44 tall.
        let list = try source("FCListRow.swift")
        XCTAssertTrue(
            list.contains(".frame(minWidth: 44, minHeight: FCListRowGeometry.minHeight, alignment: .trailing)"))
        XCTAssertGreaterThanOrEqual(list.components(separatedBy: "minHeight: FCListRowGeometry.minHeight").count - 1, 3)
        XCTAssertGreaterThanOrEqual(FCListRowGeometry.minHeight, 44)
        // Page header back: 44x44 hit area drawn over the 16pt glyph.
        XCTAssertTrue(try source("FCPageHeader.swift").contains(".frame(width: 44, height: 44)"))
        // Stacked and side-by-side dialog buttons keep the 44pt hit area (36pt visual).
        XCTAssertTrue(try source("FCConfirmationDialog.swift").contains(".frame(minHeight: 44)"))
    }
}
