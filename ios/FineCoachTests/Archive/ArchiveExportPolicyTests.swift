import XCTest

@testable import FineCoach

/// T036 (US1, AC-001..AC-005): rule-level checks of the export projection, the allow-list policy,
/// the module selection and the flow state machine. The sensitive values are written into a real
/// in-memory Core Data store and read back through `ArchiveExportSourceReader`, so "excluded"
/// is proven against the actual projection, not against hand-made input. All data is fictional.
final class ArchiveExportPolicyTests: XCTestCase {
    private typealias X = ArchiveExportFixtures

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

    private func makeSnapshot(
        _ source: ArchiveExportSource,
        keeping kept: Set<ArchiveModuleItem>
    ) throws -> ArchiveSnapshot {
        try ArchiveExportPolicy.makeSnapshot(
            source: source,
            selection: X.selection(for: source, keeping: kept),
            identity: X.identity,
            now: X.now
        )
    }

    private func weightMetric(_ source: ArchiveExportSource) -> ArchiveModuleItem {
        .bodyMetric(BuiltInBodyMetric.weight.id)
    }

    private func allItems(_ source: ArchiveExportSource) -> Set<ArchiveModuleItem> {
        Set(source.availability.allItems)
    }

    /// The payload plaintext the archive file would encrypt: what a recipient could read.
    private func payload(_ snapshot: ArchiveSnapshot) throws -> String {
        String(decoding: try ArchiveFileCodec.encodePayload(snapshot).plaintext, as: UTF8.self)
    }

    private func assertAbsent(_ values: [String], in text: String, _ label: String, line: UInt = #line) {
        for value in values {
            XCTAssertFalse(text.contains(value), "\(label) leaks \(value)", line: line)
        }
    }

    // MARK: AC-001 / AC-002: minimum disclosure and permanent exclusions

    func testTrainingRecordsOnlyExportContainsNoExcludedOrUnselectedValue() async throws {
        let source = try await seededSource()
        let snapshot = try makeSnapshot(source, keeping: [.trainingRecords])
        let text = try payload(snapshot)
        let fileName = ArchiveExportPolicy.fileName(snapshotAtUTC: snapshot.manifest.snapshotAtUTC, timeZone: X.shanghai)

        let modules = snapshot.manifest.modules
        XCTAssertTrue(modules.trainingRecords)
        XCTAssertFalse(modules.displayName || modules.sex || modules.bodyData || modules.trends || modules.summaries || modules.exerciseInfo)
        XCTAssertNil(snapshot.student)
        XCTAssertTrue(snapshot.summaries.isEmpty && snapshot.bodyMetrics.isEmpty && snapshot.bodyMeasurements.isEmpty)
        XCTAssertNil(snapshot.attribution)
        XCTAssertTrue(snapshot.exercises.allSatisfy { $0.info == nil })

        let hidden =
            X.excludedValues + [X.studentName, "female"] + X.bodyWeightValues + [X.customMetricValue, X.customMetricName]
            + X.summaries + [X.inProgressSummary]
            + [X.builtInName, X.secondBuiltInName, X.customExerciseName] + X.oneOffNames
            + [X.builtInID, X.secondBuiltInID, X.customExerciseID.uuidString, X.studentID.rawValue.uuidString]
            + [X.session1ID, X.session2ID, X.inProgressSessionID, X.abandonedSessionID, X.sectionID].map(\.rawValue.uuidString)
        assertAbsent(hidden, in: text, "payload")
        assertAbsent(hidden, in: fileName, "file name")
        XCTAssertEqual(fileName, "FineCoach-档案-20261009-1600.fcarchive")
        XCTAssertTrue(text.contains("热身与主项"), "section structure is part of the training records")
    }

    func testAllSelectedExportStillContainsNoExcludedValue() async throws {
        let source = try await seededSource()
        let snapshot = try ArchiveExportPolicy.makeSnapshot(
            source: source,
            selection: ArchiveModuleSelection(availability: source.availability),
            identity: X.identity,
            now: X.now
        )
        let text = try payload(snapshot)
        assertAbsent(
            X.excludedValues + [X.inProgressSummary, X.builtInID, X.secondBuiltInID, X.customExerciseID.uuidString, X.studentID.rawValue.uuidString],
            in: text, "all-selected payload")
        let imageMarkers = ["image", ".png", ".jpg", ".gif", ".mp4"]
        assertAbsent(imageMarkers, in: text.lowercased(), "all-selected payload (media)")
        XCTAssertTrue(text.contains(X.studentName), "selected modules are present")
        XCTAssertTrue(text.contains(X.bodyWeightValues[0]))
    }

