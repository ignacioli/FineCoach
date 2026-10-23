#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// T025: restart-level checks for the M2 foundation. The viewer snapshot store runs against
    /// a real temporary root, including the `archive.store.afterGenerationWritten` fault point;
    /// the identity rules run through real Coach stores and the real backup export / restore
    /// path (M2-FR-051, D-013). All data is fictional.
    final class ArchiveFoundationIntegrationTests: XCTestCase {
        private typealias F = ArchiveFixtures

        private let studentA = UUID(uuidString: "a0000000-0000-4000-8000-000000000001")!
        private let studentB = UUID(uuidString: "a0000000-0000-4000-8000-000000000002")!
        private let studentC = UUID(uuidString: "a0000000-0000-4000-8000-000000000003")!
        private let now = Date(timeIntervalSince1970: 1_700_000_000)
        private let backupFileID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
        private let sourceGenerationID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        private let destinationGenerationID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        private let restoredGenerationID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
        private let passwordText = "口令测试甲乙丙丁"

        // MARK: - ArchiveSnapshotStore on a real root

        private func makeStoreRoot() -> URL {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("ArchiveFoundationIT-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent(ArchiveSnapshotStore.directoryName, isDirectory: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
            return root
        }

        private func entries(_ url: URL) -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
        }

        func testStoreCommitLoadAndDeleteAllSurviveReopening() throws {
            let root = makeStoreRoot()
            let snapshot = F.fullSnapshot()
            try ArchiveSnapshotStore(rootURL: root).commit(snapshot: snapshot)

            // A fresh instance over the same root is the "restart".
            let reopened = ArchiveSnapshotStore(rootURL: root)
            XCTAssertEqual(try reopened.load(), snapshot)

            let newer = F.summariesOnlySnapshot(snapshotAt: F.snapshotAt.addingTimeInterval(60))
            try reopened.commit(snapshot: newer)
            XCTAssertEqual(try ArchiveSnapshotStore(rootURL: root).load(), newer)
            XCTAssertEqual(entries(root.appendingPathComponent("generations")).count, 1)

            try ArchiveSnapshotStore(rootURL: root).deleteAll()
            XCTAssertNil(try ArchiveSnapshotStore(rootURL: root).load())
            XCTAssertEqual(entries(root), [])
        }

        func testTerminatingAfterGenerationWrittenReopensToPreCommitState() throws {
            let root = makeStoreRoot()
            let original = F.summariesOnlySnapshot()
            try ArchiveSnapshotStore(rootURL: root).commit(snapshot: original)

            let faulty = ArchiveSnapshotStore(
                rootURL: root,
                faultInjectionBoundary: FaultInjectionBoundary(
                    injector: TestFaultInjector(failingPoints: [.archiveStoreAfterGenerationWritten])
                )
            )
            XCTAssertThrowsError(try faulty.commit(snapshot: F.fullSnapshot())) {
                XCTAssertEqual($0 as? FaultInjectionError, .injected(.archiveStoreAfterGenerationWritten))
            }

            // "Process restarts": janitor first, then the state is read from disk.
            let reopened = ArchiveSnapshotStore(rootURL: root)
            try reopened.runStartupJanitor()
            XCTAssertEqual(try reopened.load(), original)
            XCTAssertEqual(entries(root.appendingPathComponent("generations")).count, 1)
        }

        func testTerminatingAfterGenerationWrittenOnFirstInstallLeavesNoArchive() throws {
            let root = makeStoreRoot()
            let faulty = ArchiveSnapshotStore(
                rootURL: root,
                faultInjectionBoundary: FaultInjectionBoundary(
                    injector: TestFaultInjector(failingPoints: [.archiveStoreAfterGenerationWritten])
                )
            )
            XCTAssertThrowsError(try faulty.commit(snapshot: F.fullSnapshot()))

            let reopened = ArchiveSnapshotStore(rootURL: root)
            XCTAssertNil(try reopened.load())
            try reopened.runStartupJanitor()
            XCTAssertNil(try reopened.load())
            XCTAssertEqual(entries(root), [])
        }

        func testJanitorCleansOrphansAndStagingOnReopen() throws {
            let root = makeStoreRoot()
            let store = ArchiveSnapshotStore(rootURL: root)
            let snapshot = F.fullSnapshot()
            try store.commit(snapshot: snapshot)
            let generations = root.appendingPathComponent("generations")
            let orphan = generations.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: orphan.appendingPathComponent("snapshot.bin"))
            try FileManager.default.createDirectory(at: store.stagingURL, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: store.stagingURL.appendingPathComponent("partial"))

            let reopened = ArchiveSnapshotStore(rootURL: root)
            try reopened.runStartupJanitor()

            XCTAssertEqual(entries(generations).count, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.stagingURL.path))
            XCTAssertEqual(try reopened.load(), snapshot)
        }

        // MARK: - Identity settings through real Coach stores and the backup path

        private struct Harness {
            let rootDirectory: TemporaryProtectedDirectory
            let controller: PersistenceController
            let students: StudentUseCases
            let repository: CoreDataStudentRepository
            let identity: ArchiveIdentityService
            let clock: TestClock
        }

        private func makeHarness(
            rootDirectory: TemporaryProtectedDirectory? = nil,
            generationUUID: UUID? = nil,
            studentIDs: [UUID] = [],
            identityIDs: [UUID] = []
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
            let controller = try PersistenceController(storeURL: directory.databaseURL(for: resolvedUUID))
            let clock = TestClock(utcDate: now)
            let repository = CoreDataStudentRepository(writer: controller.writer)
            return Harness(
                rootDirectory: root,
                controller: controller,
                students: StudentUseCases(
                    repository: repository,
                    clock: clock,
                    ids: TestIDGenerator(ids: studentIDs)
                ),
                repository: repository,
                identity: ArchiveIdentityService(
                    writer: controller.writer,
                    ids: TestIDGenerator(ids: identityIDs)
                ),
                clock: clock
            )
        }

        private func addStudent(_ name: String, to harness: Harness) async throws {
            _ = try await harness.students.create(draft: StudentDraft(displayName: name, sex: .female))
        }

        private func coordinator(_ harness: Harness, ids: [UUID]) -> BackupCoordinator {
            BackupCoordinator(
                rootURL: harness.rootDirectory.url,
                writer: harness.controller.writer,
                clock: harness.clock,
                ids: TestIDGenerator(ids: ids)
            )
        }

        private func export(from harness: Harness) async throws -> (TemporaryProtectedDirectory, URL) {
            let destination = try TemporaryProtectedDirectory()
            let result = try await coordinator(harness, ids: [backupFileID]).exportInventory(
                BackupExportRequest(
                    password: try BackupPassword(creating: passwordText),
                    destinationDirectory: destination.url
                )
            )
            return (destination, result.fileURL)
        }

        private func restore(_ file: URL, into harness: Harness) async throws {
            try await coordinator(harness, ids: [restoredGenerationID]).restoreReplacingCurrent(
                BackupRestoreRequest(password: try BackupPassword(creating: passwordText), sourceFileURL: file)
            )
        }

        /// Every `archive.*` setting in the store, by key.
        private func archiveSettings(_ harness: Harness) async throws -> [String: String] {
            let entries = try await harness.controller.writer.read { context in
                try StudentManagedObjectMapping.settings(withKeyPrefix: "archive.", in: context)
            }
            return Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value) })
        }

        private func studentKey(_ id: UUID) -> String {
            StudentManagedObjectMapping.archiveStudentIDKey(for: id)
        }

        func testM1BBackupRestoreKeepsCurrentSourceAndPresentStudentIdentityOnly() async throws {
            // Backup source: payload schema 3, no archive keys; holds students A and C.
            let source = try makeHarness(studentIDs: [studentA, studentC])
            try await addStudent("林青", to: source)
            try await addStudent("周宁", to: source)
            let sourceSettings = try await archiveSettings(source)
            XCTAssertTrue(sourceSettings.isEmpty, "an M1-B backup carries no archive keys")
            let (backupDirectory, backupFile) = try await export(from: source)
            _ = backupDirectory
            let header = try Data(contentsOf: backupFile)
            XCTAssertEqual(
                UInt16(header[8]) << 8 | UInt16(header[9]),
                FineCoachBackupV1.payloadSchemaVersion
            )
            XCTAssertEqual(FineCoachBackupV1.payloadSchemaVersion, 3)
            try await source.controller.shutdownForTesting()

            // Current install: A and B exist; identities were generated for both. C has none.
            let currentRoot = try TemporaryProtectedDirectory()
            let currentSource = UUID(uuidString: "c0000000-0000-4000-8000-0000000000a0")!
            let currentArchiveA = UUID(uuidString: "c0000000-0000-4000-8000-0000000000a1")!
            let currentArchiveB = UUID(uuidString: "c0000000-0000-4000-8000-0000000000b1")!
            let current = try makeHarness(
                rootDirectory: currentRoot,
                generationUUID: destinationGenerationID,
                studentIDs: [studentA, studentB],
                identityIDs: [currentSource, currentArchiveA, UUID(), currentArchiveB]
            )
            try await addStudent("林青", to: current)
            try await addStudent("吴越", to: current)
            _ = try await current.identity.ensureIdentity(forStudent: StableUUID(studentA))
            // The second call reuses the source ID; only the student value is new.
            _ = try await current.identity.ensureIdentity(forStudent: StableUUID(studentB))
            let before = try await archiveSettings(current)
            XCTAssertEqual(before["archive.sourceID"], currentSource.uuidString)
            XCTAssertEqual(before[studentKey(studentA)], currentArchiveA.uuidString)
            XCTAssertEqual(before[studentKey(studentB)], currentArchiveB.uuidString)

            try await restore(backupFile, into: current)
            try await current.controller.shutdownForTesting()

            let restored = try makeHarness(rootDirectory: currentRoot)
            let after = try await archiveSettings(restored)
            XCTAssertEqual(
                after["archive.sourceID"], currentSource.uuidString, "source identity keeps the current value")
            XCTAssertEqual(
                after[studentKey(studentA)], currentArchiveA.uuidString, "present student keeps the current value")
            XCTAssertNil(after[studentKey(studentB)], "student absent from the backup is not written")
            XCTAssertNil(after[studentKey(studentC)], "student without a current identity gets none invented")
            XCTAssertEqual(Set(after.keys), ["archive.sourceID", studentKey(studentA)])
            _ = try await restored.students.student(id: StableUUID(studentA))
            _ = try await restored.students.student(id: StableUUID(studentC))
            do {
                _ = try await restored.students.student(id: StableUUID(studentB))
                XCTFail("student B exists only in the replaced install")
            } catch {
                XCTAssertEqual(error as? DomainError, .notFound)
            }
            try await restored.controller.shutdownForTesting()
        }

        func testM1BBackupRestoreWithNoCurrentIdentityWritesNothing() async throws {
            let source = try makeHarness(studentIDs: [studentA])
            try await addStudent("林青", to: source)
            let (backupDirectory, backupFile) = try await export(from: source)
            _ = backupDirectory
            try await source.controller.shutdownForTesting()

            let currentRoot = try TemporaryProtectedDirectory()
            let current = try makeHarness(rootDirectory: currentRoot, generationUUID: destinationGenerationID)
            try await restore(backupFile, into: current)
            try await current.controller.shutdownForTesting()

            let restored = try makeHarness(rootDirectory: currentRoot)
            let restoredSettings = try await archiveSettings(restored)
            XCTAssertTrue(restoredSettings.isEmpty)
            try await restored.controller.shutdownForTesting()
        }

        func testM2BackupRestoredIntoEmptyInstallKeepsBackupIdentities() async throws {
            let backupSource = UUID(uuidString: "b0000000-0000-4000-8000-0000000000a0")!
            let backupArchiveA = UUID(uuidString: "b0000000-0000-4000-8000-0000000000a1")!
            let backupArchiveB = UUID(uuidString: "b0000000-0000-4000-8000-0000000000b1")!
            let source = try makeHarness(
                studentIDs: [studentA, studentB],
                identityIDs: [backupSource, backupArchiveA, UUID(), backupArchiveB]
            )
            try await addStudent("林青", to: source)
            try await addStudent("周宁", to: source)
            _ = try await source.identity.ensureIdentity(forStudent: StableUUID(studentA))
            _ = try await source.identity.ensureIdentity(forStudent: StableUUID(studentB))
            let (backupDirectory, backupFile) = try await export(from: source)
            _ = backupDirectory
            try await source.controller.shutdownForTesting()

            let emptyRoot = try TemporaryProtectedDirectory()
            let empty = try makeHarness(rootDirectory: emptyRoot, generationUUID: destinationGenerationID)
            try await restore(backupFile, into: empty)
            try await empty.controller.shutdownForTesting()

            let restored = try makeHarness(rootDirectory: emptyRoot)
            let after = try await archiveSettings(restored)
            XCTAssertEqual(after["archive.sourceID"], backupSource.uuidString)
            XCTAssertEqual(after[studentKey(studentA)], backupArchiveA.uuidString)
            XCTAssertEqual(after[studentKey(studentB)], backupArchiveB.uuidString)
            try await restored.controller.shutdownForTesting()
        }

        func testBackupIdentitiesWinOverDifferentCurrentIdentities() async throws {
            let backupSource = UUID(uuidString: "b0000000-0000-4000-8000-0000000000a0")!
            let backupArchiveA = UUID(uuidString: "b0000000-0000-4000-8000-0000000000a1")!
            let source = try makeHarness(studentIDs: [studentA], identityIDs: [backupSource, backupArchiveA])
            try await addStudent("林青", to: source)
            _ = try await source.identity.ensureIdentity(forStudent: StableUUID(studentA))
            let (backupDirectory, backupFile) = try await export(from: source)
            _ = backupDirectory
            try await source.controller.shutdownForTesting()

            let currentRoot = try TemporaryProtectedDirectory()
            let current = try makeHarness(
                rootDirectory: currentRoot,
                generationUUID: destinationGenerationID,
                studentIDs: [studentA],
                identityIDs: [
                    UUID(uuidString: "c0000000-0000-4000-8000-0000000000a0")!,
                    UUID(uuidString: "c0000000-0000-4000-8000-0000000000a1")!,
                ]
            )
            try await addStudent("林青", to: current)
            _ = try await current.identity.ensureIdentity(forStudent: StableUUID(studentA))
            try await restore(backupFile, into: current)
            try await current.controller.shutdownForTesting()

            let restored = try makeHarness(rootDirectory: currentRoot)
            let after = try await archiveSettings(restored)
            XCTAssertEqual(after["archive.sourceID"], backupSource.uuidString)
            XCTAssertEqual(after[studentKey(studentA)], backupArchiveA.uuidString)
            try await restored.controller.shutdownForTesting()
        }

        func testPermanentDeleteRemovesTheStudentArchiveIdentityOnly() async throws {
            let source = UUID(uuidString: "d0000000-0000-4000-8000-0000000000a0")!
            let archiveA = UUID(uuidString: "d0000000-0000-4000-8000-0000000000a1")!
            let archiveB = UUID(uuidString: "d0000000-0000-4000-8000-0000000000b1")!
            let harness = try makeHarness(
                studentIDs: [studentA, studentB],
                identityIDs: [source, archiveA, UUID(), archiveB]
            )
            try await addStudent("林青", to: harness)
            try await addStudent("周宁", to: harness)
            _ = try await harness.identity.ensureIdentity(forStudent: StableUUID(studentA))
            _ = try await harness.identity.ensureIdentity(forStudent: StableUUID(studentB))
            let identityBefore = try await harness.identity.studentArchiveID(forStudent: StableUUID(studentA))
            XCTAssertEqual(identityBefore, archiveA)

            try await harness.repository.delete(id: StableUUID(studentA), confirmedDisplayName: "林青")

            let after = try await archiveSettings(harness)
            XCTAssertNil(after[studentKey(studentA)], "the deleted student's identity key is removed (open problem #4)")
            XCTAssertEqual(after[studentKey(studentB)], archiveB.uuidString)
            XCTAssertEqual(after["archive.sourceID"], source.uuidString, "the source identity stays")
            let identityAfter = try await harness.identity.studentArchiveID(forStudent: StableUUID(studentA))
            XCTAssertNil(identityAfter)
            try await harness.controller.shutdownForTesting()
        }

        func testEnsureIdentityIsStableAndFailsClosedOnACorruptValue() async throws {
            let harness = try makeHarness(
                studentIDs: [studentA],
                identityIDs: [UUID(), UUID(), UUID(), UUID()]
            )
            try await addStudent("林青", to: harness)
            let first = try await harness.identity.ensureIdentity(forStudent: StableUUID(studentA))
            let second = try await harness.identity.ensureIdentity(forStudent: StableUUID(studentA))
            XCTAssertEqual(first, second)

            try await harness.controller.writer.transaction { context in
                try StudentManagedObjectMapping.writeSetting(key: "archive.sourceID", value: "not-a-uuid", in: context)
            }
            do {
                _ = try await harness.identity.ensureIdentity(forStudent: StableUUID(studentA))
                XCTFail("a corrupt stored identity must not be overwritten")
            } catch {
                XCTAssertEqual(error as? DomainError, .incompatibleInput)
            }
            let stored = try await archiveSettings(harness)
            XCTAssertEqual(stored["archive.sourceID"], "not-a-uuid")
            try await harness.controller.shutdownForTesting()
        }
    }
#endif
