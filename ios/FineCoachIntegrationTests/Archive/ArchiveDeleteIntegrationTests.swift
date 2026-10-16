#if DEBUG
    import XCTest

    @testable import FineCoach

    /// T059 (US-4, AC-010, M2-FR-041..044, M2-FR-050): deleting the local archive through the real
    /// store directory and the real install-state resolver. All data is fictional.
    final class ArchiveDeleteIntegrationTests: XCTestCase {
        private typealias F = ArchiveFixtures

        private struct EmptyCoachProbe: CoachInstallProbe {
            func read() async throws -> CoachInstallSnapshot {
                CoachInstallSnapshot(onboardingCompleted: false, hasWorkData: false)
            }
        }

        private struct Harness {
            let work: URL
            let root: URL
            /// The archive file the Student was given, outside the app's own storage.
            let original: URL
            let originalBytes: Data

            func store() -> ArchiveSnapshotStore { ArchiveSnapshotStore(rootURL: root) }

            func resolver(_ store: ArchiveSnapshotStore? = nil) -> InstallStateResolver {
                let store = store ?? self.store()
                return InstallStateResolver(store: store, probe: EmptyCoachProbe())
            }

            func importUseCases(_ store: ArchiveSnapshotStore? = nil) -> ArchiveImportUseCases {
                let store = store ?? self.store()
                return ArchiveImportUseCases(
                    store: store, resolver: resolver(store), logger: RecordingLogger())
            }
        }

        /// Imports the original file, so the install is a real viewer install with display
        /// settings and a leftover staging file.
        private func makeInstalledHarness() async throws -> Harness {
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("ArchiveDeleteIT-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: work) }
            let bytes = try ArchiveFileCodec.encode(
                snapshot: F.fullSnapshot(), password: try ArchivePassword(creating: F.password),
                salt: F.fixedSalt, noncePrefix: F.fixedNoncePrefix)
            let original = work.appendingPathComponent("original.fcarchive")
            try bytes.write(to: original)
            let harness = Harness(
                work: work, root: work.appendingPathComponent(ArchiveSnapshotStore.directoryName, isDirectory: true),
                original: original, originalBytes: bytes)

            _ = try await harness.importUseCases().importArchive(from: original, password: F.password)
            var settings = ArchiveDisplaySettings.defaults
            settings.weightUnit = .lb
            try harness.store().writeDisplaySettings(settings)
            let staging = harness.store().stagingURL
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try Data("scratch".utf8).write(to: staging.appendingPathComponent("candidate.tmp"))
            let installed = try await harness.resolver().resolve()
            XCTAssertEqual(installed, .viewer)
            return harness
        }

        private func files(under url: URL) -> [String] {
            let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])
            return (items?.compactMap { $0 as? URL } ?? []).filter {
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }.map(\.lastPathComponent).sorted()
        }

        // MARK: Delete

        func testDeleteRemovesEveryFileResolvesUnselectedAndLeavesTheOriginalFile() async throws {
            let h = try await makeInstalledHarness()
            XCTAssertTrue(files(under: h.root).contains("display-settings.json"))
            XCTAssertTrue(files(under: h.root).contains("candidate.tmp"))

            try await ArchiveViewerUseCases(store: h.store(), logger: RecordingLogger()).deleteArchive()

            XCTAssertEqual(files(under: h.root), [], "no pointer, generation, staging file or display settings")
            let state = try await h.resolver().resolve()
            XCTAssertEqual(state, .unselected, "the app goes back to the first-launch choice (M2-FR-050)")
            XCTAssertEqual(try Data(contentsOf: h.original), h.originalBytes, "the original file is untouched")
            XCTAssertEqual(h.store().readDisplaySettings(), .defaults)
            XCTAssertNil(try h.store().load())
        }

        func testDeletedArchiveCanBeImportedAgainWithTheOriginalFileAndPassword() async throws {
            let h = try await makeInstalledHarness()
            try await ArchiveViewerUseCases(store: h.store(), logger: RecordingLogger()).deleteArchive()

            let summary = try await h.importUseCases().importArchive(from: h.original, password: F.password)
            XCTAssertEqual(summary.sourceLabel, ArchiveIdentityService.shortLabel(forSourceID: F.sourceID))
            let state = try await h.resolver().resolve()
            XCTAssertEqual(state, .viewer)
            let content = try await ArchiveViewerUseCases(store: h.store()).load()
            XCTAssertEqual(content.snapshot, F.fullSnapshot())
            XCTAssertEqual(h.store().readDisplaySettings(), .defaults, "settings were cleared, not restored")
        }

        func testDeleteLogsOnlyFixedIDsAndIsRepeatable() async throws {
            let h = try await makeInstalledHarness()
            let logger = RecordingLogger()
            let useCases = ArchiveViewerUseCases(store: h.store(), logger: logger)
            try await useCases.deleteArchive()
            try await useCases.deleteArchive()  // nothing left: still succeeds
            XCTAssertEqual(logger.events, ["archive.delete_completed", "archive.delete_completed"])
            XCTAssertEqual(files(under: h.root), [])
        }

        // MARK: Interruption

        func testTerminationBetweenPointerRemovalAndDirectoryRemovalResolvesUnselectedAndTheJanitorCleansUp()
            async throws
        {
            let h = try await makeInstalledHarness()
            let faulty = ArchiveSnapshotStore(
                rootURL: h.root,
                faultInjectionBoundary: FaultInjectionBoundary(
                    injector: TestFaultInjector(failingPoints: [.archiveStoreAfterPointerRemoved])))

            XCTAssertThrowsError(try faulty.deleteAll())
            // Residue is on disk, but without a pointer the archive is gone for the app.
            XCTAssertFalse(FileManager.default.fileExists(atPath: h.root.appendingPathComponent("current.json").path))
            XCTAssertTrue(files(under: h.root).contains("snapshot.bin"), "the kill left the generation behind")

            // "Process restarts": a fresh store, the launch janitor, then the state is derived.
            let reopened = h.store()
            try reopened.runStartupJanitor()
            XCTAssertEqual(files(under: h.root), [])
            let state = try await h.resolver(reopened).resolve()
            XCTAssertEqual(state, .unselected)
            XCTAssertEqual(try Data(contentsOf: h.original), h.originalBytes)
        }

        func testFailedDeleteIsReportedAndRetryingFinishesTheJob() async throws {
            let h = try await makeInstalledHarness()
            let faulty = ArchiveSnapshotStore(
                rootURL: h.root,
                faultInjectionBoundary: FaultInjectionBoundary(
                    injector: TestFaultInjector(failingPoints: [.archiveStoreAfterPointerRemoved])))
            let logger = RecordingLogger()
            do {
                try await ArchiveViewerUseCases(store: faulty, logger: logger).deleteArchive()
                XCTFail("the injected termination must be reported")
            } catch {
                XCTAssertEqual(error as? ArchiveViewerError, .deleteFailed)
            }
            XCTAssertEqual(logger.events, ["archive.delete_failed"])
            let state = try await h.resolver().resolve()
            XCTAssertEqual(state, .unselected)

            try await ArchiveViewerUseCases(store: h.store(), logger: logger).deleteArchive()
            XCTAssertEqual(files(under: h.root), [])
        }
    }
#endif
