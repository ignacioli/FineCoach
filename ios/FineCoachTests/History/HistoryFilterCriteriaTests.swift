import FineCoach
import XCTest

/// T073: unit coverage for the training-focus ANY-overlap (union) filter rule
/// (M1B-FR-026/D-013) as a pure function, independent of any repository.
final class HistoryFilterCriteriaTests: XCTestCase {
    func testEmptyFilterMatchesEverySession() {
        XCTAssertTrue(HistoryFilterCriteria.matchesTrainingFocus(sessionFocus: [], filter: []))
        XCTAssertTrue(HistoryFilterCriteria.matchesTrainingFocus(sessionFocus: [.chest, .back], filter: []))
    }

    func testAnyOverlapMatches() {
        XCTAssertTrue(
            HistoryFilterCriteria.matchesTrainingFocus(sessionFocus: [.chest, .arms], filter: [.arms, .core])
        )
    }

    func testExactMatchMatches() {
        XCTAssertTrue(
            HistoryFilterCriteria.matchesTrainingFocus(sessionFocus: [.thighs, .glutes], filter: [.thighs, .glutes])
        )
    }

    func testDisjointSetsDoNotMatch() {
        XCTAssertFalse(
            HistoryFilterCriteria.matchesTrainingFocus(sessionFocus: [.chest, .shoulders], filter: [.thighs, .calves])
        )
    }

    func testNonEmptyFilterAgainstEmptySessionFocusNeverMatches() {
        XCTAssertFalse(HistoryFilterCriteria.matchesTrainingFocus(sessionFocus: [], filter: [.core]))
    }

    func testCriteriaIsEmptyReflectsTrainingFocusEmptiness() {
        XCTAssertTrue(HistoryFilterCriteria(trainingFocus: []).isEmpty)
        XCTAssertFalse(HistoryFilterCriteria(trainingFocus: [.back]).isEmpty)
    }
}
