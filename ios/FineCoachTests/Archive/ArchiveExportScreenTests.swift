import XCTest

@testable import FineCoach

/// T030 to T035 structural and presentation checks for the export screens. These do not render
/// SwiftUI; they prove the facts the entry-and-layout map relies on: one shared password
/// configuration, the exclusion note carries no unlock control, leaving the flow calls `leave()`,
/// every localized key the screens use exists, and the preview shows exactly what the snapshot
/// carries. The password-prompt behavior and the screens' appearance are device and human checks.
final class ArchiveExportScreenTests: XCTestCase {
    private typealias X = ArchiveExportFixtures

    private var appRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Archive/
            .deletingLastPathComponent()  // FineCoachTests/
            .deletingLastPathComponent()  // ios/
            .appendingPathComponent("FineCoachApp")
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: appRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func swiftSources(under relativePath: String) throws -> [(name: String, text: String)] {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: appRoot.appendingPathComponent(relativePath), includingPropertiesForKeys: nil)
        )
        var result: [(String, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            result.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        return result
    }

    // MARK: Password configuration (T033, AC-004, adversarial review #3)

    func testPasswordTraitsAreConfiguredInExactlyOnePlace() throws {
        var configuring: [String] = []
        var securePresenters: [String] = []
        // The export screens and the later archive import screens (M2-08, M2-19) live here.
        for file in try swiftSources(under: "Features/ArchiveExport") + swiftSources(under: "Features/ArchiveViewer") {
            let stripped = file.text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            XCTAssertFalse(stripped.contains("textContentType(.password"), "\(file.name) declares a password content type")
            XCTAssertFalse(stripped.contains("textContentType(.newPassword"), "\(file.name) declares a password content type")
            if stripped.contains(".textContentType(") && file.text.contains("archivePasswordEntry") {
                configuring.append(file.name)
            }
            if stripped.contains("isSecure: true") {
                securePresenters.append(file.name)
            }
        }
        XCTAssertEqual(configuring, ["ArchivePasswordField.swift"])
        XCTAssertEqual(securePresenters, ["ArchivePasswordField.swift"], "masked fields must go through ArchivePasswordField")
        let field = try source("Features/ArchiveExport/ArchivePasswordField.swift")
        XCTAssertTrue(field.contains(".autocorrectionDisabled(true)"))
        XCTAssertTrue(field.contains(".textInputAutocapitalization(.never)"))
        let password = try source("Features/ArchiveExport/ArchivePasswordView.swift")
        XCTAssertEqual(password.components(separatedBy: "ArchivePasswordField(").count - 1, 2)
        XCTAssertFalse(password.contains("FCTextField"))
    }

    func testPasswordNeverReachesLoggingOrFileNames() throws {
        for file in try swiftSources(under: "Features/ArchiveExport") {
            for forbidden in ["AppLogger", "logger.", "print(", "NSLog", "os_log", "UserDefaults", "fileName"] {
                XCTAssertFalse(file.text.contains(forbidden), "\(file.name) must not use \(forbidden)")
            }
        }
    }

    // MARK: M2-EXCLUSION-NOTE (T030, M2-FR-010)

    func testExclusionNoteHasNoUnlockControl() throws {
        let note = try source("Features/ArchiveExport/ArchiveExclusionNote.swift")
        XCTAssertFalse(note.contains("Toggle"))
        XCTAssertFalse(note.contains("FCListRow"))
        XCTAssertFalse(note.contains("FCButton"))
        XCTAssertEqual(note.components(separatedBy: "Button {").count - 1, 1, "only the 查看全部 link may be a control")
        XCTAssertTrue(note.contains("showsFullList.toggle()"))
    }

    // MARK: Navigation and lifecycle (T035)

    func testLeavingTheFlowCallsLeaveAndPresentsNoModal() throws {
        let flow = try source("Features/ArchiveExport/ArchiveExportFlowView.swift")
        XCTAssertTrue(flow.contains(".onDisappear"))
        XCTAssertTrue(flow.contains("await model.leave()"))
        let viewModel = try source("Features/ArchiveExport/ArchiveExportViewModel.swift")
        XCTAssertTrue(viewModel.contains("await flow.leave()"))
        for file in try swiftSources(under: "Features/ArchiveExport") {
            let presentsModal = file.text.contains(".sheet(") || file.text.contains(".fullScreenCover(")
            if presentsModal {
                XCTAssertTrue(file.text.contains(".fcPrivacyCovered()"), "\(file.name) presents a modal without the privacy cover")
            }
        }
        let navigation = try source("App/RootNavigation.swift")
        XCTAssertTrue(navigation.contains("case .archiveExport(let studentID):"))
        XCTAssertTrue(navigation.contains("environment.requireArchiveExportUseCases()"))
    }

    /// `Text("literal.key")` is a `LocalizedStringKey`; with the bundled Noto Sans SC it lays out the
    /// ideographic comma `、` with an extra half em after it (measured on the simulator: gap 16pt vs
    /// 9.5pt in the artwork), while `Text(String(localized:))` does not. Visible export copy
    /// therefore goes through `String(localized:)` like the rest of the app (owner walkthrough
    /// 2026-10-10: the exclusion note's wide gaps).
    func testVisibleExportCopyIsNotALocalizedStringKeyLiteral() throws {
        let pattern = try NSRegularExpression(pattern: "(?<![A-Za-z])Text\\(\"archive\\.export\\.[A-Za-z.]+\"\\)")
        for file in try swiftSources(under: "Features/ArchiveExport") {
            let range = NSRange(file.text.startIndex..., in: file.text)
            XCTAssertEqual(pattern.numberOfMatches(in: file.text, range: range), 0, "\(file.name) has a literal-key Text")
        }
    }

    func testEveryStudentDetailEntryIsAVisibleActionRow() throws {
        let detail = try source("Features/Students/StudentDetail/StudentDetailView.swift")
        XCTAssertTrue(detail.contains("FCActionRow(title: String(localized: \"student.detail.exportArchive\"))"))
        XCTAssertTrue(detail.contains("FCAccessibilityID.detailExportArchive"))
        XCTAssertFalse(detail.contains("contextMenu"))
    }

    // MARK: Localization

    func testEveryExportLocalizationKeyUsedBySourceExists() throws {
        let catalog = try JSONSerialization.jsonObject(
            with: Data(contentsOf: appRoot.appendingPathComponent("Resources/Localizable.xcstrings"))
        ) as? [String: Any]
        let strings = try XCTUnwrap(catalog?["strings"] as? [String: Any])
        let pattern = try NSRegularExpression(pattern: "\"((?:archive\\.export|student\\.detail\\.exportArchive)[A-Za-z.]*)\"")
        var used = Set<String>()
        for file in try swiftSources(under: "Features/ArchiveExport") {
            let range = NSRange(file.text.startIndex..., in: file.text)
            for match in pattern.matches(in: file.text, range: range) {
                if let keyRange = Range(match.range(at: 1), in: file.text) {
                    used.insert(String(file.text[keyRange]))
                }
            }
        }
        XCTAssertGreaterThan(used.count, 40, "scan found too few keys; the scan is broken")
        // Accessibility identifiers share the prefix style but live in FCAccessibilityID, not here.
        let missing = used.filter { strings[$0] == nil }
        XCTAssertTrue(missing.isEmpty, "missing localization keys: \(missing.sorted())")
    }

    // MARK: M2-FACT-ROW (T032)

    func testFactRowsAreTheSixFactsInOrderWithThreeWarnings() {
        let facts = ArchiveFactRow.Fact.allCases
        XCTAssertEqual(facts.count, 6)
        XCTAssertEqual(facts.map(\.isWarning), [true, true, true, false, false, false])
        XCTAssertEqual(
            facts.map(\.text),
            [
                "档案不是完整备份，不能用来恢复你的数据。",
                "档案会包含刚才预览中的全部资料。",
                "文件交出并被接收后，你和 FineCoach 都无法撤回。",
                "学员只能删除自己设备上的副本。",
                "学员删除不会影响你的原始数据、已保存的文件或其他副本。",
                "请通过其他方式把密码单独告诉学员，不要和档案一起发送。",
            ]
        )
    }

    // MARK: Presentation

    func testDateRangeDropsTheEndYearOnlyWhenItMatches() throws {
        let march = try LocalDate(year: 2026, month: 3, day: 2)
        let september = try LocalDate(year: 2026, month: 9, day: 25)
        let nextYear = try LocalDate(year: 2027, month: 1, day: 5)
        XCTAssertEqual(ArchiveExportPresentation.dateRange(from: march, to: september), "2026年3月2日 – 9月25日")
        XCTAssertEqual(ArchiveExportPresentation.dateRange(from: march, to: nextYear), "2026年3月2日 – 2027年1月5日")
        XCTAssertEqual(ArchiveExportPresentation.dateRange(from: march, to: march), "2026年3月2日")
    }

    func testSelectionNotesFollowTheSelection() async throws {
        let source = try await seededSource()
        var selection = ArchiveModuleSelection(availability: source.availability)
        let metricCount = source.availability.bodyMetrics.count
        XCTAssertEqual(
            ArchiveExportPresentation.groupNote(.bodyData, selection: selection),
            "\(metricCount) 项指标"
        )
        selection.setSelected(false, item: .bodyMetric(X.customMetricID))
        XCTAssertEqual(
            ArchiveExportPresentation.groupNote(.bodyData, selection: selection),
            "\(metricCount - 1) / \(metricCount) 项指标"
        )
        XCTAssertEqual(ArchiveExportPresentation.reason(.noData), "无数据")
        XCTAssertEqual(ArchiveExportPresentation.reason(.requiresTrainingRecords), "需同时选择训练记录")
        XCTAssertEqual(
            ArchiveExportPresentation.groupNote(.trainingContent, selection: selection),
            "\(source.availability.completedSessionCount) 次训练 · 4 项"
        )
    }

    // MARK: Preview shows exactly the snapshot (M2-FR-008, M2-FR-012)

    func testPreviewListsFreeTextVerbatimAndNothingExcluded() async throws {
        let source = try await seededSource()
        let all = X.selection(for: source, keeping: Set(source.availability.allItems))
        let preview = ArchivePreviewModel(
            snapshot: try ArchiveExportPolicy.makeSnapshot(source: source, selection: all, identity: X.identity, now: X.now)
        )
        XCTAssertEqual(preview.displayName, X.studentName)
        let customNames = preview.customExercises.map(\.text)
        XCTAssertTrue(customNames.contains(X.customExerciseName))
        for name in X.oneOffNames {
            XCTAssertTrue(customNames.contains(name), "one-off exercise name \(name) must be listed")
        }
        XCTAssertEqual(Set(preview.summaries.map(\.text)), Set(X.summaries))
        XCTAssertTrue(preview.metrics.contains { $0.isCustom && $0.title == X.customMetricName })
        let shown = ([preview.displayName ?? ""] + customNames + preview.summaries.map(\.text) + preview.metrics.map(\.title)
            + preview.metrics.map(\.detail)).joined(separator: "\n")
        for excluded in X.excludedValues {
            XCTAssertFalse(shown.contains(excluded), "preview leaks \(excluded)")
        }
        XCTAssertFalse(shown.contains(X.inProgressSummary))
    }

    func testPreviewWithoutExerciseInfoShowsNoExerciseNames() async throws {
        let source = try await seededSource()
        let kept = Set(source.availability.allItems).subtracting([.exerciseInfo])
        let preview = ArchivePreviewModel(
            snapshot: try ArchiveExportPolicy.makeSnapshot(
                source: source, selection: X.selection(for: source, keeping: kept), identity: X.identity, now: X.now)
        )
        XCTAssertFalse(preview.modules.exerciseInfo)
        XCTAssertTrue(preview.customExercises.isEmpty)
        XCTAssertTrue(preview.modules.trainingRecords)
    }

    nonisolated(unsafe) private static var cachedSource: ArchiveExportSource?

    private func seededSource() async throws -> ArchiveExportSource {
        if let cached = Self.cachedSource {
            return cached
        }
        let store = try X.Store()
        try await X.seed(store)
        let source = try await X.readSource(store)
        Self.cachedSource = source
        return source
    }

    // MARK: DEBUG seed for the human review (T038)

    @MainActor
    func testDebugSeedBuildsTheReviewStudent() async throws {
        let directory = try TemporaryProtectedDirectory()
        let environment = try AppEnvironment(
            rootURL: directory.url.appendingPathComponent("seed", isDirectory: true),
            clock: ArchiveExportDebugSeed.makeClock()
        )
        let seeded = await ArchiveExportDebugSeed.seed(in: environment)
        XCTAssertTrue(seeded)
        let students = try await XCTUnwrap(environment.studentUseCases).searchActive(query: "")
        let student = try XCTUnwrap(students.first)
        XCTAssertEqual(student.displayName.value, "王小明")
        let source = try await ArchiveExportSourceReader(writer: XCTUnwrap(environment.persistenceWriter))
            .read(studentID: student.id)
        let facts = source.availability
        XCTAssertTrue(facts.hasDisplayName)
        XCTAssertTrue(facts.hasSex)
        XCTAssertEqual(facts.completedSessionCount, 6)
        XCTAssertEqual(facts.summaryCount, 3)
        XCTAssertEqual(facts.bodyMetrics.count, 3)
        XCTAssertNotEqual(facts.earliestSessionDate, facts.latestSessionDate, "sessions should span several days")
        let snapshot = try ArchiveExportPolicy.makeSnapshot(
            source: source,
            selection: ArchiveModuleSelection(availability: facts),
            identity: X.identity,
            now: X.now
        )
        let kinds = Set(snapshot.exercises.map(\.kind))
        XCTAssertEqual(kinds, [.builtIn, .custom, .oneOff])
    }
}
