import XCTest

@testable import FineCoach

/// T047..T050 / T044 rule checks for the import and viewer screens. No view is rendered:
/// source scans (no write entry, no Coach types, no modal without cover) and the pure mapping
/// from archive values to the record page. All data is fictional.
final class ArchiveViewerScreenTests: XCTestCase {
    private var appRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Archive/
            .deletingLastPathComponent()  // FineCoachTests/
            .deletingLastPathComponent()  // ios/
            .appendingPathComponent("FineCoachApp")
    }

    private func viewerSources() throws -> [(name: String, text: String)] {
        let dir = appRoot.appendingPathComponent("Features/ArchiveViewer")
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    func testViewerSourcesHaveNoCoachTypesNoWriteEntryAndNoUndiscoverableAction() throws {
        let sources = try viewerSources()
        XCTAssertGreaterThanOrEqual(sources.count, 8)
        let forbidden = [
            "AppEnvironment", "EnvironmentObject", "HistoryUseCases", "ExerciseLibraryUseCases", "StudentUseCases",
            "BodyDataUseCases", "ActiveSessionUseCases", "TemplateUseCases", "AppointmentUseCases",
            "CreditLedgerUseCases", "ArchiveExportUseCases", "Repository", "PersistenceWriter", "RootDestination",
            "CoachInstallProbe", "ShareReportFlowView", "ShareAdapter", "BackupExport", "ArchiveExportFlowView",
            ".contextMenu", ".sheet(", ".fullScreenCover(", "swipeActions",
        ]
        for (name, text) in sources {
            for word in forbidden {
                XCTAssertFalse(text.contains(word), "\(name) must not contain \(word)")
            }
        }
    }

    func testViewerRootIsBuiltFromArchiveServicesOnly() throws {
        let root = try XCTUnwrap(viewerSources().first { $0.name == "ArchiveViewerRoot.swift" }).text
        XCTAssertTrue(root.contains("init(services: ArchiveServices)"))
        XCTAssertTrue(root.contains("services.viewerUseCases"))
    }

    func testDestinationsContainNoWriteEntry() throws {
        let root = try XCTUnwrap(viewerSources().first { $0.name == "ArchiveViewerRoot.swift" }).text
        let start = try XCTUnwrap(root.range(of: "enum ArchiveViewerDestination"))
        let body = root[start.lowerBound...].prefix(400)
        for word in ["edit", "share", "export", "backup", "appointment", "package", "template"] {
            XCTAssertFalse(body.lowercased().contains(word), "destination list mentions \(word)")
        }
    }

    func testNoVisibleCopyUsesEnglishDomainWordsOrTheOldTerm() throws {
        let data = try Data(contentsOf: appRoot.appendingPathComponent("Resources/Localizable.xcstrings"))
        let strings = try XCTUnwrap(
            (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["strings"] as? [String: Any])
        for (key, value) in strings where key.hasPrefix("archive.viewer.") || key.hasPrefix("archive.import.")
            || key.hasPrefix("archive.settings.") || key.hasPrefix("archive.firstLaunch.") || key.hasPrefix("archive.blocked.")
            || key.hasPrefix("archive.summary.")
        {
            let text =
                (((value as? [String: Any])?["localizations"] as? [String: Any])?["zh-Hans"] as? [String: Any])
                .flatMap { ($0["stringUnit"] as? [String: Any])?["value"] as? String } ?? ""
            XCTAssertFalse(text.isEmpty, key)
            XCTAssertFalse(text.contains("课程记录"), key)
            XCTAssertFalse(text.contains("FineCoach"), key)
        }
    }

    // MARK: Record page mapping

    private func session(info: Bool) throws -> ArchiveViewerContent {
        let modules = ArchiveFixtures.modules(exerciseInfo: info)
        let full = ArchiveFixtures.fullSnapshot()
        let snapshot = ArchiveSnapshot(
            manifest: full.manifest, student: full.student,
            exercises: full.exercises.map {
                ArchiveExercise(
                    key: $0.key, placeholderNumber: $0.placeholderNumber, kind: $0.kind, isAssisted: $0.isAssisted,
                    info: info ? $0.info : nil)
            },
            sessions: full.sessions, summaries: full.summaries, bodyMetrics: full.bodyMetrics,
            bodyMeasurements: full.bodyMeasurements, attribution: full.attribution)
        _ = modules
        return ArchiveViewerContent(snapshot: snapshot)
    }

    func testWithoutExerciseInfoTheRecordShowsPlaceholderNamesAndNoBodyParts() throws {
        let content = try session(info: false)
        let first = try XCTUnwrap(content.snapshot.sessions.first)
        let dto = try XCTUnwrap(
            ArchiveSessionRecord.dto(
                session: first, content: content, converter: ArchiveDisplayConverter(settings: .defaults)))
        XCTAssertEqual(dto.exercises.first?.displayName, "动作 1")
        XCTAssertTrue(dto.exercises.allSatisfy { $0.equipmentIcon == nil && $0.primaryBodyPart == nil })
        XCTAssertNil(dto.studentDisplayName)
        XCTAssertNil(dto.trainingVolume)
        // The card draws the body diagram only when some exercise carries a body part.
        XCTAssertFalse(ShareReportCardView.blocks(for: dto, style: .page).contains(.trainedParts))
    }

    func testWithExerciseInfoTheRecordShowsNamesAndPoundsConvertOnlyTheDisplay() throws {
        let content = try session(info: true)
        let first = try XCTUnwrap(content.snapshot.sessions.first)
        var settings = ArchiveDisplaySettings.defaults
        settings.weightUnit = .lb
        let dto = try XCTUnwrap(
            ArchiveSessionRecord.dto(session: first, content: content, converter: ArchiveDisplayConverter(settings: settings)))
        XCTAssertEqual(dto.exercises.first?.displayName, "杠铃卧推")
        XCTAssertNotNil(dto.exercises.first?.equipmentIcon)
        XCTAssertTrue(ShareReportCardView.blocks(for: dto, style: .page).contains(.trainedParts))
        let weight = try XCTUnwrap(dto.exercises.first?.confirmedSets.first?.weightValue)
        XCTAssertNotEqual(weight.canonicalString, "60")
        // The stored value is unchanged.
        XCTAssertEqual(first.sections.first?.exercises.first?.sets.first?.weightValue?.canonicalString, "60")
        let text = TrainingSetDisplayFormatting.summary(
            for: try XCTUnwrap(dto.exercises.first?.confirmedSets.first), weightUnit: "lb")
        XCTAssertTrue(text.contains("lb"))
    }

    // MARK: Import page helpers

    func testFileDisplayNameUsesTheDateOfTheStandardName() {
        let url = URL(fileURLWithPath: "/tmp/FineCoach-档案-20260925-1830.fcarchive")
        XCTAssertEqual(ArchiveImportPresentation.fileDisplayName(url), "个人训练档案 · 9月25日")
        let other = URL(fileURLWithPath: "/tmp/some.fcarchive")
        XCTAssertEqual(ArchiveImportPresentation.fileDisplayName(other), "some.fcarchive")
    }

    func testEveryFailureHasCopyAndInvalidIsTheGenericOne() {
        XCTAssertEqual(ArchiveImportPresentation.failureMessage(.wrongPasswordOrCorrupted), "密码错误或文件已损坏，没有建立档案。")
        XCTAssertEqual(ArchiveImportPresentation.failureMessage(.incompatibleVersion), "这份档案来自不兼容的精练教练版本，没有建立档案。")
        XCTAssertEqual(ArchiveImportPresentation.failureMessage(.invalidArchive), "这不是有效的个人训练档案，没有建立档案。")
        XCTAssertEqual(ArchiveImportPresentation.failureMessage(.installStateUnavailable), "这不是有效的个人训练档案，没有建立档案。")
    }

    // MARK: Inbox copy

    private struct EmptyCoachProbe: CoachInstallProbe {
        func read() async throws -> CoachInstallSnapshot {
            CoachInstallSnapshot(onboardingCompleted: false, hasWorkData: false)
        }
    }

    @MainActor
    func testFinishingTheFlowDeletesOnlyTheInboxCopy() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("ImportFlow-\(UUID().uuidString)")
        let inbox = work.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: work) }
        let copy = inbox.appendingPathComponent("a.fcarchive")
        let source = work.appendingPathComponent("source.fcarchive")
        try Data([1, 2, 3]).write(to: copy)
        try Data([1, 2, 3]).write(to: source)
        let store = ArchiveSnapshotStore(rootURL: work.appendingPathComponent("ArchiveViewer"))
        let useCases = ArchiveImportUseCases(
            store: store, resolver: InstallStateResolver(store: store, probe: EmptyCoachProbe()), inboxRootURL: inbox)

        let model = ArchiveImportViewModel(useCases: useCases, prefilledURL: copy)
        model.password = "correct horse"
        await model.submit()  // not an archive: fails, the copy is kept for a retry
        XCTAssertEqual(model.failure, .invalidArchive)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))

        await model.finish()
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertEqual(model.password, "")

        let other = ArchiveImportViewModel(useCases: useCases, prefilledURL: nil)
        other.fileChosen(.success([source]))
        await other.finish()
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "a picked file is never deleted")
    }

    // MARK: Replace and delete (T055, T058)

    func testSettingsRowsAreWiredAndDeleteAsksForConfirmation() throws {
        let text = try XCTUnwrap(viewerSources().first { $0.name == "ArchiveSettingsView.swift" }).text
        XCTAssertFalse(text.contains("isEnabled: false"), "the import and delete rows are no longer placeholders")
        XCTAssertTrue(text.contains("action: onImportNewer"))
        XCTAssertTrue(text.contains(".fcConfirmationDialog(isPresented: $isConfirmingDelete)"))
        XCTAssertTrue(text.contains("role: .destructive"))
        // The delete row only opens the dialog; the deletion runs from the dialog's confirm action.
        XCTAssertTrue(text.contains("{ isConfirmingDelete = true }"))
    }

    func testEveryReplaceFailureHasItsReasonCopyEndingWithTheArchiveBeingUnchanged() {
        let expected: [(ArchiveReplaceFailure, String)] = [
            (.notNewer, "这份档案不比当前档案新。当前档案没有改变。"),
            (.differentSource, "这份档案来自另一个来源。当前档案没有改变。"),
            (.differentStudent, "这份档案属于另一名学员。当前档案没有改变。"),
            (.wrongPasswordOrCorrupted, "密码错误或文件已损坏。当前档案没有改变。"),
            (.incompatibleVersion, "这份档案来自不兼容的精练教练版本。当前档案没有改变。"),
            (.invalidArchive, "这不是有效的个人训练档案。当前档案没有改变。"),
            (.interrupted, "替换没有完成。当前档案没有改变。"),
        ]
        for (failure, text) in expected {
            XCTAssertEqual(ArchiveImportPresentation.replaceFailureMessage(failure), text)
        }
        XCTAssertEqual(String(localized: "archive.replace.failure.title"), "无法替换")
    }

    @MainActor
    func testReplaceModelMovesFromFormToConfirmationToReplacedAndKeepsPickedFiles() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("ReplaceFlow-\(UUID().uuidString)")
        let inbox = work.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: work) }
        let store = ArchiveSnapshotStore(rootURL: work.appendingPathComponent("ArchiveViewer"))
        try store.commit(snapshot: ArchiveFixtures.summariesOnlySnapshot())
        let newer = ArchiveFixtures.summariesOnlySnapshot(snapshotAt: ArchiveFixtures.snapshotAt.addingTimeInterval(60))
        let copy = inbox.appendingPathComponent("new.fcarchive")
        try ArchiveFileCodec.encode(
            snapshot: newer, password: try ArchivePassword(creating: ArchiveFixtures.password),
            salt: ArchiveFixtures.fixedSalt, noncePrefix: ArchiveFixtures.fixedNoncePrefix
        ).write(to: copy)
        let useCases = ArchiveImportUseCases(
            store: store, resolver: InstallStateResolver(store: store, probe: EmptyCoachProbe()), inboxRootURL: inbox)

        let model = ArchiveReplaceViewModel(useCases: useCases, prefilledURL: copy)
        XCTAssertFalse(model.canImport, "no password yet")
        model.password = "错误的口令12345"
        await model.submit()
        XCTAssertEqual(model.phase, .rejected(.wrongPasswordOrCorrupted))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path), "kept for the retry")

        model.password = ArchiveFixtures.password
        await model.submit()
        guard case .confirm(let preview) = model.phase else { return XCTFail("expected the confirmation facts") }
        XCTAssertEqual(preview.candidate.snapshotAtUTC, newer.manifest.snapshotAtUTC)
        XCTAssertEqual(try store.load(), ArchiveFixtures.summariesOnlySnapshot(), "nothing is written before the confirmation")

        await model.backToForm()
        XCTAssertEqual(model.phase, .form)
        XCTAssertEqual(model.password, "", "going back drops the password")

        model.password = ArchiveFixtures.password
        await model.submit()
        await model.confirm()
        XCTAssertTrue(model.replaced)
        XCTAssertEqual(try store.load(), newer)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path), "the Inbox copy goes after the replacement")

        let source = work.appendingPathComponent("picked.fcarchive")
        try Data([1]).write(to: source)
        let picked = ArchiveReplaceViewModel(useCases: useCases, prefilledURL: nil)
        picked.fileChosen(.success([source]))
        await picked.finish()
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "a picked file is never deleted")
    }
}
