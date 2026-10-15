import XCTest

@testable import FineCoach

/// Experience P0-D3/D4: weight steps ±2.5 kg and reps ±1 without leaving the
/// valid range, and the rest countdown starts at 120 s, adjusts by 15 s and
/// never runs below zero.
final class SetEntryAssistTests: XCTestCase {
    // MARK: - SetValueStepping

    func testWeightStepsByTwoPointFive() {
        XCTAssertEqual(SetValueStepping.stepped("120", field: .weight, up: true), "122.5")
        XCTAssertEqual(SetValueStepping.stepped("122.5", field: .weight, up: false), "120")
        XCTAssertEqual(SetValueStepping.stepped("0.5", field: .weight, up: true), "3")
    }

    func testWeightClampsAtZero() {
        XCTAssertEqual(SetValueStepping.stepped("1", field: .weight, up: false), "0")
        XCTAssertEqual(SetValueStepping.stepped("0", field: .weight, up: false), "0")
        XCTAssertFalse(SetValueStepping.canStepDown("0", field: .weight))
        XCTAssertTrue(SetValueStepping.canStepDown("2.5", field: .weight))
    }

    func testRepsStepByOneAndStayAtLeastOne() {
        XCTAssertEqual(SetValueStepping.stepped("8", field: .reps, up: true), "9")
        XCTAssertEqual(SetValueStepping.stepped("8", field: .reps, up: false), "7")
        XCTAssertEqual(SetValueStepping.stepped("1", field: .reps, up: false), "1")
        XCTAssertFalse(SetValueStepping.canStepDown("1", field: .reps))
    }

    func testEmptyOnlyStepsUpAndInvalidTextIsLeftAlone() {
        XCTAssertEqual(SetValueStepping.stepped("", field: .weight, up: true), "2.5")
        XCTAssertEqual(SetValueStepping.stepped("", field: .reps, up: true), "1")
        XCTAssertEqual(SetValueStepping.stepped("", field: .weight, up: false), "")
        XCTAssertEqual(SetValueStepping.stepped("abc", field: .weight, up: true), "abc")
        XCTAssertFalse(SetValueStepping.canStepDown("", field: .weight))
    }

    // MARK: - RestTimerState

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testStartsAtTwoMinutesAndCountsDown() {
        let timer = RestTimerState(startedAt: start)
        XCTAssertEqual(timer.remainingSeconds(at: start), 120)
        XCTAssertEqual(timer.remainingSeconds(at: start.addingTimeInterval(15.2)), 105)
        XCTAssertFalse(timer.isFinished(at: start.addingTimeInterval(119.5)))
        XCTAssertTrue(timer.isFinished(at: start.addingTimeInterval(120)))
        XCTAssertEqual(timer.remainingSeconds(at: start.addingTimeInterval(500)), 0)
    }

    func testAdjustsByFifteenSecondsButNotIntoThePast() {
        var timer = RestTimerState(startedAt: start)
        timer.adjust(by: RestTimerState.adjustmentStep, now: start)
        XCTAssertEqual(timer.remainingSeconds(at: start), 135)
        timer.adjust(by: -RestTimerState.adjustmentStep * 2, now: start)
        XCTAssertEqual(timer.remainingSeconds(at: start), 105)

        let late = start.addingTimeInterval(110)
        timer.adjust(by: -RestTimerState.adjustmentStep, now: late)
        XCTAssertEqual(timer.remainingSeconds(at: late), 0)
    }

    func testFormatsMinutesAndSeconds() {
        XCTAssertEqual(RestTimerState.text(seconds: 105), "1:45")
        XCTAssertEqual(RestTimerState.text(seconds: 7), "0:07")
        XCTAssertEqual(RestTimerState.text(seconds: 120), "2:00")
    }

    func testStaysUpForThreeSecondsAfterItEnds() {
        let timer = RestTimerState(startedAt: start)
        XCTAssertEqual(timer.autoDismissDelay(at: start), 123, accuracy: 0.001)
        let end = start.addingTimeInterval(RestTimerState.defaultDuration)
        XCTAssertEqual(timer.autoDismissDelay(at: end), RestTimerState.finishedHold, accuracy: 0.001)
        XCTAssertEqual(timer.autoDismissDelay(at: end.addingTimeInterval(1)), 2, accuracy: 0.001)
        XCTAssertEqual(timer.autoDismissDelay(at: end.addingTimeInterval(3)), 0, accuracy: 0.001)
        XCTAssertEqual(timer.autoDismissDelay(at: end.addingTimeInterval(10)), 0, accuracy: 0.001)
    }

    func testTrainingScreenPlacesTheRestBarAboveFinish() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FineCoachApp/Features/ActiveSession/ActiveSessionView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("RestTimerBar("))
        XCTAssertTrue(source.contains("activeSessionRestMinus"))
        XCTAssertTrue(source.contains("activeSessionRestPlus"))
        XCTAssertTrue(source.contains("activeSessionRestSkip"))
        XCTAssertTrue(source.contains("activeSessionRestClose"))
        XCTAssertTrue(source.contains("session.rest.ended"))
        let bar = try XCTUnwrap(source.range(of: "RestTimerBar("))
        let finish = try XCTUnwrap(source.range(of: "session.action.finish"))
        XCTAssertLessThan(bar.lowerBound, finish.lowerBound)
    }
}
