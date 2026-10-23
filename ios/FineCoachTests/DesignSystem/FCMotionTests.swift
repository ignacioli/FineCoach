import SwiftUI
import XCTest
@testable import FineCoach

/// README §14.2/§14.3 (product owner 2026-10-23, §10 C17) is the only source
/// for motion and haptic values. These assertions pin every token to it, the
/// same way `VisionHarnessTests` pins the colour, spacing and radius tokens.
final class FCMotionTests: XCTestCase {
    // MARK: §14.2 durations

    func testDurationTokensMatchSection14_2() {
        XCTAssertEqual(FCMotion.durationInstant, 0.15)
        XCTAssertEqual(FCMotion.durationFast, 0.2)
        XCTAssertEqual(FCMotion.durationStandard, 0.25)
        XCTAssertEqual(FCMotion.durationGentle, 0.35)
        XCTAssertEqual(FCMotion.durationEmphasis, 1.5)
    }

    // MARK: §14.2 curves

    func testCurveTokensMatchSection14_2() {
        // `motion.curve.standard` = easeOut, `motion.curve.symmetric` =
        // easeInOut; the duration always comes from a duration token.
        XCTAssertEqual(FCMotion.curveStandard(duration: 0.3), Animation.easeOut(duration: 0.3))
        XCTAssertEqual(FCMotion.curveSymmetric(duration: 0.3), Animation.easeInOut(duration: 0.3))
        XCTAssertNotEqual(FCMotion.curveStandard(duration: 0.3), FCMotion.curveSymmetric(duration: 0.3))
        XCTAssertEqual(FCMotion.curveStandard(duration: FCMotion.durationStandard), Animation.easeOut(duration: 0.25))
    }

    // MARK: §14.2 spring.toggle

    func testSpringToggleMatchesSection14_2() {
        XCTAssertEqual(FCMotion.springToggleResponse, 0.25)
        XCTAssertEqual(FCMotion.springToggleDampingFraction, 0.55)
        XCTAssertEqual(
            FCMotion.springToggle,
            Animation.spring(response: 0.25, dampingFraction: 0.55))
    }

    // MARK: §14.3 haptics

    func testHapticTokensMatchSection14_3() {
        XCTAssertEqual(FCHaptic.confirm, SensoryFeedback.impact(weight: .light))
        XCTAssertEqual(FCHaptic.selection, SensoryFeedback.selection)
        XCTAssertEqual(FCHaptic.attention, SensoryFeedback.warning)
        // 2026-10-23: `.success` is retired; a record is told apart by the
        // value float, not by a second, stronger haptic.
        XCTAssertNotEqual(FCHaptic.confirm, SensoryFeedback.success)
        // `SensoryFeedback.impact(weight:)` equality does not distinguish the
        // weight (`.light` and `.heavy` compare equal here), so the retired
        // heavy impact is guarded by the source scan in `SetEntryAssistTests`
        // instead of by a value comparison.
    }

    // MARK: §14.2 spacing + §14.4 record float

    func testRecordFloatUsesTheApprovedEmphasisDurationAndSpace6Distance() throws {
        // "新纪录数值浮起 space.6 (24pt)", `motion.duration.emphasis` (1.5):
        // candidate D, picked on device by the product owner 2026-10-23.
        XCTAssertEqual(FCPrimitives.space6, 24)
        XCTAssertEqual(FCMotion.durationEmphasis, 1.5)
        // The distance is the spacing token, not a new number.
        XCTAssertEqual(FCMotion.recordFloatDistance, FCPrimitives.space6)
        XCTAssertEqual(FCMotion.recordFloatDistance, 24)

        // The public `FCSetRow` init takes those two tokens as its defaults;
        // the DEBUG test bench is the only caller that overrides them.
        let rowURL = repositoryRoot().appendingPathComponent(
            "ios/FineCoachApp/DesignSystem/Components/FCSetRow.swift")
        let row = try String(contentsOf: rowURL, encoding: .utf8)
        XCTAssertTrue(row.contains("recordFloatDistance: FCMotion.recordFloatDistance"))
        XCTAssertTrue(row.contains("recordFloatDuration: FCMotion.durationEmphasis"))
        XCTAssertFalse(row.contains("duration: 0."), "no raw duration in the component")
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DesignSystem/
            .deletingLastPathComponent()  // FineCoachTests/
            .deletingLastPathComponent()  // ios/
            .deletingLastPathComponent()  // repository root
    }
}
