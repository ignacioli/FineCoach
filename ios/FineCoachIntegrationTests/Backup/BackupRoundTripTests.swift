#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    final class BackupRoundTripTests: XCTestCase {
        private let studentID = StableUUID(FictitiousFixtures.student.id)
        private let secondStudentID = StableUUID(FictitiousFixtures.secondStudent.id)
        private let completedSessionID = StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        private let completedExerciseID = StableUUID(UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
        private let completedSetID = StableUUID(UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!)
        private let inProgressSessionID = StableUUID(UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!)
        private let backupFileID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
        private let sourceGenerationID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        private let destinationGenerationID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        private let restoredGenerationID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
        private let now = Date(timeIntervalSince1970: 1_700_000_000)
        private let exportPasswordText = "口令测试甲乙丙丁"
        private let wrongPasswordText = "口令测试戊己庚辛"
        private let sqliteHeader = Data("SQLite format 3".utf8)
        private let fcbkMagic = Data("FCBK".utf8)

        func testFullInventoryRoundTripRestoresStudentSessionsAndRebuildsActivePointer() async throws {
            let source = try makeHarness(generationUUID: sourceGenerationID, ids: inventoryIDs(includeInProgress: true))
            try await seedLinQingInventory(on: source, includeInProgress: true)
            let exported = try await exportInventory(from: source, backupFileID: backupFileID)
            try await source.controller.shutdownForTesting()

            let destinationRoot = try TemporaryProtectedDirectory()
            let destination = try makeHarness(
                rootDirectory: destinationRoot,
                generationUUID: destinationGenerationID,
                ids: []
            )
            try await makeCoordinator(harness: destination, ids: [restoredGenerationID]).restoreReplacingCurrent(
                BackupRestoreRequest(
                    password: try BackupPassword(creating: exportPasswordText),
                    sourceFileURL: exported.fileURL
                )
            )
            try await destination.controller.shutdownForTesting()

            let restored = try makeHarness(rootDirectory: destinationRoot, ids: [])
            try await assertRestoredLinQingInventory(on: restored, expectInProgress: true)
            try await restored.controller.shutdownForTesting()
        }

        func testRoundTripWithoutInProgressLeavesNoActivePointer() async throws {
            let source = try makeHarness(
                generationUUID: sourceGenerationID, ids: inventoryIDs(includeInProgress: false))
            try await seedLinQingInventory(on: source, includeInProgress: false)
            let exported = try await exportInventory(from: source, backupFileID: backupFileID)
            try await source.controller.shutdownForTesting()

            let destinationRoot = try TemporaryProtectedDirectory()
            let destination = try makeHarness(
                rootDirectory: destinationRoot,
                generationUUID: destinationGenerationID,
                ids: []
            )
            try await makeCoordinator(harness: destination, ids: [restoredGenerationID]).restoreReplacingCurrent(
                BackupRestoreRequest(
                    password: try BackupPassword(creating: exportPasswordText),
                    sourceFileURL: exported.fileURL
                )
            )
            try await destination.controller.shutdownForTesting()

            let restored = try makeHarness(rootDirectory: destinationRoot, ids: [])
            try await assertRestoredLinQingInventory(on: restored, expectInProgress: false)
            let pointer = try await fetchActivePointer(writer: restored.controller.writer)
            XCTAssertNil(pointer)
            let active = try await restored.sessionUseCases.loadActive()
            XCTAssertNil(active)
            try await restored.controller.shutdownForTesting()
        }

        func testRestoreSwitchesCurrentPointerAndIsolatesOldGeneration() async throws {
            let root = try TemporaryProtectedDirectory()
            let source = try makeHarness(
                rootDirectory: root,
                generationUUID: sourceGenerationID,
                ids: inventoryIDs(includeInProgress: false) + [secondStudentID.rawValue]
            )
            try await seedLinQingInventory(on: source, includeInProgress: false)
            let exported = try await exportInventory(from: source, backupFileID: backupFileID)
            _ = try await source.studentUseCases.create(
                draft: StudentDraft(displayName: FictitiousFixtures.secondStudent.displayName, sex: .male)
            )
            let leftover = try await source.studentUseCases.student(id: secondStudentID)
            XCTAssertEqual(leftover.displayName.value, FictitiousFixtures.secondStudent.displayName)

            let oldGenerationUUID = source.generationUUID
            let oldStoreURL = source.storeURL
            XCTAssertEqual(try currentPointerUUID(rootURL: root.url), oldGenerationUUID)

            try await makeCoordinator(harness: source, ids: [restoredGenerationID]).restoreReplacingCurrent(
                BackupRestoreRequest(
                    password: try BackupPassword(creating: exportPasswordText),
                    sourceFileURL: exported.fileURL
                )
            )
            try await source.controller.shutdownForTesting()

            let currentUUID = try XCTUnwrap(currentPointerUUID(rootURL: root.url))
            XCTAssertNotEqual(currentUUID, oldGenerationUUID)

            let restored = try makeHarness(rootDirectory: root, ids: [])
            XCTAssertEqual(restored.generationUUID, currentUUID)
            XCTAssertEqual(
                restored.storeURL.standardizedFileURL,
                restored.directory.databaseURL(for: currentUUID).standardizedFileURL
            )
            XCTAssertNotEqual(restored.storeURL.standardizedFileURL, oldStoreURL.standardizedFileURL)
            try await assertRestoredLinQingInventory(on: restored, expectInProgress: false)
            let currentStudents = try await restored.studentUseCases.searchActive(query: "")
            XCTAssertEqual(currentStudents.map(\.displayName.value), [FictitiousFixtures.student.displayName])
            try await restored.controller.shutdownForTesting()

            let oldGeneration = try PersistenceController(storeURL: oldStoreURL)
            let oldUseCases = StudentUseCases(
                repository: CoreDataStudentRepository(writer: oldGeneration.writer),
                clock: TestClock(utcDate: now),
                ids: TestIDGenerator(ids: [])
            )
            let isolated = try await oldUseCases.searchActive(query: "")
            XCTAssertEqual(
                Set(isolated.map(\.displayName.value)),
                [FictitiousFixtures.student.displayName, FictitiousFixtures.secondStudent.displayName]
            )
            XCTAssertNotEqual(
                oldStoreURL.standardizedFileURL,
                restored.directory.databaseURL(for: currentUUID).standardizedFileURL
            )
            try await oldGeneration.shutdownForTesting()
        }

        func testInProcessRestoreReloadsLiveUseCasesOntoNewGeneration() async throws {
            let source = try makeHarness(
                generationUUID: sourceGenerationID,
                ids: inventoryIDs(includeInProgress: false)
            )
            try await seedLinQingInventory(on: source, includeInProgress: false)
            let exported = try await exportInventory(from: source, backupFileID: backupFileID)
            try await source.controller.shutdownForTesting()

            let destinationRoot = try TemporaryProtectedDirectory()
            let expectedName = FictitiousFixtures.student.displayName
            try await Self.restoreAndReloadLiveStack(
                rootURL: destinationRoot.url,
                clock: TestClock(utcDate: now),
                ids: TestIDGenerator(ids: [restoredGenerationID]),
                password: try BackupPassword(creating: exportPasswordText),
                fileURL: exported.fileURL,
                expectedDisplayName: expectedName
            )
        }

        @MainActor
        private static func restoreAndReloadLiveStack(
            rootURL: URL,
            clock: TestClock,
            ids: TestIDGenerator,
            password: BackupPassword,
            fileURL: URL,
            expectedDisplayName: String
        ) async throws {
            let environment = try AppEnvironment(
                rootURL: rootURL,
                clock: clock,
                idGenerator: ids
            )
            XCTAssertTrue(environment.isStorageAvailable)
            try await environment.requireBackupCoordinator().restoreReplacingCurrent(
                BackupRestoreRequest(password: password, sourceFileURL: fileURL)
            )
            try environment.reloadAfterCommittedRestore()
            let students = try await environment.requireUseCases().searchActive(query: "")
            XCTAssertEqual(students.map(\.displayName.value), [expectedDisplayName])
        }

        func testWrongPasswordRestoreLeavesCurrentStudentUnchanged() async throws {
            let source = try makeHarness(
                generationUUID: sourceGenerationID, ids: inventoryIDs(includeInProgress: false))
            try await seedLinQingInventory(on: source, includeInProgress: false)
            let exported = try await exportInventory(from: source, backupFileID: backupFileID)
            let pointerBefore = try currentPointerUUID(rootURL: source.rootDirectory.url)

            do {
                try await makeCoordinator(harness: source, ids: [restoredGenerationID]).restoreReplacingCurrent(
                    BackupRestoreRequest(
                        password: try BackupPassword(creating: wrongPasswordText),
                        sourceFileURL: exported.fileURL
                    )
                )
                XCTFail("Expected authenticationFailed")
            } catch BackupError.authenticationFailed {
                // expected
            }

            let remaining = try await source.studentUseCases.student(id: studentID)
            XCTAssertEqual(remaining.displayName.value, FictitiousFixtures.student.displayName)
            XCTAssertEqual(try currentPointerUUID(rootURL: source.rootDirectory.url), pointerBefore)
            try await source.controller.shutdownForTesting()
        }

        func testExportedFilenameIsGenericOpaqueBackup() async throws {
            let source = try makeHarness(
                generationUUID: sourceGenerationID, ids: inventoryIDs(includeInProgress: false))
            try await seedLinQingInventory(on: source, includeInProgress: false)
            let exported = try await exportInventory(from: source, backupFileID: backupFileID)
            assertGenericBackupFilename(exported.fileURL.lastPathComponent, backupFileID: backupFileID)
            XCTAssertFalse(exported.fileURL.path.contains(FictitiousFixtures.student.displayName))
            XCTAssertFalse(exported.fileURL.path.contains("Student"))
            try await source.controller.shutdownForTesting()
        }

        func testExportedFileStartsWithFCBKAndIsNotRawSQLite() async throws {
            let source = try makeHarness(
                generationUUID: sourceGenerationID, ids: inventoryIDs(includeInProgress: false))
            try await seedLinQingInventory(on: source, includeInProgress: false)
            let exported = try await exportInventory(from: source, backupFileID: backupFileID)
            let prefix = Data(try Data(contentsOf: exported.fileURL).prefix(max(4, sqliteHeader.count)))
            XCTAssertEqual(Data(prefix.prefix(4)), fcbkMagic)
            XCTAssertNotEqual(Data(prefix.prefix(4)), Data(sqliteHeader.prefix(4)))
            XCTAssertFalse(prefix.starts(with: sqliteHeader))
            try await source.controller.shutdownForTesting()
        }

        private struct Harness {
            let rootDirectory: TemporaryProtectedDirectory
            let directory: StoreGenerationDirectory
            let generationUUID: UUID
            let storeURL: URL
            let controller: PersistenceController
            let studentUseCases: StudentUseCases
            let sessionUseCases: ActiveSessionUseCases
            let historyUseCases: HistoryUseCases
            let clock: TestClock
        }

        private func makeHarness(
            rootDirectory: TemporaryProtectedDirectory? = nil,
            generationUUID: UUID? = nil,
            ids: [UUID]
        ) throws -> Harness {
            let root = try rootDirectory ?? TemporaryProtectedDirectory()
            let directory = StoreGenerationDirectory(rootURL: root.url)
            try directory.prepare()
            let pointerStore = CurrentGenerationPointerStore(url: directory.currentPointerURL)
            let metadataStore = StoreGenerationMetadataStore(directory: directory)
            let resolvedUUID: UUID
            if let existing = try pointerStore.read() {
                resolvedUUID = existing.generationUUID
            } else {
                resolvedUUID = generationUUID ?? sourceGenerationID
                try ProtectedFileStore().prepareDirectory(
                    at: directory.generationURL(for: resolvedUUID),
                    policy: .business
                )
                try metadataStore.write(
                    try StoreGenerationMetadata(
                        generationUUID: resolvedUUID,
                        createdAtUTC: now,
                        validationState: .current
                    )
                )
                try pointerStore.replace(with: try CurrentGenerationPointer(generationUUID: resolvedUUID))
            }
            let storeURL = directory.databaseURL(for: resolvedUUID)
            let controller = try PersistenceController(storeURL: storeURL)
            let clock = TestClock(utcDate: now)
            let idGenerator = TestIDGenerator(ids: ids)
            let studentRepository = CoreDataStudentRepository(writer: controller.writer)
            let sessionRepository = CoreDataSessionRepository(writer: controller.writer)
            return Harness(
                rootDirectory: root,
                directory: directory,
                generationUUID: resolvedUUID,
                storeURL: storeURL,
                controller: controller,
                studentUseCases: StudentUseCases(
                    repository: studentRepository,
                    clock: clock,
                    ids: idGenerator
                ),
                sessionUseCases: ActiveSessionUseCases(
                    sessionRepository: sessionRepository,
                    studentRepository: studentRepository,
                    exerciseRepository: CoreDataExerciseRepository(writer: controller.writer),
                    recoveryStore: ActiveSessionRecoveryStore(
                        url: directory.activeRecoveryURL,
                        protectedFileStore: ProtectedFileStore()
                    ),
                    storeGenerationUUID: resolvedUUID,
                    clock: clock,
                    ids: idGenerator
                ),
                historyUseCases: HistoryUseCases(
                    sessionRepository: sessionRepository,
                    clock: clock,
                    ids: idGenerator
                ),
                clock: clock
            )
        }

        private func makeCoordinator(harness: Harness, ids: [UUID]) -> BackupCoordinator {
            BackupCoordinator(
                rootURL: harness.rootDirectory.url,
                writer: harness.controller.writer,
                clock: harness.clock,
                ids: TestIDGenerator(ids: ids)
            )
        }

        private func inventoryIDs(includeInProgress: Bool) -> [UUID] {
            var ids = [
                studentID.rawValue,
                completedSessionID.rawValue,
                completedExerciseID.rawValue,
                completedSetID.rawValue,
            ]
            if includeInProgress {
                ids.append(inProgressSessionID.rawValue)
            }
            return ids
        }

        private func seedLinQingInventory(on harness: Harness, includeInProgress: Bool) async throws {
            _ = try await harness.studentUseCases.create(
                draft: StudentDraft(
                    displayName: FictitiousFixtures.student.displayName,
                    sex: .female,
                    trainingGoal: FictitiousFixtures.student.trainingGoal,
                    injuryNotes: FictitiousFixtures.student.syntheticNote,
                    privateCoachNote: "晚班",
                    phone: "13800001111",
                    wechatID: "linqing_test"
                )
            )
            _ = try await harness.sessionUseCases.startOrOpen(studentID: studentID)
            _ = try await harness.sessionUseCases.addSessionOnlyExercise(
                displayName: "杠铃深蹲",
                recordMode: .weightReps
            )
            _ = try await harness.sessionUseCases.addSet(
                exerciseID: completedExerciseID,
                input: weightRepsInput(weight: "0", reps: "5")
            )
            _ = try await harness.sessionUseCases.confirmSet(setID: completedSetID)
            let finished = try await harness.sessionUseCases.finish()
            XCTAssertEqual(finished.id, completedSessionID)
            XCTAssertEqual(finished.state, .completed)

            if includeInProgress {
                let active = try await harness.sessionUseCases.startOrOpen(studentID: studentID)
                XCTAssertEqual(active.id, inProgressSessionID)
                XCTAssertEqual(active.state, .inProgress)
                let pointer = try await fetchActivePointer(writer: harness.controller.writer)
                XCTAssertEqual(pointer?.sessionID, inProgressSessionID.rawValue)
            } else {
                let active = try await harness.sessionUseCases.loadActive()
                XCTAssertNil(active)
                let pointer = try await fetchActivePointer(writer: harness.controller.writer)
                XCTAssertNil(pointer)
            }
        }

        private struct ExportedBackup {
            let destination: TemporaryProtectedDirectory
            let result: BackupExportResult

            var fileURL: URL { result.fileURL }
        }

        private func exportInventory(from harness: Harness, backupFileID: UUID) async throws -> ExportedBackup {
            let destination = try TemporaryProtectedDirectory()
            let result = try await makeCoordinator(harness: harness, ids: [backupFileID]).exportInventory(
                BackupExportRequest(
                    password: try BackupPassword(creating: exportPasswordText),
                    destinationDirectory: destination.url
                )
            )
            XCTAssertEqual(
                result.fileURL.deletingLastPathComponent().standardizedFileURL,
                destination.url.standardizedFileURL
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.fileURL.path))
            return ExportedBackup(destination: destination, result: result)
        }

        private func assertRestoredLinQingInventory(on harness: Harness, expectInProgress: Bool) async throws {
            let student = try await harness.studentUseCases.student(id: studentID)
            XCTAssertEqual(student.displayName.value, FictitiousFixtures.student.displayName)
            XCTAssertEqual(student.sex, .female)
            XCTAssertEqual(student.trainingGoal?.value, FictitiousFixtures.student.trainingGoal)
            XCTAssertEqual(student.injuryNotes?.value, FictitiousFixtures.student.syntheticNote)
            XCTAssertEqual(student.privateCoachNote?.value, "晚班")
            XCTAssertEqual(student.phone?.value, "13800001111")
            XCTAssertEqual(student.wechatID?.value, "linqing_test")

            let history = try await harness.historyUseCases.listHistory(studentID: studentID)
            XCTAssertEqual(history.map(\.id), [completedSessionID])
            let completed = try XCTUnwrap(history.first)
            XCTAssertEqual(completed.studentID, studentID)
            XCTAssertEqual(completed.studentDisplayName.value, FictitiousFixtures.student.displayName)
            XCTAssertEqual(completed.completedAtUTC, now)
            let squat = try XCTUnwrap(completed.exercises.first)
            XCTAssertEqual(squat.id, completedExerciseID)
            XCTAssertEqual(squat.displayNameSnapshot.value, "杠铃深蹲")
            XCTAssertEqual(squat.recordModeSnapshot, .weightReps)
            XCTAssertEqual(squat.sourceKind, .sessionOnly)
            let trainingSet = try XCTUnwrap(squat.sets.first)
            XCTAssertEqual(trainingSet.id, completedSetID)
            XCTAssertEqual(trainingSet.state, .completed)
            XCTAssertEqual(trainingSet.weightValue?.canonicalString, DecimalValue.zero.canonicalString)
            XCTAssertEqual(trainingSet.repetitionCount?.canonicalString, try DecimalValue("5").canonicalString)

            let active = try await harness.sessionUseCases.loadActive()
            let pointer = try await fetchActivePointer(writer: harness.controller.writer)
            if expectInProgress {
                let restoredActive = try XCTUnwrap(active)
                XCTAssertEqual(restoredActive.id, inProgressSessionID)
                XCTAssertEqual(restoredActive.state, .inProgress)
                XCTAssertEqual(restoredActive.studentID, studentID)
                XCTAssertEqual(pointer?.singletonKey, ActiveSessionPointerKey.singleton)
                XCTAssertEqual(pointer?.sessionID, inProgressSessionID.rawValue)
            } else {
                XCTAssertNil(active)
                XCTAssertNil(pointer)
            }
        }

        private func assertGenericBackupFilename(_ filename: String, backupFileID: UUID) {
            XCTAssertTrue(filename.hasPrefix("FineCoach-Backup-"))
            XCTAssertTrue(filename.hasSuffix(".fcbackup"))
            XCTAssertEqual((filename as NSString).pathExtension, "fcbackup")
            let uuidStem = filename.dropFirst("FineCoach-Backup-".count).dropLast(".fcbackup".count)
            XCTAssertNotNil(UUID(uuidString: String(uuidStem)))
            XCTAssertTrue(filename.lowercased().contains(backupFileID.uuidString.lowercased()))
            XCTAssertFalse(filename.contains(FictitiousFixtures.student.displayName))
            XCTAssertFalse(filename.contains("Student"))
            XCTAssertFalse(filename.contains("1700000000"))
            XCTAssertFalse(filename.contains("2023"))
        }

        private func currentPointerUUID(rootURL: URL) throws -> UUID? {
            try CurrentGenerationPointerStore(
                url: StoreGenerationDirectory(rootURL: rootURL).currentPointerURL
            ).read()?.generationUUID
        }

        private func weightRepsInput(weight: String, reps: String) -> TrainingSetInput {
            TrainingSetInput(
                recordMode: .weightReps,
                weightValue: weight,
                repetitionCount: reps,
                unit: .kilograms
            )
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
    }
#else
    import FineCoach
    import XCTest

    final class BackupRoundTripTests: XCTestCase {
        func testReleaseKeepsBackupCoordinatorSurfaceWithoutFaultInjection() {
            XCTAssertEqual(BackupError.authenticationFailed, .authenticationFailed)
            _ = BackupCoordinator.self
            _ = BackupExportRequest.self
            _ = BackupExportResult.self
            _ = BackupRestoreRequest.self
        }
    }
#endif
