import FineCoach
import XCTest

/// M1B-FR-028: `Comparison.exerciseTrend`/`personalRecords` must let a
/// caller supply `.decreaseIsImprovement` for assisted-load exercises and
/// get the MINIMUM weight back as "best", not the maximum. Getting this
/// backwards would show a coach shrinking assistance (getting stronger) as
/// a regression, and vice versa.
final class ComparisonLoadDirectionTests: XCTestCase {
    private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    private let exerciseID = StableExerciseID(rawValue: "fc.placeholder.assisted-pullup")!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testExerciseTrendDefaultsToIncreaseIsImprovementAndPicksMaxWeight() throws {
        let sessions = try [
            makeSession(idSuffix: "1", weight: "40", daysOffset: 0),
            makeSession(idSuffix: "2", weight: "30", daysOffset: 1),
            makeSession(idSuffix: "3", weight: "50", daysOffset: 2),
        ]

        let points = Comparison.exerciseTrend(exerciseID: exerciseID, recordMode: .weightReps, across: sessions)
        XCTAssertEqual(points.map { $0.maxWeight?.canonicalString }, ["40", "30", "50"])
    }

    func testExerciseTrendWithDecreaseIsImprovementPicksMinWeightPerSession() throws {
        let sessions = try [
            makeSession(idSuffix: "1", weight: "40", secondWeight: "35", daysOffset: 0)
        ]

        let points = Comparison.exerciseTrend(
            exerciseID: exerciseID,
            recordMode: .weightReps,
            across: sessions,
            loadDirection: .decreaseIsImprovement
        )
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].maxWeight?.canonicalString, "35")
    }

    func testPersonalRecordsDefaultsToHighestWeight() throws {
        let sessions = try [
            makeSession(idSuffix: "1", weight: "40", daysOffset: 0),
            makeSession(idSuffix: "2", weight: "60", daysOffset: 1),
            makeSession(idSuffix: "3", weight: "50", daysOffset: 2),
        ]

        let records = Comparison.personalRecords(exerciseID: exerciseID, recordMode: .weightReps, across: sessions)
        XCTAssertEqual(records.highestWeight?.weight.canonicalString, "60")
    }

    func testPersonalRecordsWithDecreaseIsImprovementPicksLowestWeight() throws {
        let sessions = try [
            makeSession(idSuffix: "1", weight: "40", daysOffset: 0),
            makeSession(idSuffix: "2", weight: "20", daysOffset: 1),
            makeSession(idSuffix: "3", weight: "50", daysOffset: 2),
        ]

        let records = Comparison.personalRecords(
            exerciseID: exerciseID,
            recordMode: .weightReps,
            across: sessions,
            loadDirection: .decreaseIsImprovement
        )
        XCTAssertEqual(records.highestWeight?.weight.canonicalString, "20")
        XCTAssertEqual(records.highestWeight?.sessionID, sessionUUID(forSuffix: "2"))
    }

    // MARK: - Fixtures

    private func sessionUUID(forSuffix suffix: String) -> StableUUID {
        StableUUID(UUID(uuidString: "22222222-2222-4222-8222-22222222222\(suffix)")!)
    }

    private func makeSession(
        idSuffix: String,
        weight: String,
        secondWeight: String? = nil,
        daysOffset: Int
    ) throws -> CompletedSession {
        let completedAt = now.addingTimeInterval(TimeInterval(daysOffset) * 86_400)
        let sessionID = sessionUUID(forSuffix: idSuffix)
        let sessionExerciseID = StableUUID(UUID())
        var sets = [
            try makeSet(orderIndex: 0, weight: weight, sessionExerciseID: sessionExerciseID)
        ]
        if let secondWeight {
            sets.append(try makeSet(orderIndex: 1, weight: secondWeight, sessionExerciseID: sessionExerciseID))
        }
        let exercise = try SessionExercise(
            id: sessionExerciseID,
            sessionID: sessionID,
            orderIndex: 0,
            sourceKind: .builtIn,
            sourceID: exerciseID,
            displayNameSnapshot: NormalizedName("辅助引体向上"),
            recordModeSnapshot: .weightReps,
            actionPrivateNote: nil,
            sets: sets
        )
        return CompletedSession(
            id: sessionID,
            studentID: studentID,
            studentDisplayName: try NormalizedName("林青"),
            startedAtUTC: completedAt.addingTimeInterval(-600),
            completedAtUTC: completedAt,
            trainingFocus: nil,
            notes: SessionNotes(privateCoachNote: nil, studentFacingSummary: nil, actionPrivateNotes: [:]),
            exercises: [exercise],
            statistics: SessionStatistics(
                completedSetCount: sets.count,
                displayedDurationSeconds: try DecimalValue("600"),
                ordinaryTrainingVolume: nil
            ),
            revision: 1,
            latestReport: nil
        )
    }

    // MARK: - TrendSampleDensity (sparse-data chart tiering)

    func testTrendSampleDensityClassifiesByPointCount() throws {
        guard case .empty = Comparison.TrendSampleDensity.classify([]) else {
            return XCTFail("expected .empty for 0 points")
        }

        let onePoint = try Comparison.exerciseTrend(
            exerciseID: exerciseID,
            recordMode: .weightReps,
            across: [makeSession(idSuffix: "1", weight: "40", daysOffset: 0)]
        )
        guard case .single = Comparison.TrendSampleDensity.classify(onePoint) else {
            return XCTFail("expected .single for 1 point")
        }

        let twoPoints = try Comparison.exerciseTrend(
            exerciseID: exerciseID,
            recordMode: .weightReps,
            across: [
                makeSession(idSuffix: "1", weight: "40", daysOffset: 0),
                makeSession(idSuffix: "2", weight: "42", daysOffset: 1),
            ]
        )
        guard case .sparse(let sparsePoints) = Comparison.TrendSampleDensity.classify(twoPoints) else {
            return XCTFail("expected .sparse for 2 points")
        }
        XCTAssertEqual(sparsePoints.count, 2)

        let threePoints = try Comparison.exerciseTrend(
            exerciseID: exerciseID,
            recordMode: .weightReps,
            across: [
                makeSession(idSuffix: "1", weight: "40", daysOffset: 0),
                makeSession(idSuffix: "2", weight: "42", daysOffset: 1),
                makeSession(idSuffix: "3", weight: "44", daysOffset: 2),
            ]
        )
        guard case .sufficient(let sufficientPoints) = Comparison.TrendSampleDensity.classify(threePoints) else {
            return XCTFail("expected .sufficient for 3+ points")
        }
        XCTAssertEqual(sufficientPoints.count, 3)
    }

    private func makeSet(orderIndex: UInt32, weight: String, sessionExerciseID: StableUUID) throws -> TrainingSet {
        try TrainingSet(
            id: StableUUID(UUID()),
            sessionExerciseID: sessionExerciseID,
            orderIndex: orderIndex,
            state: .completed,
            recordMode: .weightReps,
            weightValue: DecimalValue(weight),
            repetitionCount: DecimalValue("8"),
            durationSeconds: nil,
            unit: .kilograms,
            side: .none,
            leftValue: nil,
            rightValue: nil,
            createdAtUTC: now,
            updatedAtUTC: now,
            completedAtUTC: now
        )
    }
}
