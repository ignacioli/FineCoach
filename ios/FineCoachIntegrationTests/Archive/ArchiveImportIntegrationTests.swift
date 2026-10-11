#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// T052 (US-2, AC-006, AC-007, M2-FR-026/028, NFR-008): first import through the real file
    /// codec, a real `ArchiveViewer/` directory and a real on-disk Coach store. The hostile files
    /// are produced with the Phase 2 encoder. All data is fictional.
    final class ArchiveImportIntegrationTests: XCTestCase {
        private typealias F = ArchiveFixtures
        private typealias X = ArchiveExportFixtures

        private static let goldenFile: Data = {
            try! ArchiveFileCodec.encode(
                snapshot: ArchiveFixtures.fullSnapshot(),
                password: try! ArchivePassword(creating: ArchiveFixtures.password),
                salt: ArchiveFixtures.fixedSalt,
                noncePrefix: ArchiveFixtures.fixedNoncePrefix
            )
        }()

        /// Counts reads so a branch that must not read the file can prove it.
        private final class SpyReader: ArchiveFileReading, @unchecked Sendable {
            private let lock = NSLock()
            private var reads = 0
            var readCount: Int { lock.lock(); defer { lock.unlock() }; return reads }

            func readArchive(at url: URL) throws -> Data {
                lock.lock()
                reads += 1
                lock.unlock()
                return try SecurityScopedArchiveFileReader().readArchive(at: url)
            }
        }

        private struct Harness {
            let workDirectory: URL
            let viewerRoot: URL
            let coach: X.Store
            let reader: SpyReader
            let logger: RecordingLogger
            let useCases: ArchiveImportUseCases
            let inbox: URL

            func makeStore() -> ArchiveSnapshotStore { ArchiveSnapshotStore(rootURL: viewerRoot) }

            func resolver() -> InstallStateResolver {
                InstallStateResolver(store: makeStore(), probe: CoreDataCoachInstallProbe(writer: coach.writer))
            }
        }

        private func makeHarness(
            seedCoachData: Bool = false,
            store customStore: ((URL) -> ArchiveSnapshotStore)? = nil
        ) async throws -> Harness {
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("ArchiveImportIT-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: work) }
            let viewerRoot = work.appendingPathComponent(ArchiveSnapshotStore.directoryName, isDirectory: true)
            let inbox = work.appendingPathComponent("Inbox", isDirectory: true)
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

            let coach = try X.Store(inMemory: false)
            if seedCoachData {
                try await X.seed(coach, archived: true)
            }
            let store = customStore?(viewerRoot) ?? ArchiveSnapshotStore(rootURL: viewerRoot)
            let resolver = InstallStateResolver(store: store, probe: CoreDataCoachInstallProbe(writer: coach.writer))
            let reader = SpyReader()
            let logger = RecordingLogger()
            return Harness(
                workDirectory: work,
                viewerRoot: viewerRoot,
                coach: coach,
                reader: reader,
                logger: logger,
                useCases: ArchiveImportUseCases(
                    store: store, resolver: resolver, reader: reader, logger: logger, inboxRootURL: inbox),
                inbox: inbox
            )
        }

        private func write(_ data: Data, in directory: URL, name: String = "archive.fcarchive") throws -> URL {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url)
            return url
        }

        private func listing(_ url: URL) -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
        }

        /// `ArchiveViewer/` holds no pointer, no generation, no staging file and no plaintext.
        private func assertCleanInstall(_ h: Harness, _ message: String = "", line: UInt = #line) async throws {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: h.viewerRoot.appendingPathComponent("current.json").path),
                "pointer \(message)", line: line)
            XCTAssertEqual(
                listing(h.viewerRoot.appendingPathComponent("generations")), [], "generations \(message)", line: line)
            XCTAssertEqual(
                listing(h.viewerRoot.appendingPathComponent("staging")), [], "staging \(message)", line: line)
            // No file anywhere under the viewer root can hold plaintext.
            let files = FileManager.default.enumerator(at: h.viewerRoot, includingPropertiesForKeys: [.isRegularFileKey])?
                .compactMap { $0 as? URL }.filter {
                    (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                } ?? []
            XCTAssertEqual(files, [], "files \(message)", line: line)
            let state = try await h.resolver().resolve()
            XCTAssertEqual(state, .unselected, message, line: line)
        }

        private func assertImportFails(
            _ h: Harness,
            file: URL,
            password: String = ArchiveFixtures.password,
            _ expected: ArchiveImportFailure,
            _ message: String,
            line: UInt = #line
        ) async throws {
            do {
                _ = try await h.useCases.importArchive(from: file, password: password)
                XCTFail("\(message) should fail", line: line)
            } catch {
                XCTAssertEqual(error as? ArchiveImportFailure, expected, message, line: line)
            }
            let state = await h.useCases.state
            XCTAssertEqual(state, .failed(expected), message, line: line)
            try await assertCleanInstall(h, message, line: line)
        }

        // MARK: AC-007: every failure leaves a clean install

        func testEveryFailureLeavesNoPointerNoGenerationNoPlaintextAndTheStateUnselected() async throws {
            let h = try await makeHarness()
            let good = Self.goldenFile
            let work = h.workDirectory

            try await assertImportFails(
                h, file: try write(good, in: work, name: "wrong.fcarchive"), password: "错误的口令12345",
                .wrongPasswordOrCorrupted, "wrong password")

            try await assertImportFails(
                h, file: try write(good.dropLast(20), in: work, name: "cut.fcarchive"),
                .wrongPasswordOrCorrupted, "truncated")

            var tampered = good
            tampered[good.count / 2] ^= 0x01
            try await assertImportFails(
                h, file: try write(tampered, in: work, name: "tampered.fcarchive"),
                .wrongPasswordOrCorrupted, "tampered ciphertext")

            var future = good
            future.replaceSubrange(8..<10, with: [0, 2])
            try await assertImportFails(
                h, file: try write(future, in: work, name: "future.fcarchive"),
                .incompatibleVersion, "future payload schema")

            var backup = good
            backup.replaceSubrange(0..<4, with: Data("FCBK".utf8))
            try await assertImportFails(
                h, file: try write(backup, in: work, name: "backup.fcarchive"),
                .invalidArchive, "Coach backup file")

            // Authenticated, correct password, but the identity metadata is not a UUID.
            let payload = try F.payload(of: F.fullSnapshot()) { id, object in
                if id == ArchiveFileV1.Section.manifest.rawValue {
                    object["sourceID"] = "not-a-uuid"
                }
            }
            let badIdentity = try ArchiveFileCodec.seal(
                plaintext: payload.plaintext,
                recordCount: payload.frameCount,
                password: try ArchivePassword(creating: F.password),
                salt: F.fixedSalt,
                noncePrefix: F.fixedNoncePrefix
            )
            try await assertImportFails(
                h, file: try write(badIdentity, in: work, name: "identity.fcarchive"),
                .invalidArchive, "invalid identity metadata")

            // A file that does not exist and a directory are "invalid file", not a crash.
            try await assertImportFails(
                h, file: work.appendingPathComponent("missing.fcarchive"), .invalidArchive, "missing file")
            try await assertImportFails(h, file: work, .invalidArchive, "directory")

            XCTAssertTrue(h.logger.events.allSatisfy { $0.hasPrefix("archive.import_") })
            XCTAssertFalse(h.logger.events.contains("archive.import_completed"))
        }

        func testFailedImportCanBeRetriedWithTheRightPassword() async throws {
            let h = try await makeHarness()
            let file = try write(Self.goldenFile, in: h.workDirectory)
            try await assertImportFails(
                h, file: file, password: "错误的口令12345", .wrongPasswordOrCorrupted, "first attempt")

            let summary = try await h.useCases.importArchive(from: file, password: F.password)
            XCTAssertEqual(summary.sourceLabel, ArchiveIdentityService.shortLabel(forSourceID: F.sourceID))
            XCTAssertEqual(summary.snapshotAtUTC, F.snapshotAt)
            XCTAssertEqual(summary.modules, F.modules())
            let state = await h.useCases.state
            XCTAssertEqual(state, .imported(summary))
        }

        #if DEBUG
            func testTerminationBetweenGenerationWriteAndPointerSwitchLeavesACleanUnselectedInstall() async throws {
                let faulty: (URL) -> ArchiveSnapshotStore = { root in
                    ArchiveSnapshotStore(
                        rootURL: root,
                        faultInjectionBoundary: FaultInjectionBoundary(
                            injector: TestFaultInjector(failingPoints: [.archiveStoreAfterGenerationWritten])
                        )
                    )
                }
                let h = try await makeHarness(store: faulty)
                let file = try write(Self.goldenFile, in: h.workDirectory)
                try await assertImportFails(h, file: file, .interrupted, "interrupted commit")

                // "Process restarts": the launch janitor runs on a fresh store, then the state resolves.
                try h.makeStore().runStartupJanitor()
                try await assertCleanInstall(h, "after restart")
                XCTAssertEqual(h.logger.events, ["archive.import_interrupted"])
            }
        #endif

        func testCancellingTheImportLeavesTheInstallUntouched() async throws {
            let h = try await makeHarness()
            let file = try write(Self.goldenFile, in: h.workDirectory)
            let useCases = h.useCases
            let task = Task { try await useCases.importArchive(from: file, password: F.password) }
            task.cancel()
            do {
                _ = try await task.value
                XCTFail("a cancelled import must not succeed")
            } catch {
                XCTAssertEqual(error as? ArchiveImportFailure, .interrupted)
            }
            try await assertCleanInstall(h, "after cancellation")
        }

        func testSecondImportWhileOneIsRunningIsRejected() async throws {
            let h = try await makeHarness()
            let file = try write(Self.goldenFile, in: h.workDirectory)
            let useCases = h.useCases
            async let first = useCases.importArchive(from: file, password: F.password)
            // Let the first call reach the actor and start before the duplicate arrives.
            while await useCases.state != .importing { await Task.yield() }
            do {
                _ = try await useCases.importArchive(from: file, password: F.password)
                XCTFail("duplicate import must be rejected")
            } catch {
                XCTAssertEqual(error as? ArchiveImportFailure, .importInProgress)
            }
            _ = try await first
            let state = try await h.resolver().resolve()
            XCTAssertEqual(state, .viewer)
        }

        // MARK: Success

        func testCorrectImportBecomesViewerAndSurvivesRestart() async throws {
            let h = try await makeHarness()
            let file = try write(Self.goldenFile, in: h.workDirectory)
            let before = await h.useCases.state
            XCTAssertEqual(before, .idle)

            let summary = try await h.useCases.importArchive(from: file, password: F.password)
            XCTAssertEqual(summary.sourceLabel, ArchiveIdentityService.shortLabel(forSourceID: F.sourceID))

            // A fresh store and resolver over the same directory is the "restart".
            let reopened = ArchiveSnapshotStore(rootURL: h.viewerRoot)
            try reopened.runStartupJanitor()
            let state = try await InstallStateResolver(
                store: reopened, probe: CoreDataCoachInstallProbe(writer: h.coach.writer)
            ).resolve()
            XCTAssertEqual(state, .viewer)
            let content = try await ArchiveViewerUseCases(store: reopened).load()
            XCTAssertEqual(content.snapshot, F.fullSnapshot())
            XCTAssertEqual(listing(h.viewerRoot.appendingPathComponent("generations")).count, 1)
            XCTAssertEqual(h.logger.events, ["archive.import_completed"])

            // A second first-import on a viewer install is refused without reading the file.
            let readsBefore = h.reader.readCount
            do {
                _ = try await h.useCases.importArchive(from: file, password: F.password)
                XCTFail("an installed archive is not replaced by a first import")
            } catch {
                XCTAssertEqual(error as? ArchiveImportFailure, .alreadyInstalled)
            }
            XCTAssertEqual(h.reader.readCount, readsBefore)
        }

        // MARK: AC-006: Coach data blocks

        func testInstallWithAnArchivedStudentBlocksImportAndLeavesCoachDataUntouched() async throws {
            let h = try await makeHarness(seedCoachData: true)
            let file = try write(Self.goldenFile, in: h.workDirectory)
            let inventoryBefore = try await h.coach.writer.read { try BackupInventoryMapper.collect(in: $0) }

            let resolved = try await h.resolver().resolve()
            XCTAssertEqual(resolved, .coach, "one archived student is Coach work data (D-002)")
            do {
                _ = try await h.useCases.importArchive(from: file, password: F.password)
                XCTFail("Coach data must block the import")
            } catch {
                XCTAssertEqual(error as? ArchiveImportFailure, .blockedByCoachData)
            }

            let inventoryAfter = try await h.coach.writer.read { try BackupInventoryMapper.collect(in: $0) }
            XCTAssertEqual(inventoryAfter, inventoryBefore)
            XCTAssertEqual(h.reader.readCount, 0, "a blocked import never reads the file")
            XCTAssertFalse(FileManager.default.fileExists(atPath: h.viewerRoot.path))
            XCTAssertEqual(h.logger.events, ["archive.import_blocked_coach_data"])
        }

        func testUnreadableCoachStoreFailsClosedWithoutReadingTheFile() async throws {
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("ArchiveImportIT-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: work) }
            struct BrokenProbe: CoachInstallProbe {
                func read() async throws -> CoachInstallSnapshot { throw PersistenceControllerError.storeLoadFailed }
            }
            let store = ArchiveSnapshotStore(rootURL: work.appendingPathComponent("ArchiveViewer"))
            let reader = SpyReader()
            let useCases = ArchiveImportUseCases(
                store: store, resolver: InstallStateResolver(store: store, probe: BrokenProbe()),
                reader: reader, logger: RecordingLogger())
            let file = try write(Self.goldenFile, in: work)
            do {
                _ = try await useCases.importArchive(from: file, password: F.password)
                XCTFail("an unreadable Coach store must not look like a clean install")
            } catch {
                XCTAssertEqual(error as? ArchiveImportFailure, .installStateUnavailable)
            }
            XCTAssertEqual(reader.readCount, 0)
        }

        // MARK: System open (D-010, M2-FR-024)

        func testOpenedFileRoutingNeverReadsTheFileAndInboxCopiesAreDiscardedAfterEveryBranch() async throws {
            // Blocked branch: Coach install.
            let blocked = try await makeHarness(seedCoachData: true)
            let blockedCopy = try write(Self.goldenFile, in: blocked.inbox, name: "blocked.fcarchive")
            let destination = try await blocked.useCases.openDestination()
            XCTAssertEqual(destination, .blocked)
            XCTAssertEqual(blocked.reader.readCount, 0)
            let removedBlocked = await blocked.useCases.discardInboxCopy(at: blockedCopy)
            XCTAssertTrue(removedBlocked)
            XCTAssertEqual(listing(blocked.inbox), [])

            // Prefilled import branch: success, then the Inbox copy goes.
            let clean = try await makeHarness()
            let cleanDestination = try await clean.useCases.openDestination()
            XCTAssertEqual(cleanDestination, .importPrefilled)
            let okCopy = try write(Self.goldenFile, in: clean.inbox, name: "ok.fcarchive")
            _ = try await clean.useCases.importArchive(from: okCopy, password: F.password)
            let removedOk = await clean.useCases.discardInboxCopy(at: okCopy)
            XCTAssertTrue(removedOk)
            XCTAssertEqual(listing(clean.inbox), [])
            let replaceDestination = try await clean.useCases.openDestination()
            XCTAssertEqual(replaceDestination, .replacePrefilled)

            // Failure branch: the copy goes as well.
            let failing = try await makeHarness()
            let junkCopy = try write(Data("not an archive".utf8), in: failing.inbox, name: "junk.fcarchive")
            do {
                _ = try await failing.useCases.importArchive(from: junkCopy, password: F.password)
                XCTFail("junk must fail")
            } catch {
                XCTAssertEqual(error as? ArchiveImportFailure, .invalidArchive)
            }
            let removedJunk = await failing.useCases.discardInboxCopy(at: junkCopy)
            XCTAssertTrue(removedJunk)
            XCTAssertEqual(listing(failing.inbox), [])
        }

        func testDiscardNeverTouchesFilesOutsideTheInbox() async throws {
            let h = try await makeHarness()
            let original = try write(Self.goldenFile, in: h.workDirectory, name: "original.fcarchive")
            let removedOutside = await h.useCases.discardInboxCopy(at: original)
            XCTAssertFalse(removedOutside)
            XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))

            // A path that climbs out of the Inbox resolves to the same outside file.
            let climbing = h.inbox.appendingPathComponent("../original.fcarchive")
            let removedClimbing = await h.useCases.discardInboxCopy(at: climbing)
            XCTAssertFalse(removedClimbing)
            XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))

            // The Inbox directory itself is not deleted either.
            let removedRoot = await h.useCases.discardInboxCopy(at: h.inbox)
            XCTAssertFalse(removedRoot)
            XCTAssertTrue(FileManager.default.fileExists(atPath: h.inbox.path))
        }
    }
#endif
