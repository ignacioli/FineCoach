import FineCoach
import XCTest

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
/// (T015) and the viewer snapshot store (T017). Install-state and open-router tests are added
/// to this file by later tasks.
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

        let pointer = try JSONSerialization.jsonObject(
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("display-settings.json").path))
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
        try FileManager.default.createDirectory(at: generations.appendingPathComponent("not-a-uuid"), withIntermediateDirectories: true)
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
            XCTAssertEqual(FaultInjectionPoint.archiveStoreAfterGenerationWritten.rawValue, "archive.store.afterGenerationWritten")
            XCTAssertEqual(FaultInjectionPoint.archiveStoreAfterPointerRemoved.rawValue, "archive.store.afterPointerRemoved")
        }
    #endif
}
