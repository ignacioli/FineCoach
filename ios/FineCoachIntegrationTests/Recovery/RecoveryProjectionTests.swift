#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    final class RecoveryProjectionTests: XCTestCase {
        private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        private let sessionID = StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
        private let firstExerciseID = StableUUID(UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
        private let completedSetID = StableUUID(UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!)
        private let draftSetID = StableUUID(UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!)
        private let secondDraftSetID = StableUUID(UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!)
        private let pendingSetID = StableUUID(UUID(uuidString: "99999999-9999-4999-8999-999999999999")!)
        private let storeGenerationUUID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        private let mismatchedGenerationUUID = UUID(uuidString: "12345678-1234-4234-8234-123456789012")!
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        func testSnapshotReplaceFailureIsBlockingAndDoesNotMarkSaved() async throws {
            let injector = TestFaultInjector()
            let environment = try makeUseCases(
                ids: [studentID.rawValue, sessionID.rawValue, firstExerciseID.rawValue],
                injector: injector
            )
            _ = try await environment.studentUseCases.create(
                draft: StudentDraft(displayName: "林青", sex: .female)
            )
            let started = try await environment.sessionUseCases.startOrOpen(studentID: studentID)
            XCTAssertEqual(started.exercises.count, 0)

            injector.setFailure(at: .recoverySnapshotReplace, enabled: true)
            await assertBlocked(at: .recoverySnapshotReplace) {
                _ = try await environment.sessionUseCases.addSessionOnlyExercise(
                    displayName: "杠铃深蹲",
                    recordMode: .weightReps
                )
            }

            let dbActive = try await environment.sessionUseCases.loadActive()
            let db = try XCTUnwrap(dbActive)
            XCTAssertEqual(db.exercises.count, 0)
            XCTAssertEqual(db.revision, started.revision)

            let recovered = try environment.recoveryStore.load()
            XCTAssertEqual(recovered?.session.exercises.count ?? 0, 0)
            if let recovered {
                XCTAssertEqual(recovered.revision, started.revision)
            }

            switch environment.sessionUseCases.saveStatus {
            case .saved(let revision):
                XCTAssertEqual(revision, started.revision)
            case .failed(_, let retryable):
                XCTAssertTrue(retryable)
            case .saving:
                XCTFail("Snapshot replace failure must not remain in saving")
            }
            try await environment.controller.shutdownForTesting()
        }

        func testWriterSaveFailureKeepsNewerSnapshotAndAllowsRetryReplay() async throws {
            let injector = TestFaultInjector()
            let environment = try makeUseCases(
                ids: [
                    studentID.rawValue,
                    sessionID.rawValue,
                    firstExerciseID.rawValue,
                    completedSetID.rawValue,
                    draftSetID.rawValue,
                ],
                injector: injector
            )
            _ = try await environment.studentUseCases.create(
                draft: StudentDraft(displayName: "林青", sex: .female)
            )
            _ = try await environment.sessionUseCases.startOrOpen(studentID: studentID)
            _ = try await environment.sessionUseCases.addSessionOnlyExercise(
                displayName: "杠铃深蹲",
                recordMode: .weightReps
            )
            _ = try await environment.sessionUseCases.addSet(
                exerciseID: firstExerciseID,
                input: weightRepsInput(weight: "0", reps: "5")
            )
            let confirmed = try await environment.sessionUseCases.confirmSet(setID: completedSetID)
            XCTAssertEqual(confirmed.completedSetCount, 1)

            injector.setFailure(at: .persistenceWriterSave, enabled: true)
            await assertBlocked(at: .persistenceWriterSave) {
                _ = try await environment.sessionUseCases.addSet(
                    exerciseID: firstExerciseID,
                    input: weightRepsInput(weight: "0", reps: "5")
                )
            }

            let snapshot = try XCTUnwrap(environment.recoveryStore.load())
            let dbActive = try await environment.sessionUseCases.loadActive()
            let db = try XCTUnwrap(dbActive)
            XCTAssertGreaterThan(snapshot.revision, db.revision)
            XCTAssertEqual(setState(in: snapshot.session, id: draftSetID), .draft)
            XCTAssertNil(setState(in: db, id: draftSetID))
            XCTAssertEqual(
                environment.sessionUseCases.saveStatus,
                .failed(revision: snapshot.revision, retryable: true)
            )

            injector.setFailure(at: .persistenceWriterSave, enabled: false)
            let retried = try await environment.sessionUseCases.retry()
            XCTAssertEqual(setState(in: retried, id: draftSetID), .draft)
            XCTAssertEqual(environment.sessionUseCases.saveStatus, .saved(revision: retried.revision))
            let projectedActive = try await environment.sessionUseCases.loadActive()
            let projected = try XCTUnwrap(projectedActive)
            XCTAssertEqual(setState(in: projected, id: draftSetID), .draft)
            XCTAssertEqual(projected.revision, snapshot.revision)
            try await environment.controller.shutdownForTesting()
        }

        func testFailedSaveThenMoreCommandsThenRetryPersistsFullAggregate() async throws {
            let injector = TestFaultInjector()
            let environment = try makeUseCases(
                ids: [
                    studentID.rawValue,
                    sessionID.rawValue,
                    firstExerciseID.rawValue,
                    draftSetID.rawValue,
                    secondDraftSetID.rawValue,
                ],
                injector: injector
            )
            _ = try await environment.studentUseCases.create(
                draft: StudentDraft(displayName: "林青", sex: .female)
            )
            _ = try await environment.sessionUseCases.startOrOpen(studentID: studentID)
            _ = try await environment.sessionUseCases.addSessionOnlyExercise(
                displayName: "杠铃深蹲",
                recordMode: .weightReps
            )

            injector.setFailure(at: .persistenceWriterSave, enabled: true)
            await assertBlocked(at: .persistenceWriterSave) {
                _ = try await environment.sessionUseCases.addSet(
                    exerciseID: firstExerciseID,
                    input: weightRepsInput(weight: "0", reps: "5")
                )
            }
            await assertBlocked(at: .persistenceWriterSave) {
                _ = try await environment.sessionUseCases.addSet(
                    exerciseID: firstExerciseID,
                    input: weightRepsInput(weight: "0", reps: "8")
                )
            }

            let latestSnapshot = try XCTUnwrap(environment.recoveryStore.load())
            let dbActive = try await environment.sessionUseCases.loadActive()
            let db = try XCTUnwrap(dbActive)
            XCTAssertGreaterThan(latestSnapshot.revision, db.revision)
            XCTAssertEqual(
                latestSnapshot.session.exercises.first?.sets.map(\.id),
                [draftSetID, secondDraftSetID]
            )
            XCTAssertEqual(db.exercises.first?.sets.map(\.id) ?? [], [])
            XCTAssertEqual(setState(in: latestSnapshot.session, id: draftSetID), .draft)
            XCTAssertEqual(setState(in: latestSnapshot.session, id: secondDraftSetID), .draft)

            injector.setFailure(at: .persistenceWriterSave, enabled: false)
            let retried = try await environment.sessionUseCases.retry()
            XCTAssertEqual(retried.revision, latestSnapshot.revision)
            XCTAssertEqual(retried.exercises.first?.sets.map(\.id), [draftSetID, secondDraftSetID])
            XCTAssertEqual(setState(in: retried, id: secondDraftSetID), .draft)
            XCTAssertEqual(environment.sessionUseCases.saveStatus, .saved(revision: retried.revision))
            let projectedActive = try await environment.sessionUseCases.loadActive()
            let projected = try XCTUnwrap(projectedActive)
            XCTAssertEqual(projected.exercises.first?.sets.map(\.id), [draftSetID, secondDraftSetID])
            try await environment.controller.shutdownForTesting()
        }

        func testFinishBlockedUntilProjectionMatchesAndErrorCleared() async throws {
            let injector = TestFaultInjector()
            let environment = try makeUseCases(
                ids: [
                    studentID.rawValue,
                    sessionID.rawValue,
                    firstExerciseID.rawValue,
                    completedSetID.rawValue,
                    draftSetID.rawValue,
                ],
                injector: injector
            )
            _ = try await environment.studentUseCases.create(
                draft: StudentDraft(displayName: "林青", sex: .female)
            )
            _ = try await environment.sessionUseCases.startOrOpen(studentID: studentID)
            _ = try await environment.sessionUseCases.addSessionOnlyExercise(
                displayName: "杠铃深蹲",
                recordMode: .weightReps
            )
            _ = try await environment.sessionUseCases.addSet(
                exerciseID: firstExerciseID,
                input: weightRepsInput(weight: "0", reps: "5")
            )
            _ = try await environment.sessionUseCases.confirmSet(setID: completedSetID)

            injector.setFailure(at: .persistenceWriterSave, enabled: true)
            await assertBlocked(at: .persistenceWriterSave) {
                _ = try await environment.sessionUseCases.addSet(
                    exerciseID: firstExerciseID,
                    input: weightRepsInput(weight: "0", reps: "5")
                )
            }

            do {
                _ = try await environment.sessionUseCases.finish()
                XCTFail("Expected finish to stay blocked while projection is failed")
            } catch DomainError.invalidState {
                // expected
            }

            injector.setFailure(at: .persistenceWriterSave, enabled: false)
            let retried = try await environment.sessionUseCases.retry()
            XCTAssertEqual(environment.sessionUseCases.saveStatus, .saved(revision: retried.revision))
            _ = try await environment.sessionUseCases.discardUnresolved()
            let finished = try await environment.sessionUseCases.finish()
            XCTAssertEqual(finished.state, .completed)
            XCTAssertEqual(finished.completedAtUTC, now)
            let finishedActive = try await environment.sessionUseCases.loadActive()
            XCTAssertNil(finishedActive)
            try await environment.controller.shutdownForTesting()
        }

        func testCorruptOrMismatchedGenerationSnapshotFailsClosedOnLaunch() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let recoveryURL = directory.url.appendingPathComponent("active-session-recovery-v1.json")
            let original: Session
            do {
                let environment = try makeUseCases(
                    directory: directory,
                    storeURL: storeURL,
                    ids: [studentID.rawValue, sessionID.rawValue, firstExerciseID.rawValue]
                )
                _ = try await environment.studentUseCases.create(
                    draft: StudentDraft(displayName: "林青", sex: .female)
                )
                _ = try await environment.sessionUseCases.startOrOpen(studentID: studentID)
                original = try await environment.sessionUseCases.addSessionOnlyExercise(
                    displayName: "杠铃深蹲",
                    recordMode: .weightReps
                )
                let mismatched = try ActiveSessionRecoverySnapshot(
                    storeGenerationUUID: mismatchedGenerationUUID,
                    session: original
                )
                try environment.recoveryStore.replace(mismatched)
                try await environment.controller.shutdownForTesting()
            }

            do {
                let mismatchedLaunch = try makeUseCases(directory: directory, storeURL: storeURL, ids: [])
                let decision = try await mismatchedLaunch.sessionUseCases.reconcileOnLaunch()
                XCTAssertEqual(decision, .failClosed(.generationMismatch))
                let stillActive = try await mismatchedLaunch.sessionUseCases.loadActive()
                let still = try XCTUnwrap(stillActive)
                XCTAssertEqual(still.state, .inProgress)
                XCTAssertEqual(still.id, original.id)
                XCTAssertEqual(still.exercises.first?.displayNameSnapshot.value, "杠铃深蹲")
                let inProgressCount = try await sessionCount(
                    state: "inProgress",
                    writer: mismatchedLaunch.controller.writer
                )
                XCTAssertEqual(inProgressCount, 1)
                try await mismatchedLaunch.controller.shutdownForTesting()
            }

            try Data("not-a-recovery-snapshot".utf8).write(to: recoveryURL, options: .atomic)
            let corruptLaunch = try makeUseCases(directory: directory, storeURL: storeURL, ids: [])
            do {
                let decision = try await corruptLaunch.sessionUseCases.reconcileOnLaunch()
                XCTAssertEqual(decision, .failClosed(.corruptSnapshot))
            } catch DomainError.incompatibleInput {
                // decode isolation may surface as a domain error
            } catch DomainError.persistenceFailed {
                // decode isolation may surface as a domain error
            }
            let remainingActive = try await corruptLaunch.sessionUseCases.loadActive()
            let remaining = try XCTUnwrap(remainingActive)
            XCTAssertEqual(remaining.state, .inProgress)
            XCTAssertEqual(remaining.exercises.first?.displayNameSnapshot.value, "杠铃深蹲")
            try await corruptLaunch.controller.shutdownForTesting()
        }

        func testRestartReplaysHigherSnapshotRevisionOntoEmptyOrOlderDatabase() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let original: Session
            let higherSnapshot: ActiveSessionRecoverySnapshot
            do {
                let environment = try makeUseCases(
                    directory: directory,
                    storeURL: storeURL,
                    ids: [
                        studentID.rawValue,
                        sessionID.rawValue,
                        firstExerciseID.rawValue,
                        completedSetID.rawValue,
                    ]
                )
                _ = try await environment.studentUseCases.create(
                    draft: StudentDraft(displayName: "林青", sex: .female)
                )
                _ = try await environment.sessionUseCases.startOrOpen(studentID: studentID)
                _ = try await environment.sessionUseCases.addSessionOnlyExercise(
                    displayName: "杠铃深蹲",
                    recordMode: .weightReps
                )
                _ = try await environment.sessionUseCases.addSet(
                    exerciseID: firstExerciseID,
                    input: weightRepsInput(weight: "0", reps: "5")
                )
                original = try await environment.sessionUseCases.confirmSet(setID: completedSetID)
                XCTAssertEqual(original.exercises.first?.sets.count, 1)

                let withPending = try original.copyingSet(
                    sourceSetID: completedSetID,
                    newSetID: pendingSetID,
                    now: now
                )
                XCTAssertEqual(withPending.revision, original.revision + 1)
                XCTAssertEqual(setState(in: withPending, id: pendingSetID), .pending)
                higherSnapshot = try ActiveSessionRecoverySnapshot(
                    storeGenerationUUID: storeGenerationUUID,
                    session: withPending
                )
                try environment.recoveryStore.replace(higherSnapshot)
                try await environment.controller.shutdownForTesting()
            }

            let reopened = try makeUseCases(directory: directory, storeURL: storeURL, ids: [])
            let decision = try await reopened.sessionUseCases.reconcileOnLaunch()
            switch decision {
            case .replay(let snapshot):
                XCTAssertEqual(snapshot.revision, higherSnapshot.revision)
                XCTAssertEqual(setState(in: snapshot.session, id: pendingSetID), .pending)
            case .consistent(let session):
                XCTAssertEqual(setState(in: session, id: pendingSetID), .pending)
            default:
                XCTFail("Expected replay or consistent after a higher-revision snapshot, got \(decision)")
            }

            let restoredActive = try await reopened.sessionUseCases.loadActive()
            let restored = try XCTUnwrap(restoredActive)
            XCTAssertEqual(restored.id, original.id)
            XCTAssertEqual(restored.state, .inProgress)
            XCTAssertEqual(restored.exercises.first?.sets.map(\.id), [completedSetID, pendingSetID])
            XCTAssertEqual(setState(in: restored, id: pendingSetID), .pending)
            XCTAssertEqual(setState(in: restored, id: completedSetID), .completed)
            XCTAssertFalse(restored.exercises.first?.sets.last?.contributesToStatistics ?? true)
            try await reopened.controller.shutdownForTesting()
        }

        private struct Environment {
            let directory: TemporaryProtectedDirectory
            let storeURL: URL
            let controller: PersistenceController
            let studentUseCases: StudentUseCases
            let sessionUseCases: ActiveSessionUseCases
            let recoveryStore: ActiveSessionRecoveryStore
        }

        private func makeUseCases(ids: [UUID], injector: TestFaultInjector? = nil) throws -> Environment {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            return try makeUseCases(directory: directory, storeURL: storeURL, ids: ids, injector: injector)
        }

        private func makeUseCases(
            directory: TemporaryProtectedDirectory,
            storeURL: URL,
            ids: [UUID],
            injector: TestFaultInjector? = nil
        ) throws -> Environment {
            let recoveryURL = directory.url.appendingPathComponent("active-session-recovery-v1.json")
            let faultInjectionBoundary = injector.map { FaultInjectionBoundary(injector: $0) }
            let controller: PersistenceController
            if let faultInjectionBoundary {
                controller = try PersistenceController(
                    storeURL: storeURL,
                    faultInjectionBoundary: faultInjectionBoundary
                )
            } else {
                controller = try PersistenceController(storeURL: storeURL)
            }
            let recoveryStore: ActiveSessionRecoveryStore
            if let faultInjectionBoundary {
                recoveryStore = ActiveSessionRecoveryStore(
                    url: recoveryURL,
                    faultInjectionBoundary: faultInjectionBoundary
                )
            } else {
                recoveryStore = ActiveSessionRecoveryStore(url: recoveryURL)
            }
            let clock = TestClock(utcDate: now)
            let ids = TestIDGenerator(ids: ids)
            let studentRepository = CoreDataStudentRepository(writer: controller.writer)
            let sessionRepository = CoreDataSessionRepository(writer: controller.writer)
            return Environment(
                directory: directory,
                storeURL: storeURL,
                controller: controller,
                studentUseCases: StudentUseCases(
                    repository: studentRepository,
                    clock: clock,
                    ids: ids
                ),
                sessionUseCases: ActiveSessionUseCases(
                    sessionRepository: sessionRepository,
                    studentRepository: studentRepository,
                    recoveryStore: recoveryStore,
                    storeGenerationUUID: storeGenerationUUID,
                    clock: clock,
                    ids: ids
                ),
                recoveryStore: recoveryStore
            )
        }

        private func weightRepsInput(weight: String, reps: String) -> TrainingSetInput {
            TrainingSetInput(
                recordMode: .weightReps,
                weightValue: weight,
                repetitionCount: reps,
                unit: .kilograms
            )
        }

        private func setState(in session: Session, id: StableUUID) -> SetRecordingState? {
            session.exercises.flatMap(\.sets).first { $0.id == id }?.state
        }

        private func assertBlocked(
            at point: FaultInjectionPoint,
            file: StaticString = #filePath,
            line: UInt = #line,
            _ work: () async throws -> Void
        ) async {
            do {
                try await work()
                XCTFail("Expected injected \(point.rawValue) or persistenceFailed", file: file, line: line)
            } catch let error as FaultInjectionError {
                XCTAssertEqual(error, .injected(point), file: file, line: line)
            } catch DomainError.persistenceFailed {
                return
            } catch {
                XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
        }

        private func sessionCount(state: String? = nil, writer: PersistenceWriter) async throws -> Int {
            try await writer.read { context in
                let request = NSFetchRequest<NSManagedObject>(entityName: "SessionMO")
                if let state {
                    request.predicate = NSPredicate(format: "state == %@", state)
                }
                return try context.count(for: request)
            }
        }
    }
#else
    import XCTest
    import FineCoach

    final class RecoveryProjectionTests: XCTestCase {
        func testReleaseKeepsActiveSessionDomainSurfaceWithoutFaultInjection() {
            XCTAssertEqual(SessionState.inProgress.rawValue, "inProgress")
            XCTAssertEqual(ActiveSessionPointerKey.singleton, "active")
            XCTAssertEqual(RecordMode.weightReps.rawValue, "weightReps")
        }
    }
#endif
