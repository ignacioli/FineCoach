import XCTest

@testable import FineCoach

#if DEBUG
    private struct ArchiveStoreFaultInjector: FaultInjector {
        let failing: Set<FaultInjectionPoint>

        func check(_ point: FaultInjectionPoint) throws {
            if failing.contains(point) {
                throw FaultInjectionError.injected(point)
            }
        }
    }
#endif

/// Rule-level tests for the M2 archive domain types (T014), password and replacement policy
/// (T015), the viewer snapshot store (T017), the source short label (T018), the install-state
/// resolver and the open router (T020).
final class ArchiveFoundationTests: XCTestCase {
    private typealias F = ArchiveFixtures

    // MARK: ArchiveModuleSet (T014)

    func testModuleDependenciesTrendsAndExerciseInfoRequireTrainingRecords() throws {
        XCTAssertThrowsError(
            try ArchiveModuleSet(
                displayName: false, sex: false, bodyData: false, trainingRecords: false,
                trends: true, summaries: false, exerciseInfo: false
            )
        ) { XCTAssertEqual($0 as? ArchiveSnapshotError, .moduleDependencyViolation) }
        XCTAssertThrowsError(
            try ArchiveModuleSet(
                displayName: false, sex: false, bodyData: false, trainingRecords: false,
                trends: false, summaries: false, exerciseInfo: true
            )
        ) { XCTAssertEqual($0 as? ArchiveSnapshotError, .moduleDependencyViolation) }
        XCTAssertThrowsError(
            try ArchiveModuleSet(
                displayName: true, sex: true, bodyData: true, trainingRecords: false,
                trends: true, summaries: true, exerciseInfo: true
            )
        )
    }

    func testSummariesAreIndependentOfEveryOtherModule() throws {
        let summariesAlone = try ArchiveModuleSet(
            displayName: false, sex: false, bodyData: false, trainingRecords: false,
            trends: false, summaries: true, exerciseInfo: false
        )
        XCTAssertTrue(summariesAlone.summaries)
        XCTAssertFalse(summariesAlone.trainingRecords)
        XCTAssertNoThrow(
            try ArchiveModuleSet(
                displayName: false, sex: false, bodyData: false, trainingRecords: true,
                trends: false, summaries: false, exerciseInfo: false
            ),
            "training records alone, without trends or exercise info"
        )
        XCTAssertNoThrow(
            try ArchiveModuleSet(
                displayName: true, sex: true, bodyData: true, trainingRecords: true,
                trends: true, summaries: true, exerciseInfo: true
            )
        )
    }

    func testManifestRequiresAtLeastOneModule() throws {
        let none = try ArchiveModuleSet(
            displayName: false, sex: false, bodyData: false, trainingRecords: false,
            trends: false, summaries: false, exerciseInfo: false
        )
        XCTAssertTrue(none.isEmpty)
        XCTAssertThrowsError(
            try ArchiveManifest(
                sourceID: F.sourceID,
                studentArchiveID: F.studentArchiveID,
                snapshotAtUTC: F.snapshotAt,
                modules: none,
                counts: ArchiveCounts(
                    student: 0, exercise: 0, session: 0, summary: 0,
                    bodyMetric: 0, bodyMeasurement: 0, attribution: 0
                )
            )
        ) { XCTAssertEqual($0 as? ArchiveSnapshotError, .noModuleSelected) }
    }

