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

    /// CX-D10: V6 adds only the optional ExerciseCatalogMO.isRetired attribute.
    /// A V5 store must migrate without changing the existing catalog row, and
    /// the missing optional value must read as active (`false`) rather than
    /// making an old built-in disappear.
    final class V5ToV6MigrationTests: XCTestCase {
        private let exerciseID = "8e420408-0682-4ab6-89f5-2681e54c7ce0"
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        func testV5StoreOpensUnderV6WithCatalogRowActiveByDefault() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            try makeV5Fixture(at: storeURL)

            let controller = try PersistenceController(storeURL: storeURL)
            let fixtureExerciseID = exerciseID
            let rawRetired = try await controller.writer.read { context -> Bool? in
                let object = try ExerciseManagedObjectMapping.requireCatalogItem(id: fixtureExerciseID, in: context)
                return object.value(forKey: "isRetired") as? Bool
            }
            XCTAssertEqual(rawRetired, false, "V5 rows must default to active during lightweight migration")

            let repository = CoreDataExerciseRepository(writer: controller.writer)
            let item = try await repository.catalogItem(id: try StableExerciseID(exerciseID))
            XCTAssertFalse(item.isRetired)
            XCTAssertEqual(item.canonicalName.value, "引体向上")
            XCTAssertEqual(item.metadataVersion, "m1a.wger.2026-08-30")
            try await controller.shutdownForTesting()
        }

        private func makeV5Fixture(at storeURL: URL) throws {
            let v5Model = try PersistenceController.loadModelVersionForMigrationTesting(named: "FineCoachV5")
            XCTAssertNil(
                v5Model.entitiesByName["ExerciseCatalogMO"]?.attributesByName["isRetired"],
                "the fixture must really be the pre-retired schema"
            )
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v5Model)
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
                let object = NSEntityDescription.insertNewObject(forEntityName: "ExerciseCatalogMO", into: context)
                object.setValue(exerciseID, forKey: "id")
                object.setValue("builtIn", forKey: "kind")
                object.setValue("引体向上", forKey: "canonicalName")
                object.setValue("引体向上", forKey: "normalizedName")
                object.setValue("reps", forKey: "recordMode")
                object.setValue("m1a.wger.2026-08-30", forKey: "metadataVersion")
                object.setValue("active", forKey: "lifecycle")
                object.setValue(exerciseID, forKey: "provenanceRef")
                object.setValue(now, forKey: "createdAtUTC")
                object.setValue(now, forKey: "updatedAtUTC")
                try context.save()
            }
            for store in coordinator.persistentStores {
                try coordinator.remove(store)
            }
        }
    }
#endif
