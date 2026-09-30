import XCTest

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
            .deletingLastPathComponent() // DesignSystem/
            .deletingLastPathComponent() // FineCoachTests/
            .deletingLastPathComponent() // ios/
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
}
