import XCTest

@testable import FineCoach

final class EmptyStateFirstLoadTests: XCTestCase {
    func testTodayHidesEmptyStateBeforeFirstLoadCompletes() {
        XCTAssertFalse(
            TodayEmptyStatePresentation.showsEmptyState(
                hasCompletedInitialLoad: false,
                visibleRows: [],
                inProgress: []
            )
        )
    }

    func testTodayShowsEmptyStateAfterCompletedEmptyLoad() {
        XCTAssertTrue(
            TodayEmptyStatePresentation.showsEmptyState(
                hasCompletedInitialLoad: true,
                visibleRows: [],
                inProgress: []
            )
        )
    }

    func testStudentListHidesEmptyStateBeforeFirstLoadCompletes() {
        XCTAssertFalse(
            StudentListEmptyStatePresentation.showsEmptyState(
                hasCompletedInitialLoad: false,
                studentCount: 0
            )
        )
    }

    func testStudentListShowsEmptyStateAfterCompletedEmptyLoad() {
        XCTAssertTrue(
            StudentListEmptyStatePresentation.showsEmptyState(
                hasCompletedInitialLoad: true,
                studentCount: 0
            )
        )
    }

    func testStudentListDoesNotShowEmptyStateWhenStudentsExist() {
        XCTAssertFalse(
            StudentListEmptyStatePresentation.showsEmptyState(
                hasCompletedInitialLoad: true,
                studentCount: 1
            )
        )
    }
}
