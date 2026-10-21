import XCTest

@testable import FineCoach

final class SessionGainsTests: XCTestCase {
    private let student = StableUUID(UUID())
    private let source = StableExerciseID(rawValue: "fictional.exercise")!

    func testFirstExerciseTieAndSessionOnlyDoNotProduceRecords() throws {
        let current = try session(number: 2, values: [("80", "5")])
        XCTAssertTrue(SessionGains(current: current, history: []).isEmpty)
        let older = try session(number: 1, values: [("80", "5")])
        XCTAssertTrue(SessionGains(current: current, history: [older]).isEmpty)
        let temporary = try session(number: 2, values: [("90", "5")], stable: false)
        XCTAssertTrue(SessionGains(current: temporary, history: [older]).isEmpty)
    }

    func testHolderTransfersOnlyOnStrictImprovementAndRecomputesAfterEditsUndoAndDeletion() throws {
        let older = try session(number: 1, values: [("80", "5")])
        let current = try session(number: 2, values: [("82", "5"), ("85", "5"), ("85", "5")])
        let gains = SessionGains(current: current, history: [older])
        XCTAssertEqual(gains.recordHolderSetIDs, [current.exercises[0].sets[1].id])
        XCTAssertEqual(gains.records.count, 1)
        XCTAssertTrue(gains.progress.isEmpty)
        let edited = try session(number: 2, values: [("82", "5"), ("79", "5")])
        XCTAssertEqual(
            SessionGains(current: edited, history: [older]).recordHolderSetIDs, [edited.exercises[0].sets[0].id])
        let deleted = try session(number: 2, values: [("79", "5")])
        XCTAssertTrue(SessionGains(current: deleted, history: [older]).records.isEmpty)
        var active = Session.start(id: current.id, studentID: student, now: current.startedAtUTC)
        active = active.replacingExercisesForGainsTest(current.exercises)
        XCTAssertEqual(SessionGains(current: active, history: [older]).recordHolderSetIDs, gains.recordHolderSetIDs)
        active = active.replacingExercisesForGainsTest([])
        XCTAssertTrue(SessionGains(current: active, history: [older]).recordHolderSetIDs.isEmpty)
    }

    func testAssistedDirectionAndSameWeightRepetitions() throws {
        let older = try session(number: 1, values: [("40", "5")])
        let lower = try session(number: 2, values: [("30", "5")])
        XCTAssertTrue(SessionGains(current: lower, history: [older]).records.isEmpty)
        XCTAssertEqual(SessionGains(current: lower, history: [older], assistedExerciseIDs: [source]).records.count, 1)
        let reps = try session(number: 2, values: [("40", "6")])
        XCTAssertEqual(SessionGains(current: reps, history: [older]).records.first?.kind, .mostRepsAtWeight)
        let higher = try session(number: 2, values: [("50", "5")])
        XCTAssertTrue(SessionGains(current: higher, history: [older], assistedExerciseIDs: [source]).records.isEmpty)
    }

    func testDurationAndCardioDistanceHaveIndependentHolders() throws {
        for mode in [RecordMode.duration, .cardio] {
            let older = try session(number: 1, values: [("60", "1")], mode: mode)
            let current = try session(number: 2, values: [("65", "1"), ("60", "2")], mode: mode)
            let gains = SessionGains(current: current, history: [older])
            XCTAssertEqual(gains.records.first?.kind, .longestDuration)
            XCTAssertTrue(gains.recordHolderSetIDs.contains(current.exercises[0].sets[0].id))
            if mode == .cardio {
                XCTAssertTrue(gains.recordHolderSetIDs.contains(current.exercises[0].sets[1].id))
            }
        }
    }

    func testBaselineExcludesLaterOtherStudentAndDifferentModeSessions() throws {
        let older = try session(number: 1, values: [("80", "5")])
        let current = try session(number: 2, values: [("85", "5")])
        let future = try session(number: 3, values: [("100", "5")])
        let other = try session(number: 0, values: [("200", "5")], studentID: StableUUID(UUID()))
        let wrongMode = try session(number: 0, values: [("200", "5")], mode: .duration)
        XCTAssertEqual(
            SessionGains(current: current, history: [future, other, older, wrongMode, current]).records.count, 1)
        XCTAssertTrue(SessionGains(current: current, history: [future, other, wrongMode]).records.isEmpty)
    }

