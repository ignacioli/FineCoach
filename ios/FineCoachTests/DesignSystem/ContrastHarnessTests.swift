import FineCoach
import XCTest

/// T045: one assertion group per row of `design/design-system/README.md` §11, computed
/// from `FCSemanticColors`' token hex constants via the `WCAGContrast` utility
/// (declared in `VisionHarnessTests.swift`, same target) — never a hardcoded literal
/// hex, so a token value change here is caught by the token tests (T060) and any
/// resulting contrast drift is caught here.
///
/// Every row asserts its computed ratio matches §11's own table value to 2 decimal
/// places (so the doc and the code cannot silently drift apart), plus:
/// - Text/background pairs (12 rows): ratio >= 4.5 (WCAG AA normal text).
/// - Non-text state boundaries (3 rows: pending-circle stroke, off-switch outer ring,
///   on-switch track, all against `surface.page`): ratio >= 3.0 (WCAG 1.4.11).
/// - The divider row (1 row): recorded only — purely decorative, §11 explicitly notes
///   it is not a control boundary, so no threshold is enforced.
/// - `text.disabled` (1 row): recorded, then the test explicitly skips itself — WCAG
///   exempt per §11, no threshold enforced.
///
/// 12 + 3 + 1 + 1 = 17 rows, matching §11's row count; there is at least one assertion
/// per row (18 total `XCTAssert*` calls: 15 rows get both a value-pin and a threshold
/// check, 2 rows get only a value-pin).
final class ContrastHarnessTests: XCTestCase {
    // MARK: Text pairs (>= 4.5:1)

    func testTextPrimaryOnSurfacePage() {
        let ratio = WCAGContrast.contrastRatio(FCSemanticColors.textPrimaryHex, FCSemanticColors.surfacePageHex)
        XCTAssertEqual(ratio, 16.45, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    func testTextSecondaryOnSurfacePage() {
        let ratio = WCAGContrast.contrastRatio(FCSemanticColors.textSecondaryHex, FCSemanticColors.surfacePageHex)
        XCTAssertEqual(ratio, 6.91, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    func testActionPrimaryOnSurfacePage() {
        let ratio = WCAGContrast.contrastRatio(FCSemanticColors.actionPrimaryHex, FCSemanticColors.surfacePageHex)
        XCTAssertEqual(ratio, 14.74, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    func testActionOnOnActionPrimary() {
        let ratio = WCAGContrast.contrastRatio(FCSemanticColors.actionOnHex, FCSemanticColors.actionPrimaryHex)
        XCTAssertEqual(ratio, 14.74, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    func testActionOnOnActionPressed() {
        let ratio = WCAGContrast.contrastRatio(FCSemanticColors.actionOnHex, FCSemanticColors.actionPressedHex)
        XCTAssertEqual(ratio, 16.67, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    func testTextOnActionSecondaryOnActionPrimary() {
        let ratio = WCAGContrast.contrastRatio(
            FCSemanticColors.textOnActionSecondaryHex, FCSemanticColors.actionPrimaryHex
        )
        XCTAssertEqual(ratio, 6.45, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    func testActionPrimaryOnSurfaceCanvas() {
        let ratio = WCAGContrast.contrastRatio(FCSemanticColors.actionPrimaryHex, FCSemanticColors.surfaceCanvasHex)
        XCTAssertEqual(ratio, 13.42, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    func testTextSecondaryOnSurfaceCanvas() {
        let ratio = WCAGContrast.contrastRatio(FCSemanticColors.textSecondaryHex, FCSemanticColors.surfaceCanvasHex)
        XCTAssertEqual(ratio, 6.29, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    func testActionPrimaryOnSurfaceSelected() {
        let ratio = WCAGContrast.contrastRatio(FCSemanticColors.actionPrimaryHex, FCSemanticColors.surfaceSelectedHex)
        XCTAssertEqual(ratio, 12.18, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    func testTextSecondaryOnSurfaceSelected() {
        let ratio = WCAGContrast.contrastRatio(FCSemanticColors.textSecondaryHex, FCSemanticColors.surfaceSelectedHex)
        XCTAssertEqual(ratio, 5.71, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    func testActionOnOnStatusWarning() {
        let ratio = WCAGContrast.contrastRatio(FCSemanticColors.actionOnHex, FCSemanticColors.statusWarningHex)
        XCTAssertEqual(ratio, 5.02, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    func testStatusDestructiveOnSurfacePage() {
        // §10 O1: dimmed from #D9563E (3.92:1, failed AA) to #D4442A (4.51:1).
        let ratio = WCAGContrast.contrastRatio(FCSemanticColors.statusDestructiveHex, FCSemanticColors.surfacePageHex)
        XCTAssertEqual(ratio, 4.51, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    // MARK: Non-text state boundaries (>= 3.0:1, WCAG 1.4.11)

    func testBorderControlPendingCircleStrokeOnSurfacePage() {
        // §10 O2: pending-set-circle stroke dimmed from #ECE9E2 (1.21:1) to
        // border.control #8E897F (3.48:1).
        let ratio = WCAGContrast.contrastRatio(FCSemanticColors.borderControlHex, FCSemanticColors.surfacePageHex)
        XCTAssertEqual(ratio, 3.48, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(ratio, 3.0)
    }

    func testBorderControlOffSwitchOuterRingOnSurfacePage() {
        // §10 O7: off-state switch track gained a 1.5pt border.control inner
        // stroke (3.48:1) — the track fill alone (surface.divider) is 1.21:1.
        let ratio = WCAGContrast.contrastRatio(FCSemanticColors.borderControlHex, FCSemanticColors.surfacePageHex)
        XCTAssertEqual(ratio, 3.48, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(ratio, 3.0)
    }

    func testActionPrimaryOnSwitchTrackOnSurfacePage() {
        let ratio = WCAGContrast.contrastRatio(FCSemanticColors.actionPrimaryHex, FCSemanticColors.surfacePageHex)
        XCTAssertEqual(ratio, 14.74, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(ratio, 3.0)
    }

    // MARK: Recorded, not threshold-enforced

    func testSurfaceDividerOnSurfacePageIsDecorativeNotApplicable() {
        // §11: "纯装饰分割线，不适用 3:1 要求" — purely decorative, not a control
        // boundary, so no threshold applies. Value still pinned so a silent
        // token change is caught.
        let ratio = WCAGContrast.contrastRatio(FCSemanticColors.surfaceDividerHex, FCSemanticColors.surfacePageHex)
        XCTAssertEqual(ratio, 1.21, accuracy: 0.005)
    }

    func testTextDisabledOnSurfacePageIsWCAGExempt() throws {
        let ratio = WCAGContrast.contrastRatio(FCSemanticColors.textDisabledHex, FCSemanticColors.surfacePageHex)
        XCTAssertEqual(ratio, 2.51, accuracy: 0.005)
        throw XCTSkip("§11: text.disabled is an explicit WCAG exemption (disabled state) — ratio recorded above, no threshold enforced")
    }
}
