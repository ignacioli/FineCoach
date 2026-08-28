import FineCoach
import XCTest

final class ActiveSessionRecoveryCodecTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    private let sessionID = StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
    private let generationUUID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    private let otherGenerationUUID = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
    private let squatID = StableUUID(UUID(uuidString: "33333333-3333-4333-8333-333333333333")!)
    private let completedSetID = StableUUID(UUID(uuidString: "66666666-6666-4666-8666-666666666666")!)
    private let pendingSetID = StableUUID(UUID(uuidString: "77777777-7777-4777-8777-777777777777")!)
    private let draftSetID = StableUUID(UUID(uuidString: "88888888-8888-4888-8888-888888888888")!)

    func testRoundTripPreservesCompletedPendingDraftOrderAndNotes() throws {
        let session = try recordedSession()
        let snapshot = try ActiveSessionRecoverySnapshot(
            storeGenerationUUID: generationUUID,
            session: session
        )
        let encoded = try snapshot.encoded()
        let decoded = try ActiveSessionRecoverySnapshot.decode(encoded)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.schemaID, ActiveSessionRecoverySnapshot.schemaID)
        XCTAssertEqual(ActiveSessionRecoverySnapshot.schemaID, "active-session-recovery-v1")
        XCTAssertEqual(decoded.storeGenerationUUID, generationUUID)
        XCTAssertEqual(decoded.revision, session.revision)
        XCTAssertEqual(decoded.session, session)
        XCTAssertEqual(decoded.session.exercises.map(\.id), [squatID])
        XCTAssertEqual(decoded.session.exercises.first?.displayNameSnapshot.value, "杠铃深蹲")
        XCTAssertEqual(
            decoded.session.exercises.first?.sets.map(\.state),
            [.completed, .pending, .draft]
        )
        XCTAssertEqual(
            decoded.session.exercises.first?.sets.map(\.id),
            [completedSetID, pendingSetID, draftSetID]
        )
        XCTAssertEqual(decoded.session.privateCoachNote?.value, "晚班")

        let completed = try set(in: decoded.session, id: completedSetID)
        let pending = try set(in: decoded.session, id: pendingSetID)
        let draft = try set(in: decoded.session, id: draftSetID)
        XCTAssertEqual(completed.weightValue?.canonicalString, DecimalValue.zero.canonicalString)
        XCTAssertEqual(completed.repetitionCount?.canonicalString, try DecimalValue("5").canonicalString)
        XCTAssertTrue(completed.contributesToStatistics)
        XCTAssertFalse(pending.contributesToStatistics)
        XCTAssertFalse(draft.contributesToStatistics)
        XCTAssertEqual(decoded.session.statisticsSets.map(\.id), [completedSetID])
    }

    func testHigherSnapshotRevisionReplaysOntoDatabase() throws {
        let snapshotSession = try recordedSession()
        let databaseSession = try sessionWithUnconfirmedSet()
        XCTAssertGreaterThan(snapshotSession.revision, databaseSession.revision)

        let snapshot = try ActiveSessionRecoverySnapshot(
            storeGenerationUUID: generationUUID,
            session: snapshotSession
        )
        let reconciler = RecoveryReconciler()
        let decision = reconciler.decide(
            snapshot: snapshot,
            databaseSession: databaseSession,
            currentGenerationUUID: generationUUID
        )
        XCTAssertEqual(decision, .replay(snapshot))

        let missingDatabase = reconciler.decide(
            snapshot: snapshot,
            databaseSession: nil,
            currentGenerationUUID: generationUUID
        )
        XCTAssertEqual(missingDatabase, .replay(snapshot))
    }

    func testEqualRevisionIsConsistentAndOlderSnapshotIsIgnored() throws {
        let reconciler = RecoveryReconciler()
        let session = try recordedSession()
        let snapshot = try ActiveSessionRecoverySnapshot(
            storeGenerationUUID: generationUUID,
            session: session
        )

        let equal = reconciler.decide(
            snapshot: snapshot,
            databaseSession: session,
            currentGenerationUUID: generationUUID
        )
        XCTAssertEqual(equal, .consistent(session))

        let earlierSession = try sessionWithExercise()
        let olderSnapshot = try ActiveSessionRecoverySnapshot(
            storeGenerationUUID: generationUUID,
            session: earlierSession
        )
        XCTAssertLessThan(olderSnapshot.revision, session.revision)
        let ignored = reconciler.decide(
            snapshot: olderSnapshot,
            databaseSession: session,
            currentGenerationUUID: generationUUID
        )
        XCTAssertEqual(ignored, .ignoreOlderSnapshot(session))

        let idle = reconciler.decide(
            snapshot: nil,
            databaseSession: nil,
            currentGenerationUUID: generationUUID
        )
        XCTAssertEqual(idle, .noActiveSession)
    }

    func testGenerationMismatchFailsClosedWithoutOpeningCandidate() throws {
        let session = try recordedSession()
        let snapshot = try ActiveSessionRecoverySnapshot(
            storeGenerationUUID: generationUUID,
            session: session
        )
        let decision = RecoveryReconciler().decide(
            snapshot: snapshot,
            databaseSession: session,
            currentGenerationUUID: otherGenerationUUID
        )
        XCTAssertEqual(decision, .failClosed(.generationMismatch))
        XCTAssertNotEqual(decision, .replay(snapshot))
        XCTAssertNotEqual(decision, .consistent(session))
        XCTAssertNotEqual(decision, .ignoreOlderSnapshot(session))
    }

    func testCorruptJSONAndUnknownEnumFailClosed() throws {
        let garbage = Data("not-json".utf8)
        XCTAssertThrowsError(try ActiveSessionRecoverySnapshot.decode(garbage)) { error in
            XCTAssertEqual(error as? DomainError, .incompatibleInput)
        }

        let encoded = try ActiveSessionRecoverySnapshot(
            storeGenerationUUID: generationUUID,
            session: try recordedSession()
        ).encoded()

        let unknownSessionState = try mutatingJSON(encoded) { object in
            var session = try XCTUnwrap(object["session"] as? [String: Any])
            session["state"] = "notARealState"
            object["session"] = session
        }
        XCTAssertThrowsError(try ActiveSessionRecoverySnapshot.decode(unknownSessionState)) { error in
            XCTAssertEqual(error as? DomainError, .incompatibleInput)
        }

        let unknownSetState = try mutatingJSON(encoded) { object in
            var session = try XCTUnwrap(object["session"] as? [String: Any])
            var exercises = try XCTUnwrap(session["exercises"] as? [[String: Any]])
            XCTAssertFalse(exercises.isEmpty)
            var sets = try XCTUnwrap(exercises[0]["sets"] as? [[String: Any]])
            XCTAssertFalse(sets.isEmpty)
            sets[0]["state"] = "notARealState"
            exercises[0]["sets"] = sets
            session["exercises"] = exercises
            object["session"] = session
        }
        XCTAssertThrowsError(try ActiveSessionRecoverySnapshot.decode(unknownSetState)) { error in
            XCTAssertEqual(error as? DomainError, .incompatibleInput)
        }
    }

    func testNegativeRevisionAndInvariantViolationFailClosed() throws {
        let snapshot = try ActiveSessionRecoverySnapshot(
            storeGenerationUUID: generationUUID,
            session: try recordedSession()
        )
        let encoded = try snapshot.encoded()

        let zeroRevision = try mutatingJSON(encoded) { object in
            object["revision"] = 0
        }
        XCTAssertThrowsError(try ActiveSessionRecoverySnapshot.decode(zeroRevision)) { error in
            XCTAssertEqual(error as? DomainError, .incompatibleInput)
        }

        let zeroEnvelopeAndSession = try mutatingJSON(encoded) { object in
            object["revision"] = 0
            var session = try XCTUnwrap(object["session"] as? [String: Any])
            session["revision"] = 0
            object["session"] = session
        }
        XCTAssertThrowsError(try ActiveSessionRecoverySnapshot.decode(zeroEnvelopeAndSession)) { error in
            XCTAssertEqual(error as? DomainError, .incompatibleInput)
        }
        let zeroDecoded = try decodeEnvelopeWithoutValidate(zeroEnvelopeAndSession)
        XCTAssertEqual(zeroDecoded.revision, 0)
        XCTAssertEqual(zeroDecoded.session.revision, 0)
        XCTAssertEqual(
            RecoveryReconciler().decide(
                snapshot: zeroDecoded,
                databaseSession: zeroDecoded.session,
                currentGenerationUUID: generationUUID
            ),
            .failClosed(.negativeRevision)
        )

        let mismatchedRevision = try mutatingJSON(encoded) { object in
            object["revision"] = NSNumber(value: snapshot.revision + 1)
        }
        XCTAssertThrowsError(try ActiveSessionRecoverySnapshot.decode(mismatchedRevision)) { error in
            XCTAssertEqual(error as? DomainError, .incompatibleInput)
        }
        let mismatched = try decodeEnvelopeWithoutValidate(mismatchedRevision)
        XCTAssertNotEqual(mismatched.revision, mismatched.session.revision)
        XCTAssertEqual(
            RecoveryReconciler().decide(
                snapshot: mismatched,
                databaseSession: mismatched.session,
                currentGenerationUUID: generationUUID
            ),
            .failClosed(.invariantViolation)
        )
    }

    private func recordedSession() throws -> Session {
        var session = try sessionWithUnconfirmedSet()
        session = try session.confirmingSet(setID: completedSetID, now: now)
        session = try session.copyingSet(sourceSetID: completedSetID, newSetID: pendingSetID, now: now)
        session = try session.addingSet(
            exerciseID: squatID,
            setID: draftSetID,
            input: weightRepsInput(),
            now: now
        )
        return withPrivateCoachNote(session, try ValidatedText("晚班"))
    }

    private func sessionWithExercise() throws -> Session {
        try Session.start(id: sessionID, studentID: studentID, now: now).addingSessionOnlyExercise(
            id: squatID,
            displayName: "杠铃深蹲",
            recordMode: .weightReps,
            now: now
        )
    }

    private func sessionWithUnconfirmedSet() throws -> Session {
        try sessionWithExercise().addingSet(
            exerciseID: squatID,
            setID: completedSetID,
            input: weightRepsInput(),
            now: now
        )
    }

    private func weightRepsInput() -> TrainingSetInput {
        TrainingSetInput(
            recordMode: .weightReps,
            weightValue: "0",
            repetitionCount: "5",
            unit: .kilograms
        )
    }

    private func withPrivateCoachNote(_ session: Session, _ note: ValidatedText) -> Session {
        Session(
            id: session.id,
            studentID: session.studentID,
            state: session.state,
            startedAtUTC: session.startedAtUTC,
            lastCheckpointUTC: session.lastCheckpointUTC,
            elapsedSeconds: session.elapsedSeconds,
            interruptionStartedAtUTC: session.interruptionStartedAtUTC,
            durationNeedsReview: session.durationNeedsReview,
            coachAdjustedDurationSeconds: session.coachAdjustedDurationSeconds,
            trainingFocus: session.trainingFocus,
            studentFacingSummary: session.studentFacingSummary,
            privateCoachNote: note,
            revision: session.revision,
            createdAtUTC: session.createdAtUTC,
            updatedAtUTC: session.updatedAtUTC,
            completedAtUTC: session.completedAtUTC,
            exercises: session.exercises
        )
    }

    private func set(in session: Session, id: StableUUID) throws -> TrainingSet {
        try XCTUnwrap(session.exercises.flatMap(\.sets).first { $0.id == id })
    }

    private func decodeEnvelopeWithoutValidate(_ data: Data) throws -> ActiveSessionRecoverySnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ActiveSessionRecoverySnapshot.self, from: data)
    }

    private func mutatingJSON(_ data: Data, _ mutate: (inout [String: Any]) throws -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try mutate(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }
}