    func testPlaceholderNumbersAreFixedOnFirstAppearanceAndOneOffNumberedPerOccurrence() async throws {
        let source = try await seededSource()
        let snapshot = try makeSnapshot(source, keeping: [.trainingRecords])

        XCTAssertEqual(snapshot.exercises.map(\.key), ["e1", "e2", "e3", "e4", "e5", "e6"])
        XCTAssertEqual(snapshot.exercises.map(\.placeholderNumber), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(snapshot.exercises.map(\.kind), [.builtIn, .custom, .oneOff, .builtIn, .oneOff, .oneOff])
        XCTAssertEqual(snapshot.sessions.map(\.key), ["s1", "s2"])
        XCTAssertTrue(snapshot.sessions[0].completedAtUTC < snapshot.sessions[1].completedAtUTC)

        let first = snapshot.sessions[0].sections
        XCTAssertEqual(first.map(\.name), ["热身与主项", nil])
        XCTAssertEqual(first[0].exercises.map(\.exerciseKey), ["e1", "e2"])
        XCTAssertEqual(first[0].exercises.map(\.sets.count), [2, 1], "draft and pending sets are dropped")
        XCTAssertEqual(first[1].exercises.map(\.exerciseKey), ["e3"])
        // The built-in exercise keeps e1 in the second session; each one-off gets a new key.
        let second = snapshot.sessions[1].sections
        XCTAssertEqual(second.map(\.name), [nil])
        XCTAssertEqual(second[0].exercises.map(\.exerciseKey), ["e1", "e4", "e5", "e6"])
        XCTAssertEqual(snapshot.manifest.counts, snapshot.derivedCounts)
        XCTAssertNoThrow(try snapshot.validateIntegrity())
    }

    func testNumberingNeverDependsOnNamesAndRenamedExerciseKeepsItsNumber() throws {
        let catalog = handCatalog()
        func exercise(_ id: String, _ name: String) -> ArchiveExportSource.Exercise {
            .init(identity: .stable(id), kind: .builtIn, isAssisted: false, name: name, catalog: catalog,
                  recordMode: .weightReps, sets: [handSet()])
        }
        // Same name for two exercises, a rename for one of them, in two sessions.
        let source = handSource(sessions: [
            handSession(day: 1, [exercise("A", "同名"), exercise("B", "同名")]),
            handSession(day: 2, [exercise("B", "已改名"), exercise("A", "同名")]),
        ])
        let snapshot = try makeSnapshot(source, keeping: [.trainingRecords])
        XCTAssertEqual(snapshot.exercises.map(\.placeholderNumber), [1, 2])
        XCTAssertEqual(snapshot.sessions[1].sections[0].exercises.map(\.exerciseKey), ["e2", "e1"])
    }

    // MARK: AC-003 free text

    func testSummariesAreVerbatimWhenSelectedAndAbsentAfterDeselectingAndRegenerating() async throws {
        let source = try await seededSource()
        let kept: Set<ArchiveModuleItem> = [.trainingRecords, .summaries, .exerciseInfo]
        let withSummaries = try makeSnapshot(source, keeping: kept)
        XCTAssertEqual(withSummaries.summaries.map(\.text), X.summaries)
        XCTAssertEqual(withSummaries.summaries.map(\.sessionKey), ["s1", "s2"])
        let text = try payload(withSummaries)
        // Free text the Coach must be able to review: custom and one-off names verbatim.
        let names = withSummaries.exercises.compactMap(\.info?.name)
        XCTAssertTrue(names.contains(X.customExerciseName))
        XCTAssertTrue(Set(X.oneOffNames).isSubset(of: Set(names)))
        assertAbsent(X.excludedValues, in: text, "payload with summaries")

        let without = try makeSnapshot(source, keeping: kept.subtracting([.summaries]))
        XCTAssertTrue(without.summaries.isEmpty)
        XCTAssertFalse(without.manifest.modules.summaries)
        assertAbsent(X.summaries, in: try payload(without), "payload after deselecting summaries")
    }

    func testSummariesCarrySessionKeyOnlyWithTrainingRecords() async throws {
        let source = try await seededSource()
        let snapshot = try makeSnapshot(source, keeping: [.summaries])
        XCTAssertEqual(snapshot.summaries.map(\.text), X.summaries)
        XCTAssertEqual(snapshot.summaries.map(\.sessionKey), [nil, nil])
        XCTAssertTrue(snapshot.sessions.isEmpty && snapshot.exercises.isEmpty)
        XCTAssertEqual(snapshot.summaries.map(\.localDate.canonicalString), ["2026-09-01", "2026-09-08"])
    }

    // MARK: M2-FR-007 / D-005 / D-009 / D-015 / spec §5

    func testSelectionDefaultsToEverythingAndIsFreshEveryTime() async throws {
        let source = try await seededSource()
        var first = ArchiveModuleSelection(availability: source.availability)
        for item in first.availability.allItems {
            XCTAssertEqual(first.state(of: item), .selected, "\(item)")
        }
        for group in ArchiveModuleGroup.allCases {
            XCTAssertEqual(first.groupState(group), .all)
        }
        first.setGroup(.trainingContent, selected: false)
        first.setSelected(false, item: .displayName)
        XCTAssertEqual(first.groupState(.trainingContent), .noneSelected)

        // Nothing carries over into the next flow's selection.
        let second = ArchiveModuleSelection(availability: source.availability)
        XCTAssertEqual(second, ArchiveModuleSelection(availability: source.availability))
        XCTAssertEqual(second.state(of: .displayName), .selected)
        XCTAssertEqual(second.state(of: .summaries), .selected)
        XCTAssertEqual(second.effectiveBodyMetricIDs.count, 2, "body data defaults to every metric with data")
    }

    func testItemsWithoutDataAreUnselectableAndCountAsUnselected() throws {
        // No sessions, no summaries, no body data.
        let source = handSource(sessions: [], metrics: [])
        var selection = ArchiveModuleSelection(availability: source.availability)
        for item in [ArchiveModuleItem.trainingRecords, .trends, .summaries, .exerciseInfo] {
            XCTAssertEqual(selection.state(of: item), .unavailable(.noData), "\(item)")
            XCTAssertFalse(selection.setSelected(true, item: item), "\(item) cannot be selected")
        }
        XCTAssertEqual(selection.groupState(.trainingContent), .unavailable)
        XCTAssertEqual(selection.groupState(.bodyData), .unavailable)
        XCTAssertEqual(selection.effectiveModules?.trainingRecords, false)
        XCTAssertEqual(selection.effectiveModules?.displayName, true)
        selection.setGroup(.trainingContent, selected: true)
        XCTAssertEqual(selection.effectiveModules?.summaries, false, "a group switch never selects no-data items")

        // A body metric without measurements is not offered at all.
        XCTAssertTrue(source.availability.bodyMetrics.isEmpty)
    }

    func testUndisclosedSexCountsAsNoDataAndIsNeverExported() throws {
        let source = ArchiveExportSource(
            student: .init(displayName: "示例学员", sex: .undisclosed), sessions: [], bodyMetrics: [])
        var selection = ArchiveModuleSelection(availability: source.availability)
        XCTAssertEqual(selection.state(of: .sex), .unavailable(.noData))
        XCTAssertFalse(selection.setSelected(true, item: .sex))
        XCTAssertEqual(selection.effectiveModules?.sex, false)
        let snapshot = try ArchiveExportPolicy.makeSnapshot(
            source: source, selection: selection, identity: X.identity, now: X.now)
        XCTAssertNil(snapshot.student?.sex)
    }

    func testTrendsAndExerciseInfoRequireTrainingRecords() async throws {
        let source = try await seededSource()
        var selection = ArchiveModuleSelection(availability: source.availability)
        selection.setSelected(false, item: .trainingRecords)
        XCTAssertEqual(selection.state(of: .trends), .unavailable(.requiresTrainingRecords))
        XCTAssertEqual(selection.state(of: .exerciseInfo), .unavailable(.requiresTrainingRecords))
        XCTAssertFalse(selection.setSelected(true, item: .exerciseInfo))
        XCTAssertEqual(selection.state(of: .summaries), .selected, "summaries do not depend on training records")
        let modules = try XCTUnwrap(selection.effectiveModules)
        XCTAssertFalse(modules.trainingRecords || modules.trends || modules.exerciseInfo)

        let snapshot = try ArchiveExportPolicy.makeSnapshot(
            source: source, selection: selection, identity: X.identity, now: X.now)
        XCTAssertTrue(snapshot.sessions.isEmpty && snapshot.exercises.isEmpty && snapshot.attribution == nil)

        // Switching training records back on restores the Coach's earlier intent.
        selection.setSelected(true, item: .trainingRecords)
        XCTAssertEqual(selection.state(of: .trends), .selected)
        XCTAssertEqual(selection.state(of: .exerciseInfo), .selected)
    }

    func testEmptyEffectiveSelectionCannotPreviewAndPolicyRefuses() async throws {
        let source = try await seededSource()
        var selection = ArchiveModuleSelection(availability: source.availability)
        for group in ArchiveModuleGroup.allCases {
            selection.setGroup(group, selected: false)
        }
        XCTAssertNil(selection.effectiveModules)
        XCTAssertFalse(selection.canPreview)
        XCTAssertThrowsError(
            try ArchiveExportPolicy.makeSnapshot(source: source, selection: selection, identity: X.identity, now: X.now)
        ) { XCTAssertEqual($0 as? ArchiveExportPolicyError, .nothingSelected) }

        // A student with nothing at all, and name / sex switched off, has no effective selection either.
        var bare = ArchiveModuleSelection(availability: handSource(sessions: []).availability)
        bare.setSelected(false, item: .displayName)
        bare.setSelected(false, item: .sex)
        XCTAssertFalse(bare.canPreview)
    }

    func testGroupStateIsDerivedFromChildrenAndToggleSwitchesTheWholeGroup() async throws {
        let source = try await seededSource()
        var selection = ArchiveModuleSelection(availability: source.availability)
        selection.setSelected(false, item: .sex)
        XCTAssertEqual(selection.groupState(.basicProfile), .partial)
        selection.toggleGroup(.basicProfile)
        XCTAssertEqual(selection.groupState(.basicProfile), .all)
        selection.toggleGroup(.basicProfile)
        XCTAssertEqual(selection.groupState(.basicProfile), .noneSelected)
        selection.setSelected(false, item: weightMetric(source))
        XCTAssertEqual(selection.groupState(.bodyData), .partial)
        XCTAssertEqual(selection.effectiveBodyMetricIDs, [X.customMetricID])
    }

    func testStaleSelectionIsRefused() async throws {
        let source = try await seededSource()
        let other = handSource(sessions: [])
        XCTAssertThrowsError(
            try ArchiveExportPolicy.makeSnapshot(
                source: source, selection: ArchiveModuleSelection(availability: other.availability),
                identity: X.identity, now: X.now)
        ) { XCTAssertEqual($0 as? ArchiveExportPolicyError, .selectionOutOfDate) }
    }

    // MARK: Projection: only completed sessions and confirmed sets

    func testInProgressAbandonedDraftAndPendingNeverEnterTheProjection() async throws {
        let source = try await seededSource()
        let availability = source.availability
        XCTAssertEqual(availability.completedSessionCount, 2)
        XCTAssertEqual(availability.confirmedSetCount, 8)
        XCTAssertEqual(availability.summaryCount, 2, "the in-progress summary is not counted")
        XCTAssertEqual(availability.exerciseCount, 6)
        XCTAssertEqual(availability.earliestSessionDate?.canonicalString, "2026-09-01")
        XCTAssertEqual(availability.latestSessionDate?.canonicalString, "2026-09-08")
        let snapshot = try makeSnapshot(source, keeping: allItems(source))
        let text = try payload(snapshot)
        assertAbsent([X.inProgressSummary, "示例进行中动作", "示例仅草稿动作"], in: text, "payload")
        XCTAssertEqual(snapshot.totalSetCount, 8)
        XCTAssertEqual(snapshot.sessions.map(\.durationMinutes), [62, 62])
    }

    // MARK: T061 export half: exercise info and attribution

    func testExerciseInfoWritesNamesMusclesEquipmentAndAttribution() async throws {
        let source = try await seededSource()
        let snapshot = try makeSnapshot(source, keeping: [.trainingRecords, .exerciseInfo])
        let infos = snapshot.exercises.map(\.info)
        XCTAssertEqual(infos[0], ArchiveExerciseInfo(name: X.builtInName, primaryMuscles: ["胸"], secondaryMuscles: ["肩", "臂"], equipment: "杠铃"))
        XCTAssertEqual(
            infos[1],
            ArchiveExerciseInfo(name: X.customExerciseName, primaryMuscles: [], secondaryMuscles: [], equipment: ArchiveExportPolicy.unknownEquipment))
        XCTAssertEqual(infos[2]?.name, X.oneOffNames[0])
        XCTAssertEqual(infos[3]?.name, X.secondBuiltInName)
        XCTAssertEqual(infos[3]?.equipment, "哑铃")

        let attribution = try XCTUnwrap(snapshot.attribution)
        XCTAssertEqual(attribution.sourceName, "wger.de")
        XCTAssertEqual(attribution.licenseName, "CC-BY-SA-3.0 / CC-BY-SA-4.0")
        XCTAssertTrue(attribution.licenseText.contains("ShareAlike 3.0"))
        XCTAssertTrue(attribution.licenseText.contains("ShareAlike 4.0"))
        XCTAssertEqual(attribution.exerciseKeys, ["e1", "e4"], "built-in exercises only")
        XCTAssertEqual(snapshot.manifest.counts.attribution, 1)
        XCTAssertNoThrow(try snapshot.validateIntegrity())
        assertAbsent([X.excludedActionNote], in: try payload(snapshot), "payload")
    }

    func testNoMusclesNamesOrAttributionWithoutExerciseInfo() async throws {
        let source = try await seededSource()
        let snapshot = try makeSnapshot(source, keeping: allItems(source).subtracting([.exerciseInfo]))
        XCTAssertTrue(snapshot.exercises.allSatisfy { $0.info == nil })
        XCTAssertNil(snapshot.attribution)
        assertAbsent(
            [X.builtInName, X.customExerciseName, "杠铃", "胸", "wger", "CC-BY"], in: try payload(snapshot),
            "payload without exercise info")
    }

    func testAttributionOmittedWhenNoBuiltInExerciseIsPresent() throws {
        let custom = ArchiveExportSource.Exercise(
            identity: .stable("custom-1"), kind: .custom, isAssisted: false, name: "自定义", catalog: nil,
            recordMode: .weightReps, sets: [handSet()])
        let source = handSource(sessions: [handSession(day: 1, [custom])])
        let snapshot = try makeSnapshot(source, keeping: [.trainingRecords, .exerciseInfo])
        XCTAssertNil(snapshot.attribution)
        XCTAssertEqual(snapshot.manifest.counts.attribution, 0)
    }

    func testIsAssistedIsWrittenOnEveryExerciseWhetherOrNotExerciseInfoIsSelected() async throws {
        let source = try await seededSource()
        for kept: Set<ArchiveModuleItem> in [[.trainingRecords], [.trainingRecords, .exerciseInfo]] {
            let snapshot = try makeSnapshot(source, keeping: kept)
            XCTAssertEqual(snapshot.exercises.map(\.isAssisted), [false, true, false, false, false, false])
        }
        let text = try payload(try makeSnapshot(source, keeping: [.trainingRecords]))
        XCTAssertEqual(text.components(separatedBy: "\"isAssisted\"").count - 1, 6)
    }

    // MARK: Body data (D-003)

    func testBodyDataCoversSelectedMetricsWithAllTheirMeasurements() async throws {
        let source = try await seededSource()
        let weightOnly = try makeSnapshot(source, keeping: [weightMetric(source)])
        XCTAssertTrue(weightOnly.manifest.modules.bodyData)
        XCTAssertEqual(weightOnly.bodyMetrics.map(\.key), ["m1"])
        XCTAssertEqual(weightOnly.bodyMetrics.map(\.kind), [.builtIn(.weight)])
        XCTAssertEqual(weightOnly.bodyMeasurements.map(\.value.canonicalString), X.bodyWeightValues)
        XCTAssertEqual(weightOnly.bodyMeasurements.map(\.localDay.canonicalString), ["2026-08-20", "2026-09-05"])
        XCTAssertTrue(weightOnly.sessions.isEmpty)
        assertAbsent([X.customMetricName, X.customMetricValue], in: try payload(weightOnly), "weight-only payload")

        let both = try makeSnapshot(source, keeping: [weightMetric(source), .bodyMetric(X.customMetricID)])
        XCTAssertEqual(both.bodyMetrics.map(\.key), ["m1", "m2"])
        XCTAssertEqual(both.bodyMetrics[1].name, X.customMetricName)
        XCTAssertEqual(both.bodyMetrics[1].unit, "cm")
        XCTAssertEqual(both.bodyMeasurements.count, 3)
        XCTAssertNoThrow(try both.validateIntegrity())
    }

    // MARK: File name (contract §1, M2-FR-021)

    func testFileNameIsGenericAndUsesSnapshotLocalTime() {
        let at = Date(timeIntervalSince1970: 1_791_532_800.789)  // 2026-10-09T08:00:00Z
        XCTAssertEqual(
            ArchiveExportPolicy.fileName(snapshotAtUTC: at, timeZone: X.shanghai), "FineCoach-档案-20261009-1600.fcarchive")
        XCTAssertEqual(
            ArchiveExportPolicy.fileName(snapshotAtUTC: at, timeZone: TimeZone(identifier: "UTC")!),
            "FineCoach-档案-20261009-0800.fcarchive")
        XCTAssertEqual(
            ArchiveExportPolicy.fileName(snapshotAtUTC: at, timeZone: TimeZone(identifier: "America/Los_Angeles")!),
            "FineCoach-档案-20261009-0100.fcarchive")
    }

    // MARK: Output must pass the strict decoder

    func testPolicyOutputRoundTripsThroughTheFileCodecFieldForField() async throws {
        let source = try await seededSource()
        let snapshot = try makeSnapshot(source, keeping: allItems(source))
        let password = try ArchivePassword(creating: "示例口令abcdefgh")
        let file = try ArchiveFileCodec.encode(snapshot: snapshot, password: password)
        XCTAssertEqual(try ArchiveFileCodec.decode(file: file, password: password), snapshot)
        for summary in X.summaries {
            XCTAssertNil(file.range(of: Data(summary.utf8)), "ciphertext contains no plaintext")
        }
    }

    // MARK: State machine (M2-FR-014)

    private struct FlowHarness {
        let flow: ArchiveExportFlow
        let identity: StubArchiveIdentity
        let share: ScriptedSharePresenter
        let logger: RecordingLogger
        let root: TemporaryProtectedDirectory

        var tempFiles: [String] {
            let enumerator = FileManager.default.enumerator(atPath: root.url.path)
            return (enumerator?.allObjects as? [String]) ?? []
        }
    }

    private func makeFlow(
        source: ArchiveExportSource? = nil,
        outcomes: [SystemShareOutcome] = [.completed],
        identity: StubArchiveIdentity = StubArchiveIdentity(),
        limitAssertion: @escaping @Sendable () -> Void = {}
    ) async throws -> FlowHarness {
        let root = try TemporaryProtectedDirectory()
        let share = ScriptedSharePresenter(outcomes)
        let logger = RecordingLogger()
        let useCases = ArchiveExportUseCases(
            sourceReader: StubSourceReader(source: source ?? handSource(sessions: [handSession(day: 1, [handExercise()])], summary: "示例总结")),
            identity: identity,
            share: SystemShareAdapter(presenter: share),
            tempRootURL: root.url,
            clock: TestClock(utcDate: X.now),
            calendarProvider: TestCalendarProvider(timeZone: X.shanghai),
            ids: TestIDGenerator(ids: [UUID(uuidString: "c1000000-0000-4000-8000-000000000001")!]),
            logger: logger,
            limitAssertion: limitAssertion
        )
        let flow = try await useCases.beginFlow(studentID: X.studentID)
        return FlowHarness(flow: flow, identity: identity, share: share, logger: logger, root: root)
    }

    private func advance(_ flow: ArchiveExportFlow, through state: ArchiveExportFlowState) async throws {
        _ = try await flow.preview()
        if state == .previewing { return }
        try await flow.confirmPreview()
        if state == .confirmingFacts { return }
        try await flow.confirmFacts()
    }

    private func assertInvalidTransition(
        _ expected: ArchiveExportFlowState, line: UInt = #line, _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected invalidTransition", line: line)
        } catch {
            XCTAssertEqual(error as? ArchiveExportFlowError, .invalidTransition(from: expected), line: line)
        }
    }

