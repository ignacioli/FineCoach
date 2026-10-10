#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// T037 (US1, AC-005, D-006): the export through a real on-disk Core Data store, the real file
    /// codec and a real temporary directory. Only the system share sheet is scripted. All data is
    /// fictional.
    final class ArchiveExportIntegrationTests: XCTestCase {
        private typealias X = ArchiveExportFixtures
        private let password = "长度足够的口令abc"

        private struct Harness {
            let store: X.Store
            let tempRoot: TemporaryProtectedDirectory
            let share: ScriptedSharePresenter
            let useCases: ArchiveExportUseCases

            var tempFiles: [String] {
                (FileManager.default.enumerator(atPath: tempRoot.url.path)?.allObjects as? [String]) ?? []
            }
        }

        private func makeHarness(outcomes: [SystemShareOutcome], archived: Bool = false) async throws -> Harness {
            let store = try X.Store(inMemory: false)
            try await X.seed(store, archived: archived)
            let tempRoot = try TemporaryProtectedDirectory()
            let share = ScriptedSharePresenter(outcomes)
            let calendar = TestCalendarProvider(timeZone: X.shanghai)
            let useCases = ArchiveExportUseCases(
                sourceReader: ArchiveExportSourceReader(writer: store.writer, calendarProvider: calendar),
                identity: ArchiveIdentityService(writer: store.writer),
                share: SystemShareAdapter(presenter: share),
                tempRootURL: tempRoot.url,
                clock: TestClock(utcDate: X.now),
                calendarProvider: calendar,
                logger: RecordingLogger()
            )
            return Harness(store: store, tempRoot: tempRoot, share: share, useCases: useCases)
        }

        private func generate(_ flow: ArchiveExportFlow) async throws {
            _ = try await flow.preview()
            try await flow.confirmPreview()
            try await flow.confirmFacts()
            let state = try await flow.submitPassword(password, confirmation: password)
            XCTAssertEqual(state, .generated)
        }

        private func inventory(_ store: X.Store) async throws -> BackupInventory {
            try await store.writer.read { try BackupInventoryMapper.collect(in: $0) }
        }

        private func nonArchive(_ inventory: BackupInventory) -> BackupInventory {
            var copy = inventory
            copy.settings = copy.settings.filter { !$0.key.hasPrefix("archive.") }
            return copy
        }

        func testExportedArchiveDecodesFieldEqualToThePolicySnapshot() async throws {
            let h = try await makeHarness(outcomes: [.completed])
            let flow = try await h.useCases.beginFlow(studentID: X.studentID)
            try await generate(flow)
            let generated = await flow.generatedSnapshot
            let snapshot = try XCTUnwrap(generated)
            let state = try await flow.deliver()
            XCTAssertEqual(state, .handedToSystem)

            let file = try XCTUnwrap(h.share.presentedData.first ?? nil)
            let decoded = try ArchiveFileCodec.decode(file: file, password: try ArchivePassword(importing: password))
            XCTAssertEqual(decoded, snapshot)

            // The same selection through the policy gives the same snapshot (identity is now stored).
            let source = try await ArchiveExportSourceReader(
                writer: h.store.writer, calendarProvider: TestCalendarProvider(timeZone: X.shanghai)
            ).read(studentID: X.studentID)
            let identity = try await ArchiveIdentityService(writer: h.store.writer).ensureIdentity(forStudent: X.studentID)
            let expected = try ArchiveExportPolicy.makeSnapshot(
                source: source, selection: ArchiveModuleSelection(availability: source.availability),
                identity: identity, now: X.now)
            XCTAssertEqual(decoded, expected)
            XCTAssertEqual(decoded.manifest.sourceID, identity.sourceID)
            XCTAssertEqual(h.share.presentedURLs.first?.lastPathComponent, "FineCoach-档案-20261009-1600.fcarchive")
        }

        func testTemporaryDirectoryIsEmptyAfterCompletedCancelledFailedAndLeave() async throws {
            for outcome in [SystemShareOutcome.completed, .cancelled, .failed] {
                let h = try await makeHarness(outcomes: [outcome])
                let flow = try await h.useCases.beginFlow(studentID: X.studentID)
                try await generate(flow)
                XCTAssertEqual(h.tempFiles.filter { $0.hasSuffix(".fcarchive") }.count, 1)
                _ = try await flow.deliver()
                XCTAssertEqual(h.tempFiles, [], "after \(outcome)")
            }
            let h = try await makeHarness(outcomes: [])
            let flow = try await h.useCases.beginFlow(studentID: X.studentID)
            try await generate(flow)
            await flow.leave()
            XCTAssertEqual(h.tempFiles, [], "after leaving")
        }

        func testRetryAfterCancelAndFailureRegeneratesADecodableArchive() async throws {
            let h = try await makeHarness(outcomes: [.cancelled, .failed, .completed])
            let flow = try await h.useCases.beginFlow(studentID: X.studentID)
            try await generate(flow)
            let generated = await flow.generatedSnapshot
            let snapshot = try XCTUnwrap(generated)
            for expected in [ArchiveExportFlowState.cancelled, .failed] {
                let state = try await flow.deliver()
                XCTAssertEqual(state, expected)
                XCTAssertEqual(h.tempFiles, [])
                let retried = try await flow.retry()
                XCTAssertEqual(retried, .generated)
            }
            let done = try await flow.deliver()
            XCTAssertEqual(done, .handedToSystem)
            XCTAssertEqual(h.share.presentedData.count, 3)
            for data in h.share.presentedData {
                let decoded = try ArchiveFileCodec.decode(
                    file: try XCTUnwrap(data), password: try ArchivePassword(importing: password))
                XCTAssertEqual(decoded, snapshot)
            }
            XCTAssertEqual(h.tempFiles, [])
        }

        func testExportChangesNoCoachDataExceptFirstTimeIdentitySettings() async throws {
            let h = try await makeHarness(outcomes: [.completed, .completed])
            let before = try await inventory(h.store)
            XCTAssertTrue(before.settings.allSatisfy { !$0.key.hasPrefix("archive.") })

            let flow = try await h.useCases.beginFlow(studentID: X.studentID)
            try await generate(flow)
            _ = try await flow.deliver()
            let after = try await inventory(h.store)
            XCTAssertEqual(nonArchive(after), before)
            let added = Set(after.settings.map(\.key)).subtracting(before.settings.map(\.key))
            XCTAssertEqual(
                added, ["archive.sourceID", StudentManagedObjectMapping.archiveStudentIDKey(for: X.studentID.rawValue)])

            // A second export reuses the identities and changes nothing at all.
            let second = try await h.useCases.beginFlow(studentID: X.studentID)
            try await generate(second)
            _ = try await second.deliver()
            let afterSecond = try await inventory(h.store)
            XCTAssertEqual(afterSecond, after)
        }

        func testNoPlaintextInTheTemporaryDirectoryOrTheHandedOverFile() async throws {
            let h = try await makeHarness(outcomes: [.cancelled])
            let flow = try await h.useCases.beginFlow(studentID: X.studentID)
            try await generate(flow)
            let marker = X.summaries + [X.studentName, X.customExerciseName, X.builtInName, "FCPA-plain", "sourceID"]
            let urls = (FileManager.default.enumerator(at: h.tempRoot.url, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
            let files = urls.filter { $0.hasDirectoryPath == false }
            XCTAssertEqual(files.count, 1)
            for url in files {
                let data = try Data(contentsOf: url)
                XCTAssertEqual(data.prefix(4), Data("FCPA".utf8))
                for value in marker + X.excludedValues {
                    XCTAssertNil(data.range(of: Data(value.utf8)), "plaintext \(value) found in temp file")
                }
                XCTAssertNil(data.range(of: Data(password.utf8)), "password found in temp file")
                XCTAssertFalse(url.lastPathComponent.contains(X.studentName))
            }
            _ = try await flow.deliver()
            XCTAssertEqual(h.tempFiles, [])
        }

        func testArchivedStudentCanBeExportedWithoutChangingArchiveStateOrData() async throws {
            let h = try await makeHarness(outcomes: [.completed], archived: true)
            let before = try await inventory(h.store)
            XCTAssertEqual(before.students.first?.lifecycle, .archived)

            let flow = try await h.useCases.beginFlow(studentID: X.studentID)
            try await generate(flow)
            let state = try await flow.deliver()
            XCTAssertEqual(state, .handedToSystem)

            let file = try XCTUnwrap(h.share.presentedData.first ?? nil)
            let decoded = try ArchiveFileCodec.decode(file: file, password: try ArchivePassword(importing: password))
            XCTAssertEqual(decoded.sessions.count, 2)
            let after = try await inventory(h.store)
            XCTAssertEqual(after.students.first?.lifecycle, .archived)
            XCTAssertEqual(nonArchive(after), before)
        }
    }
#endif
