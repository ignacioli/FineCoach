import FineCoach
import XCTest

final class SessionTimingTests: XCTestCase {
    private let coordinator = SessionTimingCoordinator()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    private let sessionID = StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
    private let squatID = StableUUID(UUID(uuidString: "33333333-3333-4333-8333-333333333333")!)
    private let firstSetID = StableUUID(UUID(uuidString: "66666666-6666-4666-8666-666666666666")!)

    func testCheckpointUsesUTCAndIncrementsElapsedWithMonotonicSafeDelta() throws {
        let clock = TestClock(utcDate: now)
        let session = Session.start(id: sessionID, studentID: studentID, now: clock.nowUTC())
        XCTAssertEqual(session.elapsedSeconds, .zero)
        XCTAssertEqual(session.lastCheckpointUTC, now)
        XCTAssertEqual(session.state, .inProgress)

        clock.advance(seconds: 10)
        let checkpointed = try coordinator.checkpoint(session: session, nowUTC: clock.nowUTC())

        XCTAssertEqual(checkpointed.elapsedSeconds.canonicalString, try DecimalValue.seconds(10).canonicalString)
        XCTAssertEqual(checkpointed.elapsedSeconds.canonicalString, try DecimalValue("10").canonicalString)
        XCTAssertEqual(checkpointed.lastCheckpointUTC, clock.nowUTC())
        XCTAssertGreaterThan(checkpointed.revision, session.revision)
        XCTAssertEqual(checkpointed.state, .inProgress)
        XCTAssertFalse(checkpointed.durationNeedsReview)
        XCTAssertEqual(checkpointed.exercises, session.exercises)
    }

    func testResumeMergesNonNegativeUTCDeltaIntoElapsed() throws {
        let clock = TestClock(utcDate: now)
        let session = Session.start(id: sessionID, studentID: studentID, now: clock.nowUTC())
        XCTAssertEqual(session.lastCheckpointUTC, now)
        XCTAssertEqual(session.elapsedSeconds, .zero)

        clock.advance(seconds: 45)
        let resumedFromZero = try coordinator.resumeAfterInterruption(
            session: session,
            nowUTC: clock.nowUTC(),
            interruptionStartedAtUTC: now
        )
        XCTAssertEqual(resumedFromZero.elapsedSeconds.canonicalString, try DecimalValue.seconds(45).canonicalString)
        XCTAssertEqual(resumedFromZero.lastCheckpointUTC, clock.nowUTC())
        XCTAssertGreaterThan(resumedFromZero.revision, session.revision)
        XCTAssertEqual(resumedFromZero.state, .inProgress)
        XCTAssertFalse(resumedFromZero.durationNeedsReview)

        let withPriorElapsed = session.updatingTiming(
            elapsedSeconds: try DecimalValue("30"),
            lastCheckpointUTC: now,
            interruptionStartedAtUTC: now,
            durationNeedsReview: false,
            now: now
        )
        let resumedWithPrior = try coordinator.resumeAfterInterruption(
            session: withPriorElapsed,
            nowUTC: now.addingTimeInterval(45),
            interruptionStartedAtUTC: now
        )
        XCTAssertEqual(resumedWithPrior.elapsedSeconds.canonicalString, try DecimalValue("75").canonicalString)
        XCTAssertGreaterThan(resumedWithPrior.revision, withPriorElapsed.revision)
        XCTAssertEqual(resumedWithPrior.state, .inProgress)
    }

    func testNegativeUTCJumpSetsDurationNeedsReviewAndDoesNotAbandon() throws {
        let clock = TestClock(utcDate: now)
        let session = try sessionWithCompletedSet(now: clock.nowUTC())
        XCTAssertEqual(try set(in: session, id: firstSetID).state, .completed)
        XCTAssertEqual(session.state, .inProgress)
        XCTAssertFalse(session.durationNeedsReview)

        clock.setUTC(now.addingTimeInterval(-60))

        let checkpointed = try coordinator.checkpoint(session: session, nowUTC: clock.nowUTC())
        XCTAssertTrue(checkpointed.durationNeedsReview)
        XCTAssertEqual(checkpointed.state, .inProgress)
        XCTAssertNotEqual(checkpointed.state, .abandonedEmpty)
        XCTAssertEqual(try set(in: checkpointed, id: firstSetID).state, .completed)
        XCTAssertEqual(checkpointed.elapsedSeconds, session.elapsedSeconds)
        XCTAssertEqual(checkpointed.exercises, session.exercises)
        XCTAssertGreaterThan(checkpointed.revision, session.revision)

        let resumed = try coordinator.resumeAfterInterruption(
            session: session,
            nowUTC: clock.nowUTC(),
            interruptionStartedAtUTC: now
        )
        XCTAssertTrue(resumed.durationNeedsReview)
        XCTAssertEqual(resumed.state, .inProgress)
        XCTAssertNotEqual(resumed.state, .abandonedEmpty)
        XCTAssertEqual(resumed.exercises, session.exercises)
        XCTAssertEqual(try set(in: resumed, id: firstSetID).state, .completed)
        XCTAssertEqual(resumed.elapsedSeconds, session.elapsedSeconds)
        XCTAssertGreaterThan(resumed.revision, session.revision)
    }

