import FineCoach
import XCTest

final class SessionSetDomainTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    private let sessionID = StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
    private let squatID = StableUUID(UUID(uuidString: "33333333-3333-4333-8333-333333333333")!)
    private let plankID = StableUUID(UUID(uuidString: "44444444-4444-4444-8444-444444444444")!)
    private let pullUpID = StableUUID(UUID(uuidString: "55555555-5555-4555-8555-555555555555")!)
    private let firstSetID = StableUUID(UUID(uuidString: "66666666-6666-4666-8666-666666666666")!)
    private let secondSetID = StableUUID(UUID(uuidString: "77777777-7777-4777-8777-777777777777")!)

    func testWeightZeroIsValidAndZeroRepsOrDurationCannotComplete() throws {
        let zeroWeight = try TrainingSet.makeDraft(
            id: firstSetID,
            sessionExerciseID: squatID,
            orderIndex: 0,
            input: TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "0",
                repetitionCount: "5",
                unit: .kilograms,
                side: .none
            ),
            now: now
        )
        XCTAssertEqual(zeroWeight.state, .draft)
        XCTAssertFalse(zeroWeight.contributesToStatistics)

        let completed = try zeroWeight.confirmed(now: now)
        XCTAssertEqual(completed.state, .completed)
        XCTAssertEqual(completed.weightValue?.canonicalString, DecimalValue.zero.canonicalString)
        XCTAssertEqual(completed.repetitionCount?.canonicalString, try DecimalValue("5").canonicalString)
        XCTAssertTrue(completed.contributesToStatistics)

        assertCannotComplete(
            TrainingSetInput(
                recordMode: .reps,
                repetitionCount: "0",
                unit: .repetitions
            ),
            .invalidNumber
        )
        assertCannotComplete(
            TrainingSetInput(
                recordMode: .duration,
                durationSeconds: "0",
                unit: .seconds
            ),
            .invalidNumber
        )
        assertCannotComplete(
            TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "0",
                unit: .kilograms
            ),
            .invalidNumber
        )
    }

    func testDecimalCanonicalFormRejectsBinaryFloatAndAcceptsCanonicalString() throws {
        let confirmed = try TrainingSet.makeDraft(
            id: firstSetID,
            sessionExerciseID: squatID,
            orderIndex: 0,
            input: TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "1.50",
                repetitionCount: "5",
                unit: .kilograms
            ),
            now: now
        ).confirmed(now: now)
        XCTAssertEqual(confirmed.weightValue?.canonicalString, try DecimalValue("1.50").canonicalString)
        XCTAssertEqual(confirmed.weightValue?.canonicalString, try DecimalValue("1.5").canonicalString)

        XCTAssertThrowsError(
            try TrainingSet.makeDraft(
                id: firstSetID,
                sessionExerciseID: squatID,
                orderIndex: 0,
                input: TrainingSetInput(
                    recordMode: .weightReps,
                    weightValue: "abc",
                    repetitionCount: "5",
                    unit: .kilograms
                ),
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidDecimal)
        }

        let trimmed = try TrainingSet.makeDraft(
            id: secondSetID,
            sessionExerciseID: squatID,
            orderIndex: 1,
            input: TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "  1.50  ",
                repetitionCount: " 5 ",
                unit: .kilograms
            ),
            now: now
        ).confirmed(now: now)
        XCTAssertEqual(trimmed.weightValue?.canonicalString, try DecimalValue("1.50").canonicalString)
        XCTAssertEqual(trimmed.repetitionCount?.canonicalString, try DecimalValue("5").canonicalString)
    }

    func testRecordModeValidationAndIncompleteSides() throws {
        assertCannotComplete(
            TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "60",
                repetitionCount: "5",
                durationSeconds: "30",
                unit: .kilograms
            ),
            .invalidMode
        )
        assertCannotComplete(
            TrainingSetInput(
                recordMode: .reps,
                weightValue: "60",
                repetitionCount: "10",
                unit: .repetitions
            ),
            .invalidMode
        )
        assertCannotComplete(
            TrainingSetInput(
                recordMode: .duration,
                repetitionCount: "10",
                durationSeconds: "30",
                unit: .seconds
            ),
            .invalidMode
        )

        assertCannotCompleteMatching(
            TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "40",
                repetitionCount: "8",
                unit: .kilograms,
                side: .bilateral,
                rightValue: "12"
            ),
            [.invalidNumber, .invalidState]
        )
        assertCannotCompleteMatching(
            TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "40",
                repetitionCount: "8",
                unit: .kilograms,
                side: .bilateral,
                leftValue: "10"
            ),
            [.invalidNumber, .invalidState]
        )

        let bilateral = try TrainingSet.makeDraft(
            id: firstSetID,
            sessionExerciseID: squatID,
            orderIndex: 0,
            input: TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "40",
                repetitionCount: "8",
                unit: .kilograms,
                side: .bilateral,
                leftValue: "10",
                rightValue: "12"
            ),
            now: now
        ).confirmed(now: now)
        XCTAssertEqual(bilateral.state, .completed)
        XCTAssertEqual(bilateral.side, .bilateral)
        XCTAssertEqual(bilateral.leftValue?.canonicalString, try DecimalValue("10").canonicalString)
        XCTAssertEqual(bilateral.rightValue?.canonicalString, try DecimalValue("12").canonicalString)
        XCTAssertTrue(bilateral.contributesToStatistics)

        assertCannotComplete(
            TrainingSetInput(
                recordMode: .reps,
                repetitionCount: "10",
                unit: .kilograms
            ),
            .invalidUnit
        )
    }

    func testCopyStaysPendingAndIsExcludedFromStatistics() throws {
        var session = Session.start(id: sessionID, studentID: studentID, now: now)
        session = try session.addingSessionOnlyExercise(
            id: squatID,
            displayName: "杠铃深蹲",
            recordMode: .weightReps,
            now: now
        )
        session = try session.addingSet(
            exerciseID: squatID,
            setID: firstSetID,
            input: TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "60",
                repetitionCount: "5",
                unit: .kilograms
            ),
            now: now
        )
        session = try session.confirmingSet(setID: firstSetID, now: now)
        XCTAssertEqual(session.finishGate, .canComplete)
        XCTAssertEqual(session.completedSetCount, 1)

        let original = try set(in: session, id: firstSetID)
        let pendingCopy = try original.copiedAsPending(id: secondSetID, orderIndex: 1, now: now)
        XCTAssertEqual(pendingCopy.state, .pending)
        XCTAssertNil(pendingCopy.completedAtUTC)
        XCTAssertFalse(pendingCopy.contributesToStatistics)

        let copiedSession = try session.copyingSet(sourceSetID: firstSetID, newSetID: secondSetID, now: now)
        let copiedSet = try set(in: copiedSession, id: secondSetID)
        XCTAssertEqual(copiedSet.state, .pending)
        XCTAssertNil(copiedSet.completedAtUTC)
        XCTAssertFalse(copiedSet.contributesToStatistics)
        XCTAssertEqual(copiedSession.statisticsSets.count, 1)
        XCTAssertEqual(copiedSession.statisticsSets.first?.id, firstSetID)
        XCTAssertEqual(copiedSession.completedSetCount, 1)
        XCTAssertEqual(copiedSession.finishGate, .unresolvedDrafts)

        let discarded = try copiedSession.discardingUnresolvedSets(now: now)
        XCTAssertEqual(discarded.finishGate, .canComplete)
        XCTAssertEqual(discarded.completedSetCount, 1)
        XCTAssertEqual(discarded.statisticsSets.count, 1)

        let changedInput = TrainingSetInput(
            recordMode: .weightReps,
            weightValue: "60",
            repetitionCount: "8",
            unit: .kilograms
        )
        let editedSession = try copiedSession.editingSet(setID: secondSetID, input: changedInput, now: now)
        let editedCopy = try set(in: editedSession, id: secondSetID)
        XCTAssertEqual(editedCopy.state, .draft)
        XCTAssertNotEqual(editedCopy.state, .completed)
        XCTAssertFalse(editedCopy.contributesToStatistics)
        XCTAssertEqual(editedSession.statisticsSets.count, 1)
        XCTAssertEqual(try pendingCopy.updating(input: changedInput, now: now).state, .draft)
    }

    func testUndoEditDeleteAndExerciseReorderAndDangerousDelete() throws {
        var session = Session.start(id: sessionID, studentID: studentID, now: now)
        session = try session.addingSessionOnlyExercise(
            id: squatID,
            displayName: "杠铃深蹲",
            recordMode: .weightReps,
            now: now
        )
        session = try session.addingSessionOnlyExercise(
            id: plankID,
            displayName: "平板支撑",
            recordMode: .duration,
            now: now
        )
        XCTAssertEqual(session.exercises.map(\.id), [squatID, plankID])

        session = try session.addingSet(
            exerciseID: squatID,
            setID: firstSetID,
            input: TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "60",
                repetitionCount: "5",
                unit: .kilograms
            ),
            now: now
        )
        session = try session.confirmingSet(setID: firstSetID, now: now)
        XCTAssertEqual(session.completedSetCount, 1)
        XCTAssertEqual(session.statisticsSets.count, 1)

        let confirmedSet = try set(in: session, id: firstSetID)
        XCTAssertEqual(try confirmedSet.undone(now: now).state, .pending)

        session = try session.undoingSet(setID: firstSetID, now: now)
        let undone = try set(in: session, id: firstSetID)
        XCTAssertEqual(undone.state, .pending)
        XCTAssertFalse(undone.contributesToStatistics)
        XCTAssertEqual(session.statisticsSets.count, 0)
        XCTAssertEqual(session.completedSetCount, 0)

        session = try session.deletingSet(setID: firstSetID, now: now)
        XCTAssertFalse(session.exercises.flatMap(\.sets).contains { $0.id == firstSetID })

        session = try session.reorderingExercises(ids: [plankID, squatID], now: now)
        XCTAssertEqual(session.exercises.map(\.id), [plankID, squatID])

        XCTAssertThrowsError(
            try session.reorderingExercises(ids: [plankID, plankID], now: now)
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
        XCTAssertThrowsError(
            try session.reorderingExercises(ids: [plankID], now: now)
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
        XCTAssertThrowsError(
            try session.reorderingExercises(ids: [plankID, squatID, pullUpID], now: now)
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }

        session = try session.addingSet(
            exerciseID: squatID,
            setID: firstSetID,
            input: TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "80",
                repetitionCount: "3",
                unit: .kilograms
            ),
            now: now
        )
        session = try session.confirmingSet(setID: firstSetID, now: now)
        XCTAssertThrowsError(
            try session.removingExercise(id: squatID, confirmedIfCompleted: false, now: now)
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
        session = try session.removingExercise(id: squatID, confirmedIfCompleted: true, now: now)
        XCTAssertEqual(session.exercises.map(\.id), [plankID])
        XCTAssertEqual(session.completedSetCount, 0)

        session = try session.removingExercise(id: plankID, confirmedIfCompleted: false, now: now)
        XCTAssertEqual(session.exercises.map(\.id), [])
        XCTAssertEqual(session.finishGate, .abandonEmpty)
        XCTAssertThrowsError(try session.finished(now: now)) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
        let abandoned = try session.abandoned(now: now)
        XCTAssertEqual(abandoned.state, .abandonedEmpty)

        var completable = Session.start(id: sessionID, studentID: studentID, now: now)
        completable = try completable.addingSessionOnlyExercise(
            id: pullUpID,
            displayName: "引体向上",
            recordMode: .reps,
            now: now
        )
        completable = try completable.addingSet(
            exerciseID: pullUpID,
            setID: firstSetID,
            input: TrainingSetInput(
                recordMode: .reps,
                repetitionCount: "8",
                unit: .repetitions
            ),
            now: now
        )
        completable = try completable.confirmingSet(setID: firstSetID, now: now)
        completable = try completable.addingSet(
            exerciseID: pullUpID,
            setID: secondSetID,
            input: TrainingSetInput(
                recordMode: .reps,
                repetitionCount: "6",
                unit: .repetitions
            ),
            now: now
        )
        XCTAssertEqual(completable.finishGate, .unresolvedDrafts)
        XCTAssertThrowsError(try completable.finished(now: now)) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
        let finished = try completable.discardingUnresolvedSets(now: now).finished(now: now)
        XCTAssertEqual(finished.state, .completed)
        XCTAssertEqual(finished.completedSetCount, 1)
        XCTAssertEqual(finished.finishGate, .canComplete)
    }

    func testRepetitionMustBePositiveInteger() {
        assertCannotComplete(
            TrainingSetInput(
                recordMode: .reps,
                repetitionCount: "5.5",
                unit: .repetitions
            ),
            .invalidNumber
        )
        assertCannotComplete(
            TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "60",
                repetitionCount: "-1",
                unit: .kilograms
            ),
            .invalidNumber
        )
    }

    private func set(in session: Session, id: StableUUID) throws -> TrainingSet {
        try XCTUnwrap(session.exercises.flatMap(\.sets).first { $0.id == id })
    }

    private func assertCannotComplete(
        _ input: TrainingSetInput,
        _ expected: DomainError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let draft = try TrainingSet.makeDraft(
                id: firstSetID,
                sessionExerciseID: squatID,
                orderIndex: 0,
                input: input,
                now: now
            )
            XCTAssertThrowsError(try draft.confirmed(now: now), file: file, line: line) { error in
                XCTAssertEqual(error as? DomainError, expected, file: file, line: line)
            }
        } catch {
            XCTAssertEqual(error as? DomainError, expected, file: file, line: line)
        }
    }

    private func assertCannotCompleteMatching(
        _ input: TrainingSetInput,
        _ expected: [DomainError],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let draft = try TrainingSet.makeDraft(
                id: firstSetID,
                sessionExerciseID: squatID,
                orderIndex: 0,
                input: input,
                now: now
            )
            XCTAssertThrowsError(try draft.confirmed(now: now), file: file, line: line) { error in
                XCTAssertTrue(
                    expected.contains { $0 == error as? DomainError },
                    file: file,
                    line: line
                )
            }
        } catch {
            XCTAssertTrue(expected.contains { $0 == error as? DomainError }, file: file, line: line)
        }
    }
}
