#if DEBUG
    import XCTest

    @testable import FineCoach

    /// T056 (US-3, AC-009, M2-FR-036..040, NFR-008): replacing the installed archive through the
    /// real file codec and a real `ArchiveViewer/` directory. Every rejection and the interrupted
    /// commit are checked by comparing the bytes of every file under the viewer root. All data is
    /// fictional.
    final class ArchiveReplaceIntegrationTests: XCTestCase {
        private typealias F = ArchiveFixtures

        private struct EmptyCoachProbe: CoachInstallProbe {
            func read() async throws -> CoachInstallSnapshot {
                CoachInstallSnapshot(onboardingCompleted: false, hasWorkData: false)
            }
        }

        /// Counts reads so a branch that must not read the file can prove it.
        private final class SpyReader: ArchiveFileReading, @unchecked Sendable {
            private let lock = NSLock()
            private var reads = 0
            var readCount: Int {
                lock.lock()
                defer { lock.unlock() }
                return reads
            }

            func readArchive(at url: URL) throws -> Data {
                lock.lock()
                reads += 1
                lock.unlock()
                return try SecurityScopedArchiveFileReader().readArchive(at: url)
            }
        }

        private struct Harness {
            let work: URL
            let viewerRoot: URL
            let reader: SpyReader
            let logger: RecordingLogger
            let useCases: ArchiveImportUseCases

            func plainStore() -> ArchiveSnapshotStore { ArchiveSnapshotStore(rootURL: viewerRoot) }
        }

        private static let newerAt = F.snapshotAt.addingTimeInterval(3_600)
        private static let olderAt = F.snapshotAt.addingTimeInterval(-3_600)
        private static let otherID = UUID(uuidString: "99999999-8888-4777-8666-555555555555")!

        /// T1 (the installed one) is `fullSnapshot`; candidates are the smallest valid snapshot
        /// with the given identity and time, so a merge would be visible in the loaded content.
        private func candidate(
            at time: Date,
            source: UUID = F.sourceID,
            student: UUID = F.studentArchiveID
        ) throws -> ArchiveSnapshot {
            let base = F.summariesOnlySnapshot(snapshotAt: time)
            return ArchiveSnapshot(
                manifest: try ArchiveManifest(
                    sourceID: source, studentArchiveID: student, snapshotAtUTC: time,
                    modules: base.manifest.modules, counts: base.manifest.counts),
                summaries: base.summaries)
        }

        private func file(
            _ snapshot: ArchiveSnapshot, named name: String, in h: Harness, password: String = F.password
        ) throws -> URL {
            let data = try ArchiveFileCodec.encode(
                snapshot: snapshot, password: try ArchivePassword(creating: password),
                salt: F.fixedSalt, noncePrefix: F.fixedNoncePrefix)
            return try write(data, named: name, in: h)
        }

        private func write(_ data: Data, named name: String, in h: Harness) throws -> URL {
            let url = h.work.appendingPathComponent(name)
            try data.write(to: url)
            return url
        }

        /// Installs T1 and a non-default display setting, then returns the harness.
        private func makeHarness(
            installed: ArchiveSnapshot? = F.fullSnapshot(),
            faultyStore: Bool = false
        ) throws -> Harness {
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("ArchiveReplaceIT-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: work) }
            let root = work.appendingPathComponent(ArchiveSnapshotStore.directoryName, isDirectory: true)
            let plain = ArchiveSnapshotStore(rootURL: root)
            if let installed {
                try plain.commit(snapshot: installed)
                var settings = ArchiveDisplaySettings.defaults
                settings.weightUnit = .lb
                settings.density = .compact
                try plain.writeDisplaySettings(settings)
            }
            let store =
                faultyStore
                ? ArchiveSnapshotStore(
                    rootURL: root,
                    faultInjectionBoundary: FaultInjectionBoundary(
                        injector: TestFaultInjector(failingPoints: [.archiveStoreAfterGenerationWritten])))
                : plain
            let reader = SpyReader()
            let logger = RecordingLogger()
            return Harness(
                work: work, viewerRoot: root, reader: reader, logger: logger,
                useCases: ArchiveImportUseCases(
                    store: store, resolver: InstallStateResolver(store: store, probe: EmptyCoachProbe()),
                    reader: reader, logger: logger))
        }

        /// Relative path -> bytes of every regular file under the viewer root.
        private func tree(_ h: Harness) -> [String: Data] {
            var result: [String: Data] = [:]
            let root = h.viewerRoot.resolvingSymlinksInPath().path
            guard
                let items = FileManager.default.enumerator(
                    at: h.viewerRoot, includingPropertiesForKeys: [.isRegularFileKey])
            else { return result }
            for case let url as URL in items {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let path = url.resolvingSymlinksInPath().path
                result[String(path.dropFirst(root.count))] = try? Data(contentsOf: url)
            }
            return result
        }

        private func generationCount(_ h: Harness) -> Int {
            ((try? FileManager.default.contentsOfDirectory(
                atPath: h.viewerRoot.appendingPathComponent("generations").path)) ?? []).count
        }

        private func assertRejected(
            _ h: Harness, file: URL, password: String = F.password,
            _ expected: ArchiveReplaceFailure, _ message: String, line: UInt = #line
        ) async throws {
            let before = tree(h)
            do {
                _ = try await h.useCases.prepareReplacement(from: file, password: password)
                XCTFail("\(message) should be rejected", line: line)
            } catch {
                XCTAssertEqual(error as? ArchiveReplaceFailure, expected, message, line: line)
            }
            XCTAssertEqual(tree(h), before, "\(message): installed snapshot must be byte-identical", line: line)
            // Nothing is held for a confirmation either.
            do {
                _ = try await h.useCases.confirmReplacement()
                XCTFail("\(message): nothing to confirm", line: line)
            } catch {
                XCTAssertEqual(error as? ArchiveReplaceFailure, .noPendingReplacement, message, line: line)
            }
            XCTAssertEqual(tree(h), before, message, line: line)
            let content = try await ArchiveViewerUseCases(store: h.plainStore()).load()
            XCTAssertEqual(content.snapshot, F.fullSnapshot(), "\(message): still T1", line: line)
        }

        // MARK: Success

        func testReplacingT1WithT2KeepsOnlyT2AndMergesNothing() async throws {
            let h = try makeHarness()
            let t2 = try candidate(at: Self.newerAt)
            let url = try file(t2, named: "t2.fcarchive", in: h)
            let beforeFile = try Data(contentsOf: url)

            // Step 1 writes nothing and shows both archives' facts (M2-FR-038).
            let before = tree(h)
            let preview = try await h.useCases.prepareReplacement(from: url, password: F.password)
            XCTAssertEqual(tree(h), before, "validation alone changes nothing; the user still has to confirm")
            XCTAssertEqual(preview.current.snapshotAtUTC, F.snapshotAt)
            XCTAssertEqual(preview.current.modules, F.modules())
            XCTAssertEqual(preview.candidate.snapshotAtUTC, Self.newerAt)
            XCTAssertEqual(preview.candidate.modules, t2.manifest.modules)
            XCTAssertEqual(preview.candidate.sourceLabel, preview.current.sourceLabel)

            let summary = try await h.useCases.confirmReplacement()
            XCTAssertEqual(summary, preview.candidate)

            // A fresh store is the "restart": only T2, none of T1's content, one generation.
            let reopened = ArchiveSnapshotStore(rootURL: h.viewerRoot)
            try reopened.runStartupJanitor()
            let content = try await ArchiveViewerUseCases(store: reopened).load()
            XCTAssertEqual(content.snapshot, t2)
            XCTAssertTrue(content.snapshot.sessions.isEmpty, "no per-record merge with T1")
            XCTAssertTrue(content.snapshot.bodyMetrics.isEmpty)
            XCTAssertEqual(generationCount(h), 1)
            XCTAssertEqual(try Data(contentsOf: url), beforeFile, "the source file is not touched")
            XCTAssertEqual(h.logger.events, ["archive.replace_completed"])

            // The same file again is now a duplicate, and a second confirm has nothing to commit.
            do {
                _ = try await h.useCases.prepareReplacement(from: url, password: F.password)
                XCTFail("T2 is not newer than T2")
            } catch {
                XCTAssertEqual(error as? ArchiveReplaceFailure, .notNewer)
            }
            do {
                _ = try await h.useCases.confirmReplacement()
                XCTFail("a replacement cannot be confirmed twice")
            } catch {
                XCTAssertEqual(error as? ArchiveReplaceFailure, .noPendingReplacement)
            }
        }

        func testDisplaySettingsSurviveAReplacement() async throws {
            let h = try makeHarness()
            let url = try file(try candidate(at: Self.newerAt), named: "t2.fcarchive", in: h)
            _ = try await h.useCases.prepareReplacement(from: url, password: F.password)
            _ = try await h.useCases.confirmReplacement()

            let settings = ArchiveSnapshotStore(rootURL: h.viewerRoot).readDisplaySettings()
            XCTAssertEqual(settings.weightUnit, .lb)
            XCTAssertEqual(settings.density, .compact)
        }

        func testCancellingAfterValidationDropsTheCandidateAndChangesNothing() async throws {
            let h = try makeHarness()
            let url = try file(try candidate(at: Self.newerAt), named: "t2.fcarchive", in: h)
            let before = tree(h)
            _ = try await h.useCases.prepareReplacement(from: url, password: F.password)
            await h.useCases.cancelReplacement()
            do {
                _ = try await h.useCases.confirmReplacement()
                XCTFail("a cancelled candidate cannot be confirmed")
            } catch {
                XCTAssertEqual(error as? ArchiveReplaceFailure, .noPendingReplacement)
            }
            XCTAssertEqual(tree(h), before)
        }

        // MARK: Rejections keep T1 byte-identical (M2-FR-039)

        func testOlderSameTimeOtherSourceOtherStudentAreRejectedWithTheirReason() async throws {
            let h = try makeHarness()
            try await assertRejected(
                h, file: try file(try candidate(at: Self.olderAt), named: "t0.fcarchive", in: h),
                .notNewer, "older T0")
            // The same snapshot time, even with different content, is a duplicate (D-004).
            try await assertRejected(
                h, file: try file(try candidate(at: F.snapshotAt), named: "copy.fcarchive", in: h),
                .notNewer, "same-time copy")
            try await assertRejected(
                h, file: try file(F.fullSnapshot(), named: "t1.fcarchive", in: h), .notNewer, "T1 itself")
            try await assertRejected(
                h, file: try file(try candidate(at: Self.newerAt, source: Self.otherID), named: "src.fcarchive", in: h),
                .differentSource, "another source")
            try await assertRejected(
                h,
                file: try file(try candidate(at: Self.newerAt, student: Self.otherID), named: "stu.fcarchive", in: h),
                .differentStudent, "another student of the same source")
            XCTAssertEqual(
                h.logger.events,
                [
                    "archive.replace_rejected_not_newer", "archive.replace_rejected_not_newer",
                    "archive.replace_rejected_not_newer", "archive.replace_rejected_source",
                    "archive.replace_rejected_student",
                ])
        }

        func testWrongPasswordCorruptedAndIncompatibleFilesAreRejectedWithTheirReason() async throws {
            let h = try makeHarness()
            let good = try ArchiveFileCodec.encode(
                snapshot: try candidate(at: Self.newerAt), password: try ArchivePassword(creating: F.password),
                salt: F.fixedSalt, noncePrefix: F.fixedNoncePrefix)

            try await assertRejected(
                h, file: try write(good, named: "wrong.fcarchive", in: h), password: "错误的口令12345",
                .wrongPasswordOrCorrupted, "wrong password")

            var tampered = good
            tampered[good.count / 2] ^= 0x01
            try await assertRejected(
                h, file: try write(tampered, named: "tampered.fcarchive", in: h),
                .wrongPasswordOrCorrupted, "damaged file")

            try await assertRejected(
                h, file: try write(good.dropLast(20), named: "cut.fcarchive", in: h),
                .wrongPasswordOrCorrupted, "truncated file")

            var future = good
            future.replaceSubrange(8..<10, with: [0, 2])
            try await assertRejected(
                h, file: try write(future, named: "future.fcarchive", in: h), .incompatibleVersion, "future version")

            var backup = good
            backup.replaceSubrange(0..<4, with: Data("FCBK".utf8))
            try await assertRejected(
                h, file: try write(backup, named: "backup.fcarchive", in: h), .invalidArchive, "not an archive")
            try await assertRejected(
                h, file: h.work.appendingPathComponent("missing.fcarchive"), .invalidArchive, "missing file")

            XCTAssertFalse(h.logger.events.contains("archive.replace_completed"))
            XCTAssertTrue(h.logger.events.allSatisfy { $0.hasPrefix("archive.import_rejected_") })
        }

        func testReplacingWithoutAnInstalledArchiveIsRefusedWithoutReadingTheFile() async throws {
            let h = try makeHarness(installed: nil)
            let url = try file(try candidate(at: Self.newerAt), named: "t2.fcarchive", in: h)
            do {
                _ = try await h.useCases.prepareReplacement(from: url, password: F.password)
                XCTFail("there is nothing to replace")
            } catch {
                XCTAssertEqual(error as? ArchiveReplaceFailure, .notInstalled)
            }
            XCTAssertEqual(h.reader.readCount, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: h.viewerRoot.path))
        }

        func testCancellingWhileValidatingChangesNothing() async throws {
            let h = try makeHarness()
            let url = try file(try candidate(at: Self.newerAt), named: "t2.fcarchive", in: h)
            let before = tree(h)
            let useCases = h.useCases
            let task = Task { try await useCases.prepareReplacement(from: url, password: F.password) }
            task.cancel()
            do {
                _ = try await task.value
                XCTFail("a cancelled validation must not succeed")
            } catch {
                XCTAssertEqual(error as? ArchiveReplaceFailure, .interrupted)
            }
            XCTAssertEqual(tree(h), before)
        }

        // MARK: Interruption

        func testTerminationBetweenGenerationWriteAndPointerSwitchKeepsT1AndSettings() async throws {
            let h = try makeHarness(faultyStore: true)
            let url = try file(try candidate(at: Self.newerAt), named: "t2.fcarchive", in: h)
            let before = tree(h)
            let pointerBefore = try Data(contentsOf: h.viewerRoot.appendingPathComponent("current.json"))

            _ = try await h.useCases.prepareReplacement(from: url, password: F.password)
            do {
                _ = try await h.useCases.confirmReplacement()
                XCTFail("the injected termination must stop the commit")
            } catch {
                XCTAssertEqual(error as? ArchiveReplaceFailure, .interrupted)
            }
            // The pointer, T1's generation and the settings are byte-identical; the use case's
            // own janitor already removed the orphan generation of the failed commit.
            XCTAssertEqual(tree(h), before)
            XCTAssertEqual(try Data(contentsOf: h.viewerRoot.appendingPathComponent("current.json")), pointerBefore)

            // "Process restarts": launch janitor on a fresh store, then T1 is still what shows.
            try h.plainStore().runStartupJanitor()
            XCTAssertEqual(tree(h), before)
            let content = try await ArchiveViewerUseCases(store: h.plainStore()).load()
            XCTAssertEqual(content.snapshot, F.fullSnapshot())
            XCTAssertEqual(h.plainStore().readDisplaySettings().weightUnit, .lb)
            XCTAssertEqual(h.logger.events, ["archive.replace_interrupted"])
        }

        func testLeftoverGenerationOfAKilledReplacementIsRemovedByTheLaunchJanitor() throws {
            let h = try makeHarness()
            let before = tree(h)
            // What a process kill between the generation write and the pointer switch leaves.
            let orphan = h.viewerRoot.appendingPathComponent("generations/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
            try Data("orphan".utf8).write(to: orphan.appendingPathComponent("snapshot.bin"))
            XCTAssertEqual(generationCount(h), 2)

            try h.plainStore().runStartupJanitor()
            XCTAssertEqual(tree(h), before)
            XCTAssertEqual(generationCount(h), 1)
        }
    }
#endif
