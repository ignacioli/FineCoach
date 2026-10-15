import XCTest

@testable import FineCoach

/// T069l: `FCStepper`'s step rule — ±1, clamped to the range, so the
/// disabled side can never push the value out of bounds.
final class FCStepperTests: XCTestCase {
    func testStepsByOneInsideTheRange() {
        XCTAssertEqual(FCStepper.stepped(20, by: 1, in: 1...999), 21)
        XCTAssertEqual(FCStepper.stepped(20, by: -1, in: 1...999), 19)
    }

    func testClampsAtBothEnds() {
        XCTAssertEqual(FCStepper.stepped(1, by: -1, in: 1...999), 1)
        XCTAssertEqual(FCStepper.stepped(999, by: 1, in: 1...999), 999)
    }

    /// P0-a / P0-b: weight and reps use the editable capsule. The integer
    /// stepper and the duration / cardio fields stay as they were.
    func testSetEditorUsesTheEditableStepperForWeightAndReps() throws {
        let source = try String(contentsOf: setEditorURL(), encoding: .utf8)
        XCTAssertTrue(source.contains("FCStepperField("))
        XCTAssertFalse(source.contains("FCTextField(String(localized: \"session.field.weight\")"))
        XCTAssertFalse(source.contains("FCTextField(String(localized: \"session.field.reps\")"))
        XCTAssertTrue(source.contains("session.field.durationFlexible"))
        XCTAssertTrue(source.contains("SetValueStepping.canStepDown"))
    }

    func testEditableStepperDeclaresFocusStrokeAndHitArea() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FineCoachApp/DesignSystem/Components/FCStepper.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("struct FCStepperField"))
        XCTAssertTrue(source.contains("strokeBorder(FCSemanticColors.actionPrimary, lineWidth: 1.5)"))
        XCTAssertTrue(source.contains("minWidth: 44, minHeight: 44"))
        XCTAssertTrue(source.contains(".fcFont(.numeralLarge)"))
    }

    private func setEditorURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FineCoachApp/Features/ActiveSession/SetEditor.swift")
    }
}