    func testFlowCannotSkipPreviewConfirmationOrPasswordAndNeverGeneratesEarly() async throws {
        let h = try await makeFlow()
        let flow = h.flow
        var state = await flow.state
        XCTAssertEqual(state, .selecting)
        await assertInvalidTransition(.selecting) { try await flow.confirmPreview() }
        await assertInvalidTransition(.selecting) { try await flow.confirmFacts() }
        await assertInvalidTransition(.selecting) { _ = try await flow.submitPassword("长度足够的口令abc", confirmation: "长度足够的口令abc") }
        await assertInvalidTransition(.selecting) { _ = try await flow.deliver() }
        await assertInvalidTransition(.selecting) { _ = try await flow.retry() }

        _ = try await flow.preview()
        await assertInvalidTransition(.previewing) { try await flow.confirmFacts() }
        await assertInvalidTransition(.previewing) { _ = try await flow.submitPassword("长度足够的口令abc", confirmation: "长度足够的口令abc") }
        await assertInvalidTransition(.previewing) { _ = try await flow.preview() }
        await assertInvalidTransition(.previewing) { try await flow.setGroup(.bodyData, selected: false) }

        try await flow.confirmPreview()
        await assertInvalidTransition(.confirmingFacts) { _ = try await flow.submitPassword("长度足够的口令abc", confirmation: "长度足够的口令abc") }

        state = await flow.state
        XCTAssertEqual(state, .confirmingFacts)
        XCTAssertEqual(h.identity.calls, 0, "nothing was generated, so no identity was created")
        XCTAssertEqual(h.tempFiles, [])
        XCTAssertTrue(h.share.presentedURLs.isEmpty)
    }

