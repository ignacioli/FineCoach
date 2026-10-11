#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// V4 only adds the optional `SessionMO.creditSettlementNote` column (owner
    /// decision 2026-10-11). A V3 store must open under the bundled current
    /// model via lightweight migration with every existing Session field
    /// intact and the new note empty (never inferred for old Sessions), and
    /// the migrated store must accept a note write afterwards.
    final class V3ToV4MigrationTests: XCTestCase {
        private let studentID = UUID(uuidString: "31111111-1111-4111-8111-111111111111")!
        private let sessionID = UUID(uuidString: "32222222-2222-4222-8222-222222222222")!
        private let appointmentID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        func testV3StoreOpensUnderV4WithSessionIntactAndNoCreditNote() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            try makeV3Fixture(at: storeURL)

            let controller = try PersistenceController(storeURL: storeURL)
            let sessionID = sessionID
            let migrated = try await controller.writer.read { context -> [String: String] in
                let request = NSFetchRequest<NSManagedObject>(entityName: "SessionMO")
                request.predicate = NSPredicate(format: "id == %@", sessionID as CVarArg)
                guard let session = try context.fetch(request).first else {
                    return [:]
                }
                return [
                    "state": session.value(forKey: "state") as? String ?? "",
                    "summary": session.value(forKey: "studentFacingSummary") as? String ?? "",
                    "focus": String(session.value(forKey: "trainingFocusMask") as? Int32 ?? -1),
                    "appointment": (session.value(forKey: "appointmentID") as? UUID)?.uuidString ?? "",
                    "note": session.value(forKey: "creditSettlementNote") as? String ?? "<nil>",
                ]
            }
            XCTAssertEqual(migrated["state"], "completed")
            XCTAssertEqual(migrated["summary"], "状态不错")
            XCTAssertEqual(migrated["focus"], "3")
            XCTAssertEqual(migrated["appointment"], appointmentID.uuidString)
            XCTAssertEqual(migrated["note"], "<nil>", "old Sessions must not get an inferred note")

            let repository = CoreDataSessionRepository(writer: controller.writer)
            let before = try await repository.creditSettlementNote(sessionID: StableUUID(sessionID))
            XCTAssertNil(before)
            try await repository.recordCreditSettlementNote(.noActivePackage, sessionID: StableUUID(sessionID))
            let notes = try await repository.creditSettlementNotes(studentID: StableUUID(studentID))
            XCTAssertEqual(notes, [StableUUID(sessionID): .noActivePackage])
            let completed = try await repository.completedSession(id: StableUUID(sessionID))
            XCTAssertEqual(completed.id.rawValue, sessionID)

            try await controller.shutdownForTesting()
        }

        private func makeV3Fixture(at storeURL: URL) throws {
            let v3Model = try PersistenceController.loadModelVersionForMigrationTesting(named: "FineCoachV3")
            XCTAssertNil(
                v3Model.entitiesByName["SessionMO"]?.attributesByName["creditSettlementNote"],
                "the fixture must really be the pre-note schema"
            )
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v3Model)
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator

            try context.performAndWait {
                let student = NSEntityDescription.insertNewObject(forEntityName: "StudentMO", into: context)
                student.setValue(studentID, forKey: "id")
                student.setValue("周宁", forKey: "displayName")
                student.setValue("male", forKey: "sex")
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
                session.setValue(Int32(3), forKey: "trainingFocusMask")
                session.setValue("状态不错", forKey: "studentFacingSummary")
                session.setValue(appointmentID, forKey: "appointmentID")
                session.setValue(Int64(1), forKey: "revision")
                session.setValue(now, forKey: "createdAtUTC")
                session.setValue(now, forKey: "updatedAtUTC")
                session.setValue(now, forKey: "completedAtUTC")
                session.setValue(student, forKey: "student")

                try context.save()
                context.reset()
            }
            for store in coordinator.persistentStores {
                try coordinator.remove(store)
            }
        }
    }
#endif
