import FineCoach
import XCTest

final class HistoryReportDomainTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    private let sessionID = StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
    private let squatID = StableUUID(UUID(uuidString: "33333333-3333-4333-8333-333333333333")!)
    private let plankID = StableUUID(UUID(uuidString: "44444444-4444-4444-8444-444444444444")!)
    private let pullUpID = StableUUID(UUID(uuidString: "55555555-5555-4555-8555-555555555555")!)
    private let firstSetID = StableUUID(UUID(uuidString: "66666666-6666-4666-8666-666666666666")!)
    private let secondSetID = StableUUID(UUID(uuidString: "77777777-7777-4777-8777-777777777777")!)
    private let draftSetID = StableUUID(UUID(uuidString: "88888888-8888-4888-8888-888888888888")!)
    private let rowID = StableUUID(UUID(uuidString: "99999999-9999-4999-8999-999999999999")!)
    private let rowSetID = StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
    private let leftID = StableUUID(UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
    private let leftSetID = StableUUID(UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!)
    private let rightID = StableUUID(UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!)
    private let rightSetID = StableUUID(UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!)
    private let pullUpSetID = StableUUID(UUID(uuidString: "12121212-1212-4212-8212-121212121212")!)
    private let plankSetID = StableUUID(UUID(uuidString: "13131313-1313-4313-8313-131313131313")!)
    private let reportID = StableUUID(UUID(uuidString: "14141414-1414-4414-8414-141414141414")!)

    func testNoteKindsStayIsolatedAndNonCompletedSessionsCannotMakeCompletedSession() throws {
        let studentName = try NormalizedName("林青")
        let inProgress = try inProgressSessionWithCompletedSquat()
        XCTAssertEqual(inProgress.state, .inProgress)
        XCTAssertThrowsError(
            try CompletedSession.make(from: inProgress, studentDisplayName: studentName)
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
        XCTAssertThrowsError(
            try inProgress.updatingPrivateCoachNote(try ValidatedText("合成教练备注"), now: now)
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
        XCTAssertThrowsError(
            try inProgress.updatingStudentFacingSummary(try ValidatedText("合成课后总结"), now: now)
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
        XCTAssertThrowsError(
            try inProgress.updatingActionPrivateNote(
                exerciseID: squatID,
                note: try ValidatedText("合成动作备注"),
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
        XCTAssertThrowsError(
            try inProgress.updatingTrainingFocus(try ValidatedText("下肢力量"), now: now)
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }

        let abandoned = try Session.start(id: sessionID, studentID: studentID, now: now).abandoned(now: now)
        XCTAssertEqual(abandoned.state, .abandonedEmpty)
        XCTAssertThrowsError(
            try CompletedSession.make(from: abandoned, studentDisplayName: studentName)
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
        XCTAssertThrowsError(
            try abandoned.updatingPrivateCoachNote(try ValidatedText("合成教练备注"), now: now)
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }

        var session = try addingConfirmedExercise(
            inProgress,
            id: pullUpID,
            displayName: "引体向上",
            recordMode: .reps,
            setID: pullUpSetID,
            input: TrainingSetInput(
                recordMode: .reps,
                repetitionCount: "8",
                unit: .repetitions
            )
        )
        session = try session.finished(now: now)
        XCTAssertEqual(session.state, .completed)
        XCTAssertNil(session.sessionNotes.privateCoachNote)
        XCTAssertNil(session.sessionNotes.studentFacingSummary)
        XCTAssertTrue(session.sessionNotes.actionPrivateNotes.isEmpty)

        let revisionBeforePrivateNote = session.revision
        let afterPrivateNote = now.addingTimeInterval(10)
        session = try session.updatingPrivateCoachNote(try ValidatedText("合成教练备注"), now: afterPrivateNote)
        XCTAssertGreaterThan(session.revision, revisionBeforePrivateNote)
        XCTAssertEqual(session.sessionNotes.privateCoachNote?.value, "合成教练备注")
        XCTAssertNil(session.sessionNotes.studentFacingSummary)
        XCTAssertTrue(session.sessionNotes.actionPrivateNotes.isEmpty)
        XCTAssertNil(session.trainingFocus)
        XCTAssertEqual(session.privateCoachNote?.value, "合成教练备注")

        let afterSummary = afterPrivateNote.addingTimeInterval(10)
        session = try session.updatingStudentFacingSummary(try ValidatedText("合成课后总结"), now: afterSummary)
        XCTAssertEqual(session.sessionNotes.studentFacingSummary?.value, "合成课后总结")
        XCTAssertEqual(session.sessionNotes.privateCoachNote?.value, "合成教练备注")
        XCTAssertTrue(session.sessionNotes.actionPrivateNotes.isEmpty)
        XCTAssertNotEqual(session.sessionNotes.privateCoachNote, session.sessionNotes.studentFacingSummary)

        let afterAction = afterSummary.addingTimeInterval(10)
        session = try session.updatingActionPrivateNote(
            exerciseID: squatID,
            note: try ValidatedText("合成动作备注"),
            now: afterAction
        )
        XCTAssertEqual(session.sessionNotes.actionPrivateNotes[squatID]?.value, "合成动作备注")
        XCTAssertNil(session.sessionNotes.actionPrivateNotes[pullUpID])
        XCTAssertEqual(session.sessionNotes.actionPrivateNotes.count, 1)
        XCTAssertEqual(session.sessionNotes.privateCoachNote?.value, "合成教练备注")
        XCTAssertEqual(session.sessionNotes.studentFacingSummary?.value, "合成课后总结")
        XCTAssertEqual(
            try setExercise(in: session, id: squatID).actionPrivateNote?.value,
            "合成动作备注"
        )
        XCTAssertNil(try setExercise(in: session, id: pullUpID).actionPrivateNote)

        let afterFocus = afterAction.addingTimeInterval(10)
        let revisionBeforeFocus = session.revision
        session = try session.updatingTrainingFocus(try ValidatedText("下肢力量"), now: afterFocus)
        XCTAssertGreaterThan(session.revision, revisionBeforeFocus)
        XCTAssertEqual(session.trainingFocus?.value, "下肢力量")
        XCTAssertEqual(session.sessionNotes.privateCoachNote?.value, "合成教练备注")
        XCTAssertEqual(session.sessionNotes.studentFacingSummary?.value, "合成课后总结")
        XCTAssertEqual(session.sessionNotes.actionPrivateNotes[squatID]?.value, "合成动作备注")

        let completed = try CompletedSession.make(from: session, studentDisplayName: studentName)
        XCTAssertEqual(completed.id, session.id)
        XCTAssertEqual(completed.studentID, studentID)
        XCTAssertEqual(completed.studentDisplayName, studentName)
        XCTAssertEqual(completed.startedAtUTC, session.startedAtUTC)
        XCTAssertEqual(completed.completedAtUTC, session.completedAtUTC)
        XCTAssertEqual(completed.trainingFocus?.value, "下肢力量")
        XCTAssertEqual(completed.notes.privateCoachNote?.value, "合成教练备注")
        XCTAssertEqual(completed.notes.studentFacingSummary?.value, "合成课后总结")
        XCTAssertEqual(completed.notes.actionPrivateNotes[squatID]?.value, "合成动作备注")
        XCTAssertNil(completed.notes.actionPrivateNotes[pullUpID])
        XCTAssertEqual(completed.revision, session.revision)
        XCTAssertNil(completed.latestReport)
        XCTAssertNotEqual(completed.notes.privateCoachNote, completed.notes.studentFacingSummary)
        XCTAssertNotEqual(completed.notes.actionPrivateNotes[squatID], completed.notes.privateCoachNote)
    }

    func testDraftAndPendingSetsAreExcludedAndEditingCompletedSetRecalculatesStatistics() throws {
        var session = try inProgressSessionWithCompletedSquat()
        session = try session.copyingSet(sourceSetID: firstSetID, newSetID: secondSetID, now: now)
        session = try session.addingSet(
            exerciseID: squatID,
            setID: draftSetID,
            input: TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "80",
                repetitionCount: "3",
                unit: .kilograms
            ),
            now: now
        )
        XCTAssertEqual(try set(in: session, id: secondSetID).state, .pending)
        XCTAssertEqual(try set(in: session, id: draftSetID).state, .draft)
        XCTAssertEqual(session.statistics.completedSetCount, 1)
        XCTAssertEqual(session.completedSetCount, 1)
        XCTAssertEqual(session.statistics.ordinaryTrainingVolume, try DecimalValue("300"))
        XCTAssertFalse(try set(in: session, id: secondSetID).contributesToStatistics)
        XCTAssertFalse(try set(in: session, id: draftSetID).contributesToStatistics)

        XCTAssertThrowsError(
            try session.editingCompletedSet(
                setID: firstSetID,
                input: TrainingSetInput(
                    recordMode: .weightReps,
                    weightValue: "80",
                    repetitionCount: "6",
                    unit: .kilograms
                ),
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }

        session = try addingConfirmedExercise(
            session,
            id: pullUpID,
            displayName: "引体向上",
            recordMode: .reps,
            setID: pullUpSetID,
            input: TrainingSetInput(
                recordMode: .reps,
                repetitionCount: "8",
                unit: .repetitions
            )
        )
        session = try addingConfirmedExercise(
            session,
            id: plankID,
            displayName: "平板支撑",
            recordMode: .duration,
            setID: plankSetID,
            input: TrainingSetInput(
                recordMode: .duration,
                durationSeconds: "30",
                unit: .seconds
            )
        )
        XCTAssertEqual(session.statistics.completedSetCount, 3)
        XCTAssertEqual(session.statistics.ordinaryTrainingVolume, try DecimalValue("300"))

        session = try session.discardingUnresolvedSets(now: now).finished(now: now)
        XCTAssertEqual(session.state, .completed)
        XCTAssertEqual(session.statistics.completedSetCount, 3)
        XCTAssertEqual(session.statistics.ordinaryTrainingVolume, try DecimalValue("300"))
        XCTAssertEqual(session.exercises.flatMap(\.sets).count, 3)

        let completedBeforeEdit = try CompletedSession.make(
            from: session,
            studentDisplayName: try NormalizedName("林青")
        )
        XCTAssertEqual(completedBeforeEdit.statistics.completedSetCount, 3)
        XCTAssertEqual(completedBeforeEdit.statistics.ordinaryTrainingVolume, try DecimalValue("300"))

        let editedAt = now.addingTimeInterval(30)
        let revisionBeforeEdit = session.revision
        session = try session.editingCompletedSet(
            setID: firstSetID,
            input: TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "80",
                repetitionCount: "6",
                unit: .kilograms
            ),
            now: editedAt
        )
        XCTAssertGreaterThan(session.revision, revisionBeforeEdit)
        XCTAssertEqual(try set(in: session, id: firstSetID).state, .completed)
        XCTAssertTrue(try set(in: session, id: firstSetID).contributesToStatistics)
        XCTAssertEqual(session.statistics.completedSetCount, 3)
        XCTAssertEqual(session.statistics.ordinaryTrainingVolume, try DecimalValue("480"))

        let completedAfterEdit = try CompletedSession.make(
            from: session,
            studentDisplayName: try NormalizedName("林青")
        )
        XCTAssertEqual(completedAfterEdit.statistics.completedSetCount, 3)
        XCTAssertEqual(completedAfterEdit.statistics.ordinaryTrainingVolume, try DecimalValue("480"))
        XCTAssertEqual(completedAfterEdit.revision, session.revision)

        var bodyweightOnly = Session.start(id: sessionID, studentID: studentID, now: now)
        bodyweightOnly = try addingConfirmedExercise(
            bodyweightOnly,
            id: pullUpID,
            displayName: "引体向上",
            recordMode: .reps,
            setID: pullUpSetID,
            input: TrainingSetInput(
                recordMode: .reps,
                repetitionCount: "8",
                unit: .repetitions
            )
        )
        bodyweightOnly = try bodyweightOnly.finished(now: now)
        XCTAssertEqual(bodyweightOnly.statistics.completedSetCount, 1)
        XCTAssertNil(bodyweightOnly.statistics.ordinaryTrainingVolume)

        var sided = Session.start(id: sessionID, studentID: studentID, now: now)
        sided = try addingConfirmedExercise(
            sided,
            id: squatID,
            displayName: "杠铃深蹲",
            recordMode: .weightReps,
            setID: firstSetID,
            input: TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "60",
                repetitionCount: "5",
                unit: .kilograms,
                side: .none
            )
        )
        sided = try addingConfirmedExercise(
            sided,
            id: rowID,
            displayName: "哑铃划船",
            recordMode: .weightReps,
            setID: rowSetID,
            input: TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "40",
                repetitionCount: "8",
                unit: .kilograms,
                side: .bilateral,
                leftValue: "10",
                rightValue: "12"
            )
        )
        sided = try addingConfirmedExercise(
            sided,
            id: leftID,
            displayName: "左腿箭步蹲",
            recordMode: .weightReps,
            setID: leftSetID,
            input: TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "40",
                repetitionCount: "5",
                unit: .kilograms,
                side: .left,
                leftValue: "20"
            )
        )
        sided = try addingConfirmedExercise(
            sided,
            id: rightID,
            displayName: "右腿箭步蹲",
            recordMode: .weightReps,
            setID: rightSetID,
            input: TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "40",
                repetitionCount: "4",
                unit: .kilograms,
                side: .right,
                rightValue: "15"
            )
        )
        sided = try sided.finished(now: now)
        XCTAssertEqual(sided.statistics.completedSetCount, 4)
        XCTAssertEqual(sided.statistics.ordinaryTrainingVolume, try DecimalValue("636"))
    }

    func testShareReportFreshnessAndHandedToSystemAreOrthogonal() throws {
        let report = ShareReport.make(
            id: reportID,
            sessionID: sessionID,
            generatedForRevision: 7,
            now: now
        )
        XCTAssertEqual(report.id, reportID)
        XCTAssertEqual(report.sessionID, sessionID)
        XCTAssertEqual(report.generatedForRevision, 7)
        XCTAssertEqual(report.createdAtUTC, now)
        XCTAssertEqual(report.freshness, .current)
        XCTAssertNil(report.handedToSystemAtUTC)

        let handedAt = now.addingTimeInterval(15)
        let handed = report.recordingHandedToSystem(at: handedAt)
        XCTAssertEqual(handed.freshness, .current)
        XCTAssertEqual(handed.handedToSystemAtUTC, handedAt)
        XCTAssertEqual(handed.id, report.id)
        XCTAssertEqual(handed.sessionID, report.sessionID)
        XCTAssertEqual(handed.generatedForRevision, report.generatedForRevision)
        XCTAssertEqual(handed.createdAtUTC, report.createdAtUTC)

        let staleAfterHandoff = handed.markingStale()
        XCTAssertEqual(staleAfterHandoff.freshness, .stale)
        XCTAssertEqual(staleAfterHandoff.handedToSystemAtUTC, handedAt)
        XCTAssertEqual(staleAfterHandoff.id, handed.id)
        XCTAssertEqual(staleAfterHandoff.createdAtUTC, handed.createdAtUTC)

        let staleWithoutHandoff = report.markingStale()
        XCTAssertEqual(staleWithoutHandoff.freshness, .stale)
        XCTAssertNil(staleWithoutHandoff.handedToSystemAtUTC)
        XCTAssertEqual(staleWithoutHandoff.createdAtUTC, report.createdAtUTC)

        let handedWhileStale = staleWithoutHandoff.recordingHandedToSystem(at: handedAt)
        XCTAssertEqual(handedWhileStale.freshness, .stale)
        XCTAssertNotEqual(handedWhileStale.freshness, ShareReportFreshness.current)
        XCTAssertEqual(handedWhileStale.handedToSystemAtUTC, handedAt)
        XCTAssertEqual(handedWhileStale.createdAtUTC, staleWithoutHandoff.createdAtUTC)
    }

    func testDisplayedDurationUsesCoachAdjustedSecondsWhenPresent() throws {
        var session = try inProgressSessionWithCompletedSquat()
        let checkpoint = now.addingTimeInterval(180)
        session = session.updatingTiming(
            elapsedSeconds: try DecimalValue("180"),
            lastCheckpointUTC: checkpoint,
            interruptionStartedAtUTC: nil,
            durationNeedsReview: false,
            now: checkpoint
        )
        XCTAssertNil(session.coachAdjustedDurationSeconds)
        XCTAssertEqual(session.displayedDurationSeconds, try DecimalValue("180"))
        XCTAssertEqual(session.statistics.displayedDurationSeconds, try DecimalValue("180"))

        session = try session.applyingCoachAdjustedDuration(try DecimalValue("90"), now: checkpoint)
        XCTAssertEqual(session.coachAdjustedDurationSeconds, try DecimalValue("90"))
        XCTAssertEqual(session.elapsedSeconds, try DecimalValue("180"))
        XCTAssertEqual(session.displayedDurationSeconds, try DecimalValue("90"))
        XCTAssertEqual(session.statistics.displayedDurationSeconds, try DecimalValue("90"))

        session = try session.finished(now: checkpoint)
        XCTAssertEqual(session.state, .completed)
        XCTAssertEqual(session.displayedDurationSeconds, try DecimalValue("90"))
        XCTAssertEqual(session.statistics.displayedDurationSeconds, try DecimalValue("90"))

        let completed = try CompletedSession.make(
            from: session,
            studentDisplayName: try NormalizedName("林青")
        )
        XCTAssertEqual(completed.statistics.displayedDurationSeconds, try DecimalValue("90"))
    }

    private func inProgressSessionWithCompletedSquat() throws -> Session {
        let session = Session.start(id: sessionID, studentID: studentID, now: now)
        return try addingConfirmedExercise(
            session,
            id: squatID,
            displayName: "杠铃深蹲",
            recordMode: .weightReps,
            setID: firstSetID,
            input: TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "60",
                repetitionCount: "5",
                unit: .kilograms
            )
        )
    }

    private func addingConfirmedExercise(
        _ session: Session,
        id: StableUUID,
        displayName: String,
        recordMode: RecordMode,
        setID: StableUUID,
        input: TrainingSetInput
    ) throws -> Session {
        var session = try session.addingSessionOnlyExercise(
            id: id,
            displayName: displayName,
            recordMode: recordMode,
            now: now
        )
        session = try session.addingSet(
            exerciseID: id,
            setID: setID,
            input: input,
            now: now
        )
        return try session.confirmingSet(setID: setID, now: now)
    }

    private func set(in session: Session, id: StableUUID) throws -> TrainingSet {
        try XCTUnwrap(session.exercises.flatMap(\.sets).first { $0.id == id })
    }

    private func setExercise(in session: Session, id: StableUUID) throws -> SessionExercise {
        try XCTUnwrap(session.exercises.first { $0.id == id })
    }
}
