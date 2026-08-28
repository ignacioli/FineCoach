#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    final class ExercisePersistenceTests: XCTestCase {
        private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        private let sessionID = StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        private let sessionExerciseID = StableUUID(UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
        private let now = Date(timeIntervalSince1970: 1_700_000_000)
        private let squatID = StableExerciseID(rawValue: "fc.placeholder.squat")!
        private let pullupID = StableExerciseID(rawValue: "fc.placeholder.pullup")!
        private let customID = StableExerciseID(rawValue: "fc.custom.my-press")!
        private let archivedCustomID = StableExerciseID(rawValue: "fc.custom.ning-press")!
        private let reusedCustomID = StableExerciseID(rawValue: "fc.custom.ning-press-2")!

        func testBuiltInAndCustomSurviveReopenAndPreferencesDoNotChangeIdentity() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let clock = TestClock(utcDate: now)
            let squatCanonical: String
            let customCanonical: String

            do {
                let controller = try PersistenceController(storeURL: storeURL)
                let repository = CoreDataExerciseRepository(writer: controller.writer)
                try await repository.seedPlaceholderCatalogIfNeeded(now: clock.nowUTC())
                try await repository.seedPlaceholderCatalogIfNeeded(now: clock.nowUTC())

                let squat = try await repository.catalogItem(id: squatID)
                XCTAssertEqual(squat.kind, .builtIn)
                XCTAssertEqual(squat.canonicalName.value, "占位深蹲")
                squatCanonical = squat.canonicalName.value

                let custom = try await repository.createCustom(
                    name: " 我的推举 ",
                    recordMode: .weightReps,
                    id: customID,
                    now: clock.nowUTC()
                )
                XCTAssertEqual(custom.id, customID)
                XCTAssertEqual(custom.canonicalName.value, "我的推举")
                customCanonical = custom.canonicalName.value

                let preference = try await repository.setPreference(
                    exerciseID: squatID,
                    alias: "深蹲别名",
                    isFavorite: true,
                    isHidden: false
                )
                XCTAssertEqual(preference.exerciseID, squatID)
                XCTAssertEqual(preference.alias?.value, "深蹲别名")
                XCTAssertTrue(preference.isFavorite)
                XCTAssertFalse(preference.isHidden)

                try await controller.shutdownForTesting()
            }

            let reopened = try PersistenceController(storeURL: storeURL)
            let repository = CoreDataExerciseRepository(writer: reopened.writer)
            let squat = try await repository.catalogItem(id: squatID)
            XCTAssertEqual(squat.id, squatID)
            XCTAssertEqual(squat.canonicalName.value, squatCanonical)
            XCTAssertEqual(squat.canonicalName.value, "占位深蹲")

            let custom = try await repository.catalogItem(id: customID)
            XCTAssertEqual(custom.id, customID)
            XCTAssertEqual(custom.canonicalName.value, customCanonical)

            let byAlias = try await repository.searchActive(query: "深蹲别名")
            XCTAssertEqual(byAlias.map(\.id), [squatID])
            let entry = try XCTUnwrap(byAlias.first)
            XCTAssertEqual(entry.item.id, squatID)
            XCTAssertEqual(entry.item.canonicalName.value, "占位深蹲")
            XCTAssertEqual(entry.preference?.alias?.value, "深蹲别名")
            XCTAssertEqual(entry.preference?.isFavorite, true)
            XCTAssertEqual(entry.displayedName, "深蹲别名")

            let forbidden = try await repository.searchActive(query: "杠铃深蹲")
            XCTAssertTrue(forbidden.isEmpty)
            try await reopened.shutdownForTesting()
        }

        func testSessionOnlyDoesNotInsertCatalogAndSnapshotSurvivesRelease() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let clock = TestClock(utcDate: now)
            let ids = TestIDGenerator(ids: [
                studentID.rawValue, sessionID.rawValue, sessionExerciseID.rawValue,
            ])
            let controller = try PersistenceController(storeURL: storeURL)
            let exerciseRepository = CoreDataExerciseRepository(writer: controller.writer)
            let studentRepository = CoreDataStudentRepository(writer: controller.writer)
            let sessionRepository = CoreDataSessionRepository(writer: controller.writer)
            try await exerciseRepository.seedPlaceholderCatalogIfNeeded(now: clock.nowUTC())
            let catalogCountAfterSeed = try await catalogCount(writer: controller.writer)
            XCTAssertEqual(catalogCountAfterSeed, 3)

            let student = try StudentDraft(displayName: "林青", sex: .female).makeStudent(
                id: StableUUID(ids.makeID()),
                now: clock.nowUTC()
            )
            _ = try await studentRepository.create(student)
            var session = Session.start(
                id: StableUUID(ids.makeID()),
                studentID: student.id,
                now: clock.nowUTC()
            )
            session = try session.addingSessionOnlyExercise(
                id: StableUUID(ids.makeID()),
                displayName: "仅本次侧平举",
                recordMode: .reps,
                now: clock.nowUTC()
            )
            session = try await sessionRepository.save(session)
            let sessionOnly = try XCTUnwrap(session.exercises.first)
            XCTAssertEqual(sessionOnly.sourceKind, .sessionOnly)
            XCTAssertNil(sessionOnly.sourceID)
            XCTAssertEqual(sessionOnly.displayNameSnapshot.value, "仅本次侧平举")

            let sessionOnlyOwnerID = try StableExerciseID(sessionOnly.id.rawValue.uuidString)
            try await exerciseRepository.acquireUnifiedClaim(
                try ExerciseNameClaim(
                    normalizedName: "仅本次侧平举",
                    ownerKind: .sessionOnly,
                    ownerID: sessionOnlyOwnerID,
                    scope: .currentSession
                )
            )
            let catalogCountAfterClaim = try await catalogCount(writer: controller.writer)
            XCTAssertEqual(catalogCountAfterClaim, catalogCountAfterSeed)
            let hasRowAfterClaim = try await exerciseRepository.hasCatalogRow(id: sessionOnlyOwnerID)
            XCTAssertFalse(hasRowAfterClaim)

            let abandoned = try session.abandoned(now: clock.nowUTC())
            _ = try await sessionRepository.save(abandoned)
            try await exerciseRepository.releaseSessionScopeClaims()

            let search = try await exerciseRepository.searchActive(query: "仅本次侧平举")
            XCTAssertTrue(search.isEmpty)
            let hasRowAfterRelease = try await exerciseRepository.hasCatalogRow(id: sessionOnlyOwnerID)
            XCTAssertFalse(hasRowAfterRelease)
            let catalogCountAfterRelease = try await catalogCount(writer: controller.writer)
            XCTAssertEqual(catalogCountAfterRelease, catalogCountAfterSeed)

            let persisted = try await sessionRepository.session(id: session.id)
            XCTAssertEqual(persisted.state, .abandonedEmpty)
            XCTAssertEqual(persisted.exercises.count, 1)
            XCTAssertEqual(persisted.exercises[0].displayNameSnapshot.value, "仅本次侧平举")
            XCTAssertEqual(persisted.exercises[0].sourceKind, .sessionOnly)
            try await controller.shutdownForTesting()
        }

        func testActiveNameConflictAndArchivedNameCanBeReused() async throws {
            let environment = try makeRepository()
            try await environment.repository.seedPlaceholderCatalogIfNeeded(now: environment.clock.nowUTC())

            do {
                _ = try await environment.repository.createCustom(
                    name: "  占位深蹲  ",
                    recordMode: .weightReps,
                    id: customID,
                    now: environment.clock.nowUTC()
                )
                XCTFail("Expected built-in name conflict")
            } catch DomainError.conflict {
                // expected
            }

            do {
                _ = try await environment.repository.updateCustom(
                    id: squatID,
                    name: "课中改名",
                    recordMode: .weightReps,
                    now: environment.clock.nowUTC()
                )
                XCTFail("Expected built-in core fields to stay read-only")
            } catch DomainError.invalidState {
                // expected
            }

            let created = try await environment.repository.createCustom(
                name: "周宁推举",
                recordMode: .reps,
                id: archivedCustomID,
                now: environment.clock.nowUTC()
            )
            XCTAssertEqual(created.canonicalName.value, "周宁推举")
            _ = try await environment.repository.archiveCustom(
                id: archivedCustomID,
                now: environment.clock.nowUTC()
            )
            let reused = try await environment.repository.createCustom(
                name: "周宁推举",
                recordMode: .reps,
                id: reusedCustomID,
                now: environment.clock.nowUTC()
            )
            XCTAssertEqual(reused.id, reusedCustomID)
            XCTAssertEqual(reused.canonicalName.value, "周宁推举")
            XCTAssertNotEqual(reused.id, archivedCustomID)
            try await environment.controller.shutdownForTesting()
        }

        func testHiddenPreferenceOmittedUnlessIncludeHidden() async throws {
            let environment = try makeRepository()
            try await environment.repository.seedPlaceholderCatalogIfNeeded(now: environment.clock.nowUTC())
            _ = try await environment.repository.setPreference(
                exerciseID: pullupID,
                alias: nil,
                isFavorite: nil,
                isHidden: true
            )

            let visible = try await environment.repository.searchActive(query: "", includeHidden: false)
            XCTAssertEqual(visible.map(\.item.canonicalName.value), ["占位支撑", "占位深蹲"])
            XCTAssertFalse(visible.contains { $0.id == pullupID })

            let includingHidden = try await environment.repository.searchActive(query: "", includeHidden: true)
            XCTAssertEqual(includingHidden.map(\.item.canonicalName.value), ["占位引体", "占位支撑", "占位深蹲"])
            let hiddenEntry = try XCTUnwrap(includingHidden.first { $0.id == pullupID })
            XCTAssertEqual(hiddenEntry.preference?.isHidden, true)
            XCTAssertEqual(hiddenEntry.item.canonicalName.value, "占位引体")
            try await environment.controller.shutdownForTesting()
        }

        private struct Environment {
            let directory: TemporaryProtectedDirectory
            let controller: PersistenceController
            let repository: CoreDataExerciseRepository
            let clock: TestClock
        }

        private func makeRepository() throws -> Environment {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let controller = try PersistenceController(storeURL: storeURL)
            let clock = TestClock(utcDate: now)
            return Environment(
                directory: directory,
                controller: controller,
                repository: CoreDataExerciseRepository(writer: controller.writer),
                clock: clock
            )
        }

        private func catalogCount(writer: PersistenceWriter) async throws -> Int {
            try await writer.read { context in
                let request = NSFetchRequest<NSManagedObject>(entityName: "ExerciseCatalogMO")
                return try context.count(for: request)
            }
        }
    }
#else
    import XCTest
    import FineCoach

    final class ExercisePersistenceTests: XCTestCase {
        func testReleaseKeepsExerciseDomainSurfaceWithoutFaultInjection() {
            XCTAssertEqual(ExerciseKind.builtIn.rawValue, "builtIn")
            XCTAssertEqual(ExerciseClaimScope.activeCatalog.rawValue, "activeCatalog")
        }
    }
#endif
