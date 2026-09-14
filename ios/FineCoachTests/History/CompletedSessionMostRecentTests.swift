import FineCoach
import XCTest

/// Covers `CompletedSession.mostRecent(in:)`, the pure sort function backing
/// StudentDetailView's "上次完成的训练" preview card (Bug 3 fix). Getting the
/// comparison direction backwards, or accidentally trusting array/fetch
/// order instead of `completedAtUTC`, would be a silent regression a human
/// walkthrough on a short list might not catch.
final class CompletedSessionMostRecentTests: XCTestCase {
    private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)

    func testPicksNewestByCompletedAtUTCRegardlessOfArrayOrder() throws {
        let oldest = try makeCompletedSession(
            id: "22222222-2222-4222-8222-222222222222",
            completedAtUTC: Date(timeIntervalSince1970: 1_000)
        )
        let newest = try makeCompletedSession(
            id: "33333333-3333-4333-8333-333333333333",
            completedAtUTC: Date(timeIntervalSince1970: 3_000)
        )
        let middle = try makeCompletedSession(
            id: "44444444-4444-4444-8444-444444444444",
            completedAtUTC: Date(timeIntervalSince1970: 2_000)
        )

        // Deliberately NOT sorted, and the newest is neither first nor last,
        // so passing rules out both "trust array order" and a reversed
        // comparator.
        let unordered = [oldest, newest, middle]
        XCTAssertEqual(CompletedSession.mostRecent(in: unordered)?.id, newest.id)

        let reversed = [newest, middle, oldest]
        XCTAssertEqual(CompletedSession.mostRecent(in: reversed)?.id, newest.id)
    }

    func testEmptyHistoryReturnsNil() {
        XCTAssertNil(CompletedSession.mostRecent(in: []))
    }

    private func makeCompletedSession(id: String, completedAtUTC: Date) throws -> CompletedSession {
        CompletedSession(
            id: StableUUID(UUID(uuidString: id)!),
            studentID: studentID,
            studentDisplayName: try NormalizedName("林青"),
            startedAtUTC: completedAtUTC.addingTimeInterval(-600),
            completedAtUTC: completedAtUTC,
            trainingFocus: nil,
            notes: SessionNotes(privateCoachNote: nil, studentFacingSummary: nil, actionPrivateNotes: [:]),
            exercises: [],
            statistics: SessionStatistics(
                completedSetCount: 3,
                displayedDurationSeconds: try DecimalValue("600"),
                ordinaryTrainingVolume: nil
            ),
            revision: 1,
            latestReport: nil
        )
    }
}
