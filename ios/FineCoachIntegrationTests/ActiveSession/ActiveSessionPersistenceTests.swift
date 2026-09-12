#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    final class ActiveSessionPersistenceTests: XCTestCase {
        private let firstID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        private let secondID = StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
        private let sessionID = StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        private let secondSessionID = StableUUID(UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!)
        private let firstExerciseID = StableUUID(UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
        private let secondExerciseID = StableUUID(UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!)
        private let setID = StableUUID(UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!)
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        func testStartCreatesSingletonPointerAndSecondStartReturnsSameSession() async throws {
            let environment = try makeUseCases(
                ids: [firstID.rawValue, sessionID.rawValue, secondID.rawValue]
            )
            _ = try await environment.studentUseCases.create(
                draft: StudentDraft(displayName: "林青", sex: .female)
            )

            let first = try await environment.sessionUseCases.startOrOpen(studentID: firstID)
            let secondOpen = try await environment.sessionUseCases.startOrOpen(studentID: firstID)
            XCTAssertEqual(first.id, sessionID)
            XCTAssertEqual(secondOpen.id, first.id)
            XCTAssertEqual(first.state, .inProgress)
            let inProgressCount = try await sessionCount(state: "inProgress", writer: environment.controller.writer)
            XCTAssertEqual(inProgressCount, 1)

            let pointer = try await fetchActivePointer(writer: environment.controller.writer)
            XCTAssertEqual(pointer?.singletonKey, ActiveSessionPointerKey.singleton)
            XCTAssertEqual(pointer?.singletonKey, "active")
            XCTAssertEqual(pointer?.sessionID, first.id.rawValue)

            _ = try await environment.studentUseCases.create(
                draft: StudentDraft(displayName: "周宁", sex: .male)
            )
            let otherStudentOpen = try await environment.sessionUseCases.startOrOpen(studentID: secondID)
            XCTAssertEqual(otherStudentOpen.id, first.id)
            XCTAssertEqual(otherStudentOpen.studentID, firstID)
            let stillInProgress = try await sessionCount(state: "inProgress", writer: environment.controller.writer)
            let totalSessions = try await sessionCount(writer: environment.controller.writer)
            XCTAssertEqual(stillInProgress, 1)
            XCTAssertEqual(totalSessions, 1)
            try await environment.controller.shutdownForTesting()
        }

        func testArchivedStudentCannotStartSession() async throws {
            let environment = try makeUseCases(ids: [firstID.rawValue, sessionID.rawValue])
            _ = try await environment.studentUseCases.create(
                draft: StudentDraft(displayName: "周宁", sex: .male)
            )
            _ = try await environment.studentUseCases.archive(id: firstID)

            do {
                _ = try await environment.sessionUseCases.startOrOpen(studentID: firstID)
                XCTFail("Expected archived student start to fail")
            } catch DomainError.invalidState {
                // expected
            }

            let archivedSessionCount = try await sessionCount(writer: environment.controller.writer)
            let archivedPointer = try await fetchActivePointer(writer: environment.controller.writer)
            XCTAssertEqual(archivedSessionCount, 0)
            XCTAssertNil(archivedPointer)
            try await environment.controller.shutdownForTesting()
        }

        func testOrderConstraintAndExerciseDeleteRollback() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let original: Session
            do {
                let environment = try makeUseCases(
                    directory: directory,
                    storeURL: storeURL,
                    ids: [
                        firstID.rawValue,
                        sessionID.rawValue,
                        firstExerciseID.rawValue,
                        secondExerciseID.rawValue,
                        setID.rawValue,
                    ]
                )
                _ = try await environment.studentUseCases.create(
                    draft: StudentDraft(displayName: "林青", sex: .female)
                )
                _ = try await environment.sessionUseCases.startOrOpen(studentID: firstID)
                _ = try await environment.sessionUseCases.addSessionOnlyExercise(
                    displayName: "杠铃深蹲",
                    recordMode: .weightReps
                )
                _ = try await environment.sessionUseCases.addSessionOnlyExercise(
                    displayName: "平板支撑",
                    recordMode: .duration
                )
                _ = try await environment.sessionUseCases.addSet(
                    exerciseID: firstExerciseID,
                    input: weightRepsInput(weight: "0", reps: "5")
                )
                _ = try await environment.sessionUseCases.confirmSet(setID: setID)
                original = try await environment.sessionUseCases.reorderExercises(
                    orderedIDs: [secondExerciseID, firstExerciseID]
                )
                XCTAssertEqual(original.exercises.map(\.id), [secondExerciseID, firstExerciseID])
                XCTAssertEqual(original.exercises.map(\.orderIndex), [0, 1])
                try await environment.controller.shutdownForTesting()
            }

            do {
                let reopened = try makeUseCases(directory: directory, storeURL: storeURL, ids: [])
                let restoredActive = try await reopened.sessionUseCases.loadActive()
                let restored = try XCTUnwrap(restoredActive)
                XCTAssertEqual(restored.id, original.id)
                XCTAssertEqual(restored.exercises.map(\.id), [secondExerciseID, firstExerciseID])
                XCTAssertEqual(restored.exercises.map(\.orderIndex), [0, 1])
                XCTAssertEqual(Set(restored.exercises.map(\.orderIndex)).count, restored.exercises.count)

                let persistedIndexes = try await fetchExerciseOrderIndexes(
                    sessionID: restored.id.rawValue,
                    writer: reopened.controller.writer
                )
                XCTAssertEqual(persistedIndexes, [0, 1])
                XCTAssertEqual(Set(persistedIndexes).count, persistedIndexes.count)

                do {
                    _ = try await reopened.sessionUseCases.removeExercise(
                        exerciseID: firstExerciseID,
                        confirmedIfCompleted: false
                    )
                    XCTFail("Expected unconfirmed delete of completed exercise to fail")
                } catch DomainError.invalidState {
                    // expected
                }

                let afterFailedDeleteActive = try await reopened.sessionUseCases.loadActive()
                let afterFailedDelete = try XCTUnwrap(afterFailedDeleteActive)
                XCTAssertEqual(afterFailedDelete.exercises.map(\.id), [secondExerciseID, firstExerciseID])
                XCTAssertEqual(
                    afterFailedDelete.exercises.first(where: { $0.id == firstExerciseID })?.sets.map(\.id),
                    [setID]
                )
                try await reopened.controller.shutdownForTesting()
            }

            let verified = try makeUseCases(directory: directory, storeURL: storeURL, ids: [])
            let reloadedActive = try await verified.sessionUseCases.loadActive()
            let reloaded = try XCTUnwrap(reloadedActive)
            XCTAssertEqual(reloaded.exercises.map(\.id), [secondExerciseID, firstExerciseID])
            let squat = try XCTUnwrap(reloaded.exercises.first(where: { $0.id == firstExerciseID }))
            XCTAssertEqual(squat.displayNameSnapshot.value, "杠铃深蹲")
            XCTAssertEqual(squat.sets.map(\.id), [setID])
            XCTAssertEqual(squat.sets.first?.state, .completed)
            try await verified.controller.shutdownForTesting()
        }

        func testFinishTransactionClearsPointerAndAbandonDoesNotCreateCompletedHistory() async throws {
            do {
                let environment = try makeUseCases(
                    ids: [
                        firstID.rawValue,
                        sessionID.rawValue,
                        firstExerciseID.rawValue,
                        setID.rawValue,
                    ]
                )
                _ = try await environment.studentUseCases.create(
                    draft: StudentDraft(displayName: "林青", sex: .female)
                )
                _ = try await environment.sessionUseCases.startOrOpen(studentID: firstID)
                _ = try await environment.sessionUseCases.addSessionOnlyExercise(
                    displayName: "杠铃深蹲",
                    recordMode: .weightReps
                )
                _ = try await environment.sessionUseCases.addSet(
                    exerciseID: firstExerciseID,
                    input: weightRepsInput(weight: "0", reps: "5")
                )
                _ = try await environment.sessionUseCases.confirmSet(setID: setID)

                let finished = try await environment.sessionUseCases.finish()
                XCTAssertEqual(finished.state, .completed)
                XCTAssertEqual(finished.completedAtUTC, now)
                let finishedActive = try await environment.sessionUseCases.loadActive()
                let finishedPointer = try await fetchActivePointer(writer: environment.controller.writer)
                let completedCount = try await sessionCount(state: "completed", writer: environment.controller.writer)
                let remainingInProgress = try await sessionCount(
                    state: "inProgress", writer: environment.controller.writer)
                XCTAssertNil(finishedActive)
                XCTAssertNil(finishedPointer)
                XCTAssertEqual(completedCount, 1)
                XCTAssertEqual(remainingInProgress, 0)
                try await environment.controller.shutdownForTesting()
            }

            let empty = try makeUseCases(ids: [firstID.rawValue, secondSessionID.rawValue])
            _ = try await empty.studentUseCases.create(
                draft: StudentDraft(displayName: "林青", sex: .female)
            )
            _ = try await empty.sessionUseCases.startOrOpen(studentID: firstID)
            let abandoned = try await empty.sessionUseCases.abandonEmpty()
            XCTAssertEqual(abandoned.state, .abandonedEmpty)
            XCTAssertNil(abandoned.completedAtUTC)
            let abandonedActive = try await empty.sessionUseCases.loadActive()
            let abandonedPointer = try await fetchActivePointer(writer: empty.controller.writer)
            let abandonedCompleted = try await sessionCount(state: "completed", writer: empty.controller.writer)
            let abandonedEmptyCount = try await sessionCount(state: "abandonedEmpty", writer: empty.controller.writer)
            XCTAssertNil(abandonedActive)
            XCTAssertNil(abandonedPointer)
            XCTAssertEqual(abandonedCompleted, 0)
            XCTAssertEqual(abandonedEmptyCount, 1)
            try await empty.controller.shutdownForTesting()
        }

        func testWriterSaveFailureRollsBackStart() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            do {
                let healthy = try makeUseCases(
                    directory: directory,
                    storeURL: storeURL,
                    ids: [firstID.rawValue]
                )
                _ = try await healthy.studentUseCases.create(
                    draft: StudentDraft(displayName: "林青", sex: .female)
                )
                try await healthy.controller.shutdownForTesting()
            }

            do {
                let failing = try makeUseCases(
                    directory: directory,
                    storeURL: storeURL,
                    ids: [sessionID.rawValue],
                    faultInjectionBoundary: FaultInjectionBoundary(
                        injector: TestFaultInjector(failingPoints: [.persistenceWriterSave])
                    )
                )
                do {
                    _ = try await failing.sessionUseCases.startOrOpen(studentID: firstID)
                    XCTFail("Expected injected save failure")
                } catch FaultInjectionError.injected(.persistenceWriterSave) {
                    // expected
                }
                try await failing.controller.shutdownForTesting()
            }

            let reopened = try makeUseCases(directory: directory, storeURL: storeURL, ids: [])
            let rolledBackActive = try await reopened.sessionUseCases.loadActive()
            let rolledBackInProgress = try await sessionCount(state: "inProgress", writer: reopened.controller.writer)
            let rolledBackTotal = try await sessionCount(writer: reopened.controller.writer)
            let rolledBackPointer = try await fetchActivePointer(writer: reopened.controller.writer)
            XCTAssertNil(rolledBackActive)
            XCTAssertEqual(rolledBackInProgress, 0)
            XCTAssertEqual(rolledBackTotal, 0)
            XCTAssertNil(rolledBackPointer)
            let remaining = try await reopened.studentUseCases.student(id: firstID)
            XCTAssertEqual(remaining.displayName.value, "林青")
            try await reopened.controller.shutdownForTesting()
        }

        func testRestartReadsFullAggregate() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let original: Session
            do {
                let environment = try makeUseCases(
                    directory: directory,
                    storeURL: storeURL,
                    ids: [
                        firstID.rawValue,
                        sessionID.rawValue,
                        firstExerciseID.rawValue,
                        setID.rawValue,
                    ]
                )
                _ = try await environment.studentUseCases.create(
                    draft: StudentDraft(displayName: "林青", sex: .female)
                )
                _ = try await environment.sessionUseCases.startOrOpen(studentID: firstID)
                _ = try await environment.sessionUseCases.addSessionOnlyExercise(
                    displayName: "杠铃深蹲",
                    recordMode: .weightReps
                )
                _ = try await environment.sessionUseCases.addSet(
                    exerciseID: firstExerciseID,
                    input: weightRepsInput(weight: "0", reps: "5")
                )
                original = try await environment.sessionUseCases.confirmSet(setID: setID)
                XCTAssertEqual(original.exercises.count, 1)
                XCTAssertEqual(original.completedSetCount, 1)
                try await environment.controller.shutdownForTesting()
            }

            let reopened = try makeUseCases(directory: directory, storeURL: storeURL, ids: [])
            let restoredActive = try await reopened.sessionUseCases.loadActive()
            let restored = try XCTUnwrap(restoredActive)
            XCTAssertEqual(restored.id, original.id)
            XCTAssertEqual(restored.studentID, firstID)
            XCTAssertEqual(restored.state, .inProgress)
            XCTAssertEqual(restored.revision, original.revision)
            XCTAssertEqual(restored.exercises.count, 1)
            let exercise = try XCTUnwrap(restored.exercises.first)
            XCTAssertEqual(exercise.id, firstExerciseID)
            XCTAssertEqual(exercise.displayNameSnapshot.value, "杠铃深蹲")
            XCTAssertEqual(exercise.recordModeSnapshot, .weightReps)
            XCTAssertEqual(exercise.sourceKind, .sessionOnly)
            XCTAssertEqual(exercise.orderIndex, 0)
            XCTAssertEqual(exercise.sets.count, 1)
            let set = try XCTUnwrap(exercise.sets.first)
            XCTAssertEqual(set.id, setID)
            XCTAssertEqual(set.state, .completed)
            XCTAssertEqual(set.recordMode, .weightReps)
            XCTAssertEqual(set.weightValue?.canonicalString, DecimalValue.zero.canonicalString)
            XCTAssertEqual(set.repetitionCount?.canonicalString, try DecimalValue("5").canonicalString)
            XCTAssertEqual(set.unit, .kilograms)
            XCTAssertEqual(set.side, .none)
            XCTAssertEqual(set.completedAtUTC, now)
            XCTAssertTrue(set.contributesToStatistics)
            try await reopened.controller.shutdownForTesting()
        }

        private struct Environment {
            let directory: TemporaryProtectedDirectory
            let storeURL: URL
            let controller: PersistenceController
            let studentUseCases: StudentUseCases
            let sessionUseCases: ActiveSessionUseCases
        }

        private func makeUseCases(ids: [UUID]) throws -> Environment {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            return try makeUseCases(directory: directory, storeURL: storeURL, ids: ids)
        }

        private func makeUseCases(
            directory: TemporaryProtectedDirectory,
            storeURL: URL,
            ids: [UUID],
            faultInjectionBoundary: FaultInjectionBoundary? = nil
        ) throws -> Environment {
            let controller: PersistenceController
            if let faultInjectionBoundary {
                controller = try PersistenceController(
                    storeURL: storeURL,
                    faultInjectionBoundary: faultInjectionBoundary
                )
            } else {
                controller = try PersistenceController(storeURL: storeURL)
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
                    exerciseRepository: CoreDataExerciseRepository(writer: controller.writer),
                    sectionRepository: CoreDataSessionSectionRepository(writer: controller.writer),
                    recoveryStore: ActiveSessionRecoveryStore(
                        url: directory.url.appendingPathComponent("active-session-recovery-v1.json"),
                        protectedFileStore: ProtectedFileStore()
                    ),
                    storeGenerationUUID: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
                    clock: clock,
                    ids: ids
                )
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

        private func sessionCount(state: String? = nil, writer: PersistenceWriter) async throws -> Int {
            try await writer.read { context in
                let request = NSFetchRequest<NSManagedObject>(entityName: "SessionMO")
                if let state {
                    request.predicate = NSPredicate(format: "state == %@", state)
                }
                return try context.count(for: request)
            }
        }

        private func fetchActivePointer(
            writer: PersistenceWriter
        ) async throws -> (singletonKey: String, sessionID: UUID)? {
            try await writer.read { context in
                let request = NSFetchRequest<NSManagedObject>(entityName: "ActiveSessionPointerMO")
                request.predicate = NSPredicate(
                    format: "singletonKey == %@",
                    ActiveSessionPointerKey.singleton
                )
                request.fetchLimit = 1
                guard let object = try context.fetch(request).first else {
                    return nil
                }
                guard let singletonKey = object.value(forKey: "singletonKey") as? String,
                    let sessionID = object.value(forKey: "sessionID") as? UUID
                else {
                    throw DomainError.incompatibleInput
                }
                return (singletonKey, sessionID)
            }
        }

        private func fetchExerciseOrderIndexes(sessionID: UUID, writer: PersistenceWriter) async throws -> [Int] {
            try await writer.read { context in
                let request = NSFetchRequest<NSManagedObject>(entityName: "SessionExerciseMO")
                request.predicate = NSPredicate(format: "sessionID == %@", sessionID as CVarArg)
                request.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
                return try context.fetch(request).compactMap { object in
                    (object.value(forKey: "orderIndex") as? NSNumber)?.intValue
                }
            }
        }
    }
#else
    import XCTest
    import FineCoach

    final class ActiveSessionPersistenceTests: XCTestCase {
        func testReleaseKeepsActiveSessionDomainSurfaceWithoutFaultInjection() {
            XCTAssertEqual(SessionState.inProgress.rawValue, "inProgress")
            XCTAssertEqual(ActiveSessionPointerKey.singleton, "active")
            XCTAssertEqual(RecordMode.weightReps.rawValue, "weightReps")
        }
    }
#endif
