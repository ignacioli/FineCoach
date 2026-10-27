import XCTest

@testable import FineCoach

final class EstimatedOneRepMaxTrendTests: XCTestCase {
    private let squat = try! StableExerciseID("a2f5b6ef-b780-49c0-8d96-fdaff23e27ce")
    private let other = try! StableExerciseID("aaaaaaaa-0000-4000-8000-000000000001")
    private let now = Date(timeIntervalSince1970: 1_792_843_200)

    private func session(
        action: StableExerciseID? = nil, day: Int = 0,
        sets: [(String, String, SetRecordingState)]
    ) throws -> CompletedSession {
        let sessionID = StableUUID(UUID())
        let exerciseID = StableUUID(UUID())
        let date = now.addingTimeInterval(TimeInterval(day * 86_400))
        let trainingSets = try sets.enumerated().map { index, item in
            TrainingSet(
                id: StableUUID(UUID()), sessionExerciseID: exerciseID, orderIndex: UInt32(index), state: item.2,
                recordMode: .weightReps, weightValue: try DecimalValue(item.0),
                repetitionCount: try DecimalValue(item.1),
                durationSeconds: nil, unit: .kilograms, side: .none, leftValue: nil, rightValue: nil,
                createdAtUTC: date, updatedAtUTC: date, completedAtUTC: item.2 == .completed ? date : nil)
        }
        let exercise = SessionExercise(
            id: exerciseID, sessionID: sessionID, orderIndex: 0, sourceKind: .builtIn, sourceID: action ?? squat,
            displayNameSnapshot: try NormalizedName("虚构趋势动作"), recordModeSnapshot: .weightReps,
            actionPrivateNote: nil, sets: trainingSets)
        return CompletedSession(
            id: sessionID, studentID: StableUUID(UUID()), studentDisplayName: try NormalizedName("虚构趋势学员"),
            startedAtUTC: date, completedAtUTC: date, trainingFocus: [],
            notes: SessionNotes(privateCoachNote: nil, studentFacingSummary: nil, actionPrivateNotes: [:]),
            exercises: [exercise],
            statistics: SessionStatistics(
                completedSetCount: trainingSets.count, displayedDurationSeconds: .zero, ordinaryTrainingVolume: nil),
            revision: 1, latestReport: nil)
    }

    func testEachSessionUsesMaximumEligibleEstimateAndSortsChronologically() throws {
        let first = try session(day: -1, sets: [("60", "10", .completed), ("90", "1", .completed)])
        let second = try session(sets: [("100", "6", .completed), ("200", "11", .completed), ("300", "1", .pending)])
        let points = EstimatedOneRepMaxTrend.points(exerciseID: squat, sessions: [second, first])
        XCTAssertEqual(points.map(\.sessionID), [first.id, second.id])
        XCTAssertEqual(points.map(\.maxWeight), try [DecimalValue("90"), DecimalValue("120")])
        XCTAssertEqual(TrendMetric.estimatedOneRepMax.value(for: points[1]), try DecimalValue("120"))
    }

    func testSessionWithoutEligibleSetsProducesNoPointAndNoZero() throws {
        let invalid = try session(sets: [("100", "11", .completed), ("0", "5", .completed)])
        let unrecorded = try session(sets: [("100", "5", .pending)])
        let valid = try session(day: 1, sets: [("90", "1", .completed)])
        let points = EstimatedOneRepMaxTrend.points(exerciseID: squat, sessions: [invalid, valid, unrecorded])
        XCTAssertEqual(points.map(\.sessionID), [valid.id])
        XCTAssertEqual(points.first?.maxWeight, try DecimalValue("90"))
    }

    func testOutsideAllowlistHasNeitherSegmentNorPointsAndSelectionFallsBack() throws {
        let history = try [session(action: other, sets: [("100", "5", .completed)])]
        XCTAssertTrue(EstimatedOneRepMaxTrend.points(exerciseID: other, sessions: history).isEmpty)
        XCTAssertEqual(TrendMetric.options(for: other), [.weight, .reps, .volume])
        XCTAssertEqual(TrendMetric.options(for: nil), [.weight, .reps, .volume])
        for id in EstimatedOneRepMax.exerciseIDs {
            XCTAssertEqual(TrendMetric.options(for: id), [.weight, .reps, .volume, .estimatedOneRepMax])
            XCTAssertEqual(TrendMetric.estimatedOneRepMax.resolved(for: id), .estimatedOneRepMax)
        }
        XCTAssertEqual(TrendMetric.estimatedOneRepMax.resolved(for: other), .weight)
        XCTAssertEqual(TrendMetric.estimatedOneRepMax.resolved(for: nil), .weight)
        XCTAssertEqual(TrendMetric.volume.resolved(for: other), .volume)
    }
}
