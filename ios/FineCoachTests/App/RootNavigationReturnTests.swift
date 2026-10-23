import XCTest

@testable import FineCoach

final class RootNavigationReturnTests: XCTestCase {
    private let sessionID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    func testReturnToTodayClearsTheWholeStackAndSelectsToday() {
        var path: [RootDestination] = [
            .sessionSummary(sessionID),
            .shareReport(sessionID),
        ]
        var tab: RootTab = .students

        path.returnToToday(tab: &tab)

        XCTAssertTrue(path.isEmpty)
        XCTAssertEqual(tab, .today)
    }

    func testReturnToTodayClearsAStaleStackEvenWhenTodayIsAlreadySelected() {
        var path: [RootDestination] = [.settings]
        var tab: RootTab = .today

        path.returnToToday(tab: &tab)

        XCTAssertTrue(path.isEmpty)
        XCTAssertEqual(tab, .today)
    }
}
