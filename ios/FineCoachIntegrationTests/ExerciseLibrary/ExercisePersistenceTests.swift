#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    private final class FailOnNthWriterSaveInjector: FaultInjector, @unchecked Sendable {
        private let lock = NSLock()
        private var saveChecks = 0
        private var failOnSave: Int?
        private var thrownFailures = 0

        var failureCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return thrownFailures
        }

        func arm(failOnSave: Int) {
            lock.lock()
            saveChecks = 0
            self.failOnSave = failOnSave
            thrownFailures = 0
            lock.unlock()
        }

        func check(_ point: FaultInjectionPoint) throws {
            guard point == .persistenceWriterSave else {
                return
            }
            lock.lock()
            saveChecks += 1
            let shouldFail = saveChecks == failOnSave
            if shouldFail {
                thrownFailures += 1
            }
            lock.unlock()
            if shouldFail {
                throw FaultInjectionError.injected(point)
            }
        }
    }

    final class ExercisePersistenceTests: XCTestCase {
        private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        private let sessionID = StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        private let sessionExerciseID = StableUUID(UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
        private let now = Date(timeIntervalSince1970: 1_700_000_000)
        private let squatID = StableExerciseID(rawValue: "a2f5b6ef-b780-49c0-8d96-fdaff23e27ce")!
        private let pullupID = StableExerciseID(rawValue: "8e420408-0682-4ab6-89f5-2681e54c7ce0")!
        private let customID = StableExerciseID(rawValue: "fc.custom.my-press")!
        private let archivedCustomID = StableExerciseID(rawValue: "fc.custom.ning-press")!
        private let reusedCustomID = StableExerciseID(rawValue: "fc.custom.ning-press-2")!

        func testSearchSupportsPinyinForBuiltInAliasAndCustomExercise() async throws {
            let environment = try makeRepository()
            try await environment.repository.seedPlaceholderCatalogIfNeeded(now: environment.clock.nowUTC())

            let chineseMatches = try await environment.repository.searchActive(query: "卧推")
            XCTAssertFalse(chineseMatches.isEmpty)
            let fullPinyinMatches = try await environment.repository.searchActive(query: "wo tui")
            // Pinyin also matches homophones: 卧腿 and 卧推 both become wotui.
            // Preserve every Chinese match and its order without excluding valid phonetic matches.
            let chineseIDs = Set(chineseMatches.map(\.id))
            XCTAssertEqual(fullPinyinMatches.filter { chineseIDs.contains($0.id) }.map(\.id), chineseMatches.map(\.id))
            XCTAssertTrue(fullPinyinMatches.contains { $0.item.canonicalName.value == "弹力带仰卧腿外展" })
            let initialMatches = try await environment.repository.searchActive(query: "wt")
            XCTAssertEqual(initialMatches.filter { chineseIDs.contains($0.id) }.map(\.id), chineseMatches.map(\.id))
            XCTAssertTrue(initialMatches.contains { $0.item.canonicalName.value == "仰卧抬腿" })

            let equipmentMatches = try await environment.repository.searchActive(query: "固定器械")
            XCTAssertFalse(equipmentMatches.isEmpty)
            XCTAssertTrue(equipmentMatches.allSatisfy { $0.equipmentClass == "固定器械" })
            let muscleMatches = try await environment.repository.searchActive(query: "胸")
            XCTAssertTrue(muscleMatches.contains { $0.item.canonicalName.value == "杠铃平板卧推" })

            _ = try await environment.repository.setPreference(
                exerciseID: squatID,
                alias: "卧推别名",
                isFavorite: nil,
                isHidden: nil
            )
            let aliasMatches = try await environment.repository.searchActive(query: "bie ming")
            XCTAssertTrue(aliasMatches.contains { $0.id == squatID })

            let custom = try await environment.repository.createCustom(
                name: "自定义动作",
                recordMode: .reps,
                id: customID,
                now: environment.clock.nowUTC()
            )
            let customMatches = try await environment.repository.searchActive(query: "ziding")
            XCTAssertTrue(customMatches.contains { $0.id == custom.id })

            _ = try await environment.repository.setPreference(
                exerciseID: customID,
                alias: "旧别名",
                isFavorite: nil,
                isHidden: nil
            )
            let oldAliasMatches = try await environment.repository.searchActive(query: "jiu")
            XCTAssertTrue(oldAliasMatches.contains { $0.id == customID })
            _ = try await environment.repository.setPreference(
                exerciseID: customID,
                alias: "新别名",
                isFavorite: nil,
                isHidden: nil
            )
            let oldAliasAfterUpdate = try await environment.repository.searchActive(query: "jiu")
            XCTAssertFalse(oldAliasAfterUpdate.contains { $0.id == customID })
            let newAliasMatches = try await environment.repository.searchActive(query: "xin")
            XCTAssertTrue(newAliasMatches.contains { $0.id == customID })
            try await environment.controller.shutdownForTesting()
        }

        func testSearchAppliesPolyphoneFixesToBuiltInCustomAndAliasNames() async throws {
            let environment = try makeRepository()
            try await environment.repository.seedPlaceholderCatalogIfNeeded(now: environment.clock.nowUTC())

            for query in ["tanlidai", "tan li dai", "tld"] {
                let results = try await environment.repository.searchActive(query: query)
                XCTAssertTrue(results.contains { $0.item.canonicalName.value == "弹力带站姿弯举" }, query)
            }
            let oldBuiltInPinyin = try await environment.repository.searchActive(query: "danlidai")
            XCTAssertFalse(oldBuiltInPinyin.contains { $0.item.canonicalName.value.contains("弹力带") })
            let builtInFullPinyin = try await environment.repository.searchActive(query: "dilei")
            XCTAssertTrue(builtInFullPinyin.contains { $0.item.canonicalName.value == "地雷管推举" })
            let builtInInitials = try await environment.repository.searchActive(query: "dl")
            XCTAssertTrue(builtInInitials.contains { $0.item.canonicalName.value == "地雷管推举" })

            let custom = try await environment.repository.createCustom(
                name: "自定义弹力带",
                recordMode: .reps,
                id: StableExerciseID(rawValue: "fc.custom.polyphone")!,
                now: environment.clock.nowUTC()
            )
            let customFullPinyin = try await environment.repository.searchActive(query: "tanlidai")
            XCTAssertTrue(customFullPinyin.contains { $0.id == custom.id })
            let customInitials = try await environment.repository.searchActive(query: "tld")
            XCTAssertTrue(customInitials.contains { $0.id == custom.id })
            let oldCustomPinyin = try await environment.repository.searchActive(query: "danlidai")
            XCTAssertFalse(oldCustomPinyin.contains { $0.id == custom.id })

            _ = try await environment.repository.setPreference(
                exerciseID: custom.id,
                alias: "地板动作",
                isFavorite: nil,
                isHidden: nil
            )
            let aliasFullPinyin = try await environment.repository.searchActive(query: "diban")
            XCTAssertTrue(aliasFullPinyin.contains { $0.id == custom.id })
            let aliasInitials = try await environment.repository.searchActive(query: "db")
            XCTAssertTrue(aliasInitials.contains { $0.id == custom.id })
            let oldAliasPinyin = try await environment.repository.searchActive(query: "deban")
            XCTAssertFalse(oldAliasPinyin.contains { $0.id == custom.id })
            try await environment.controller.shutdownForTesting()
        }

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
                XCTAssertEqual(squat.canonicalName.value, "杠铃深蹲")
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
            XCTAssertEqual(squat.canonicalName.value, "杠铃深蹲")

            let custom = try await repository.catalogItem(id: customID)
            XCTAssertEqual(custom.id, customID)
            XCTAssertEqual(custom.canonicalName.value, customCanonical)

            let byAlias = try await repository.searchActive(query: "深蹲别名")
            XCTAssertEqual(byAlias.map(\.id), [squatID])
            let entry = try XCTUnwrap(byAlias.first)
            XCTAssertEqual(entry.item.id, squatID)
            XCTAssertEqual(entry.item.canonicalName.value, "杠铃深蹲")
            XCTAssertEqual(entry.preference?.alias?.value, "深蹲别名")
            XCTAssertEqual(entry.preference?.isFavorite, true)
            XCTAssertEqual(entry.displayedName, "深蹲别名")

            let foundSquat = try await repository.searchActive(query: "杠铃深蹲")
            XCTAssertEqual(foundSquat.map(\.id), [squatID])
            XCTAssertEqual(foundSquat.first?.primaryMuscleGroup, "大腿")
            XCTAssertEqual(foundSquat.first?.equipmentClass, "杠铃")
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
            XCTAssertEqual(catalogCountAfterSeed, 542)

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

        func testSessionOnlyNameAlreadyClaimedByBuiltInStillConflicts() async throws {
            let environment = try makeRepository()
            try await environment.repository.seedPlaceholderCatalogIfNeeded(now: environment.clock.nowUTC())
            let ownerID = try StableExerciseID("33333333-3333-4333-8333-333333333333")
            let claim = try ExerciseNameClaim(
                normalizedName: "杠铃深蹲",
                ownerKind: .sessionOnly,
                ownerID: ownerID,
                scope: .currentSession
            )
            do {
                try await environment.repository.acquireUnifiedClaim(claim)
                XCTFail("an existing built-in claim must reject an ordinary session-only duplicate")
            } catch {
                XCTAssertEqual(error as? DomainError, .conflict)
            }
            try await environment.controller.shutdownForTesting()
        }

        func testOrdinarySessionOnlyCreationWithExistingBuiltInStillConflicts() async throws {
            let environment = try makeRepository()
            try await environment.repository.seedPlaceholderCatalogIfNeeded(now: environment.clock.nowUTC())
            let studentRepository = CoreDataStudentRepository(writer: environment.controller.writer)
            let student = try StudentDraft(displayName: "临时动作重名学员", sex: .male).makeStudent(
                id: StableUUID(UUID(uuidString: "34343434-3434-4434-8434-343434343434")!),
                now: environment.clock.nowUTC()
            )
            _ = try await studentRepository.create(student)
            let sessions = ActiveSessionUseCases(
                sessionRepository: CoreDataSessionRepository(writer: environment.controller.writer),
                studentRepository: studentRepository,
                exerciseRepository: environment.repository,
                sectionRepository: CoreDataSessionSectionRepository(writer: environment.controller.writer),
                recoveryStore: ActiveSessionRecoveryStore(
                    url: environment.directory.url.appendingPathComponent("active-session-recovery-v1.json"),
                    protectedFileStore: ProtectedFileStore()
                ),
                storeGenerationUUID: UUID(uuidString: "45454545-4545-4454-8454-454545454545")!,
                clock: environment.clock,
                ids: TestIDGenerator(ids: [
                    UUID(uuidString: "56565656-5656-4656-8656-565656565656")!,
                    UUID(uuidString: "67676767-6767-4767-8767-676767676767")!,
                ])
            )
            _ = try await sessions.startOrOpen(studentID: student.id)
            do {
                _ = try await sessions.addSessionOnlyExercise(
                    displayName: "杠铃深蹲",
                    recordMode: .weightReps
                )
                XCTFail("an ordinary session-only duplicate must remain a conflict")
            } catch {
                XCTAssertEqual(error as? DomainError, .conflict)
            }
            try await environment.controller.shutdownForTesting()
        }

        func testActiveNameConflictAndArchivedNameCanBeReused() async throws {
            let environment = try makeRepository()
            try await environment.repository.seedPlaceholderCatalogIfNeeded(now: environment.clock.nowUTC())

            do {
                _ = try await environment.repository.createCustom(
                    name: "  杠铃深蹲  ",
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
            XCTAssertEqual(visible.count, 540)
            XCTAssertFalse(visible.contains { $0.id == pullupID })

            let includingHidden = try await environment.repository.searchActive(query: "", includeHidden: true)
            XCTAssertEqual(includingHidden.count, 541)
            let hiddenEntry = try XCTUnwrap(includingHidden.first { $0.id == pullupID })
            XCTAssertEqual(hiddenEntry.preference?.isHidden, true)
            XCTAssertEqual(hiddenEntry.item.canonicalName.value, "引体向上")
            try await environment.controller.shutdownForTesting()
        }

        func testCatalogUpgradePreservesPreferencesCustomSnapshotAndTemplate() async throws {
            let environment = try makeRepository()
            let current = try currentCatalog()
            let legacy = try legacyCatalog(from: current)
            XCTAssertEqual(legacy.exercises.count, 146)
            try await seedLegacyCatalog(legacy, writer: environment.controller.writer, now: environment.clock.nowUTC())

            let pullUpBefore = try await environment.repository.catalogItem(id: pullupID)
            let renamedLegacyExercise = try XCTUnwrap(
                legacy.exercises.first { $0.canonicalName == "单臂哑铃划船" }
            )
            let renamedID = try StableExerciseID(renamedLegacyExercise.id)
            let renamedBefore = try await environment.repository.catalogItem(id: renamedID)
            let renamedCreatedAt = renamedBefore.createdAtUTC
            _ = try await environment.repository.setPreference(
                exerciseID: pullupID,
                alias: "升级别名",
                isFavorite: true,
                isHidden: false,
                isAssisted: true,
                isUnilateral: true
            )
            let custom = try await environment.repository.createCustom(
                name: "升级保留自定义",
                recordMode: .reps,
                id: customID,
                now: environment.clock.nowUTC()
            )

            let sessionID = StableUUID(UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!)
            let studentRepository = CoreDataStudentRepository(writer: environment.controller.writer)
            let sessionRepository = CoreDataSessionRepository(writer: environment.controller.writer)
            let student = try StudentDraft(displayName: "升级测试学员", sex: .female).makeStudent(
                id: studentID,
                now: environment.clock.nowUTC()
            )
            _ = try await studentRepository.create(student)
            var session = Session.start(id: sessionID, studentID: studentID, now: environment.clock.nowUTC())
            session = try session.addingCatalogExercise(
                id: sessionExerciseID,
                item: renamedBefore,
                now: environment.clock.nowUTC()
            )
            session = try session.addingSet(
                exerciseID: sessionExerciseID,
                setID: StableUUID(UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!),
                input: TrainingSetInput(
                    recordMode: renamedBefore.recordMode,
                    weightValue: "40",
                    repetitionCount: "8",
                    unit: .kilograms
                ),
                now: environment.clock.nowUTC()
            )
            session = try session.confirmingSet(
                setID: StableUUID(UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!),
                now: environment.clock.nowUTC()
            )
            session = try session.finished(now: environment.clock.nowUTC())
            _ = try await sessionRepository.save(session)

            let templateRepository = CoreDataTemplateRepository(writer: environment.controller.writer)
            let templateID = StableUUID(UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!)
            let templateExerciseID = StableUUID(UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!)
            let template = try TrainingTemplate(
                id: templateID,
                name: "升级模板",
                createdAtUTC: environment.clock.nowUTC(),
                updatedAtUTC: environment.clock.nowUTC()
            )
            _ = try await templateRepository.createTemplate(template)
            let templateExercise = TemplateExercise(
                id: templateExerciseID,
                templateID: templateID,
                sectionID: nil,
                orderIndex: 0,
                sourceKind: .builtIn,
                sourceID: renamedBefore.id,
                displayNameSnapshot: renamedBefore.canonicalName,
                recordModeSnapshot: renamedBefore.recordMode,
                plannedSets: []
            )
            try await templateRepository.replaceExercises(templateID: templateID, with: [templateExercise])

            let result = try await environment.repository.syncBuiltInCatalog(current, now: environment.clock.nowUTC())
            XCTAssertEqual(result.insertedCount, 396)
            let storedIDs = try await catalogIDs(writer: environment.controller.writer)
            XCTAssertEqual(storedIDs.count, 543)
            XCTAssertEqual(storedIDs, Set(current.exercises.map(\.id)).union([customID.rawValue]))

            let upgradedPullUp = try await environment.repository.catalogItem(id: pullupID)
            XCTAssertEqual(upgradedPullUp.canonicalName.value, pullUpBefore.canonicalName.value)
            let preference = try await preference(for: pullupID, writer: environment.controller.writer)
            XCTAssertEqual(preference?.alias?.value, "升级别名")
            XCTAssertTrue(preference?.isFavorite == true)
            XCTAssertTrue(preference?.isAssisted == true)
            XCTAssertTrue(preference?.isUnilateral == true)
            let upgradedCustom = try await environment.repository.catalogItem(id: customID)
            XCTAssertEqual(upgradedCustom, custom)
            let renamedAfter = try await environment.repository.catalogItem(id: renamedID)
            XCTAssertEqual(renamedAfter.canonicalName.value, "哑铃支撑划船")
            XCTAssertEqual(renamedAfter.createdAtUTC, renamedCreatedAt)

            let persistedSession = try await sessionRepository.session(id: sessionID)
            XCTAssertEqual(
                persistedSession.exercises.first?.displayNameSnapshot.value,
                renamedBefore.canonicalName.value
            )
            XCTAssertEqual(persistedSession.exercises.first?.sourceID, renamedID)
            XCTAssertEqual(persistedSession.state, .completed)
            let history = try await sessionRepository.listCompleted(studentID: studentID)
            XCTAssertEqual(history.first?.exercises.first?.sourceID, renamedID)
            XCTAssertEqual(
                history.first?.exercises.first?.displayNameSnapshot.value,
                renamedBefore.canonicalName.value
            )
            let persistedTemplateExercises = try await templateRepository.exercises(templateID: templateID)
            let persistedTemplateExercise = try XCTUnwrap(persistedTemplateExercises.first)
            XCTAssertEqual(persistedTemplateExercise.displayNameSnapshot.value, renamedBefore.canonicalName.value)
            XCTAssertEqual(persistedTemplateExercise.sourceID, renamedID)
            try await environment.controller.shutdownForTesting()
        }

        func testCatalogSyncIsIdempotentAndRollbackKeepsPreviousCatalog() async throws {
            let environment = try makeRepository()
            let current = try currentCatalog()
            let legacy = try legacyCatalog(from: current)
            try await seedLegacyCatalog(legacy, writer: environment.controller.writer, now: environment.clock.nowUTC())
            let first = try await environment.repository.syncBuiltInCatalog(current, now: environment.clock.nowUTC())
            let second = try await environment.repository.syncBuiltInCatalog(current, now: environment.clock.nowUTC())
            XCTAssertEqual(second.insertedCount, 0)
            XCTAssertEqual(second.updatedCount, 0)
            XCTAssertEqual(second.retiredCount, 0)
            XCTAssertEqual(second.hiddenByCustomClaimCount, 0)
            XCTAssertEqual(first.insertedCount, 396)

            let injector = TestFaultInjector()
            let failingDirectory = try TemporaryProtectedDirectory()
            let failingURL = failingDirectory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let failingController = try PersistenceController(
                storeURL: failingURL,
                faultInjectionBoundary: FaultInjectionBoundary(injector: injector)
            )
            let failingRepository = CoreDataExerciseRepository(writer: failingController.writer)
            try await seedLegacyCatalog(legacy, writer: failingController.writer, now: environment.clock.nowUTC())
            _ = try await failingRepository.setPreference(
                exerciseID: pullupID,
                alias: "回滚偏好",
                isFavorite: true,
                isHidden: false,
                isAssisted: true,
                isUnilateral: true
            )
            let legacyIDs = Set(legacy.exercises.map(\.id))
            let newID = try StableExerciseID(
                XCTUnwrap(current.exercises.first { !legacyIDs.contains($0.id) }).id
            )
            injector.setFailure(at: .persistenceWriterSave, enabled: true)
            do {
                _ = try await failingRepository.syncBuiltInCatalog(current, now: environment.clock.nowUTC())
                XCTFail("catalog sync should fail at the writer save boundary")
            } catch {
                XCTAssertTrue(error is FaultInjectionError)
            }
            let retained = try await failingRepository.searchActive(query: "")
            XCTAssertEqual(retained.count, 146)
            let hasNewRow = try await failingRepository.hasCatalogRow(id: newID)
            XCTAssertFalse(hasNewRow)
            let retainedPullUp = try await failingRepository.catalogItem(id: pullupID)
            XCTAssertEqual(retainedPullUp.canonicalName.value, "引体向上")
            let retainedPreference = try await preference(for: pullupID, writer: failingController.writer)
            XCTAssertEqual(retainedPreference?.alias?.value, "回滚偏好")
            XCTAssertTrue(retainedPreference?.isFavorite == true)
            XCTAssertTrue(retainedPreference?.isAssisted == true)
            XCTAssertTrue(retainedPreference?.isUnilateral == true)
            try await failingController.shutdownForTesting()
            let reopenedController = try PersistenceController(storeURL: failingURL)
            let reopenedRepository = CoreDataExerciseRepository(writer: reopenedController.writer)
            let reopenedPullUp = try await reopenedRepository.catalogItem(id: pullupID)
            XCTAssertEqual(reopenedPullUp.canonicalName.value, "引体向上")
            let reopenedPreference = try await preference(for: pullupID, writer: reopenedController.writer)
            XCTAssertEqual(reopenedPreference?.alias?.value, "回滚偏好")
            let reopenedHasNewRow = try await reopenedRepository.hasCatalogRow(id: newID)
            XCTAssertFalse(reopenedHasNewRow)
            try await reopenedController.shutdownForTesting()
            try await environment.controller.shutdownForTesting()
        }

        func testRetiredCatalogItemIsHiddenButAddressableByID() async throws {
            let environment = try makeRepository()
            let current = try currentCatalog()
            try await environment.repository.syncBuiltInCatalog(current, now: environment.clock.nowUTC())
            let retired = try XCTUnwrap(current.exercises.first(where: { $0.retired == true }))
            let retiredID = try StableExerciseID(retired.id)
            let retiredSearch = try await environment.repository.searchActive(query: retired.canonicalName)
            XCTAssertTrue(retiredSearch.isEmpty)
            let item = try await environment.repository.catalogItem(id: retiredID)
            XCTAssertTrue(item.isRetired)
            XCTAssertEqual(item.canonicalName.value, retired.canonicalName)
            try await environment.controller.shutdownForTesting()
        }

        func testCustomClaimWinsAndRenameOrArchiveImmediatelyRevealsBuiltIn() async throws {
            let environment = try makeRepository()
            let current = try currentCatalog()
            let legacy = try legacyCatalog(from: current)
            let legacyIDs = Set(legacy.exercises.map(\.id))
            let newExercises = current.exercises.filter { !legacyIDs.contains($0.id) }
            let renameTarget = try XCTUnwrap(newExercises.first)
            let archiveTarget = try XCTUnwrap(newExercises.dropFirst().first)
            let renameID = try StableExerciseID(renameTarget.id)
            let archiveID = try StableExerciseID(archiveTarget.id)
            let renameCustomID = try StableExerciseID("fc.custom.catalog-rename")
            let archiveCustomID = try StableExerciseID("fc.custom.catalog-archive")
            try await seedLegacyCatalog(legacy, writer: environment.controller.writer, now: environment.clock.nowUTC())
            _ = try await environment.repository.createCustom(
                name: renameTarget.canonicalName,
                recordMode: .reps,
                id: renameCustomID,
                now: environment.clock.nowUTC()
            )
            _ = try await environment.repository.createCustom(
                name: archiveTarget.canonicalName,
                recordMode: .reps,
                id: archiveCustomID,
                now: environment.clock.nowUTC()
            )
            try await environment.repository.syncBuiltInCatalog(current, now: environment.clock.nowUTC())
            let renameHidden = try await environment.repository.searchActive(query: renameTarget.canonicalName)
            let archiveHidden = try await environment.repository.searchActive(query: archiveTarget.canonicalName)
            XCTAssertTrue(renameHidden.contains { $0.id == renameCustomID })
            XCTAssertFalse(renameHidden.contains { $0.id == renameID })
            XCTAssertTrue(archiveHidden.contains { $0.id == archiveCustomID })
            XCTAssertFalse(archiveHidden.contains { $0.id == archiveID })

            _ = try await environment.repository.updateCustom(
                id: renameCustomID,
                name: "改名释放目录项",
                recordMode: .reps,
                now: environment.clock.nowUTC()
            )
            let renameVisible = try await environment.repository.searchActive(query: renameTarget.canonicalName)
            XCTAssertEqual(renameVisible.map(\.id), [renameID])
            _ = try await environment.repository.archiveCustom(id: archiveCustomID, now: environment.clock.nowUTC())
            let archiveVisible = try await environment.repository.searchActive(query: archiveTarget.canonicalName)
            XCTAssertEqual(archiveVisible.map(\.id), [archiveID])
            try await environment.controller.shutdownForTesting()
        }

        func testSessionOnlyClaimHidesBuiltInUntilFinishAbandonOrDelete() async throws {
            let current = try currentCatalog()
            let legacy = try legacyCatalog(from: current)
            let legacyIDs = Set(legacy.exercises.map(\.id))
            let target = try XCTUnwrap(current.exercises.first { !legacyIDs.contains($0.id) })
            let targetID = try StableExerciseID(target.id)
            let releasePaths = ["finish", "abandon", "delete", "deleteSection"]

            for releasePath in releasePaths {
                let environment = try makeRepository()
                try await seedLegacyCatalog(
                    legacy, writer: environment.controller.writer, now: environment.clock.nowUTC())
                let studentRepository = CoreDataStudentRepository(writer: environment.controller.writer)
                let studentID = StableUUID(UUID(uuidString: "12121212-1212-4212-8212-121212121212")!)
                _ = try await studentRepository.create(
                    try StudentDraft(displayName: "临时动作冲突测试", sex: .female).makeStudent(
                        id: studentID,
                        now: environment.clock.nowUTC()
                    )
                )
                let sessionID = UUID(uuidString: "13131313-1313-4313-8313-131313131313")!
                let sessionExerciseID = UUID(uuidString: "14141414-1414-4414-8414-141414141414")!
                let setID = UUID(uuidString: "15151515-1515-4515-8515-151515151515")!
                let sessions = ActiveSessionUseCases(
                    sessionRepository: CoreDataSessionRepository(writer: environment.controller.writer),
                    studentRepository: studentRepository,
                    exerciseRepository: environment.repository,
                    sectionRepository: CoreDataSessionSectionRepository(writer: environment.controller.writer),
                    recoveryStore: ActiveSessionRecoveryStore(
                        url: environment.directory.url.appendingPathComponent("active-session-recovery-v1.json"),
                        protectedFileStore: ProtectedFileStore()
                    ),
                    storeGenerationUUID: UUID(uuidString: "16161616-1616-4616-8616-161616161616")!,
                    clock: environment.clock,
                    ids: TestIDGenerator(ids: [sessionID, sessionExerciseID, setID])
                )
                _ = try await sessions.startOrOpen(studentID: studentID)
                let withSessionOnly = try await sessions.addSessionOnlyExercise(
                    displayName: target.canonicalName,
                    recordMode: target.recordMode
                )
                try await environment.repository.syncBuiltInCatalog(current, now: environment.clock.nowUTC())

                let hidden = try await environment.repository.searchActive(query: target.canonicalName)
                XCTAssertFalse(hidden.contains { $0.id == targetID }, releasePath)
                do {
                    _ = try await environment.repository.selectableCatalogItem(id: targetID)
                    XCTFail("session-only collision must make the built-in unavailable: \(releasePath)")
                } catch {
                    XCTAssertEqual(error as? DomainError, .invalidState, releasePath)
                }
                do {
                    _ = try await sessions.addCatalogExercise(itemID: targetID)
                    XCTFail("session-only collision must block the add path: \(releasePath)")
                } catch {
                    XCTAssertEqual(error as? DomainError, .invalidState, releasePath)
                }

                switch releasePath {
                case "finish":
                    _ = try await sessions.addSet(
                        exerciseID: withSessionOnly.exercises[0].id,
                        input: completedInput(for: target.recordMode)
                    )
                    _ = try await sessions.confirmSet(setID: StableUUID(setID))
                    _ = try await sessions.finish()
                case "abandon":
                    _ = try await sessions.abandonEmpty()
                case "delete":
                    _ = try await sessions.removeExercise(
                        exerciseID: withSessionOnly.exercises[0].id,
                        confirmedIfCompleted: true
                    )
                case "deleteSection":
                    let section = try await sessions.createSection(name: "临时分组")
                    _ = try await sessions.moveExerciseToSection(
                        exerciseID: withSessionOnly.exercises[0].id,
                        toSectionID: section.id
                    )
                    _ = try await sessions.deleteSection(
                        sectionID: section.id,
                        disposition: .deleteWithExercises
                    )
                default:
                    XCTFail("unexpected release path")
                }

                let visible = try await environment.repository.searchActive(query: target.canonicalName)
                XCTAssertEqual(visible.map(\.id), [targetID], releasePath)
                try await environment.controller.shutdownForTesting()
            }
        }

        func testTerminalSessionCommitsWhenPostFinishCatalogReconcileFails() async throws {
            let current = try currentCatalog()
            let legacy = try legacyCatalog(from: current)
            let legacyIDs = Set(legacy.exercises.map(\.id))
            let target = try XCTUnwrap(current.exercises.first { !legacyIDs.contains($0.id) })

            for terminal in ["finish", "abandon"] {
                let directory = try TemporaryProtectedDirectory()
                let injector = FailOnNthWriterSaveInjector()
                let controller = try PersistenceController(
                    storeURL: directory.url.appendingPathComponent("generation/FineCoach.sqlite"),
                    faultInjectionBoundary: FaultInjectionBoundary(injector: injector)
                )
                let repository = CoreDataExerciseRepository(writer: controller.writer)
                let clock = TestClock(utcDate: now)
                try await seedLegacyCatalog(legacy, writer: controller.writer, now: now)
                let studentRepository = CoreDataStudentRepository(writer: controller.writer)
                let student = try StudentDraft(displayName: "结束同步失败学员", sex: .female).makeStudent(
                    id: StableUUID(UUID(uuidString: "78787878-7878-4878-8878-787878787878")!),
                    now: now
                )
                _ = try await studentRepository.create(student)
                let sessionID = UUID(uuidString: "89898989-8989-4898-8898-898989898989")!
                let sessionExerciseID = UUID(uuidString: "90909090-9090-4090-8090-909090909090")!
                let setID = UUID(uuidString: "a0a0a0a0-a0a0-40a0-80a0-a0a0a0a0a0a0")!
                let sessions = ActiveSessionUseCases(
                    sessionRepository: CoreDataSessionRepository(writer: controller.writer),
                    studentRepository: studentRepository,
                    exerciseRepository: repository,
                    sectionRepository: CoreDataSessionSectionRepository(writer: controller.writer),
                    recoveryStore: ActiveSessionRecoveryStore(
                        url: directory.url.appendingPathComponent("active-session-recovery-v1.json"),
                        protectedFileStore: ProtectedFileStore()
                    ),
                    storeGenerationUUID: UUID(uuidString: "b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1")!,
                    clock: clock,
                    ids: TestIDGenerator(ids: [sessionID, sessionExerciseID, setID])
                )
                _ = try await sessions.startOrOpen(studentID: student.id)
                let withSessionOnly = try await sessions.addSessionOnlyExercise(
                    displayName: target.canonicalName,
                    recordMode: target.recordMode
                )
                try await repository.syncBuiltInCatalog(current, now: now)

                if terminal == "finish" {
                    _ = try await sessions.addSet(
                        exerciseID: withSessionOnly.exercises[0].id,
                        input: completedInput(for: target.recordMode)
                    )
                    _ = try await sessions.confirmSet(setID: StableUUID(setID))
                }
                injector.arm(failOnSave: 2)

                let ended: Session
                if terminal == "finish" {
                    ended = try await sessions.finish()
                } else {
                    ended = try await sessions.abandonEmpty()
                }
                XCTAssertEqual(ended.state, terminal == "finish" ? .completed : .abandonedEmpty)
                XCTAssertEqual(injector.failureCount, 1)
                let persisted = try await CoreDataSessionRepository(writer: controller.writer).session(
                    id: StableUUID(sessionID)
                )
                XCTAssertEqual(persisted.state, ended.state)
                let remainingSessionClaims = try await controller.writer.read { context in
                    try ExerciseManagedObjectMapping.fetchClaims(scope: .currentSession, in: context).count
                }
                XCTAssertEqual(remainingSessionClaims, 0)
                let visible = try await repository.searchActive(query: target.canonicalName)
                XCTAssertEqual(visible.map(\.id), [try StableExerciseID(target.id)])
                try await controller.shutdownForTesting()
            }
        }

        func testAddingRetiredCatalogItemIsRejectedButIDReadRemainsAvailable() async throws {
            let environment = try makeRepository()
            let current = try currentCatalog()
            try await environment.repository.syncBuiltInCatalog(current, now: environment.clock.nowUTC())
            let retired = try XCTUnwrap(current.exercises.first(where: { $0.retired == true }))
            let retiredID = try StableExerciseID(retired.id)
            let item = try await environment.repository.catalogItem(id: retiredID)
            XCTAssertTrue(item.isRetired)
            let studentRepository = CoreDataStudentRepository(writer: environment.controller.writer)
            let sessionRepository = CoreDataSessionRepository(writer: environment.controller.writer)
            let historicalStudentID = StableUUID(UUID(uuidString: "34343434-3434-4434-8434-343434343434")!)
            _ = try await studentRepository.create(
                try StudentDraft(displayName: "停用动作历史测试", sex: .female).makeStudent(
                    id: historicalStudentID,
                    now: environment.clock.nowUTC()
                )
            )
            let historicalSessionID = StableUUID(UUID(uuidString: "35353535-3535-4535-8535-353535353535")!)
            let historicalExerciseID = StableUUID(UUID(uuidString: "36363636-3636-4636-8636-363636363636")!)
            let historicalSetID = StableUUID(UUID(uuidString: "37373737-3737-4737-8737-373737373737")!)
            var historical = Session.start(
                id: historicalSessionID,
                studentID: historicalStudentID,
                now: environment.clock.nowUTC()
            )
            historical = try historical.addingCatalogExercise(
                id: historicalExerciseID,
                item: item,
                now: environment.clock.nowUTC()
            )
            historical = try historical.addingSet(
                exerciseID: historicalExerciseID,
                setID: historicalSetID,
                input: completedInput(for: item.recordMode),
                now: environment.clock.nowUTC()
            )
            historical = try historical.confirmingSet(setID: historicalSetID, now: environment.clock.nowUTC())
            historical = try historical.finished(now: environment.clock.nowUTC())
            _ = try await sessionRepository.save(historical)
            let history = try await sessionRepository.listCompleted(studentID: historicalStudentID)
            XCTAssertEqual(history.first?.exercises.first?.sourceID, retiredID)

            let templateRepository = CoreDataTemplateRepository(writer: environment.controller.writer)
            let historicalTemplateID = StableUUID(UUID(uuidString: "38383838-3838-4838-8838-383838383838")!)
            let historicalTemplateExerciseID = StableUUID(
                UUID(uuidString: "39393939-3939-4939-8939-393939393939")!
            )
            _ = try await templateRepository.createTemplate(
                TrainingTemplate(
                    id: historicalTemplateID,
                    name: "停用动作模板",
                    createdAtUTC: environment.clock.nowUTC(),
                    updatedAtUTC: environment.clock.nowUTC()
                )
            )
            try await templateRepository.replaceExercises(
                templateID: historicalTemplateID,
                with: [
                    TemplateExercise(
                        id: historicalTemplateExerciseID,
                        templateID: historicalTemplateID,
                        sectionID: nil,
                        orderIndex: 0,
                        sourceKind: .builtIn,
                        sourceID: retiredID,
                        displayNameSnapshot: item.canonicalName,
                        recordModeSnapshot: item.recordMode,
                        plannedSets: []
                    )
                ]
            )
            let templateExercises = try await templateRepository.exercises(templateID: historicalTemplateID)
            XCTAssertEqual(templateExercises.first?.sourceID, retiredID)

            let studentID = StableUUID(UUID(uuidString: "31313131-3131-4313-8313-313131313131")!)
            _ = try await studentRepository.create(
                try StudentDraft(displayName: "停用动作测试", sex: .female).makeStudent(
                    id: studentID,
                    now: environment.clock.nowUTC()
                )
            )
            let sessions = ActiveSessionUseCases(
                sessionRepository: CoreDataSessionRepository(writer: environment.controller.writer),
                studentRepository: studentRepository,
                exerciseRepository: environment.repository,
                sectionRepository: CoreDataSessionSectionRepository(writer: environment.controller.writer),
                recoveryStore: ActiveSessionRecoveryStore(
                    url: environment.directory.url.appendingPathComponent("active-session-recovery-v1.json"),
                    protectedFileStore: ProtectedFileStore()
                ),
                storeGenerationUUID: UUID(uuidString: "32323232-3232-4323-8323-323232323232")!,
                clock: environment.clock,
                ids: TestIDGenerator(ids: [UUID(uuidString: "33333333-3333-4333-8333-333333333333")!])
            )
            _ = try await sessions.startOrOpen(studentID: studentID)
            do {
                _ = try await sessions.addCatalogExercise(itemID: retiredID)
                XCTFail("retired catalog item must not be selectable")
            } catch {
                XCTAssertEqual(error as? DomainError, .invalidState)
            }
            try await environment.controller.shutdownForTesting()
        }

        func testAddingCustomShadowedBuiltInIsRejected() async throws {
            let environment = try makeRepository()
            let current = try currentCatalog()
            let legacy = try legacyCatalog(from: current)
            let legacyIDs = Set(legacy.exercises.map(\.id))
            let shadowed = try XCTUnwrap(current.exercises.first { !legacyIDs.contains($0.id) })
            let shadowedID = try StableExerciseID(shadowed.id)
            try await seedLegacyCatalog(legacy, writer: environment.controller.writer, now: environment.clock.nowUTC())
            _ = try await environment.repository.createCustom(
                name: shadowed.canonicalName,
                recordMode: .reps,
                id: customID,
                now: environment.clock.nowUTC()
            )
            try await environment.repository.syncBuiltInCatalog(current, now: environment.clock.nowUTC())
            let addressable = try await environment.repository.catalogItem(id: shadowedID)

            let studentRepository = CoreDataStudentRepository(writer: environment.controller.writer)
            let sessionRepository = CoreDataSessionRepository(writer: environment.controller.writer)
            let studentID = StableUUID(UUID(uuidString: "21212121-2121-4212-8212-212121212121")!)
            _ = try await studentRepository.create(
                try StudentDraft(displayName: "自定义重名测试", sex: .male).makeStudent(
                    id: studentID,
                    now: environment.clock.nowUTC()
                )
            )
            let historicalSessionID = StableUUID(UUID(uuidString: "24242424-2424-4424-8424-242424242424")!)
            let historicalExerciseID = StableUUID(UUID(uuidString: "25252525-2525-4525-8525-252525252525")!)
            let historicalSetID = StableUUID(UUID(uuidString: "26262626-2626-4626-8626-262626262626")!)
            var historical = Session.start(
                id: historicalSessionID,
                studentID: studentID,
                now: environment.clock.nowUTC()
            )
            historical = try historical.addingCatalogExercise(
                id: historicalExerciseID,
                item: addressable,
                now: environment.clock.nowUTC()
            )
            historical = try historical.addingSet(
                exerciseID: historicalExerciseID,
                setID: historicalSetID,
                input: completedInput(for: addressable.recordMode),
                now: environment.clock.nowUTC()
            )
            historical = try historical.confirmingSet(setID: historicalSetID, now: environment.clock.nowUTC())
            historical = try historical.finished(now: environment.clock.nowUTC())
            _ = try await sessionRepository.save(historical)
            let history = try await sessionRepository.listCompleted(studentID: studentID)
            XCTAssertEqual(history.first?.exercises.first?.sourceID, shadowedID)

            let sessions = ActiveSessionUseCases(
                sessionRepository: sessionRepository,
                studentRepository: studentRepository,
                exerciseRepository: environment.repository,
                sectionRepository: CoreDataSessionSectionRepository(writer: environment.controller.writer),
                recoveryStore: ActiveSessionRecoveryStore(
                    url: environment.directory.url.appendingPathComponent("active-session-recovery-v1.json"),
                    protectedFileStore: ProtectedFileStore()
                ),
                storeGenerationUUID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
                clock: environment.clock,
                ids: TestIDGenerator(ids: [UUID(uuidString: "23232323-2323-4323-8323-232323232323")!])
            )
            _ = try await sessions.startOrOpen(studentID: studentID)
            do {
                _ = try await sessions.addCatalogExercise(itemID: shadowedID)
                XCTFail("custom-shadowed built-in must not be selectable")
            } catch {
                XCTAssertEqual(error as? DomainError, .invalidState)
            }
            XCTAssertEqual(addressable.canonicalName.value, shadowed.canonicalName)
            try await environment.controller.shutdownForTesting()
        }

        func testCXD12PullUpsUpdateEquipmentFromBodyweightToBarAndKeepPreference() async throws {
            let environment = try makeRepository()
            let current = try currentCatalog()
            let legacy = try legacyCatalog(from: current)
            try await seedLegacyCatalog(legacy, writer: environment.controller.writer, now: environment.clock.nowUTC())
            let studentRepository = CoreDataStudentRepository(writer: environment.controller.writer)
            let sessionRepository = CoreDataSessionRepository(writer: environment.controller.writer)
            _ = try await studentRepository.create(
                try StudentDraft(displayName: "引体升级学员", sex: .male).makeStudent(
                    id: studentID,
                    now: environment.clock.nowUTC()
                )
            )
            let recordIDs: [(StableExerciseID, StableUUID, StableUUID, StableUUID)] = [
                (
                    StableExerciseID(rawValue: "8e420408-0682-4ab6-89f5-2681e54c7ce0")!,
                    StableUUID(UUID(uuidString: "12121212-1212-4212-8212-121212121212")!),
                    StableUUID(UUID(uuidString: "13131313-1313-4313-8313-131313131313")!),
                    StableUUID(UUID(uuidString: "16161616-1616-4616-8616-161616161616")!)
                ),
                (
                    StableExerciseID(rawValue: "87e6abc5-a701-442a-b4fb-bb2a7598a754")!,
                    StableUUID(UUID(uuidString: "14141414-1414-4414-8414-141414141414")!),
                    StableUUID(UUID(uuidString: "15151515-1515-4515-8515-151515151515")!),
                    StableUUID(UUID(uuidString: "17171717-1717-4717-8717-171717171717")!)
                ),
            ]
            var snapshots: [StableExerciseID: String] = [:]
            for (id, sessionID, exerciseID, setID) in recordIDs {
                let oldItem = try await environment.repository.catalogItem(id: id)
                snapshots[id] = oldItem.canonicalName.value
                var session = Session.start(id: sessionID, studentID: studentID, now: environment.clock.nowUTC())
                session = try session.addingCatalogExercise(
                    id: exerciseID,
                    item: oldItem,
                    now: environment.clock.nowUTC()
                )
                session = try session.addingSet(
                    exerciseID: exerciseID,
                    setID: setID,
                    input: TrainingSetInput(
                        recordMode: oldItem.recordMode,
                        repetitionCount: "6",
                        unit: .repetitions
                    ),
                    now: environment.clock.nowUTC()
                )
                session = try session.confirmingSet(setID: setID, now: environment.clock.nowUTC())
                session = try session.finished(now: environment.clock.nowUTC())
                _ = try await sessionRepository.save(session)
            }
            for id in [
                StableExerciseID(rawValue: "8e420408-0682-4ab6-89f5-2681e54c7ce0")!,
                StableExerciseID(rawValue: "87e6abc5-a701-442a-b4fb-bb2a7598a754")!,
            ] {
                _ = try await environment.repository.setPreference(
                    exerciseID: id,
                    alias: "旧偏好",
                    isFavorite: true,
                    isHidden: false,
                    isAssisted: true,
                    isUnilateral: true
                )
            }
            try await environment.repository.syncBuiltInCatalog(current, now: environment.clock.nowUTC())
            let expectedIDs: Set<StableExerciseID> = [
                StableExerciseID(rawValue: "8e420408-0682-4ab6-89f5-2681e54c7ce0")!,
                StableExerciseID(rawValue: "87e6abc5-a701-442a-b4fb-bb2a7598a754")!,
            ]
            let entries = try await environment.repository.searchActive(query: "")
                .filter { expectedIDs.contains($0.id) }
            XCTAssertEqual(entries.count, 2)
            XCTAssertTrue(entries.allSatisfy { $0.equipmentClass == "单杠" })
            for entry in entries {
                let preference = try await preference(for: entry.id, writer: environment.controller.writer)
                XCTAssertEqual(preference?.alias?.value, "旧偏好")
                XCTAssertTrue(preference?.isFavorite == true)
                XCTAssertTrue(preference?.isAssisted == true)
                XCTAssertTrue(preference?.isUnilateral == true)
            }
            for (id, sessionID, exerciseID, _) in recordIDs {
                let persisted = try await sessionRepository.session(id: sessionID)
                let exercise = try XCTUnwrap(persisted.exercises.first)
                XCTAssertEqual(persisted.state, .completed)
                XCTAssertEqual(exercise.sourceID, id)
                XCTAssertEqual(exercise.displayNameSnapshot.value, snapshots[id])
                XCTAssertEqual(exercise.id, exerciseID)
            }
            try await environment.controller.shutdownForTesting()
        }

        func testCXD15HackExercisesUpdateEquipmentFromFixedMachineToHackSquat() async throws {
            let environment = try makeRepository()
            let current = try currentCatalog()
            let legacy = try legacyCatalog(from: current)
            let hackIDs = [
                StableExerciseID(rawValue: "f462df26-3264-48c2-b5aa-2374d0670c24")!,
                StableExerciseID(rawValue: "95a9cc46-270e-45f2-8a17-5665a23ff70b")!,
            ]
            for id in hackIDs {
                let legacyExercise = try XCTUnwrap(legacy.exercises.first { $0.id == id.rawValue })
                XCTAssertEqual(legacyExercise.equipmentClass, "固定器械")
                let currentExercise = try XCTUnwrap(current.exercises.first { $0.id == id.rawValue })
                XCTAssertEqual(currentExercise.equipmentClass, "哈克机")
            }

            try await seedLegacyCatalog(legacy, writer: environment.controller.writer, now: environment.clock.nowUTC())
            try await environment.repository.syncBuiltInCatalog(current, now: environment.clock.nowUTC())

            let entries = try await environment.repository.searchActive(query: "")
            for id in hackIDs {
                let entry = try XCTUnwrap(entries.first { $0.id == id })
                XCTAssertEqual(entry.equipmentClass, "哈克机")
                XCTAssertEqual(entry.displayedName, entry.item.canonicalName.value)
            }
            try await environment.controller.shutdownForTesting()
        }

        func testRecentSelectionUsesPersistedCompletedHistoryForStudentAndCoach() async throws {
            let environment = try makeRepository()
            try await environment.repository.seedPlaceholderCatalogIfNeeded(now: environment.clock.nowUTC())
            let students = CoreDataStudentRepository(writer: environment.controller.writer)
            let sessions = CoreDataSessionRepository(writer: environment.controller.writer)
            let firstStudentID = StableUUID(UUID(uuidString: "71717171-7171-4717-8717-717171717171")!)
            let secondStudentID = StableUUID(UUID(uuidString: "72727272-7272-4727-8727-727272727272")!)
            _ = try await students.create(
                try StudentDraft(displayName: "最近动作学员一", sex: .female).makeStudent(
                    id: firstStudentID,
                    now: environment.clock.nowUTC()
                ))
            _ = try await students.create(
                try StudentDraft(displayName: "最近动作学员二", sex: .male).makeStudent(
                    id: secondStudentID,
                    now: environment.clock.nowUTC()
                ))

            let older = try await makeCompletedCatalogSession(
                studentID: firstStudentID,
                exerciseID: squatID,
                sessionID: StableUUID(UUID(uuidString: "73737373-7373-4737-8737-737373737373")!),
                sessionExerciseID: StableUUID(UUID(uuidString: "74747474-7474-4747-8747-747474747474")!),
                exerciseRepository: environment.repository,
                sessionRepository: sessions,
                completedAt: now
            )
            let newer = try await makeCompletedCatalogSession(
                studentID: secondStudentID,
                exerciseID: pullupID,
                sessionID: StableUUID(UUID(uuidString: "75757575-7575-4757-8757-757575757575")!),
                sessionExerciseID: StableUUID(UUID(uuidString: "76767676-7676-4767-8767-767676767676")!),
                exerciseRepository: environment.repository,
                sessionRepository: sessions,
                completedAt: now.addingTimeInterval(60)
            )
            XCTAssertEqual(older.state, .completed)
            XCTAssertEqual(newer.state, .completed)

            let history = HistoryUseCases(
                sessionRepository: sessions,
                clock: environment.clock,
                ids: SystemIDGenerator()
            )
            let allHistory = try await history.listAllHistory()
            let available = try await environment.repository.searchActive(query: "")
            XCTAssertEqual(
                RecentExerciseSelection.entries(
                    from: allHistory,
                    studentID: firstStudentID,
                    availableEntries: available
                ).map(\.id),
                [squatID]
            )
            XCTAssertEqual(
                RecentExerciseSelection.entries(from: allHistory, availableEntries: available).map(\.id),
                [pullupID, squatID]
            )
            try await environment.controller.shutdownForTesting()
        }

        private func makeCompletedCatalogSession(
            studentID: StableUUID,
            exerciseID: StableExerciseID,
            sessionID: StableUUID,
            sessionExerciseID: StableUUID,
            exerciseRepository: CoreDataExerciseRepository,
            sessionRepository: CoreDataSessionRepository,
            completedAt: Date
        ) async throws -> Session {
            var session = Session.start(id: sessionID, studentID: studentID, now: completedAt)
            let item = try await exerciseRepository.catalogItem(id: exerciseID)
            session = try session.addingCatalogExercise(
                id: sessionExerciseID,
                item: item,
                now: completedAt
            )
            let sessionExerciseIDValue = try XCTUnwrap(session.exercises.first?.id)
            session = try session.addingSet(
                exerciseID: sessionExerciseIDValue,
                setID: StableUUID(UUID()),
                input: TrainingSetInput(
                    recordMode: item.recordMode,
                    weightValue: item.recordMode == .weightReps ? "20" : nil,
                    repetitionCount: "8",
                    unit: item.recordMode == .weightReps ? .kilograms : .repetitions
                ),
                now: completedAt
            )
            let setID = try XCTUnwrap(session.exercises.first?.sets.first?.id)
            session = try session.confirmingSet(setID: setID, now: completedAt)
            session = try session.finished(now: completedAt)
            return try await sessionRepository.saveAndReleaseSessionScopeClaims(session)
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

        private func catalogIDs(writer: PersistenceWriter) async throws -> Set<String> {
            try await writer.read { context in
                let request = NSFetchRequest<NSManagedObject>(entityName: "ExerciseCatalogMO")
                return Set(try context.fetch(request).compactMap { $0.value(forKey: "id") as? String })
            }
        }

        private func currentCatalog() throws -> PlaceholderExerciseCatalog {
            try PlaceholderExerciseCatalogLoader.loadFromBundle(Bundle(for: PersistenceController.self))
        }

        private func seedLegacyCatalog(
            _ catalog: PlaceholderExerciseCatalog,
            writer: PersistenceWriter,
            now: Date
        ) async throws {
            try await writer.transaction { context in
                for loaded in catalog.exercises {
                    let item = try ExerciseCatalogItem.makeBuiltIn(
                        id: try StableExerciseID(loaded.id),
                        canonicalName: loaded.canonicalName,
                        recordMode: loaded.recordMode,
                        metadataVersion: catalog.metadataVersion,
                        provenanceRef: loaded.provenanceRef,
                        now: now,
                        isRetired: loaded.retired ?? false
                    )
                    _ = try ExerciseManagedObjectMapping.upsertCatalogItem(item, in: context)
                    try ExerciseManagedObjectMapping.acquireUnifiedClaim(
                        try ExerciseNameClaim(
                            normalizedName: item.normalizedName,
                            ownerKind: .builtIn,
                            ownerID: item.id,
                            scope: .activeCatalog
                        ),
                        in: context
                    )
                }
            }
        }

        private func legacyCatalog(from _: PlaceholderExerciseCatalog) throws -> PlaceholderExerciseCatalog {
            // This is the exact pre-CX2a shipped manifest. Keep upgrade tests
            // independent of the current catalog's projection or ordering.
            let catalog = try loadBaselineCatalog()
            XCTAssertEqual(catalog.exercises.count, 146)
            XCTAssertEqual(catalog.provenance.records.count, 146)
            return catalog
        }

        private func preference(
            for id: StableExerciseID,
            writer: PersistenceWriter
        ) async throws -> ExercisePreference? {
            try await writer.read { context in
                try ExerciseManagedObjectMapping.fetchPreference(exerciseID: id.rawValue, in: context)
                    .map { try ExerciseManagedObjectMapping.makePreference(from: $0) }
            }
        }

        private func completedInput(for recordMode: RecordMode) -> TrainingSetInput {
            switch recordMode {
            case .weightReps:
                return TrainingSetInput(
                    recordMode: recordMode,
                    weightValue: "1",
                    repetitionCount: "1",
                    unit: .kilograms
                )
            case .reps:
                return TrainingSetInput(
                    recordMode: recordMode,
                    repetitionCount: "1",
                    unit: .repetitions
                )
            case .duration:
                return TrainingSetInput(
                    recordMode: recordMode,
                    durationSeconds: "1",
                    unit: .seconds
                )
            case .cardio:
                return TrainingSetInput(
                    recordMode: recordMode,
                    durationSeconds: "1",
                    unit: .seconds,
                    distanceValue: "1"
                )
            }
        }

        private func loadBaselineCatalog() throws -> PlaceholderExerciseCatalog {
            let testFileURL = URL(fileURLWithPath: #filePath)
            let iosRoot =
                testFileURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let fixtureURL = iosRoot.appendingPathComponent(
                "TestSupport/Fixtures/ExerciseCatalog/provenance-baseline-146.json"
            )
            return try JSONDecoder().decode(
                PlaceholderExerciseCatalog.self,
                from: Data(contentsOf: fixtureURL)
            )
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