    func testThirtyMinuteInterruptionRequiresReviewAndAllowsDurationEditLater() throws {
        XCTAssertEqual(SessionTimingCoordinator.reviewThreshold, 30 * 60)
        let session = try sessionWithCompletedSet(now: now)
        XCTAssertEqual(try set(in: session, id: firstSetID).state, .completed)
        XCTAssertFalse(session.durationNeedsReview)

        let atThreshold = try coordinator.resumeAfterInterruption(
            session: session,
            nowUTC: now.addingTimeInterval(SessionTimingCoordinator.reviewThreshold),
            interruptionStartedAtUTC: now
        )
        XCTAssertTrue(atThreshold.durationNeedsReview)
        XCTAssertNil(atThreshold.coachAdjustedDurationSeconds)
        XCTAssertEqual(atThreshold.state, .inProgress)
        XCTAssertEqual(try set(in: atThreshold, id: firstSetID).state, .completed)
        XCTAssertEqual(
            atThreshold.exercises.flatMap(\.sets).map(\.state),
            session.exercises.flatMap(\.sets).map(\.state)
        )
        XCTAssertGreaterThan(atThreshold.revision, session.revision)

        let underThreshold = try coordinator.resumeAfterInterruption(
            session: session,
            nowUTC: now.addingTimeInterval(SessionTimingCoordinator.reviewThreshold - 1),
            interruptionStartedAtUTC: now
        )
        XCTAssertFalse(underThreshold.durationNeedsReview)
        XCTAssertEqual(try set(in: underThreshold, id: firstSetID).state, .completed)
        XCTAssertEqual(underThreshold.state, .inProgress)
        XCTAssertGreaterThan(underThreshold.revision, session.revision)
    }

    func testAnomalousClockDoesNotAutoFailSession() throws {
        let clock = TestClock(utcDate: now)
        let session = try sessionWithCompletedSet(now: clock.nowUTC())
        XCTAssertEqual(session.finishGate, .canComplete)
        XCTAssertEqual(session.state, .inProgress)

        clock.advance(seconds: 24 * 60 * 60)
        let resumed = try coordinator.resumeAfterInterruption(
            session: session,
            nowUTC: clock.nowUTC(),
            interruptionStartedAtUTC: now
        )

        XCTAssertTrue(resumed.durationNeedsReview)
        XCTAssertEqual(resumed.state, .inProgress)
        XCTAssertNotEqual(resumed.state, .abandonedEmpty)
        XCTAssertNotEqual(resumed.state, .completed)
        XCTAssertEqual(resumed.finishGate, .canComplete)
        XCTAssertEqual(try set(in: resumed, id: firstSetID).state, .completed)
        XCTAssertGreaterThan(resumed.revision, session.revision)

        XCTAssertThrowsError(try resumed.finished(now: clock.nowUTC())) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
        let adjusted = try resumed.applyingCoachAdjustedDuration(resumed.elapsedSeconds, now: clock.nowUTC())
        let finished = try adjusted.finished(now: clock.nowUTC())
        XCTAssertEqual(finished.state, .completed)
        XCTAssertThrowsError(
            try coordinator.checkpoint(session: finished, nowUTC: clock.nowUTC())
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }

        let empty = Session.start(id: sessionID, studentID: studentID, now: now)
        let emptyResumed = try coordinator.resumeAfterInterruption(
            session: empty,
            nowUTC: now.addingTimeInterval(24 * 60 * 60),
            interruptionStartedAtUTC: now
        )
        XCTAssertTrue(emptyResumed.durationNeedsReview)
        XCTAssertEqual(emptyResumed.state, .inProgress)
        XCTAssertEqual(emptyResumed.finishGate, .abandonEmpty)
    }

    func testReviewFlagSticksUntilCoachAdjustment() throws {
        var session = Session.start(id: sessionID, studentID: studentID, now: now)
        session = session.updatingTiming(
            elapsedSeconds: .zero,
            lastCheckpointUTC: now,
            interruptionStartedAtUTC: now,
            durationNeedsReview: true,
            now: now
        )
        XCTAssertTrue(session.durationNeedsReview)

        let resumed = try coordinator.resumeAfterInterruption(
            session: session,
            nowUTC: now.addingTimeInterval(12),
            interruptionStartedAtUTC: now
        )
        XCTAssertTrue(resumed.durationNeedsReview)
        XCTAssertEqual(resumed.state, .inProgress)
        XCTAssertGreaterThan(resumed.revision, session.revision)

        let checkpointed = try coordinator.checkpoint(
            session: resumed,
            nowUTC: now.addingTimeInterval(22)
        )
        XCTAssertTrue(checkpointed.durationNeedsReview)
        XCTAssertEqual(checkpointed.state, .inProgress)
        XCTAssertGreaterThan(checkpointed.revision, resumed.revision)
    }

    private func sessionWithCompletedSet(now: Date) throws -> Session {
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
        return try session.confirmingSet(setID: firstSetID, now: now)
    }

    private func set(in session: Session, id: StableUUID) throws -> TrainingSet {
        try XCTUnwrap(session.exercises.flatMap(\.sets).first { $0.id == id })
    }
}
