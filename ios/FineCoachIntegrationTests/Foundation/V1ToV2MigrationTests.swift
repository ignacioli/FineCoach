#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// M1-B T006 (kept current through T075/Revision 1.2): proves a V1 store
    /// fixture opens cleanly under the bundled CURRENT model (now FineCoachV3,
    /// via Core Data's automatic multi-hop V1->V2->V3 inferred migration) and
    /// that the original M1-A data survives byte-for-byte (data-model §7). The
    /// V2->V3-specific assertions (old trainingFocus/weekdays columns gone,
    /// new mask columns default empty) live in V2ToV3MigrationTests.swift.
    final class V1ToV2MigrationTests: XCTestCase {
        private let studentID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        private let sessionID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        private let sessionExerciseID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        private let trainingSetID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        private struct MigratedSnapshot: Equatable, Sendable {
            let studentDisplayName: String?
            let studentSex: String?
            let studentLifecycle: String?
            let sessionStudentID: UUID?
            let sessionState: String?
            let sessionTrainingFocusMask: Int32?
            let sessionAppointmentID: UUID?
            let exerciseDisplayName: String?
            let exerciseSectionID: UUID?
            let exerciseSessionRelationID: UUID?
            let setWeightValue: NSDecimalNumber?
            let setRepetitionCount: NSDecimalNumber?
            let setDistanceValue: NSDecimalNumber?
            let setSpeedValue: NSDecimalNumber?
            let setResistanceValue: NSDecimalNumber?
            let newEntityFetchCount: Int
        }

        func testV1StoreFixtureOpensUnderV2WithDataIntact() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")

            try makeV1Fixture(at: storeURL)

            let controller = try PersistenceController(storeURL: storeURL)
            let studentID = studentID
            let sessionID = sessionID
            let sessionExerciseID = sessionExerciseID
            let trainingSetID = trainingSetID

            let snapshot = try await controller.writer.read { context -> MigratedSnapshot in
                func fetchOne(_ entityName: String, id: UUID) throws -> NSManagedObject? {
                    let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
                    request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                    request.fetchLimit = 1
                    return try context.fetch(request).first
                }

                let student = try fetchOne("StudentMO", id: studentID)
                let session = try fetchOne("SessionMO", id: sessionID)
                let exercise = try fetchOne("SessionExerciseMO", id: sessionExerciseID)
                let set = try fetchOne("TrainingSetMO", id: trainingSetID)
                let relatedSession = exercise?.value(forKey: "session") as? NSManagedObject

                let seriesRequest = NSFetchRequest<NSManagedObject>(entityName: "RecurrenceSeriesMO")
                let newEntityCount = try context.count(for: seriesRequest)

                return MigratedSnapshot(
                    studentDisplayName: student?.value(forKey: "displayName") as? String,
                    studentSex: student?.value(forKey: "sex") as? String,
                    studentLifecycle: student?.value(forKey: "lifecycle") as? String,
                    sessionStudentID: session?.value(forKey: "studentID") as? UUID,
                    sessionState: session?.value(forKey: "state") as? String,
                    sessionTrainingFocusMask: session?.value(forKey: "trainingFocusMask") as? Int32,
                    sessionAppointmentID: session?.value(forKey: "appointmentID") as? UUID,
                    exerciseDisplayName: exercise?.value(forKey: "displayNameSnapshot") as? String,
                    exerciseSectionID: exercise?.value(forKey: "sectionID") as? UUID,
                    exerciseSessionRelationID: relatedSession?.value(forKey: "id") as? UUID,
                    setWeightValue: set?.value(forKey: "weightValue") as? NSDecimalNumber,
                    setRepetitionCount: set?.value(forKey: "repetitionCount") as? NSDecimalNumber,
                    setDistanceValue: set?.value(forKey: "distanceValue") as? NSDecimalNumber,
                    setSpeedValue: set?.value(forKey: "speedValue") as? NSDecimalNumber,
                    setResistanceValue: set?.value(forKey: "resistanceValue") as? NSDecimalNumber,
                    newEntityFetchCount: newEntityCount
                )
            }

            XCTAssertEqual(snapshot.studentDisplayName, "林青")
            XCTAssertEqual(snapshot.studentSex, "female")
            XCTAssertEqual(snapshot.studentLifecycle, "active")
            XCTAssertEqual(snapshot.sessionStudentID, studentID)
            XCTAssertEqual(snapshot.sessionState, "completed")
            // Revision 1.2/D-013: the V1 fixture's free-text trainingFocus ("上肢力量")
            // is a column that no longer exists post-migration -- it is discarded, not
            // converted (product-owner decision), and the new trainingFocusMask column
            // defaults to 0 (empty Set<BodyPart>), never fabricated from the old text.
            XCTAssertEqual(snapshot.sessionTrainingFocusMask, 0)
            // T005 incremental field: absent on a migrated V1 row, not fabricated.
            XCTAssertNil(snapshot.sessionAppointmentID)
            XCTAssertEqual(snapshot.exerciseDisplayName, "杠铃卧推")
            XCTAssertNil(snapshot.exerciseSectionID)
            // Relationship survives migration.
            XCTAssertEqual(snapshot.exerciseSessionRelationID, sessionID)
            XCTAssertEqual(snapshot.setWeightValue, NSDecimalNumber(string: "60"))
            XCTAssertEqual(snapshot.setRepetitionCount, NSDecimalNumber(string: "8"))
            XCTAssertNil(snapshot.setDistanceValue)
            XCTAssertNil(snapshot.setSpeedValue)
            XCTAssertNil(snapshot.setResistanceValue)
            // New M1-B-only entity is queryable (schema present) and empty (nothing fabricated).
            XCTAssertEqual(snapshot.newEntityFetchCount, 0)

            try await controller.shutdownForTesting()
        }

        // MARK: - V1 fixture construction

        private func makeV1Fixture(at storeURL: URL) throws {
            let v1Model = try PersistenceController.loadModelVersionForMigrationTesting(named: "FineCoachV1")
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v1Model)
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: nil
            )
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator

            try context.performAndWait {
                let student = NSEntityDescription.insertNewObject(forEntityName: "StudentMO", into: context)
                student.setValue(studentID, forKey: "id")
                student.setValue("林青", forKey: "displayName")
                student.setValue("female", forKey: "sex")
                student.setValue("active", forKey: "lifecycle")
                student.setValue(now, forKey: "createdAtUTC")
                student.setValue(now, forKey: "updatedAtUTC")

                let session = NSEntityDescription.insertNewObject(forEntityName: "SessionMO", into: context)
                session.setValue(sessionID, forKey: "id")
                session.setValue(studentID, forKey: "studentID")
                session.setValue("completed", forKey: "state")
                session.setValue(now, forKey: "startedAtUTC")
                session.setValue(now, forKey: "lastCheckpointUTC")
                session.setValue(NSDecimalNumber(string: "1800"), forKey: "elapsedSeconds")
                session.setValue(false, forKey: "durationNeedsReview")
                session.setValue("上肢力量", forKey: "trainingFocus")
                session.setValue(Int64(1), forKey: "revision")
                session.setValue(now, forKey: "createdAtUTC")
                session.setValue(now, forKey: "updatedAtUTC")
                session.setValue(now, forKey: "completedAtUTC")
                session.setValue(student, forKey: "student")

                let sessionExercise = NSEntityDescription.insertNewObject(
                    forEntityName: "SessionExerciseMO", into: context)
                sessionExercise.setValue(sessionExerciseID, forKey: "id")
                sessionExercise.setValue(sessionID, forKey: "sessionID")
                sessionExercise.setValue(Int32(0), forKey: "orderIndex")
                sessionExercise.setValue("builtIn", forKey: "sourceKind")
                sessionExercise.setValue("barbell-bench-press", forKey: "sourceID")
                sessionExercise.setValue("杠铃卧推", forKey: "displayNameSnapshot")
                sessionExercise.setValue("weightReps", forKey: "recordModeSnapshot")
                sessionExercise.setValue(session, forKey: "session")

                let trainingSet = NSEntityDescription.insertNewObject(forEntityName: "TrainingSetMO", into: context)
                trainingSet.setValue(trainingSetID, forKey: "id")
                trainingSet.setValue(sessionExerciseID, forKey: "sessionExerciseID")
                trainingSet.setValue(Int32(0), forKey: "orderIndex")
                trainingSet.setValue("completed", forKey: "state")
                trainingSet.setValue("weightReps", forKey: "recordMode")
                trainingSet.setValue(NSDecimalNumber(string: "60"), forKey: "weightValue")
                trainingSet.setValue(NSDecimalNumber(string: "8"), forKey: "repetitionCount")
                trainingSet.setValue("kg", forKey: "unit")
                trainingSet.setValue("none", forKey: "side")
                trainingSet.setValue(now, forKey: "createdAtUTC")
                trainingSet.setValue(now, forKey: "updatedAtUTC")
                trainingSet.setValue(now, forKey: "completedAtUTC")
                trainingSet.setValue(sessionExercise, forKey: "sessionExercise")

                try context.save()
                // A private-queue context may only be touched on its own
                // queue; resetting it outside `performAndWait` intermittently
                // crashed in -[NSManagedObjectContext reset] (EXC_BAD_ACCESS).
                context.reset()
            }

            for store in coordinator.persistentStores {
                try coordinator.remove(store)
            }
        }
    }
#endif