    func testPasswordRulesBlockGenerationAndLeaveNoFile() async throws {
        let h = try await makeFlow()
        try await advance(h.flow, through: .settingPassword)

        for (entry, confirmation, expected) in [
            ("", "", ArchiveExportFlowError.passwordTooShort),
            ("1234567", "1234567", .passwordTooShort),
            ("长度足够的口令abc", "长度足够的口令abd", .passwordMismatch),
        ] {
            do {
                _ = try await h.flow.submitPassword(entry, confirmation: confirmation)
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? ArchiveExportFlowError, expected)
            }
        }
        let state = await h.flow.state
        XCTAssertEqual(state, .settingPassword)
        XCTAssertEqual(h.identity.calls, 0)
        XCTAssertEqual(h.tempFiles, [])

        let generated = try await h.flow.submitPassword("长度足够的口令abc", confirmation: "长度足够的口令abc")
        XCTAssertEqual(generated, .generated)
        XCTAssertEqual(h.identity.calls, 1)
        XCTAssertEqual(h.tempFiles.filter { $0.hasSuffix(".fcarchive") }.count, 1)
    }

    func testReturningToSelectionAndRegeneratingDropsDeselectedSummary() async throws {
        let h = try await makeFlow()
        let first = try await h.flow.preview()
        XCTAssertEqual(first.summaries.map(\.text), ["示例总结"])
        try await h.flow.back()
        var state = await h.flow.state
        XCTAssertEqual(state, .selecting)
        try await h.flow.setSelected(false, item: .summaries)
        let second = try await h.flow.preview()
        XCTAssertTrue(second.summaries.isEmpty)
        XCTAssertFalse(second.manifest.modules.summaries)

        try await h.flow.confirmPreview()
        try await h.flow.back()
        state = await h.flow.state
        XCTAssertEqual(state, .previewing)
        try await h.flow.confirmPreview()
        try await h.flow.confirmFacts()
        try await h.flow.back()
        state = await h.flow.state
        XCTAssertEqual(state, .confirmingFacts)
        await assertInvalidTransition(.confirmingFacts) { _ = try await h.flow.deliver() }
    }

    func testPreviewIsRefusedWhenNothingEffectiveIsSelected() async throws {
        let h = try await makeFlow()
        for group in ArchiveModuleGroup.allCases {
            try await h.flow.setGroup(group, selected: false)
        }
        do {
            _ = try await h.flow.preview()
            XCTFail("expected nothingSelected")
        } catch {
            XCTAssertEqual(error as? ArchiveExportFlowError, .nothingSelected)
        }
        let state = await h.flow.state
        XCTAssertEqual(state, .selecting)
    }

    func testNewFlowAlwaysStartsWithEverythingSelected() async throws {
        let first = try await makeFlow()
        try await first.flow.setGroup(.trainingContent, selected: false)
        let second = try await makeFlow()
        let selection = await second.flow.selection
        for item in selection.availability.allItems {
            XCTAssertEqual(selection.state(of: item), .selected)
        }
    }

    // MARK: Delivery mapping (AC-005, M2-FR-022/023)

    func testDeliveryOutcomesMapToStatesAndAlwaysDeleteTheTemporaryFile() async throws {
        let expectations: [(SystemShareOutcome, ArchiveExportFlowState, String?)] = [
            (.completed, .handedToSystem, "archive.export_handed_off"),
            (.cancelled, .cancelled, "archive.export_delivery_cancelled"),
            (.failed, .failed, "archive.export_failed"),
        ]
        for (outcome, expectedState, expectedEvent) in expectations {
            let h = try await makeFlow(outcomes: [outcome])
            try await advance(h.flow, through: .settingPassword)
            let generated = try await h.flow.submitPassword("长度足够的口令abc", confirmation: "长度足够的口令abc")
            XCTAssertEqual(generated, .generated)
            XCTAssertEqual(h.tempFiles.filter { $0.hasSuffix(".fcarchive") }.count, 1, "file exists while the system holds it")

            let result = try await h.flow.deliver()
            XCTAssertEqual(result, expectedState, "\(outcome)")
            XCTAssertEqual(h.tempFiles, [], "temporary archive is deleted after \(outcome)")
            XCTAssertEqual(h.logger.events, expectedEvent.map { [$0] } ?? [])
            let handed = try XCTUnwrap(h.share.presentedData.first ?? nil)
            XCTAssertEqual(handed.prefix(4), Data("FCPA".utf8), "the system was handed the encrypted archive")
        }
    }

    func testRetryAfterCancelRegeneratesFromMemoryWithoutRecreatingIdentity() async throws {
        let h = try await makeFlow(outcomes: [.cancelled, .completed])
        try await advance(h.flow, through: .settingPassword)
        let password = "长度足够的口令abc"
        _ = try await h.flow.submitPassword(password, confirmation: password)
        let cancelled = try await h.flow.deliver()
        XCTAssertEqual(cancelled, .cancelled)
        XCTAssertEqual(h.tempFiles, [])

        let retried = try await h.flow.retry()
        XCTAssertEqual(retried, .generated)
        let file = try XCTUnwrap(h.tempFiles.first { $0.hasSuffix(".fcarchive") })
        let bytes = try Data(contentsOf: h.root.url.appendingPathComponent(file))
        let kept = await h.flow.generatedSnapshot
        let snapshot = try XCTUnwrap(kept)
        XCTAssertEqual(try ArchiveFileCodec.decode(file: bytes, password: try ArchivePassword(importing: password)), snapshot)
        XCTAssertEqual(h.identity.calls, 1)

        let done = try await h.flow.deliver()
        XCTAssertEqual(done, .handedToSystem)
        XCTAssertEqual(h.tempFiles, [])
        await assertInvalidTransition(.handedToSystem) { _ = try await h.flow.retry() }
        let afterHandoff = await h.flow.generatedSnapshot
        XCTAssertNil(afterHandoff, "nothing is kept after the system took over")
    }

    func testIdentityFailureEndsInFailedWithoutAFileAndRetryRunsAgain() async throws {
        struct Boom: Error {}
        let identity = StubArchiveIdentity(failure: Boom())
        let h = try await makeFlow(identity: identity)
        try await advance(h.flow, through: .settingPassword)
        let password = "长度足够的口令abc"
        let failed = try await h.flow.submitPassword(password, confirmation: password)
        XCTAssertEqual(failed, .failed)
        XCTAssertEqual(h.tempFiles, [])
        XCTAssertEqual(h.logger.events, ["archive.export_failed"])

        identity.setFailure(nil)
        let retried = try await h.flow.retry()
        XCTAssertEqual(retried, .generated)
        XCTAssertEqual(identity.calls, 2)
    }

    func testLeavingTheFlowDeletesTheFileAndClosesIt() async throws {
        let h = try await makeFlow()
        try await advance(h.flow, through: .settingPassword)
        let password = "长度足够的口令abc"
        _ = try await h.flow.submitPassword(password, confirmation: password)
        XCTAssertFalse(h.tempFiles.isEmpty)
        await h.flow.leave()
        XCTAssertEqual(h.tempFiles, [])
        do {
            _ = try await h.flow.deliver()
            XCTFail("expected flowClosed")
        } catch {
            XCTAssertEqual(error as? ArchiveExportFlowError, .flowClosed)
        }
        await h.flow.leave()
    }

    func testSecondDeliverWhileTheSystemSheetIsOpenIsRejected() async throws {
        final class SlowPresenter: SystemSharePresenting, @unchecked Sendable {
            func present(fileURLs: [URL]) async -> SystemShareOutcome {
                try? await Task.sleep(nanoseconds: 400_000_000)
                return .completed
            }
        }
        let root = try TemporaryProtectedDirectory()
        let useCases = ArchiveExportUseCases(
            sourceReader: StubSourceReader(source: handSource(sessions: [handSession(day: 1, [handExercise()])])),
            identity: StubArchiveIdentity(),
            share: SystemShareAdapter(presenter: SlowPresenter()),
            tempRootURL: root.url,
            clock: TestClock(utcDate: X.now),
            calendarProvider: TestCalendarProvider(timeZone: X.shanghai),
            logger: RecordingLogger()
        )
        let flow = try await useCases.beginFlow(studentID: X.studentID)
        try await advance(flow, through: .settingPassword)
        _ = try await flow.submitPassword("长度足够的口令abc", confirmation: "长度足够的口令abc")

        async let first = flow.deliver()
        try await Task.sleep(nanoseconds: 100_000_000)
        do {
            _ = try await flow.deliver()
            XCTFail("expected deliveryInProgress")
        } catch {
            XCTAssertEqual(error as? ArchiveExportFlowError, .deliveryInProgress)
        }
        let result = try await first
        XCTAssertEqual(result, .handedToSystem)
    }

    // MARK: Limits (plan §7.3): log and assert only

    func testOverLimitExportLogsOnlyTheFixedEventAndStillProducesAFile() async throws {
        // 65 body metrics exceed the 64-metric limit.
        let metrics = (0..<65).map { index in
            ArchiveExportSource.BodyMetric(
                id: StableUUID(UUID()), kind: .custom, name: "示例指标\(index)", unit: "u",
                measurements: [.init(localDay: handDay(1), value: try! DecimalValue("1"), enteredUnit: "u")])
        }
        let flag = Flag()
        let h = try await makeFlow(source: handSource(sessions: [], metrics: metrics), limitAssertion: { flag.set() })
        try await advance(h.flow, through: .settingPassword)
        let state = try await h.flow.submitPassword("长度足够的口令abc", confirmation: "长度足够的口令abc")
        XCTAssertEqual(state, .generated, "export adds no user-visible state; the importer fails closed")
        XCTAssertEqual(h.logger.events, ["archive.export_limit_exceeded"])
        XCTAssertTrue(flag.isSet)
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set() { lock.lock(); value = true; lock.unlock() }
    }

    // MARK: Janitor

    func testJanitorRemovesLeftoverFlowDirectories() throws {
        let root = try TemporaryProtectedDirectory()
        var lease = ArchiveExportTempLease(rootURL: root.url, flowID: UUID())
        try lease.write(archive: Data("x".utf8), fileName: "FineCoach-档案-20261009-1600.fcarchive")
        XCTAssertFalse((try FileManager.default.contentsOfDirectory(atPath: root.url.path)).isEmpty)
        try ArchiveExportUseCases.cleanupOrphans(in: root.url)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.url.path), [])
        try ArchiveExportUseCases.cleanupOrphans(in: root.url)  // idempotent
    }

    // MARK: Hand-built source helpers

    private func handDay(_ day: Int) -> LocalDate { try! LocalDate(year: 2026, month: 9, day: day) }

    private func handSet() -> ArchiveSet {
        ArchiveSet(weightValue: try! DecimalValue("40"), repetitionCount: try! DecimalValue("8"), unit: .kilograms)
    }

    private func handCatalog() -> ArchiveExportSource.CatalogReference {
        .init(
            primaryMuscles: ["胸"], secondaryMuscles: ["肩"], equipment: "杠铃", sourceName: "wger.de",
            licenseName: "CC-BY-SA-3.0", licenseText: "示例许可文本")
    }

    private func handExercise(id: String = "builtin-1") -> ArchiveExportSource.Exercise {
        .init(identity: .stable(id), kind: .builtIn, isAssisted: false, name: "示例内置", catalog: handCatalog(),
              recordMode: .weightReps, sets: [handSet()])
    }

    private func handSession(day: Int, _ exercises: [ArchiveExportSource.Exercise], summary: String? = nil)
        -> ArchiveExportSource.Session
    {
        .init(
            completedAtUTC: Date(timeIntervalSince1970: 1_788_228_000 + Double(day) * 86_400),
            localDate: handDay(day), durationMinutes: 45, trainingFocus: [.chest], summary: summary,
            sections: [.init(name: nil, exercises: exercises)])
    }

    private func handSource(
        sessions: [ArchiveExportSource.Session],
        summary: String? = nil,
        metrics: [ArchiveExportSource.BodyMetric] = []
    ) -> ArchiveExportSource {
        let withSummary = sessions.map { session in
            ArchiveExportSource.Session(
                completedAtUTC: session.completedAtUTC, localDate: session.localDate,
                durationMinutes: session.durationMinutes, trainingFocus: session.trainingFocus,
                summary: summary ?? session.summary, sections: session.sections)
        }
        return .init(student: .init(displayName: "示例学员", sex: .other), sessions: withSummary, bodyMetrics: metrics)
    }
}
