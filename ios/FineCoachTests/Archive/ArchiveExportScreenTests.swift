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
        let student = try XCTUnwrap(students.first { $0.displayName.value == "王小明" })
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

    @MainActor
    func testDebugSeedBuildsTheFullReviewRoster() async throws {
        let directory = try TemporaryProtectedDirectory()
        let environment = try AppEnvironment(
            rootURL: directory.url.appendingPathComponent("roster", isDirectory: true),
            clock: ArchiveExportDebugSeed.makeClock()
        )
        let seeded = await ArchiveExportDebugSeed.seed(in: environment)
        XCTAssertTrue(seeded, "seed stopped early")
        let studentUseCases = try XCTUnwrap(environment.studentUseCases)
        let appointmentUseCases = try XCTUnwrap(environment.appointmentUseCases)
        let credits = try XCTUnwrap(environment.creditLedgerUseCases)
        let reader = ArchiveExportSourceReader(writer: try XCTUnwrap(environment.persistenceWriter))

        let active = try await studentUseCases.searchActive(query: "")
        let archived = try await studentUseCases.listArchived()
        XCTAssertEqual(active.count, 6)
        XCTAssertEqual(archived.map(\.displayName.value), ["孙已归档"])
        let longName = try XCTUnwrap(active.first { $0.displayName.value.hasPrefix("欧阳慕容") })
        XCTAssertGreaterThan(longName.displayName.value.count, 25)
        let expectedActive = ["王小明", "李思远", "陈嘉怡", "张浩然", "赵无数"]
        for name in expectedActive {
            XCTAssertTrue(active.contains { $0.displayName.value == name }, "missing \(name)")
        }
        let undisclosed = try XCTUnwrap(active.first { $0.displayName.value == "赵无数" })
        XCTAssertEqual(undisclosed.sex, .undisclosed)
        let nothingInProgress = try await studentUseCases.inProgressTraining()
        XCTAssertNil(nothingInProgress, "seed must not leave a training in progress")

        func student(_ name: String) throws -> Student {
            try XCTUnwrap((active + archived).first { $0.displayName.value == name })
        }
        func sessionCount(_ name: String) async throws -> Int {
            try await reader.read(studentID: student(name).id).availability.completedSessionCount
        }
        let expectedSessions = [
            "王小明": 6, "李思远": 5, "陈嘉怡": 3, longName.displayName.value: 1,
            "张浩然": 4, "赵无数": 0, "孙已归档": 2,
        ]
        for (name, count) in expectedSessions {
            let actual = try await sessionCount(name)
            XCTAssertEqual(actual, count, "sessions for \(name)")
        }
        let haoranFacts = try await reader.read(studentID: student("张浩然").id).availability
        XCTAssertEqual(haoranFacts.bodyMetrics.count, 4)
        XCTAssertEqual(haoranFacts.summaryCount, 2, "only non-empty student-facing summaries count")

        func activePackage(_ studentID: StableUUID) async throws -> CoursePackage {
            let found = try await credits.activePackage(studentID: studentID)
            return try XCTUnwrap(found)
        }
        // Packages: (name, total, balance)
        let expectedPackages: [(String, Int, Int)] = [
            ("李思远", 10, 5), ("陈嘉怡", 3, 0), (longName.displayName.value, 5, 4),
        ]
        for (name, total, balance) in expectedPackages {
            let package = try await activePackage(student(name).id)
            XCTAssertEqual(package.totalCredits, total, name)
            let actual = try await credits.balance(packageID: package.id)
            XCTAssertEqual(actual, balance, name)
        }
        let siyuanPackage = try await activePackage(student("李思远").id)
        XCTAssertEqual(siyuanPackage.isBalanceLow(ledgerBalance: 5), false)
        let jiayiPackage = try await activePackage(student("陈嘉怡").id)
        XCTAssertTrue(jiayiPackage.isBalanceLow(ledgerBalance: 0))
        let longPackage = try await activePackage(longName.id)
        XCTAssertTrue(longPackage.isExpired(asOf: appointmentUseCases.todayLocalDate()))
        for name in ["王小明", "张浩然", "赵无数"] {
            let package = try await credits.activePackage(studentID: student(name).id)
            XCTAssertNil(package, name)
        }

        // Appointments by state and per student.
        var all: [Appointment] = []
        for item in active + archived {
            all += try await appointmentUseCases.appointments(studentID: item.id)
        }
        func count(_ status: AppointmentStatus) -> Int { all.filter { $0.status == status }.count }
        XCTAssertEqual(count(.completed), 1)
        XCTAssertEqual(count(.absent), 1)
        XCTAssertEqual(count(.cancelled), 1)
        XCTAssertEqual(count(.inProgress), 0)
        // 6 weekly + 4 every-two-days + today 13:00, 15:30 + in 2 days
        XCTAssertEqual(count(.scheduled), 13)
        XCTAssertEqual(all.filter { $0.seriesID != nil }.count, 10)
        let cancelled = try XCTUnwrap(all.first { $0.status == .cancelled })
        XCTAssertEqual(cancelled.cancellationReason?.value, "合成测试：学员临时有事")
        XCTAssertEqual(cancelled.studentID, longName.id)
        XCTAssertEqual(all.first { $0.status == .absent }?.absentCreditChoice, .notCharged)
        XCTAssertNotNil(all.first { $0.status == .completed }?.linkedSessionID)

        // Today: completed, absent, cancelled, and three scheduled rows.
        let today = try await appointmentUseCases.todayOrdering()
        XCTAssertEqual(today.count, 6)
        XCTAssertEqual(today.filter { $0.appointment.status == .scheduled }.count, 3)
        XCTAssertTrue(all.contains { $0.date > appointmentUseCases.todayLocalDate() }, "no future appointments")

        // Templates: one saved from a session, one blank with exercises.
        let templates = try await XCTUnwrap(environment.templateUseCases).templates()
        XCTAssertEqual(Set(templates.map(\.name.value)), ["推日·胸肩", "腿日基础"])
    }
}
