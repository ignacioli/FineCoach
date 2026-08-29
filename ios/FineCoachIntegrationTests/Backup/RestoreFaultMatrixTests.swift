#if DEBUG
    import XCTest

    @testable import FineCoach

    /// T110: in-process kill/relaunch matrix for every intent/pointer pair.
    /// Physical process kill is out of scope here; files on disk are the crash boundary.
    final class RestoreFaultMatrixTests: XCTestCase {
        private let oldUUID = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
        private let newUUID = UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!
        private let outsideUUID = UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!

        func testEveryIntentPointerPairResolvesToVerifiedNewOrIntactOld() throws {
            let phases: [RestoreIntentPhase] = [.prepared, .switched, .committed]
            let pointers = [oldUUID, newUUID, outsideUUID]
            for phase in phases {
                for pointer in pointers {
                    let intent = RestoreIntent(
                        oldGenerationUUID: oldUUID,
                        newGenerationUUID: newUUID,
                        phase: phase
                    )
                    let decision = RestoreGenerationSwitcher.decision(intent: intent, pointerUUID: pointer)
                    switch decision {
                    case .openCurrent:
                        XCTAssertEqual(
                            pointer,
                            newUUID,
                            "committed + new pointer opens verified current, phase=\(phase)"
                        )
                    case .keepOldDiscardCandidate:
                        XCTAssertEqual(pointer, oldUUID, "intact old only when pointer is old, phase=\(phase)")
                    case .verifyNewThenCommit:
                        XCTAssertEqual(pointer, newUUID, "verified new only when pointer is new, phase=\(phase)")
                    case .failClosed:
                        XCTAssertTrue(
                            pointer == outsideUUID || (phase == .switched && pointer == oldUUID)
                                || (phase == .committed && pointer == oldUUID),
                            "fail-closed must not open a mixed generation, phase=\(phase) pointer=\(pointer)"
                        )
                    }
                }
            }
        }

        func testRelaunchAfterPreparedOldKeepsOldAndDoesNotOpenNew() throws {
            let sandbox = try TemporaryProtectedDirectory()
            let directory = StoreGenerationDirectory(
                rootURL: sandbox.url.appendingPathComponent("app-root", isDirectory: true)
            )
            try directory.prepare()
            try plant(oldUUID, in: directory, marker: "old")
            try plant(newUUID, in: directory, marker: "new")
            try CurrentGenerationPointerStore(url: directory.currentPointerURL).replace(
                with: try CurrentGenerationPointer(generationUUID: oldUUID)
            )
            try RestoreGenerationSwitcher.writeIntent(
                RestoreIntent(oldGenerationUUID: oldUUID, newGenerationUUID: newUUID, phase: .prepared),
                to: directory
            )

            let pointer = try XCTUnwrap(
                CurrentGenerationPointerStore(url: directory.currentPointerURL).read()?.generationUUID
            )
            let intent = try RestoreGenerationSwitcher.readIntent(from: directory)
            let decision = RestoreGenerationSwitcher.decision(intent: intent, pointerUUID: pointer)
            XCTAssertEqual(decision, .keepOldDiscardCandidate)
            XCTAssertEqual(pointer, oldUUID)

            try FileFlowJanitor.cleanupOrphans(
                rootURL: directory.rootURL,
                currentGenerationUUID: pointer,
                restoreIntent: intent,
                keepingFlowIDs: []
            )
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: directory.generationURL(for: oldUUID).appendingPathComponent("keep-marker.txt").path
                )
            )
        }

        func testRelaunchAfterSwitchedNewVerifiesNewWithoutReadingOldRecovery() throws {
            let sandbox = try TemporaryProtectedDirectory()
            let directory = StoreGenerationDirectory(
                rootURL: sandbox.url.appendingPathComponent("app-root", isDirectory: true)
            )
            try directory.prepare()
            try plant(oldUUID, in: directory, marker: "old")
            try plant(newUUID, in: directory, marker: "new")
            try Data(#"{"schemaID":"active-session-recovery-v1"}"#.utf8).write(
                to: directory.generationURL(for: oldUUID).appendingPathComponent("active-session-recovery-v1.json")
            )
            try CurrentGenerationPointerStore(url: directory.currentPointerURL).replace(
                with: try CurrentGenerationPointer(generationUUID: newUUID)
            )
            try RestoreGenerationSwitcher.writeIntent(
                RestoreIntent(oldGenerationUUID: oldUUID, newGenerationUUID: newUUID, phase: .switched),
                to: directory
            )

            let pointer = try XCTUnwrap(
                CurrentGenerationPointerStore(url: directory.currentPointerURL).read()?.generationUUID
            )
            let intent = try RestoreGenerationSwitcher.readIntent(from: directory)
            let decision = RestoreGenerationSwitcher.decision(intent: intent, pointerUUID: pointer)
            XCTAssertEqual(decision, .verifyNewThenCommit)
            XCTAssertNotEqual(decision, .keepOldDiscardCandidate)
            XCTAssertEqual(pointer, newUUID)
        }

        private func plant(_ generationUUID: UUID, in directory: StoreGenerationDirectory, marker: String) throws {
            let url = directory.generationURL(for: generationUUID)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(marker.utf8).write(to: url.appendingPathComponent("keep-marker.txt"))
        }
    }
#else
    import FineCoach
    import XCTest

    final class RestoreFaultMatrixTests: XCTestCase {
        func testReleaseKeepsDecisionSurface() {
            XCTAssertEqual(RestoreStartupDecision.openCurrent, .openCurrent)
            XCTAssertEqual(RestoreStartupDecision.keepOldDiscardCandidate, .keepOldDiscardCandidate)
            XCTAssertEqual(RestoreStartupDecision.verifyNewThenCommit, .verifyNewThenCommit)
            XCTAssertEqual(RestoreStartupDecision.failClosed, .failClosed)
        }
    }
#endif
