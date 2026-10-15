#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// V5 only adds the optional `ExercisePreferenceMO.isUnilateral` column
    /// (P0-D8, product-owner decision 2026-10-15). A V4 store must open under
    /// the bundled current model via lightweight migration with every
    /// existing preference field intact and no override inferred (`nil`, so
    /// the library default still applies), and must accept an override
    /// afterwards.
    final class V4ToV5MigrationTests: XCTestCase {
        private let exerciseID = "custom-41111111-1111-4111-8111-111111111111"
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        func testV4StoreOpensUnderV5WithPreferenceIntactAndNoUnilateralOverride() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            try makeV4Fixture(at: storeURL)

            let controller = try PersistenceController(storeURL: storeURL)
            let exerciseID = exerciseID
            let migrated = try await controller.writer.read { context -> ExercisePreference? in
                try ExerciseManagedObjectMapping.fetchPreference(exerciseID: exerciseID, in: context)
                    .map { try ExerciseManagedObjectMapping.makePreference(from: $0) }
            }
            let preference = try XCTUnwrap(migrated)
            XCTAssertEqual(preference.alias?.value, "单臂划船")
            XCTAssertTrue(preference.isFavorite)
            XCTAssertTrue(preference.isAssisted)
            XCTAssertNil(preference.isUnilateral, "old preferences must not get an inferred override")

            let repository = CoreDataExerciseRepository(writer: controller.writer)
            let updated = try await repository.setPreference(
                exerciseID: try StableExerciseID(exerciseID),
                alias: nil,
                isFavorite: nil,
                isHidden: nil,
                isUnilateral: true
            )
            XCTAssertEqual(updated.isUnilateral, true)
            XCTAssertEqual(updated.alias?.value, "单臂划船", "the override must not touch other fields")

            try await controller.shutdownForTesting()
        }

        private func makeV4Fixture(at storeURL: URL) throws {
            let v4Model = try PersistenceController.loadModelVersionForMigrationTesting(named: "FineCoachV4")
            XCTAssertNil(
                v4Model.entitiesByName["ExercisePreferenceMO"]?.attributesByName["isUnilateral"],
                "the fixture must really be the pre-unilateral schema"
            )
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v4Model)
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
                let item = NSEntityDescription.insertNewObject(forEntityName: "ExerciseCatalogMO", into: context)
                item.setValue(exerciseID, forKey: "id")
                item.setValue("custom", forKey: "kind")
                item.setValue("哑铃单臂划船", forKey: "canonicalName")
                item.setValue("哑铃单臂划船", forKey: "normalizedName")
                item.setValue("weightReps", forKey: "recordMode")
                item.setValue("custom", forKey: "metadataVersion")
                item.setValue("active", forKey: "lifecycle")
                item.setValue(now, forKey: "createdAtUTC")
                item.setValue(now, forKey: "updatedAtUTC")

                let preference = NSEntityDescription.insertNewObject(
                    forEntityName: "ExercisePreferenceMO",
                    into: context
                )
                preference.setValue(exerciseID, forKey: "exerciseID")
                preference.setValue("单臂划船", forKey: "alias")
                preference.setValue(true, forKey: "isFavorite")
                preference.setValue(false, forKey: "isHidden")
                preference.setValue(true, forKey: "isAssisted")
                preference.setValue(item, forKey: "exercise")
                try context.save()
            }
        }
    }
#endif
