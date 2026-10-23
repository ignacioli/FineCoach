import XCTest

@testable import FineCoach

final class SessionGainsTests: XCTestCase {
    private let student = StableUUID(UUID())
    private let source = StableExerciseID(rawValue: "fictional.exercise")!

    func testFirstExerciseTieAndSessionOnlyDoNotProduceRecords() throws {
        let current = try session(number: 2, values: [("80", "5")])
        XCTAssertTrue(SessionGains(current: current, history: []).isEmpty)
        XCTAssertTrue(SessionGains(current: current, history: []).rows.isEmpty)
        let older = try session(number: 1, values: [("80", "5")])
        XCTAssertTrue(SessionGains(current: current, history: [older]).isEmpty)
        XCTAssertTrue(SessionGains(current: current, history: [older]).rows.isEmpty)
        let temporary = try session(number: 2, values: [("90", "5")], stable: false)
        XCTAssertTrue(SessionGains(current: temporary, history: [older]).isEmpty)
    }

    func testHolderTransfersOnlyOnStrictImprovementAndRecomputesAfterEditsUndoAndDeletion() throws {
        let older = try session(number: 1, values: [("80", "5")])
        let current = try session(number: 2, values: [("82", "5"), ("85", "5"), ("85", "5")])
        let gains = SessionGains(current: current, history: [older])
        XCTAssertEqual(gains.recordHolderSetIDs, [current.exercises[0].sets[1].id])
        // Two identical 85 kg sets exist, so the holder is not strictly above
        // every other set of the session (no new-record haptic).
        XCTAssertTrue(gains.strictRecordHolderSetIDs.isEmpty)
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

    /// Revision 1.5: same weight, more reps is progress -- never a record.
    func testSameWeightMoreRepsIsProgressNotRecordButTakesTheHolderOnceABetterWeightSetExists() throws {
        let older = try session(number: 1, values: [("80", "5")])

        let sameWeight = try session(number: 2, values: [("80", "7")])
        let plain = SessionGains(current: sameWeight, history: [older])
        XCTAssertTrue(plain.records.isEmpty)
        XCTAssertTrue(plain.recordHolderSetIDs.isEmpty)
        XCTAssertEqual(plain.rows.count, 1)
        XCTAssertFalse(plain.rows[0].isNewRecord)
        XCTAssertEqual(plain.rows[0].previous.repetitionCount?.canonicalString, "5")
        XCTAssertEqual(plain.rows[0].current.repetitionCount?.canonicalString, "7")

        // 85 kg 5 reps sets the record; the later 85 kg 8 reps set takes over the
        // badge (tie-break on reps) without being a new-record improvement.
        let transfer = try session(number: 2, values: [("85", "5"), ("85", "8")])
        let gains = SessionGains(current: transfer, history: [older])
        XCTAssertEqual(gains.records.count, 1)
        XCTAssertEqual(gains.recordHolderSetIDs, [transfer.exercises[0].sets[1].id])
        XCTAssertTrue(gains.strictRecordHolderSetIDs.isEmpty)
        XCTAssertEqual(gains.rows.count, 1)
        XCTAssertTrue(gains.rows[0].isNewRecord)
        XCTAssertEqual(gains.rows[0].current.repetitionCount?.canonicalString, "8")
    }

    func testHigherWeightFewerRepsIsARecordButNotProgress() throws {
        let older = try session(number: 1, values: [("80", "8")])
        let current = try session(number: 2, values: [("85", "5")])
        let gains = SessionGains(current: current, history: [older])
        XCTAssertEqual(gains.records.first?.kind, .highestWeight)
        XCTAssertEqual(gains.recordHolderSetIDs, [current.exercises[0].sets[0].id])
        XCTAssertEqual(gains.strictRecordHolderSetIDs, [current.exercises[0].sets[0].id])
        XCTAssertTrue(gains.progress.isEmpty)
        XCTAssertEqual(gains.rows.count, 1)
        XCTAssertTrue(gains.rows[0].isNewRecord)
        XCTAssertEqual(gains.rows[0].previous.displaySummary, "80 kg × 8")
        XCTAssertEqual(gains.rows[0].current.displaySummary, "85 kg × 5")
    }

    func testTwoMetricsBetterWithoutBeatingHistoryIsProgress() throws {
        let best = try session(number: 1, values: [("100", "5")])
        let last = try session(number: 2, values: [("80", "5")])
        let current = try session(number: 3, values: [("85", "6")])
        let gains = SessionGains(current: current, history: [best, last])
        XCTAssertTrue(gains.records.isEmpty)
        XCTAssertTrue(gains.recordHolderSetIDs.isEmpty)
        XCTAssertEqual(gains.rows.count, 1)
        XCTAssertFalse(gains.rows[0].isNewRecord)
        XCTAssertEqual(gains.progress.count, 1)
        XCTAssertEqual(gains.rows[0].previous.displaySummary, "80 kg × 5")
        XCTAssertEqual(gains.rows[0].current.displaySummary, "85 kg × 6")
    }

    func testOneBetterOneWorseAndSingleSetVolumeAreNotListed() throws {
        let best = try session(number: 1, values: [("100", "5")])
        let last = try session(number: 2, values: [("80", "5")])

        // Heavier but fewer reps: one better, one worse.
        let heavierFewer = try session(number: 3, values: [("85", "4")])
        XCTAssertTrue(SessionGains(current: heavierFewer, history: [best, last]).rows.isEmpty)

        // Lighter but more reps: still one better, one worse.
        let lighterMore = try session(number: 3, values: [("75", "8")])
        XCTAssertTrue(SessionGains(current: lighterMore, history: [best, last]).rows.isEmpty)

        // Higher single-set volume (75 x 12 = 900 > 80 x 5 = 400) is not a
        // record and not progress under Revision 1.5.
        let volume = try session(number: 3, values: [("75", "12")])
        let gains = SessionGains(current: volume, history: [best, last])
        XCTAssertTrue(gains.records.isEmpty)
        XCTAssertTrue(gains.rows.isEmpty)
    }

    func testTieIsNotListed() throws {
        let last = try session(number: 1, values: [("80", "5")])
        let current = try session(number: 2, values: [("80", "5")])
        let gains = SessionGains(current: current, history: [last])
        XCTAssertTrue(gains.records.isEmpty)
        XCTAssertTrue(gains.rows.isEmpty)
        XCTAssertTrue(gains.isEmpty)
    }

    func testAssistedDirectionAndSameWeightRepetitions() throws {
        let older = try session(number: 1, values: [("40", "5")])

        let lower = try session(number: 2, values: [("30", "5")])
        XCTAssertTrue(SessionGains(current: lower, history: [older]).records.isEmpty)
        let assisted = SessionGains(current: lower, history: [older], assistedExerciseIDs: [source])
        XCTAssertEqual(assisted.records.count, 1)
        XCTAssertEqual(assisted.records.first?.kind, .highestWeight)
        XCTAssertEqual(assisted.recordHolderSetIDs, [lower.exercises[0].sets[0].id])
        XCTAssertEqual(assisted.rows.count, 1)
        XCTAssertTrue(assisted.rows[0].isNewRecord)

        // Same assisted weight, more reps: progress, not a record.
        let reps = try session(number: 2, values: [("40", "6")])
        let assistedSameWeight = SessionGains(
            current: reps, history: [older], assistedExerciseIDs: [source])
        XCTAssertTrue(assistedSameWeight.records.isEmpty)
        XCTAssertEqual(assistedSameWeight.rows.count, 1)
        XCTAssertFalse(assistedSameWeight.rows[0].isNewRecord)

        // Same rule for an ordinary exercise: more reps at the same weight is
        // progress, never a record (Revision 1.5).
        let ordinarySameWeight = SessionGains(current: reps, history: [older])
        XCTAssertTrue(ordinarySameWeight.records.isEmpty)
        XCTAssertTrue(ordinarySameWeight.recordHolderSetIDs.isEmpty)
        XCTAssertEqual(ordinarySameWeight.rows.count, 1)
        XCTAssertFalse(ordinarySameWeight.rows[0].isNewRecord)

        let higher = try session(number: 2, values: [("50", "5")])
        XCTAssertTrue(SessionGains(current: higher, history: [older], assistedExerciseIDs: [source]).records.isEmpty)
        XCTAssertEqual(SessionGains(current: higher, history: [older]).records.count, 1)
    }

    func testDurationAndCardioRecordTheirDuration() throws {
        for mode in [RecordMode.duration, .cardio] {
            let older = try session(number: 1, values: [("60", "1")], mode: mode)
            let current = try session(number: 2, values: [("65", "1"), ("60", "2")], mode: mode)
            let gains = SessionGains(current: current, history: [older])
            XCTAssertEqual(gains.records.first?.kind, .longestDuration)
            XCTAssertEqual(gains.recordHolderSetIDs, [current.exercises[0].sets[0].id])
            XCTAssertEqual(gains.rows.count, 1)
            XCTAssertTrue(gains.rows[0].isNewRecord)
        }
    }

    func testCardioDoesNotUseDistanceAsARecord() throws {
        let older = try session(number: 1, values: [("60", "1")], mode: .cardio)
        // Longer distance with a shorter duration: no record, no progress.
        let current = try session(number: 2, values: [("50", "5")], mode: .cardio)
        let gains = SessionGains(current: current, history: [older])
        XCTAssertTrue(gains.records.isEmpty)
        XCTAssertTrue(gains.recordHolderSetIDs.isEmpty)
        XCTAssertTrue(gains.rows.isEmpty)
    }

    func testRepsRecordIsStrictlyMoreRepetitions() throws {
        let older = try session(number: 1, values: [("8", "0")], mode: .reps)
        let current = try session(number: 2, values: [("10", "0"), ("9", "0")], mode: .reps)
        let gains = SessionGains(current: current, history: [older])
        XCTAssertEqual(gains.records.first?.kind, .mostReps)
        XCTAssertEqual(gains.recordHolderSetIDs, [current.exercises[0].sets[0].id])
        XCTAssertEqual(gains.strictRecordHolderSetIDs, [current.exercises[0].sets[0].id])
        XCTAssertEqual(gains.rows.count, 1)
        XCTAssertTrue(gains.rows[0].isNewRecord)

        let tie = try session(number: 2, values: [("8", "0")], mode: .reps)
        XCTAssertTrue(SessionGains(current: tie, history: [older]).records.isEmpty)
        XCTAssertTrue(SessionGains(current: tie, history: [older]).rows.isEmpty)
    }

    /// Only a set whose main metric strictly beats history AND every earlier
    /// set of this session is a new-record haptic (D-FR-013, Revision 1.5).
    func testOnlyAStrictMainMetricImprovementIsAHapticNewRecord() throws {
        let older = try session(number: 1, values: [("80", "5")])

        let strict = try session(number: 2, values: [("85", "5")])
        XCTAssertEqual(
            SessionGains(current: strict, history: [older]).strictRecordHolderSetIDs,
            [strict.exercises[0].sets[0].id])

        let tieTransfer = try session(number: 2, values: [("85", "5"), ("85", "8")])
        XCTAssertTrue(SessionGains(current: tieTransfer, history: [older]).strictRecordHolderSetIDs.isEmpty)

        let heavier = try session(number: 2, values: [("85", "5"), ("90", "3")])
        XCTAssertEqual(
            SessionGains(current: heavier, history: [older]).strictRecordHolderSetIDs,
            [heavier.exercises[0].sets[1].id])

        // An identical later set keeps the earlier holder (equality keeps the
        // earlier set); the holder is no longer strictly above every set, so
        // the later confirmation is a plain success, not a new-record haptic.
        let repeated = try session(number: 2, values: [("85", "5"), ("85", "5")])
        let repeatedGains = SessionGains(current: repeated, history: [older])
        XCTAssertEqual(repeatedGains.recordHolderSetIDs, [repeated.exercises[0].sets[0].id])
        XCTAssertTrue(repeatedGains.strictRecordHolderSetIDs.isEmpty)
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
        XCTAssertEqual(SessionGains(current: record, history: [best, last]).rows.count, 1)
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
                recordMode: mode,
                weightValue: mode == .weightReps ? try DecimalValue(value.0) : nil,
                repetitionCount: mode == .reps
                    ? try DecimalValue(value.0) : (mode == .weightReps ? try DecimalValue(value.1) : nil),
                durationSeconds: mode == .duration || mode == .cardio ? try DecimalValue(value.0) : nil,
                unit: mode == .weightReps ? .kilograms : (mode == .reps ? .repetitions : .seconds), side: .none,
                leftValue: nil, rightValue: nil,
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
