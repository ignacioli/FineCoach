import XCTest

@testable import FineCoach

/// Experience P0-D1: the "上次" reference and first-set prefill must come from
/// the newest completed Session that has completed sets of the same Exercise
/// (same `sourceID` and record mode, as in the trend view), never from array
/// order, drafts/pending sets, or a different record mode.
final class LastExercisePerformanceLookupTests: XCTestCase {
    private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    private let squat = StableExerciseID(rawValue: "fc.test.squat")!
    private let bench = StableExerciseID(rawValue: "fc.test.bench")!
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testPicksNewestSessionRegardlessOfArrayOrder() throws {
        let older = try makeSession(days: 0, exercises: [(squat, nil, .weightReps, [("100", .completed)])])
        let newer = try makeSession(
            days: 7, exercises: [(squat, nil, .weightReps, [("110", .completed), ("115", .completed)])])

        for order in [[older, newer], [newer, older]] {
            let performance = try XCTUnwrap(
                LastExercisePerformanceLookup(sessions: order).performance(for: try current(squat))
            )
            XCTAssertEqual(performance.sessionID, newer.id)
            XCTAssertEqual(performance.sets.map { $0.weightValue?.canonicalString }, ["110", "115"])
            XCTAssertEqual(performance.firstSet.weightValue?.canonicalString, "110")
        }
    }

    func testSkipsSessionsWithoutCompletedSetsOfThatExercise() throws {
        let older = try makeSession(days: 0, exercises: [(squat, nil, .weightReps, [("100", .completed)])])
        let newerOnlyPending = try makeSession(days: 7, exercises: [(squat, nil, .weightReps, [("120", .pending)])])

        let performance = try XCTUnwrap(
            LastExercisePerformanceLookup(sessions: [older, newerOnlyPending]).performance(for: try current(squat))
        )
        XCTAssertEqual(performance.sessionID, older.id)
        XCTAssertEqual(performance.sets.count, 1)
    }

    func testDropsNonCompletedSetsFromTheMatchedSession() throws {
        let session = try makeSession(
            days: 0,
            exercises: [(squat, nil, .weightReps, [("100", .completed), ("105", .draft), ("110", .completed)])]
        )
        let performance = try XCTUnwrap(
            LastExercisePerformanceLookup(sessions: [session]).performance(for: try current(squat))
        )
        XCTAssertEqual(performance.sets.map { $0.weightValue?.canonicalString }, ["100", "110"])
    }

    func testMatchesBySourceIDAndRecordModeOnly() throws {
        let session = try makeSession(
            days: 0,
            exercises: [
                (squat, nil, .reps, [("100", .completed)]),
                (bench, nil, .weightReps, [("60", .completed)]),
            ]
        )
        let lookup = LastExercisePerformanceLookup(sessions: [session])
        XCTAssertNil(lookup.performance(for: try current(squat)), "different record mode must not match")
        XCTAssertEqual(lookup.performance(for: try current(bench))?.firstSet.weightValue?.canonicalString, "60")
    }

    func testSessionOnlyExerciseMatchesByNameAndNeverACatalogExercise() throws {
        let session = try makeSession(
            days: 0,
            exercises: [
                (nil, "弹力带深蹲", .weightReps, [("10", .completed)]),
                (squat, "弹力带深蹲", .weightReps, [("99", .completed)]),
            ]
        )
        let lookup = LastExercisePerformanceLookup(sessions: [session])
        XCTAssertEqual(
            lookup.performance(for: try current(nil, name: "弹力带深蹲"))?.firstSet.weightValue?.canonicalString,
            "10"
        )
        XCTAssertNil(lookup.performance(for: try current(nil, name: "壶铃摆")))
    }

    func testEmptyHistoryHasNoPerformance() throws {
        XCTAssertNil(LastExercisePerformanceLookup.empty.performance(for: try current(squat)))
    }

    func testReferenceTextUsesTheFirstSetAndTheCompletedCount() throws {
        let session = try makeSession(
            days: 0,
            exercises: [(squat, nil, .weightReps, [("120", .completed), ("122.5", .completed)])]
        )
        let performance = try XCTUnwrap(
            LastExercisePerformanceLookup(sessions: [session]).performance(for: try current(squat))
        )
        XCTAssertEqual(performance.firstSet.displaySummary, "120 kg × 8")
        XCTAssertEqual(
            performance.referenceText,
            String(
                format: String(localized: "session.lastReferenceFormat"),
                locale: Locale(identifier: "en_US_POSIX"),
                "120 kg × 8",
                2
            )
        )
    }

    // MARK: - Fixtures

    private typealias ExerciseSpec = (StableExerciseID?, String?, RecordMode, [(String, SetRecordingState)])

    private func current(_ sourceID: StableExerciseID?, name: String = "深蹲") throws -> SessionExercise {
        SessionExercise(
            id: StableUUID(UUID()),
            sessionID: StableUUID(UUID()),
            orderIndex: 0,
            sourceKind: sourceID == nil ? .sessionOnly : .builtIn,
            sourceID: sourceID,
            displayNameSnapshot: try NormalizedName(name),
            recordModeSnapshot: .weightReps,
            actionPrivateNote: nil,
            sets: []
        )
    }

    private func makeSession(days: Double, exercises: [ExerciseSpec]) throws -> CompletedSession {
        let sessionID = StableUUID(UUID())
        let completedAt = base.addingTimeInterval(days * 86_400)
        let built = try exercises.enumerated().map { index, spec in
            let exerciseID = StableUUID(UUID())
            let sets = try spec.3.enumerated().map { setIndex, value in
                try TrainingSet(
                    id: StableUUID(UUID()),
                    sessionExerciseID: exerciseID,
                    orderIndex: UInt32(setIndex),
                    state: value.1,
                    recordMode: spec.2,
                    weightValue: DecimalValue(value.0),
                    repetitionCount: DecimalValue("8"),
                    durationSeconds: nil,
                    unit: .kilograms,
                    side: .none,
                    leftValue: nil,
                    rightValue: nil,
                    createdAtUTC: completedAt,
                    updatedAtUTC: completedAt,
                    completedAtUTC: value.1 == .completed ? completedAt : nil
                )
            }
            return SessionExercise(
                id: exerciseID,
                sessionID: sessionID,
                orderIndex: UInt32(index),
                sourceKind: spec.0 == nil ? .sessionOnly : .builtIn,
                sourceID: spec.0,
                displayNameSnapshot: try NormalizedName(spec.1 ?? "深蹲"),
                recordModeSnapshot: spec.2,
                actionPrivateNote: nil,
                sets: sets
            )
        }
        return CompletedSession(
            id: sessionID,
            studentID: studentID,
            studentDisplayName: try NormalizedName("林青"),
            startedAtUTC: completedAt.addingTimeInterval(-600),
            completedAtUTC: completedAt,
            trainingFocus: [],
            notes: SessionNotes(privateCoachNote: nil, studentFacingSummary: nil, actionPrivateNotes: [:]),
            exercises: built,
            statistics: SessionStatistics(
                completedSetCount: 0,
                displayedDurationSeconds: try DecimalValue("600"),
                ordinaryTrainingVolume: nil
            ),
            revision: 1,
            latestReport: nil
        )
    }
}