    func testSnapshotLocalEncodingRoundTripsAndPreservesIsAssisted() throws {
        let snapshot = F.fullSnapshot()
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ArchiveSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.exercises.map(\.isAssisted), [false, true, false])
        XCTAssertNoThrow(try decoded.validateIntegrity())
    }

    func testSnapshotTypesCarryNoCoachSideIdentifiers() throws {
        let data = try JSONEncoder().encode(F.fullSnapshot())
        let text = String(decoding: data, as: UTF8.self)
        // The only UUIDs are the two archive identities from the manifest.
        let uuidPattern = try NSRegularExpression(
            pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
        )
        let matches = uuidPattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        XCTAssertEqual(matches.count, 2)
    }

    // MARK: ArchivePassword (T015)

    func testPasswordCreationRequiresAtLeastEightCharacters() throws {
        XCTAssertThrowsError(try ArchivePassword(creating: "")) {
            XCTAssertEqual($0 as? ArchivePasswordError, .tooShort)
        }
        XCTAssertThrowsError(try ArchivePassword(creating: "1234567")) {
            XCTAssertEqual($0 as? ArchivePasswordError, .tooShort)
        }
        XCTAssertNoThrow(try ArchivePassword(creating: "12345678"))
        // Unicode characters, not bytes: 7 CJK characters are 21 bytes but still too short.
        XCTAssertThrowsError(try ArchivePassword(creating: "口令测试甲乙丙"))
        XCTAssertNoThrow(try ArchivePassword(creating: "口令测试甲乙丙丁"))
    }

    func testPasswordIsNeverTruncated() throws {
        let long = String(repeating: "安", count: 500) + "end"
        let password = try ArchivePassword(creating: long)
        XCTAssertEqual(password.utf8, Data(long.precomposedStringWithCanonicalMapping.utf8))
        XCTAssertEqual(password.utf8.count, 500 * 3 + 3)
    }

    func testPasswordSharesTheBackupRuleAndNormalization() throws {
        for raw in ["12345678", "口令测试甲乙丙丁", "e\u{0301}e\u{0301}e\u{0301}e\u{0301}abcd", " 口令测试甲乙丙丁"] {
            XCTAssertEqual(try ArchivePassword(creating: raw).utf8, try BackupPassword(creating: raw).utf8)
        }
        XCTAssertThrowsError(try BackupPassword(creating: "1234567"))
        // Export and import agree on canonical form (decomposed vs composed input).
        XCTAssertEqual(
            try ArchivePassword(importing: "é").utf8,
            try ArchivePassword(importing: "e\u{0301}").utf8
        )
        XCTAssertEqual(
            try ArchivePassword(creating: "caf\u{00E9}1234").utf8,
            try ArchivePassword(importing: "cafe\u{0301}1234").utf8
        )
    }

    func testImportPasswordIsNotLengthChecked() throws {
        XCTAssertNoThrow(try ArchivePassword(importing: "x"))
        XCTAssertTrue(try ArchivePassword(importing: "").utf8.isEmpty)
    }

    // MARK: ArchiveReplacementPolicy (T015)

    private func manifest(
        source: UUID = F.sourceID,
        student: UUID = F.studentArchiveID,
        at date: Date = F.snapshotAt
    ) -> ArchiveManifest {
        F.manifest(
            modules: F.modules(),
            counts: ArchiveCounts(
                student: 0, exercise: 0, session: 0, summary: 0,
                bodyMetric: 0, bodyMeasurement: 0, attribution: 0
            ),
            snapshotAt: date,
            sourceID: source,
            studentArchiveID: student
        )
    }

    func testReplacementPolicyReturnsEachOutcome() {
        let current = manifest()
        let newer = F.snapshotAt.addingTimeInterval(60)
        let older = F.snapshotAt.addingTimeInterval(-60)
        let otherID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!

        XCTAssertEqual(
            ArchiveReplacementPolicy.evaluate(current: current, candidate: manifest(source: otherID, at: newer)),
            .differentSource
        )
        XCTAssertEqual(
            ArchiveReplacementPolicy.evaluate(current: current, candidate: manifest(student: otherID, at: newer)),
            .differentStudent
        )
        XCTAssertEqual(
            ArchiveReplacementPolicy.evaluate(current: current, candidate: manifest(at: older)),
            .notNewer
        )
        XCTAssertEqual(
            ArchiveReplacementPolicy.evaluate(current: current, candidate: manifest(at: F.snapshotAt)),
            .notNewer,
            "equal snapshot time is a duplicate (D-004)"
        )
        XCTAssertEqual(
            ArchiveReplacementPolicy.evaluate(current: current, candidate: manifest(at: newer)),
            .accept
        )
        XCTAssertEqual(
            ArchiveReplacementPolicy.evaluate(
                current: current,
                candidate: manifest(at: F.snapshotAt.addingTimeInterval(0.001))
            ),
            .accept,
            "one millisecond newer is newer"
        )
    }

    func testReplacementPolicyChecksInDocumentedOrder() {
        let current = manifest()
        let otherID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
        let older = F.snapshotAt.addingTimeInterval(-60)
        XCTAssertEqual(
            ArchiveReplacementPolicy.evaluate(
                current: current,
                candidate: manifest(source: otherID, student: otherID, at: older)
            ),
            .differentSource,
            "source is judged before student and age"
        )
        XCTAssertEqual(
            ArchiveReplacementPolicy.evaluate(current: current, candidate: manifest(student: otherID, at: older)),
            .differentStudent,
            "student is judged before age"
        )
    }

    // MARK: ArchiveSnapshotStore (T017)

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(ArchiveSnapshotStore.directoryName, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        return root
    }

    private func entries(_ url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    func testStoreStartsEmptyAndCommitLoadRoundTrips() throws {
        let root = try makeRoot()
        let store = ArchiveSnapshotStore(rootURL: root)
        XCTAssertNil(try store.load())

        let snapshot = F.fullSnapshot()
        try store.commit(snapshot: snapshot)
        XCTAssertEqual(try store.load(), snapshot)
        XCTAssertEqual(entries(root), ["current.json", "generations"])
        XCTAssertEqual(entries(root.appendingPathComponent("generations")).count, 1)

        let pointer =
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: root.appendingPathComponent("current.json"))
            ) as? [String: Any]
        XCTAssertEqual(pointer?["snapshotSchemaVersion"] as? Int, ArchiveSnapshotStore.currentSnapshotSchemaVersion)
        XCTAssertNotNil(UUID(uuidString: pointer?["generation"] as? String ?? ""))
        XCTAssertEqual(Set(pointer?.keys.map { $0 } ?? []), ["generation", "snapshotSchemaVersion"])

        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
        let snapshotFile = root.appendingPathComponent("generations")
            .appendingPathComponent(entries(root.appendingPathComponent("generations"))[0])
            .appendingPathComponent("snapshot.bin")
        XCTAssertEqual(try snapshotFile.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testCommitReplacesGenerationAndKeepsDisplaySettings() throws {
        let root = try makeRoot()
        let store = ArchiveSnapshotStore(rootURL: root)
        try store.commit(snapshot: F.summariesOnlySnapshot())
        let settings = ArchiveDisplaySettings(weightUnit: .lb, lengthUnit: .inch, density: .compact)
        try store.writeDisplaySettings(settings)

        let newer = F.fullSnapshot(snapshotAt: F.snapshotAt.addingTimeInterval(3_600))
        try store.commit(snapshot: newer)

        XCTAssertEqual(try store.load(), newer)
        XCTAssertEqual(entries(root.appendingPathComponent("generations")).count, 1, "old generation deleted")
        XCTAssertEqual(store.readDisplaySettings(), settings, "display settings survive replacement (M2-FR-032)")
    }

    func testDisplaySettingsDefaultsAndRequireAnInstalledArchive() throws {
        let root = try makeRoot()
        let store = ArchiveSnapshotStore(rootURL: root)
        XCTAssertEqual(store.readDisplaySettings(), .defaults)
        XCTAssertEqual(ArchiveDisplaySettings.defaults.weightUnit, .kg)
        XCTAssertEqual(ArchiveDisplaySettings.defaults.lengthUnit, .cm)
        XCTAssertEqual(ArchiveDisplaySettings.defaults.density, .standard)
        XCTAssertThrowsError(try store.writeDisplaySettings(.defaults)) {
            XCTAssertEqual($0 as? ArchiveSnapshotStoreError, .noArchive)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("display-settings.json").path))
    }

    func testDeleteAllRemovesEverythingIncludingDisplaySettings() throws {
        let root = try makeRoot()
        let store = ArchiveSnapshotStore(rootURL: root)
        try store.commit(snapshot: F.fullSnapshot())
        try store.writeDisplaySettings(ArchiveDisplaySettings(weightUnit: .lb))
        try FileManager.default.createDirectory(at: store.stagingURL, withIntermediateDirectories: true)

        try store.deleteAll()

        XCTAssertNil(try store.load())
        XCTAssertEqual(entries(root), [])
        XCTAssertEqual(store.readDisplaySettings(), .defaults)
        XCTAssertNoThrow(try store.deleteAll(), "deleting nothing is not an error")
    }

    func testUnreadableOrNewerSnapshotIsReportedNotSilentlyEmpty() throws {
        let root = try makeRoot()
        let store = ArchiveSnapshotStore(rootURL: root)
        try store.commit(snapshot: F.fullSnapshot())
        let generations = root.appendingPathComponent("generations")
        let generation = generations.appendingPathComponent(entries(generations)[0])
        try Data("{}".utf8).write(to: generation.appendingPathComponent("snapshot.bin"))
        XCTAssertThrowsError(try store.load()) {
            XCTAssertEqual($0 as? ArchiveSnapshotStoreError, .snapshotUnreadable)
        }

        let newerPointer = #"{"generation":"\#(UUID().uuidString)","snapshotSchemaVersion":2}"#
        try Data(newerPointer.utf8).write(to: root.appendingPathComponent("current.json"))
        XCTAssertThrowsError(try store.load()) {
            XCTAssertEqual($0 as? ArchiveSnapshotStoreError, .incompatibleSnapshotSchema)
        }
    }

    func testJanitorClearsStagingAndOrphanGenerationsButKeepsCurrent() throws {
        let root = try makeRoot()
        let store = ArchiveSnapshotStore(rootURL: root)
        let snapshot = F.fullSnapshot()
        try store.commit(snapshot: snapshot)
        let generations = root.appendingPathComponent("generations")
        let orphan = generations.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: orphan.appendingPathComponent("snapshot.bin"))
        try FileManager.default.createDirectory(
            at: generations.appendingPathComponent("not-a-uuid"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store.stagingURL, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: store.stagingURL.appendingPathComponent("partial"))

        try store.runStartupJanitor()

        XCTAssertEqual(entries(generations).count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.stagingURL.path))
        XCTAssertEqual(try store.load(), snapshot)
    }

    func testJanitorWithoutPointerRemovesLeftoversAndDoesNothingOnFreshInstall() throws {
        let root = try makeRoot()
        let store = ArchiveSnapshotStore(rootURL: root)
        XCTAssertNoThrow(try store.runStartupJanitor())
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path), "fresh install stays untouched")

        try store.commit(snapshot: F.fullSnapshot())
        try store.writeDisplaySettings(.defaults)
        try FileManager.default.removeItem(at: root.appendingPathComponent("current.json"))
        try store.runStartupJanitor()
        XCTAssertEqual(entries(root), [])
    }

    // MARK: Short label (T018)

    func testShortLabelIsDeterministicAndMatchesIndependentlyComputedValues() {
        // Expected values computed outside Swift: SHA-256 of the 16 UUID bytes, first four
        // bytes as a big-endian integer, modulo 10000.
        let cases: [(String, String)] = [
            ("11111111-2222-3333-4444-555555555555", "5048"),
            ("00000000-0000-0000-0000-000000000000", "2239"),
            ("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", "3435"),
            ("00000000-0000-0000-0000-000000000014", "0752"),
            ("00000000-0000-0000-0000-000000000221", "0035"),
        ]
        for (raw, expected) in cases {
            let id = UUID(uuidString: raw)!
            XCTAssertEqual(ArchiveIdentityService.shortLabel(forSourceID: id), expected, raw)
            XCTAssertEqual(ArchiveIdentityService.shortLabel(forSourceID: id), expected, "deterministic")
        }
        XCTAssertEqual(ArchiveIdentityService.shortLabel(forSourceID: F.sourceID), "5048")
    }

    func testShortLabelIsAlwaysFourDigits() {
        for index in 0..<200 {
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
            let label = ArchiveIdentityService.shortLabel(forSourceID: id)
            XCTAssertEqual(label.count, 4)
            XCTAssertTrue(label.allSatisfy(\.isNumber))
        }
    }

    // MARK: ArchiveOpenRouter (T020)

    func testOpenRouterMapsEachInstallStateToItsDestination() {
        XCTAssertEqual(ArchiveOpenRouter.destination(for: .unselected), .importPrefilled)
        XCTAssertEqual(ArchiveOpenRouter.destination(for: .viewer), .replacePrefilled)
        XCTAssertEqual(ArchiveOpenRouter.destination(for: .coach), .blocked)
    }

    // MARK: InstallStateResolver (T020)

    private struct StubProbe: CoachInstallProbe {
        let result: Result<CoachInstallSnapshot, Error>

        init(onboarding: Bool = false, workData: Bool = false) {
            result = .success(CoachInstallSnapshot(onboardingCompleted: onboarding, hasWorkData: workData))
        }

        init(failing error: Error) {
            result = .failure(error)
        }

        func read() async throws -> CoachInstallSnapshot {
            try result.get()
        }
    }

    private func resolver(
        root: URL,
        probe: any CoachInstallProbe
    ) -> InstallStateResolver {
        InstallStateResolver(store: ArchiveSnapshotStore(rootURL: root), probe: probe)
    }

    func testResolverReturnsEachOfTheThreeStates() async throws {
        let emptyRoot = try makeRoot()
        let unselected = try await resolver(root: emptyRoot, probe: StubProbe()).resolve()
        XCTAssertEqual(unselected, .unselected)

        let coachByWork = try await resolver(root: emptyRoot, probe: StubProbe(workData: true)).resolve()
        XCTAssertEqual(coachByWork, .coach)
        let coachByMarker = try await resolver(root: emptyRoot, probe: StubProbe(onboarding: true)).resolve()
        XCTAssertEqual(coachByMarker, .coach)

        let viewerRoot = try makeRoot()
        try ArchiveSnapshotStore(rootURL: viewerRoot).commit(snapshot: F.fullSnapshot())
        let viewer = try await resolver(root: viewerRoot, probe: StubProbe()).resolve()
        XCTAssertEqual(viewer, .viewer)
    }

    func testViewerWinsWhenThePointerAndCoachDataBothExist() async throws {
        let root = try makeRoot()
        try ArchiveSnapshotStore(rootURL: root).commit(snapshot: F.fullSnapshot())
        let state = try await resolver(root: root, probe: StubProbe(onboarding: true, workData: true)).resolve()
        XCTAssertEqual(state, .viewer)
        // The viewer answer does not depend on the Coach store being readable.
        let unreadable = try await resolver(
            root: root,
            probe: StubProbe(failing: PersistenceControllerError.storeLoadFailed)
        ).resolve()
        XCTAssertEqual(unreadable, .viewer)
    }

    func testViewerPrecedenceEventIsAFixedIDWithoutUserData() {
        XCTAssertEqual(AppLogEvent.archiveInstallViewerPrecedence.rawValue, "archive.viewer_precedence")
    }

    func testUnreadableOrNewerSnapshotPointerIsNotViewer() async throws {
        let root = try makeRoot()
        let store = ArchiveSnapshotStore(rootURL: root)
        try store.commit(snapshot: F.fullSnapshot())
        let generations = root.appendingPathComponent("generations")
        let generation = generations.appendingPathComponent(entries(generations)[0])
        try Data("{}".utf8).write(to: generation.appendingPathComponent("snapshot.bin"))
        // Coach data present: unreadable viewer data is "not viewer" and the Coach side wins.
        let unreadableWithCoach = try await resolver(root: root, probe: StubProbe(workData: true)).resolve()
        XCTAssertEqual(unreadableWithCoach, .coach)
        // Empty Coach store: fail closed instead of offering a first import (privacy review F2).
        do {
            _ = try await resolver(root: root, probe: StubProbe()).resolve()
            XCTFail("an unreadable viewer snapshot with an empty Coach store must not resolve to unselected")
        } catch {
            XCTAssertEqual(error as? ArchiveSnapshotStoreError, .snapshotUnreadable)
        }

        let newerPointer = #"{"generation":"\#(UUID().uuidString)","snapshotSchemaVersion":2}"#
        try Data(newerPointer.utf8).write(to: root.appendingPathComponent("current.json"))
        let newer = try await resolver(root: root, probe: StubProbe(workData: true)).resolve()
        XCTAssertEqual(newer, .coach)
    }

    func testNewerSchemaPointerWithAnEmptyCoachStoreThrowsInsteadOfUnselected() async throws {
        let root = try makeRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let newerPointer = #"{"generation":"\#(UUID().uuidString)","snapshotSchemaVersion":2}"#
        try Data(newerPointer.utf8).write(to: root.appendingPathComponent("current.json"))
        do {
            _ = try await resolver(root: root, probe: StubProbe()).resolve()
            XCTFail("a newer-schema pointer must not resolve to unselected")
        } catch {
            XCTAssertEqual(error as? ArchiveSnapshotStoreError, .incompatibleSnapshotSchema)
        }
    }

    // MARK: Inbox sweep (privacy review F1)

    func testInboxSweepDeletesEveryEntryExceptTheInFlightOneAndNeverTouchesOutsideFiles() throws {
        let base = try makeRoot()
        let inbox = base.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let archive = inbox.appendingPathComponent("a.fcarchive")
        let backup = inbox.appendingPathComponent("b.fcbackup")
        let stray = inbox.appendingPathComponent("stray.txt")
        let inFlight = inbox.appendingPathComponent("inflight.fcarchive")
        let sibling = base.appendingPathComponent("outside.fcarchive")
        for url in [archive, backup, stray, inFlight, sibling] {
            try Data("x".utf8).write(to: url)
        }

        let removed = ArchiveImportUseCases.sweepInbox(inboxRoot: inbox, keeping: [inFlight])
        XCTAssertEqual(removed, 3)
        XCTAssertEqual(entries(inbox), ["inflight.fcarchive"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path), "files outside Inbox are untouched")

        XCTAssertEqual(ArchiveImportUseCases.sweepInbox(inboxRoot: inbox), 1)
        XCTAssertEqual(entries(inbox), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: inbox.path), "the Inbox itself stays")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
    }

    func testDiscardInboxCopyRefusesOutsideFilesAndTheInboxRoot() throws {
        let base = try makeRoot()
        let inbox = base.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let outside = base.appendingPathComponent("outside.fcbackup")
        try Data("x".utf8).write(to: outside)
        XCTAssertFalse(ArchiveImportUseCases.discardInboxCopy(at: outside, inboxRoot: inbox))
        XCTAssertFalse(ArchiveImportUseCases.discardInboxCopy(at: inbox, inboxRoot: inbox))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: inbox.path))
        let inside = inbox.appendingPathComponent("x.fcbackup")
        try Data("x".utf8).write(to: inside)
        XCTAssertTrue(ArchiveImportUseCases.discardInboxCopy(at: inside, inboxRoot: inbox))
    }

    // MARK: snapshot.bin protection (privacy review F3)

    func testCommittedSnapshotFileIsProtectedAndExcludedFromBackup() throws {
        let root = try makeRoot()
        let store = ArchiveSnapshotStore(rootURL: root)
        try store.commit(snapshot: F.fullSnapshot())
        let generations = root.appendingPathComponent("generations")
        let file = generations.appendingPathComponent(entries(generations)[0]).appendingPathComponent("snapshot.bin")
        let audit = try ProtectedFileStore().audit(url: file)
        XCTAssertTrue(audit.isExcludedFromBackup)
        #if !targetEnvironment(simulator)
            XCTAssertEqual(audit.protectionRawValue, FileProtectionType.completeUnlessOpen.rawValue)
        #endif
    }

    func testUnreadableCoachStoreWithoutViewerThrowsInsteadOfGuessingUnselected() async throws {
        let root = try makeRoot()
        do {
            _ = try await resolver(root: root, probe: StubProbe(failing: PersistenceControllerError.storeLoadFailed))
                .resolve()
            XCTFail("a Coach store that cannot be read must not resolve to a state")
        } catch {
            XCTAssertEqual(error as? PersistenceControllerError, .storeLoadFailed)
        }
    }

    // Real Core Data counts: these cases are about what counts as Coach work data.

    private func makeCoachStore() throws -> PersistenceController {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallStateTests-\(UUID().uuidString).sqlite")
        return try PersistenceController(storeURL: url, inMemory: true)
    }

    private func resolveWithRealCounts(_ controller: PersistenceController) async throws -> InstallState {
        try await resolver(root: try makeRoot(), probe: CoreDataCoachInstallProbe(writer: controller.writer))
            .resolve()
    }

    func testEmptyCoachStoreResolvesToUnselected() async throws {
        let controller = try makeCoachStore()
        let state = try await resolveWithRealCounts(controller)
        XCTAssertEqual(state, .unselected)
    }

    func testOnlyOneArchivedStudentResolvesToCoach() async throws {
        let controller = try makeCoachStore()
        let repository = CoreDataStudentRepository(writer: controller.writer)
        let useCases = StudentUseCases(
            repository: repository,
            clock: TestClock(),
            ids: TestIDGenerator(ids: [UUID(uuidString: "a0000000-0000-4000-8000-000000000001")!])
        )
        let student = try await useCases.create(draft: StudentDraft(displayName: "林青", sex: .female))
        _ = try await useCases.archive(id: student.id)
        let active = try await useCases.searchActive(query: "")
        XCTAssertTrue(active.isEmpty, "the only student is archived")

        let state = try await resolveWithRealCounts(controller)
        XCTAssertEqual(state, .coach)
    }

    func testOnlyTheBuiltInExerciseLibraryResolvesToUnselected() async throws {
        let controller = try makeCoachStore()
        let exercises = ExerciseLibraryUseCases(
            repository: CoreDataExerciseRepository(writer: controller.writer),
            clock: TestClock(),
            ids: TestIDGenerator(ids: [])
        )
        try await exercises.seedIfNeeded()
        let library = try await exercises.search(query: "")
        XCTAssertFalse(library.isEmpty, "the built-in library is seeded")

        let state = try await resolveWithRealCounts(controller)
        XCTAssertEqual(state, .unselected)
    }

    func testM1UpgradeWithOnboardingCompletedAndNoStudentsResolvesToCoach() async throws {
        let controller = try makeCoachStore()
        let repository = CoreDataStudentRepository(writer: controller.writer)
        try await repository.markOnboardingCompleted()
        let state = try await resolveWithRealCounts(controller)
        XCTAssertEqual(state, .coach)
    }

    func testACustomExerciseCountsAsCoachWorkData() async throws {
        let controller = try makeCoachStore()
        let exercises = ExerciseLibraryUseCases(
            repository: CoreDataExerciseRepository(writer: controller.writer),
            clock: TestClock(),
            ids: TestIDGenerator(ids: [UUID(uuidString: "e0000000-0000-4000-8000-000000000001")!])
        )
        _ = try await exercises.createCustom(name: "壶铃摆动", recordMode: .weightReps)
        let state = try await resolveWithRealCounts(controller)
        XCTAssertEqual(state, .coach)
    }

    #if DEBUG
        func testFaultAfterGenerationWrittenLeavesPreviousArchiveAndJanitorRemovesOrphan() throws {
            let root = try makeRoot()
            let plain = ArchiveSnapshotStore(rootURL: root)
            let original = F.summariesOnlySnapshot()
            try plain.commit(snapshot: original)

            let faulty = ArchiveSnapshotStore(
                rootURL: root,
                faultInjectionBoundary: FaultInjectionBoundary(
                    injector: ArchiveStoreFaultInjector(failing: [.archiveStoreAfterGenerationWritten])
                )
            )
            XCTAssertThrowsError(try faulty.commit(snapshot: F.fullSnapshot())) {
                XCTAssertEqual($0 as? FaultInjectionError, .injected(.archiveStoreAfterGenerationWritten))
            }
            XCTAssertEqual(try plain.load(), original, "pointer never moved")
            XCTAssertEqual(entries(root.appendingPathComponent("generations")).count, 2, "orphan generation left")

            try plain.runStartupJanitor()
            XCTAssertEqual(entries(root.appendingPathComponent("generations")).count, 1)
            XCTAssertEqual(try plain.load(), original)
        }

        func testFaultAfterPointerRemovedLeavesNoArchiveAndJanitorFinishesTheDelete() throws {
            let root = try makeRoot()
            let plain = ArchiveSnapshotStore(rootURL: root)
            try plain.commit(snapshot: F.fullSnapshot())
            try plain.writeDisplaySettings(ArchiveDisplaySettings(weightUnit: .lb))

            let faulty = ArchiveSnapshotStore(
                rootURL: root,
                faultInjectionBoundary: FaultInjectionBoundary(
                    injector: ArchiveStoreFaultInjector(failing: [.archiveStoreAfterPointerRemoved])
                )
            )
            XCTAssertThrowsError(try faulty.deleteAll()) {
                XCTAssertEqual($0 as? FaultInjectionError, .injected(.archiveStoreAfterPointerRemoved))
            }
            XCTAssertNil(try plain.load(), "the archive is already gone once the pointer is removed")
            XCTAssertFalse(entries(root.appendingPathComponent("generations")).isEmpty, "directories still on disk")

            try plain.runStartupJanitor()
            XCTAssertEqual(entries(root), [])
            XCTAssertEqual(plain.readDisplaySettings(), .defaults)
        }

        func testFaultPointRawValuesAreTheNamedContractPoints() {
            XCTAssertEqual(
                FaultInjectionPoint.archiveStoreAfterGenerationWritten.rawValue, "archive.store.afterGenerationWritten")
            XCTAssertEqual(
                FaultInjectionPoint.archiveStoreAfterPointerRemoved.rawValue, "archive.store.afterPointerRemoved")
        }
    #endif
}