    func testProgressUsesLastSessionAndDoesNotListEqualOrWorseOrRecordAgain() throws {
        let best = try session(number: 1, values: [("100", "5")])
        let last = try session(number: 2, values: [("80", "5"), ("70", "10")])
        let current = try session(number: 3, values: [("80", "7")])
        let gains = SessionGains(current: current, history: [best, last])
        XCTAssertTrue(gains.records.isEmpty)
        XCTAssertEqual(gains.progress.count, 1)
        XCTAssertEqual(gains.progress[0].previous.weightValue?.canonicalString, "80")
        for value in ["5", "4"] {
            let unchanged = try session(number: 3, values: [("80", value)])
            XCTAssertTrue(SessionGains(current: unchanged, history: [best, last]).progress.isEmpty)
        }
        let record = try session(number: 3, values: [("110", "5")])
        XCTAssertTrue(SessionGains(current: record, history: [best, last]).progress.isEmpty)
    }

    func testMilestoneBoundariesAndEqualCompletionTimeIDOrder() throws {
        for number in [9, 10, 11, 25, 50, 100, 149, 150, 151, 200] {
            let history = try (1..<number).map { try session(number: $0, values: [("80", "5")]) }
            let current = try session(number: number, values: [("80", "5")])
            XCTAssertEqual(
                SessionGains(current: current, history: history).milestoneSessionNumber,
                [10, 25, 50, 100, 150, 200].contains(number) ? number : nil)
        }
        let history = try (1...8).map { try session(number: $0, values: [("80", "5")]) }
        let ninth = try session(number: 9, values: [("80", "5")])
        let tenth = try session(number: 10, values: [("80", "5")], at: ninth.completedAtUTC)
        XCTAssertEqual(SessionGains(current: tenth, history: history + [ninth]).milestoneSessionNumber, 10)
        XCTAssertNil(SessionGains(current: ninth, history: history + [tenth]).milestoneSessionNumber)
    }

    private func session(
        number: Int, values: [(String, String)], mode: RecordMode = .weightReps,
        stable: Bool = true, studentID: StableUUID? = nil, at: Date? = nil
    ) throws -> CompletedSession {
        let id = StableUUID(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))!)
        let exerciseID = StableUUID(UUID())
        let date = at ?? Date(timeIntervalSince1970: Double(number * 1000))
        let sets = try values.enumerated().map { index, value in
            TrainingSet(
                id: StableUUID(UUID()), sessionExerciseID: exerciseID, orderIndex: UInt32(index), state: .completed,
                recordMode: mode, weightValue: mode == .weightReps ? try DecimalValue(value.0) : nil,
                repetitionCount: mode == .weightReps ? try DecimalValue(value.1) : nil,
                durationSeconds: mode == .duration || mode == .cardio ? try DecimalValue(value.0) : nil,
                unit: mode == .weightReps ? .kilograms : .seconds, side: .none, leftValue: nil, rightValue: nil,
                distanceValue: mode == .cardio ? try DecimalValue(value.1) : nil,
                createdAtUTC: date, updatedAtUTC: date, completedAtUTC: date)
        }
        let exercise = SessionExercise(
            id: exerciseID, sessionID: id, orderIndex: 0,
            sourceKind: stable ? .builtIn : .sessionOnly, sourceID: stable ? source : nil,
            displayNameSnapshot: try NormalizedName("合成动作"), recordModeSnapshot: mode,
            actionPrivateNote: nil, sets: sets)
        return CompletedSession(
            id: id, studentID: studentID ?? student, studentDisplayName: try NormalizedName("合成学员"),
            startedAtUTC: date.addingTimeInterval(-100), completedAtUTC: date, trainingFocus: [],
            notes: SessionNotes(privateCoachNote: nil, studentFacingSummary: nil, actionPrivateNotes: [:]),
            exercises: [exercise],
            statistics: SessionStatistics(
                completedSetCount: sets.count, displayedDurationSeconds: .zero, ordinaryTrainingVolume: nil),
            revision: 1, latestReport: nil)
    }
}

extension Session {
    fileprivate func replacingExercisesForGainsTest(_ exercises: [SessionExercise]) -> Session {
        Session(
            id: id, studentID: studentID, state: state, startedAtUTC: startedAtUTC,
            lastCheckpointUTC: lastCheckpointUTC,
            elapsedSeconds: elapsedSeconds, interruptionStartedAtUTC: interruptionStartedAtUTC,
            durationNeedsReview: durationNeedsReview,
            coachAdjustedDurationSeconds: coachAdjustedDurationSeconds, trainingFocus: trainingFocus,
            studentFacingSummary: studentFacingSummary, privateCoachNote: privateCoachNote, revision: revision,
            createdAtUTC: createdAtUTC, updatedAtUTC: updatedAtUTC, completedAtUTC: completedAtUTC, exercises: exercises
        )
    }
}
