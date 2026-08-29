#if DEBUG
    import XCTest

    @testable import FineCoach

    /// In-process simulation of T097 process terminate/relaunch: persist intent/pointer/lease
    /// files, then re-read them and run the startup decision table plus janitor. Does not kill
    /// the iOS process.
    final class RestoreCrashRecoveryTests: XCTestCase {
        private let currentUUID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        private let oldUUID = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
        private let newUUID = UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!
        private let orphanGenerationUUID = UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!
        private let outsidePointerUUID = UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!
        private let exportFlowID = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
        private let restoreFlowID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        private let orphanFlowID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        private let backupFileID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        private let overheadBytes: UInt64 = 256 * 1024 * 1024

        func testDecisionTableExhaustiveForStartupContract() {
            XCTAssertEqual(
                RestoreGenerationSwitcher.decision(intent: nil, pointerUUID: currentUUID),
                .openCurrent
            )
            XCTAssertEqual(
                RestoreGenerationSwitcher.decision(intent: nil, pointerUUID: newUUID),
                .openCurrent
            )

            let prepared = RestoreIntent(
                oldGenerationUUID: oldUUID,
                newGenerationUUID: newUUID,
                phase: .prepared
            )
            XCTAssertEqual(
                RestoreGenerationSwitcher.decision(intent: prepared, pointerUUID: oldUUID),
                .keepOldDiscardCandidate
            )
            XCTAssertEqual(
                RestoreGenerationSwitcher.decision(intent: prepared, pointerUUID: newUUID),
                .verifyNewThenCommit
            )
            XCTAssertEqual(
                RestoreGenerationSwitcher.decision(intent: prepared, pointerUUID: outsidePointerUUID),
                .failClosed
            )

            let switched = RestoreIntent(
                oldGenerationUUID: oldUUID,
                newGenerationUUID: newUUID,
                phase: .switched
            )
            XCTAssertEqual(
                RestoreGenerationSwitcher.decision(intent: switched, pointerUUID: newUUID),
                .verifyNewThenCommit
            )
            XCTAssertEqual(
                RestoreGenerationSwitcher.decision(intent: switched, pointerUUID: outsidePointerUUID),
                .failClosed
            )
            XCTAssertEqual(
                RestoreGenerationSwitcher.decision(intent: switched, pointerUUID: oldUUID),
                .failClosed
            )

            let committed = RestoreIntent(
                oldGenerationUUID: oldUUID,
                newGenerationUUID: newUUID,
                phase: .committed
            )
            let committedWhenNewIsCurrent = RestoreGenerationSwitcher.decision(
                intent: committed,
                pointerUUID: newUUID
            )
            XCTAssertNotEqual(committedWhenNewIsCurrent, .keepOldDiscardCandidate)
            XCTAssertNotEqual(committedWhenNewIsCurrent, .failClosed)
            switch committedWhenNewIsCurrent {
            case .verifyNewThenCommit, .openCurrent:
                break
            case .keepOldDiscardCandidate, .failClosed:
                XCTFail("committed + pointer=new must not read old recovery, got \(committedWhenNewIsCurrent)")
            }

            XCTAssertEqual(
                RestoreGenerationSwitcher.decision(intent: committed, pointerUUID: outsidePointerUUID),
                .failClosed
            )
            XCTAssertEqual(
                RestoreGenerationSwitcher.decision(intent: committed, pointerUUID: oldUUID),
                .failClosed
            )

            XCTAssertNotEqual(
                RestoreGenerationSwitcher.decision(intent: prepared, pointerUUID: newUUID),
                .keepOldDiscardCandidate
            )
            XCTAssertNotEqual(
                RestoreGenerationSwitcher.decision(intent: switched, pointerUUID: newUUID),
                .keepOldDiscardCandidate
            )
            XCTAssertNotEqual(
                RestoreGenerationSwitcher.decision(intent: nil, pointerUUID: newUUID),
                .keepOldDiscardCandidate
            )
        }

        func testJanitorDeletesOrphanLeaseExportCandidateAndStagingWithoutTouchingCurrentOrIntentGenerations()
            throws
        {
            let sandbox = try TemporaryProtectedDirectory()
            let directory = StoreGenerationDirectory(
                rootURL: sandbox.url.appendingPathComponent("app-root", isDirectory: true)
            )
            try directory.prepare()

            try plantGeneration(currentUUID, in: directory, marker: "current")
            try plantGeneration(oldUUID, in: directory, marker: "intent-old")
            try plantGeneration(newUUID, in: directory, marker: "intent-new")
            try plantGeneration(orphanGenerationUUID, in: directory, marker: "orphan-generation")

            let exportBackup = try plantFlowFile(
                flowID: exportFlowID,
                in: directory,
                fileName: opaqueBackupFileName(backupFileID),
                contents: Data([0xFC, 0x42, 0x4B, 0x31])
            )
            let stagingCopy = try plantFlowFile(
                flowID: restoreFlowID,
                in: directory,
                fileName: "staging.fcbackup",
                contents: Data([0x53, 0x54, 0x41, 0x47])
            )
            let orphanLeaseFile = try plantFlowFile(
                flowID: orphanFlowID,
                in: directory,
                fileName: "partial.bin",
                contents: Data([0x00])
            )

            let externalCopy = sandbox.url.appendingPathComponent(
                "FineCoach-Backup-55555555-5555-4555-8555-555555555555.fcbackup"
            )
            try Data([0xEE, 0xFF]).write(to: externalCopy)

            let intent = RestoreIntent(
                oldGenerationUUID: oldUUID,
                newGenerationUUID: newUUID,
                phase: .prepared
            )
            try FileFlowJanitor.cleanupOrphans(
                rootURL: directory.rootURL,
                currentGenerationUUID: currentUUID,
                restoreIntent: intent,
                keepingFlowIDs: []
            )

            XCTAssertTrue(exists(markerURL(currentUUID, in: directory)))
            XCTAssertTrue(exists(markerURL(oldUUID, in: directory)))
            XCTAssertTrue(exists(markerURL(newUUID, in: directory)))
            XCTAssertFalse(exists(markerURL(orphanGenerationUUID, in: directory)))
            XCTAssertFalse(exists(directory.generationURL(for: orphanGenerationUUID)))

            XCTAssertFalse(exists(exportBackup))
            XCTAssertFalse(exists(stagingCopy))
            XCTAssertFalse(exists(orphanLeaseFile))
            XCTAssertFalse(exists(flowDirectory(exportFlowID, in: directory)))
            XCTAssertFalse(exists(flowDirectory(restoreFlowID, in: directory)))
            XCTAssertFalse(exists(flowDirectory(orphanFlowID, in: directory)))
            XCTAssertTrue(exists(externalCopy))
            XCTAssertFalse(externalCopy.path.contains("林青"))
            XCTAssertFalse(externalCopy.path.contains("周宁"))
        }

        func testDiskShortRequiredFreeBytesFormulaAndFakeLimitExceeded() {
            XCTAssertEqual(BackupSecurityCeiling.requiredFreeBytes(plaintextLength: 0), overheadBytes)
            XCTAssertEqual(
                BackupSecurityCeiling.requiredFreeBytes(plaintextLength: 10),
                30 + overheadBytes
            )
            XCTAssertEqual(
                BackupSecurityCeiling.requiredFreeBytes(plaintextLength: 1_048_576),
                3 * 1_048_576 + overheadBytes
            )

            let fake = FakeInsufficientDisk()
            XCTAssertThrowsError(
                try fake.ensureFreeBytes(
                    BackupSecurityCeiling.requiredFreeBytes(plaintextLength: 1_048_576)
                )
            ) { error in
                XCTAssertEqual(error as? BackupError, .limitExceeded)
            }
        }

        func testBeforeExportCallbackLeaseCleanupRemovesTempFcbackupUnderAppFlowDir() throws {
            let sandbox = try TemporaryProtectedDirectory()
            let directory = try makePreparedRoot(in: sandbox)
            try plantGeneration(currentUUID, in: directory, marker: "current")

            let relativePath =
                "flows/\(exportFlowID.uuidString.lowercased())/\(opaqueBackupFileName(backupFileID))"
            let lease = FileFlowLease(
                flowID: exportFlowID,
                kind: .backupExport,
                phase: "handedToSystem",
                managedRelativePaths: [relativePath],
                byteBudget: 1_048_576
            )
            assertLeaseOmitsExternalURLBookmarkAndStudentData(lease)

            let tempBackup = try plantFlowFile(
                flowID: exportFlowID,
                in: directory,
                fileName: opaqueBackupFileName(backupFileID),
                contents: Data([0xFC, 0x42, 0x4B, 0x31])
            )
            XCTAssertTrue(exists(tempBackup))
            XCTAssertFalse(tempBackup.lastPathComponent.contains("林青"))
            XCTAssertFalse(tempBackup.path.contains("file:"))

            try FileFlowJanitor.cleanupOrphans(
                rootURL: directory.rootURL,
                currentGenerationUUID: currentUUID,
                restoreIntent: nil,
                keepingFlowIDs: [exportFlowID]
            )
            XCTAssertTrue(exists(tempBackup), "active in-process lease must keep the export candidate")

            try FileFlowJanitor.cleanupOrphans(
                rootURL: directory.rootURL,
                currentGenerationUUID: currentUUID,
                restoreIntent: nil,
                keepingFlowIDs: []
            )
            XCTAssertFalse(exists(tempBackup))
            XCTAssertFalse(exists(flowDirectory(exportFlowID, in: directory)))
            XCTAssertTrue(exists(markerURL(currentUUID, in: directory)))
        }

        func testExclusiveLeaseRejectsSecondFlowUntilReleased() throws {
            let sandbox = try TemporaryProtectedDirectory()
            let directory = try makePreparedRoot(in: sandbox)
            try plantGeneration(currentUUID, in: directory, marker: "current")
            let first = FileFlowLease(
                flowID: exportFlowID,
                kind: .backupExport,
                phase: "writingCandidate",
                managedRelativePaths: ["flows/\(exportFlowID.uuidString.lowercased())/candidate.fcbackup"],
                byteBudget: 1024
            )
            try FileFlowLeaseStore.acquire(first, in: directory)
            let second = FileFlowLease(
                flowID: restoreFlowID,
                kind: .restoreImport,
                phase: "staging",
                managedRelativePaths: ["flows/\(restoreFlowID.uuidString.lowercased())/staging.fcbackup"],
                byteBudget: 2048
            )
            XCTAssertThrowsError(try FileFlowLeaseStore.acquire(second, in: directory)) { error in
                XCTAssertEqual(error as? BackupError, .invalidState)
            }
            try FileFlowLeaseStore.release(in: directory)
            try FileFlowLeaseStore.acquire(second, in: directory)
            try FileFlowLeaseStore.release(in: directory)
        }

        func testKeepOldDiscardClearsIntentThenJanitorRemovesCandidate() throws {
            let sandbox = try TemporaryProtectedDirectory()
            let directory = try makePreparedRoot(in: sandbox)
            try plantGeneration(currentUUID, in: directory, marker: "current")
            try plantGeneration(newUUID, in: directory, marker: "candidate")
            try writePointer(currentUUID, in: directory)
            try writeIntent(
                RestoreIntent(
                    oldGenerationUUID: currentUUID,
                    newGenerationUUID: newUUID,
                    phase: .prepared
                ),
                to: directory
            )
            let relaunch = try simulateRelaunch(directory: directory)
            XCTAssertEqual(relaunch.decision, .keepOldDiscardCandidate)
            try RestoreGenerationSwitcher.clearIntent(in: directory)
            try FileFlowJanitor.cleanupOrphans(
                rootURL: directory.rootURL,
                currentGenerationUUID: currentUUID,
                restoreIntent: nil,
                keepingFlowIDs: []
            )
            XCTAssertTrue(exists(markerURL(currentUUID, in: directory)))
            XCTAssertFalse(exists(markerURL(newUUID, in: directory)))
        }

        func testAfterStagingBeforeIntentDiscardsUnreferencedCandidateAndStaging() throws {
            let sandbox = try TemporaryProtectedDirectory()
            let directory = try makePreparedRoot(in: sandbox)
            try plantGeneration(currentUUID, in: directory, marker: "current")
            try plantGeneration(newUUID, in: directory, marker: "uncommitted-candidate")
            try writePointer(currentUUID, in: directory)

            let staging = try plantFlowFile(
                flowID: restoreFlowID,
                in: directory,
                fileName: "staging.fcbackup",
                contents: Data([0x53, 0x54, 0x41, 0x47])
            )
            let relaunch = try simulateRelaunch(directory: directory)
            XCTAssertNil(relaunch.intent)
            XCTAssertEqual(relaunch.decision, .openCurrent)
            XCTAssertEqual(relaunch.pointer, currentUUID)

            try FileFlowJanitor.cleanupOrphans(
                rootURL: directory.rootURL,
                currentGenerationUUID: relaunch.pointer,
                restoreIntent: relaunch.intent,
                keepingFlowIDs: []
            )

            XCTAssertTrue(exists(markerURL(currentUUID, in: directory)))
            XCTAssertFalse(exists(markerURL(newUUID, in: directory)))
            XCTAssertFalse(exists(directory.generationURL(for: newUUID)))
            XCTAssertFalse(exists(staging))
            XCTAssertFalse(exists(flowDirectory(restoreFlowID, in: directory)))
        }

        func testPreparedSwitchedCommittedIntentKeepsPairedGenerationsOnRelaunch() throws {
            let cases: [(RestoreIntentPhase, UUID, RestoreStartupDecision)] = [
                (.prepared, oldUUID, .keepOldDiscardCandidate),
                (.prepared, newUUID, .verifyNewThenCommit),
                (.switched, newUUID, .verifyNewThenCommit),
                (.committed, newUUID, .verifyNewThenCommit),
            ]

            for (phase, pointer, expected) in cases {
                let sandbox = try TemporaryProtectedDirectory()
                let directory = try makePreparedRoot(in: sandbox)
                try plantGeneration(oldUUID, in: directory, marker: "intent-old")
                try plantGeneration(newUUID, in: directory, marker: "intent-new")
                try plantGeneration(orphanGenerationUUID, in: directory, marker: "orphan")
                try plantOldRecovery(in: directory)
                try writePointer(pointer, in: directory)
                let intent = RestoreIntent(
                    oldGenerationUUID: oldUUID,
                    newGenerationUUID: newUUID,
                    phase: phase
                )
                try writeIntent(intent, to: directory)

                let relaunch = try simulateRelaunch(directory: directory)
                XCTAssertEqual(relaunch.intent, intent)
                if phase == .committed, pointer == newUUID {
                    XCTAssertNotEqual(relaunch.decision, .keepOldDiscardCandidate)
                    XCTAssertNotEqual(relaunch.decision, .failClosed)
                    if relaunch.decision != expected {
                        XCTAssertEqual(relaunch.decision, .openCurrent)
                    }
                } else {
                    XCTAssertEqual(relaunch.decision, expected)
                }
                if pointer == newUUID {
                    XCTAssertNotEqual(relaunch.decision, .keepOldDiscardCandidate)
                }

                try FileFlowJanitor.cleanupOrphans(
                    rootURL: directory.rootURL,
                    currentGenerationUUID: pointer,
                    restoreIntent: relaunch.intent,
                    keepingFlowIDs: []
                )
                XCTAssertTrue(exists(markerURL(oldUUID, in: directory)))
                XCTAssertTrue(exists(markerURL(newUUID, in: directory)))
                XCTAssertFalse(exists(markerURL(orphanGenerationUUID, in: directory)))
                XCTAssertTrue(exists(oldRecoveryURL(in: directory)))
            }
        }

        func testPointerOutsidePairFailsClosedWithoutOpeningOldRecovery() throws {
            let sandbox = try TemporaryProtectedDirectory()
            let directory = try makePreparedRoot(in: sandbox)
            try plantGeneration(oldUUID, in: directory, marker: "intent-old")
            try plantGeneration(newUUID, in: directory, marker: "intent-new")
            try plantOldRecovery(in: directory)
            try writePointer(outsidePointerUUID, in: directory)
            let intent = RestoreIntent(
                oldGenerationUUID: oldUUID,
                newGenerationUUID: newUUID,
                phase: .prepared
            )
            try writeIntent(intent, to: directory)

            let relaunch = try simulateRelaunch(directory: directory)
            XCTAssertEqual(relaunch.decision, .failClosed)
            XCTAssertNotEqual(relaunch.decision, .keepOldDiscardCandidate)
            XCTAssertNotEqual(relaunch.decision, .openCurrent)
            XCTAssertNotEqual(relaunch.decision, .verifyNewThenCommit)

            try FileFlowJanitor.cleanupOrphans(
                rootURL: directory.rootURL,
                currentGenerationUUID: outsidePointerUUID,
                restoreIntent: relaunch.intent,
                keepingFlowIDs: []
            )
            XCTAssertTrue(exists(markerURL(oldUUID, in: directory)))
            XCTAssertTrue(exists(markerURL(newUUID, in: directory)))
            XCTAssertTrue(exists(oldRecoveryURL(in: directory)))
        }

        func testAttributeResetReappliesBackupExclusionOnKeptGenerations() throws {
            let sandbox = try TemporaryProtectedDirectory()
            let directory = try makePreparedRoot(in: sandbox)
            try plantGeneration(currentUUID, in: directory, marker: "current")
            try plantGeneration(oldUUID, in: directory, marker: "intent-old")
            try plantGeneration(newUUID, in: directory, marker: "intent-new")
            try writePointer(oldUUID, in: directory)
            let intent = RestoreIntent(
                oldGenerationUUID: oldUUID,
                newGenerationUUID: newUUID,
                phase: .prepared
            )
            try writeIntent(intent, to: directory)

            try clearBackupExclusion(at: directory.generationURL(for: currentUUID))
            try clearBackupExclusion(at: directory.generationURL(for: oldUUID))
            try clearBackupExclusion(at: directory.generationURL(for: newUUID))
            try clearBackupExclusion(at: directory.currentPointerURL)
            try clearBackupExclusion(at: directory.restoreIntentURL)

            try FileFlowJanitor.cleanupOrphans(
                rootURL: directory.rootURL,
                currentGenerationUUID: currentUUID,
                restoreIntent: intent,
                keepingFlowIDs: []
            )

            let store = ProtectedFileStore()
            XCTAssertTrue(try store.audit(url: directory.generationURL(for: currentUUID)).isExcludedFromBackup)
            XCTAssertTrue(try store.audit(url: directory.generationURL(for: oldUUID)).isExcludedFromBackup)
            XCTAssertTrue(try store.audit(url: directory.generationURL(for: newUUID)).isExcludedFromBackup)
            XCTAssertTrue(try store.audit(url: directory.currentPointerURL).isExcludedFromBackup)
            XCTAssertTrue(try store.audit(url: directory.restoreIntentURL).isExcludedFromBackup)
            XCTAssertTrue(exists(markerURL(currentUUID, in: directory)))
            XCTAssertTrue(exists(markerURL(oldUUID, in: directory)))
            XCTAssertTrue(exists(markerURL(newUUID, in: directory)))
        }

        private struct RelaunchState {
            let pointer: UUID
            let intent: RestoreIntent?
            let decision: RestoreStartupDecision
        }

        private struct FakeInsufficientDisk {
            func ensureFreeBytes(_ required: UInt64) throws {
                _ = required
                throw BackupError.limitExceeded
            }
        }

        private func makePreparedRoot(in sandbox: TemporaryProtectedDirectory) throws -> StoreGenerationDirectory {
            let directory = StoreGenerationDirectory(
                rootURL: sandbox.url.appendingPathComponent("app-root", isDirectory: true)
            )
            try directory.prepare()
            return directory
        }

        private func simulateRelaunch(directory: StoreGenerationDirectory) throws -> RelaunchState {
            let pointer = try XCTUnwrap(
                CurrentGenerationPointerStore(url: directory.currentPointerURL).read()?.generationUUID
            )
            let intent = try readIntent(from: directory)
            let decision = RestoreGenerationSwitcher.decision(intent: intent, pointerUUID: pointer)
            return RelaunchState(pointer: pointer, intent: intent, decision: decision)
        }

        private func writePointer(_ generationUUID: UUID, in directory: StoreGenerationDirectory) throws {
            try CurrentGenerationPointerStore(url: directory.currentPointerURL).replace(
                with: CurrentGenerationPointer(generationUUID: generationUUID)
            )
        }

        private func writeIntent(_ intent: RestoreIntent, to directory: StoreGenerationDirectory) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try ProtectedFileStore().atomicReplace(
                data: encoder.encode(intent),
                at: directory.restoreIntentURL,
                policy: .business
            )
        }

        private func readIntent(from directory: StoreGenerationDirectory) throws -> RestoreIntent? {
            let url = directory.restoreIntentURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            return try JSONDecoder().decode(RestoreIntent.self, from: Data(contentsOf: url))
        }

        private func plantGeneration(
            _ generationUUID: UUID,
            in directory: StoreGenerationDirectory,
            marker: String
        ) throws {
            let url = directory.generationURL(for: generationUUID)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(marker.utf8).write(to: markerURL(generationUUID, in: directory))
        }

        private func plantOldRecovery(in directory: StoreGenerationDirectory) throws {
            try Data(#"{"schemaID":"active-session-recovery-v1"}"#.utf8).write(
                to: oldRecoveryURL(in: directory)
            )
        }

        @discardableResult
        private func plantFlowFile(
            flowID: UUID,
            in directory: StoreGenerationDirectory,
            fileName: String,
            contents: Data
        ) throws -> URL {
            let flowURL = flowDirectory(flowID, in: directory)
            try FileManager.default.createDirectory(at: flowURL, withIntermediateDirectories: true)
            let fileURL = flowURL.appendingPathComponent(fileName, isDirectory: false)
            try contents.write(to: fileURL)
            return fileURL
        }

        private func flowDirectory(_ flowID: UUID, in directory: StoreGenerationDirectory) -> URL {
            directory.flowURL.appendingPathComponent(flowID.uuidString.lowercased(), isDirectory: true)
        }

        private func markerURL(_ generationUUID: UUID, in directory: StoreGenerationDirectory) -> URL {
            directory.generationURL(for: generationUUID).appendingPathComponent("keep-marker.txt")
        }

        private func oldRecoveryURL(in directory: StoreGenerationDirectory) -> URL {
            directory.generationURL(for: oldUUID).appendingPathComponent("active-session-recovery-v1.json")
        }

        private func opaqueBackupFileName(_ fileID: UUID) -> String {
            "FineCoach-Backup-\(fileID.uuidString.lowercased()).fcbackup"
        }

        private func exists(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.path)
        }

        private func clearBackupExclusion(at url: URL) throws {
            var mutableURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = false
            try mutableURL.setResourceValues(values)
        }

        private func assertLeaseOmitsExternalURLBookmarkAndStudentData(_ lease: FileFlowLease) {
            XCTAssertEqual(lease.kind, .backupExport)
            XCTAssertFalse(lease.phase.contains("://"))
            for path in lease.managedRelativePaths {
                XCTAssertFalse(path.hasPrefix("/"), "managed paths must be relative: \(path)")
                XCTAssertFalse(path.contains("://"))
                XCTAssertFalse(path.contains("file:"))
                XCTAssertFalse(path.lowercased().contains("bookmark"))
                XCTAssertFalse(path.contains("林青"))
                XCTAssertFalse(path.contains("周宁"))
                XCTAssertFalse(path.contains(FictitiousFixtures.student.id.uuidString))
                XCTAssertFalse(path.contains(FictitiousFixtures.student.displayName))
            }
            for child in Mirror(reflecting: lease).children {
                XCTAssertFalse(child.value is URL)
                let description = String(describing: child.value)
                XCTAssertFalse(description.contains("林青"))
                XCTAssertFalse(description.contains("file://"))
            }
        }
    }
#else
    import FineCoach
    import XCTest

    final class RestoreCrashRecoveryTests: XCTestCase {
        func testReleaseKeepsRestoreDecisionSurfaceWithoutProcessKill() {
            XCTAssertEqual(FileFlowKind.backupExport.rawValue, "backupExport")
            XCTAssertEqual(FileFlowKind.restoreImport.rawValue, "restoreImport")
            XCTAssertEqual(RestoreIntentPhase.prepared.rawValue, "prepared")
            XCTAssertEqual(RestoreIntentPhase.switched.rawValue, "switched")
            XCTAssertEqual(RestoreIntentPhase.committed.rawValue, "committed")
            let pointer = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
            XCTAssertEqual(
                RestoreGenerationSwitcher.decision(intent: nil, pointerUUID: pointer),
                .openCurrent
            )
        }
    }
#endif
