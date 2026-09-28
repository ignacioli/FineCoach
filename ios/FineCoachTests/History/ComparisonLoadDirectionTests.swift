@testable import FineCoach
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

    // T069i (owner 2026-09-28): the personal best shows its day and reps —
    // the most reps at the top weight, ties going to the most recent session.
    func testMostRepsAtTopWeightUsesTheSetsOfTheOwnersExample() throws {
        // 哈克深蹲: 25kg × 8, 20kg × 12, 20kg × 12 in one session.
        let session = try makeSession(idSuffix: "1", sets: [("25", "8"), ("20", "12"), ("20", "12")], daysOffset: 0)

        let records = Comparison.personalRecords(exerciseID: exerciseID, recordMode: .weightReps, across: [session])
        XCTAssertEqual(records.mostRepsAtWeight?.weight.canonicalString, "25")
        XCTAssertEqual(records.mostRepsAtWeight?.reps.canonicalString, "8")
        XCTAssertEqual(records.mostRepsAtWeight?.sessionID, sessionUUID(forSuffix: "1"))
    }

    func testSameTopWeightInTwoSessionsPicksTheOneWithMoreReps() throws {
        let sessions = try [
            makeSession(idSuffix: "1", sets: [("25", "10")], daysOffset: 0),
            makeSession(idSuffix: "2", sets: [("25", "8")], daysOffset: 3),
        ]

        let records = Comparison.personalRecords(exerciseID: exerciseID, recordMode: .weightReps, across: sessions)
        XCTAssertEqual(records.mostRepsAtWeight?.reps.canonicalString, "10")
        XCTAssertEqual(records.mostRepsAtWeight?.sessionID, sessionUUID(forSuffix: "1"))
    }

    func testExactTieGoesToTheMostRecentSessionRegardlessOfOrder() throws {
        let older = try makeSession(idSuffix: "1", sets: [("25", "8")], daysOffset: 0)
        let newer = try makeSession(idSuffix: "2", sets: [("25", "8")], daysOffset: 5)

        for order in [[older, newer], [newer, older]] {
            let records = Comparison.personalRecords(exerciseID: exerciseID, recordMode: .weightReps, across: order)
            XCTAssertEqual(records.mostRepsAtWeight?.sessionID, sessionUUID(forSuffix: "2"))
        }
    }

    // T069i (owner 2026-09-28): the comparison lists each shared exercise's
    // completed sets, merging consecutive identical sets into one line.
    func testSetRunsMergeConsecutiveIdenticalSets() throws {
        let newer = try makeSession(idSuffix: "1", sets: [("30", "10"), ("25", "12"), ("25", "12")], daysOffset: 12)
        let older = try makeSession(
            idSuffix: "2",
            sets: [("25", "12"), ("25", "12"), ("25", "12"), ("25", "12"), ("25", "12"), ("25", "12")],
            daysOffset: 0
        )

        let newerLines = HistoryPresentation.setRuns(newer.exercises[0].sets)
        let olderLines = HistoryPresentation.setRuns(older.exercises[0].sets)
        XCTAssertEqual(newerLines.count, 2)
        XCTAssertTrue(newerLines[1].hasSuffix("2 组"), newerLines[1])
        XCTAssertFalse(newerLines[0].contains("组"), newerLines[0])
        XCTAssertEqual(olderLines.count, 1)
        XCTAssertTrue(olderLines[0].hasSuffix("6 组"), olderLines[0])

        let shared = HistoryPresentation.sharedExercises(newer, older)
        XCTAssertEqual(shared.map(\.name), ["辅助引体向上"])
        XCTAssertEqual(shared[0].a, newerLines)
        XCTAssertEqual(shared[0].b, olderLines)
    }

    // MARK: - Fixtures

    private func makeSession(idSuffix: String, sets setValues: [(weight: String, reps: String)], daysOffset: Int) throws -> CompletedSession {
        let base = try makeSession(idSuffix: idSuffix, weight: setValues[0].weight, daysOffset: daysOffset)
        let exercise = base.exercises[0]
        let sets = try setValues.enumerated().map { index, value in
            try makeSet(orderIndex: UInt32(index), weight: value.weight, reps: value.reps, sessionExerciseID: exercise.id)
        }
        let rebuilt = try SessionExercise(
            id: exercise.id,
            sessionID: exercise.sessionID,
            orderIndex: exercise.orderIndex,
            sourceKind: exercise.sourceKind,
            sourceID: exercise.sourceID,
            displayNameSnapshot: exercise.displayNameSnapshot,
            recordModeSnapshot: exercise.recordModeSnapshot,
            actionPrivateNote: nil,
            sets: sets
        )
        return CompletedSession(
            id: base.id,
            studentID: base.studentID,
            studentDisplayName: base.studentDisplayName,
            startedAtUTC: base.startedAtUTC,
            completedAtUTC: base.completedAtUTC,
            trainingFocus: [],
            notes: base.notes,
            exercises: [rebuilt],
            statistics: SessionStatistics(
                completedSetCount: sets.count,
                displayedDurationSeconds: try DecimalValue("600"),
                ordinaryTrainingVolume: nil
            ),
            revision: 1,
            latestReport: nil
        )
    }

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
            trainingFocus: [],
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

    private func makeSet(orderIndex: UInt32, weight: String, reps: String = "8", sessionExerciseID: StableUUID) throws -> TrainingSet {
        try TrainingSet(
            id: StableUUID(UUID()),
            sessionExerciseID: sessionExerciseID,
            orderIndex: orderIndex,
            state: .completed,
            recordMode: .weightReps,
            weightValue: DecimalValue(weight),
            repetitionCount: DecimalValue(reps),
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
