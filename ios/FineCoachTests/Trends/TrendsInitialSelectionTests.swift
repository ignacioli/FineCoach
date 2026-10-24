import XCTest

@testable import FineCoach

final class TrendsInitialSelectionTests: XCTestCase {
    private let exerciseID = try! StableExerciseID("fictional.trends.selection")
    private let lowID = StableUUID(UUID(uuidString: "00000000-0000-4000-8000-000000000001")!)
    private let highID = StableUUID(UUID(uuidString: "00000000-0000-4000-8000-000000000002")!)

    func testLatestWeightRepsModeWinsRegardlessOfInputOrder() throws {
        let older = try session(id: highID, completedAt: 100, mode: .reps)
        let newer = try session(id: lowID, completedAt: 200, mode: .weightReps)
        for sessions in [[older, newer], [newer, older]] {
            XCTAssertEqual(
                TrendsViewModel.initialOptionKey(exerciseID: exerciseID, sessions: sessions),
                "\(exerciseID.rawValue)|weightReps")
        }
    }

    func testLatestRepsModeWinsRegardlessOfInputOrder() throws {
        let older = try session(id: highID, completedAt: 100, mode: .weightReps)
        let newer = try session(id: lowID, completedAt: 200, mode: .reps)
        for sessions in [[older, newer], [newer, older]] {
            XCTAssertEqual(
                TrendsViewModel.initialOptionKey(exerciseID: exerciseID, sessions: sessions),
                "\(exerciseID.rawValue)|reps")
        }
    }

    func testMissingExerciseReturnsNil() throws {
        let history = [try session(id: lowID, completedAt: 100, mode: .reps)]
        XCTAssertNil(
            TrendsViewModel.initialOptionKey(
                exerciseID: try StableExerciseID("fictional.missing"), sessions: history))
        XCTAssertNil(TrendsViewModel.initialOptionKey(exerciseID: exerciseID, sessions: []))
    }

    func testEqualCompletionTimesUseLexicographicallyGreaterSessionID() throws {
        for mode in [RecordMode.reps, .weightReps] {
            let lower = try session(id: lowID, completedAt: 100, mode: mode == .reps ? .weightReps : .reps)
            let higher = try session(id: highID, completedAt: 100, mode: mode)
            for sessions in [[lower, higher], [higher, lower]] {
                XCTAssertEqual(
                    TrendsViewModel.initialOptionKey(exerciseID: exerciseID, sessions: sessions),
                    "\(exerciseID.rawValue)|\(mode.rawValue)")
            }
        }
    }

    private func session(id: StableUUID, completedAt: TimeInterval, mode: RecordMode) throws -> CompletedSession {
        let time = Date(timeIntervalSince1970: completedAt)
        let exercise = SessionExercise(
            id: StableUUID(UUID()), sessionID: id, orderIndex: 0, sourceKind: .builtIn, sourceID: exerciseID,
            displayNameSnapshot: try NormalizedName("虚构预选动作"), recordModeSnapshot: mode,
            actionPrivateNote: nil, sets: [])
        return CompletedSession(
            id: id, studentID: lowID, studentDisplayName: try NormalizedName("虚构预选学员"),
            startedAtUTC: time, completedAtUTC: time, trainingFocus: [],
            notes: SessionNotes(privateCoachNote: nil, studentFacingSummary: nil, actionPrivateNotes: [:]),
            exercises: [exercise],
            statistics: SessionStatistics(
                completedSetCount: 0, displayedDurationSeconds: .zero, ordinaryTrainingVolume: nil),
            revision: 1, latestReport: nil)
    }
}
