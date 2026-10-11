import XCTest

@testable import FineCoach

/// T051 (US-2): rule-level checks of the viewer queries (M2-FR-030..032, D-009, M1B-FR-026/028).
/// No view is rendered. All data is fictional.
final class ArchiveViewerQueryTests: XCTestCase {
    private typealias F = ArchiveFixtures

    // MARK: Fixtures

    private func dec(_ raw: String) -> DecimalValue { F.decimal(raw) }

    private func weightSet(_ weight: String, _ reps: String) -> ArchiveSet {
        ArchiveSet(weightValue: dec(weight), repetitionCount: dec(reps), unit: .kilograms)
    }

    private func entry(_ key: String, _ sets: [ArchiveSet], mode: RecordMode = .weightReps) -> ArchiveSessionExercise {
        ArchiveSessionExercise(exerciseKey: key, recordMode: mode, sets: sets)
    }

    private func session(
        _ key: String,
        _ day: LocalDate,
        at seconds: TimeInterval,
        focus: Set<BodyPart>,
        _ entries: [ArchiveSessionExercise]
    ) -> ArchiveSession {
        ArchiveSession(
            key: key,
            localDate: day,
            completedAtUTC: Date(timeIntervalSince1970: seconds),
            durationMinutes: 50,
            trainingFocus: focus,
            sections: [ArchiveSection(name: nil, exercises: entries)]
        )
    }

    /// e1 ordinary load, e2 assisted load, e3 cardio. Three sessions, oldest first by key.
    private func trendSnapshot(
        modules: ArchiveModuleSet = F.modules(),
        withInfo: Bool = true
    ) -> ArchiveSnapshot {
        func info(_ name: String) -> ArchiveExerciseInfo? {
            withInfo ? ArchiveExerciseInfo(name: name, primaryMuscles: [], secondaryMuscles: [], equipment: "其他") : nil
        }
        let exercises = [
            ArchiveExercise(key: "e1", placeholderNumber: 1, kind: .builtIn, isAssisted: false, info: info("示例卧推")),
            ArchiveExercise(key: "e2", placeholderNumber: 2, kind: .custom, isAssisted: true, info: info("示例辅助引体")),
            ArchiveExercise(key: "e3", placeholderNumber: 3, kind: .oneOff, isAssisted: false, info: info("示例跑步")),
            ArchiveExercise(key: "e4", placeholderNumber: 4, kind: .custom, isAssisted: false, info: info("示例未使用动作")),
        ]
        let cardio = ArchiveSet(
            durationSeconds: dec("900"), unit: .seconds, distanceValue: dec("2.4"), speedValue: dec("9.6"),
            resistanceValue: dec("3")
        )
        let sessions = [
            session(
                "s1", F.day(2026, 9, 1), at: 1_788_246_000, focus: [.chest, .back],
                [
                    entry("e1", [weightSet("60", "8"), weightSet("62.5", "6")]),
                    entry("e2", [weightSet("30", "10"), weightSet("35", "8")]),
                    entry("e3", [cardio], mode: .cardio),
                ]
            ),
            session(
                "s2", F.day(2026, 9, 8), at: 1_788_850_800, focus: [],
                [
                    entry("e1", [weightSet("65", "5")]),
                    entry("e2", [weightSet("20", "8")]),
                ]
            ),
            session(
                "s3", F.day(2026, 9, 15), at: 1_789_455_600, focus: [.arms],
                [
                    entry("e1", [weightSet("65", "7"), weightSet("70", "3")]),
                    entry("e2", [weightSet("25", "8")]),
                ]
            ),
        ]
        return F.assemble(modules: modules, exercises: exercises, sessions: sessions)
    }

    private func content(_ snapshot: ArchiveSnapshot) -> ArchiveViewerContent {
        ArchiveViewerContent(snapshot: snapshot)
    }

    private func keys(_ sessions: [ArchiveSession]) -> [String] { sessions.map(\.key) }

    // MARK: Filtering (M2-FR-031)

    func testNoFilterListsEverySessionNewestFirst() throws {
        let view = content(trendSnapshot())
        XCTAssertEqual(keys(try view.sessions()), ["s3", "s2", "s1"])
    }

    func testDateRangeFilterIsInclusive() throws {
        let view = content(trendSnapshot())
        let range = F.day(2026, 9, 1)...F.day(2026, 9, 8)
        XCTAssertEqual(keys(try view.sessions(matching: ArchiveSessionFilter(dateRange: range))), ["s2", "s1"])
        let single = F.day(2026, 9, 8)...F.day(2026, 9, 8)
        XCTAssertEqual(keys(try view.sessions(matching: ArchiveSessionFilter(dateRange: single))), ["s2"])
        let none = F.day(2026, 10, 1)...F.day(2026, 10, 31)
        XCTAssertEqual(try view.sessions(matching: ArchiveSessionFilter(dateRange: none)), [])
    }

    func testBodyPartFilterMatchesAnySelectedPart() throws {
        let view = content(trendSnapshot())
        XCTAssertEqual(keys(try view.sessions(matching: ArchiveSessionFilter(trainingFocus: [.chest]))), ["s1"])
        // Multi-select is a union: back OR arms.
        XCTAssertEqual(
            keys(try view.sessions(matching: ArchiveSessionFilter(trainingFocus: [.back, .arms]))), ["s3", "s1"])
        XCTAssertEqual(try view.sessions(matching: ArchiveSessionFilter(trainingFocus: [.calves])), [])
        // A session without a training focus never matches a non-empty selection.
        let withEmptyFocus = try view.sessions(matching: ArchiveSessionFilter(trainingFocus: Set(BodyPart.allCases)))
        XCTAssertFalse(keys(withEmptyFocus).contains("s2"))
    }

    func testCriteriaCombineWithAnd() throws {
        let view = content(trendSnapshot())
        let filter = ArchiveSessionFilter(
            dateRange: F.day(2026, 9, 5)...F.day(2026, 9, 30),
            trainingFocus: [.chest, .arms]
        )
        XCTAssertEqual(keys(try view.sessions(matching: filter)), ["s3"])
    }

    func testFilteringDoesNotChangeTheSource() throws {
        let snapshot = trendSnapshot()
        let view = content(snapshot)
        _ = try view.sessions(matching: ArchiveSessionFilter(trainingFocus: [.chest], exerciseNameQuery: "卧推"))
        XCTAssertEqual(view.snapshot, snapshot)
    }

    // MARK: Name search (only with exercise info)

    func testNameSearchWorksWhenExerciseInfoIsIncluded() throws {
        let view = content(trendSnapshot())
        XCTAssertTrue(view.isNameSearchAvailable)
        XCTAssertEqual(
            keys(try view.sessions(matching: ArchiveSessionFilter(exerciseNameQuery: "卧推"))), ["s3", "s2", "s1"])
        XCTAssertEqual(keys(try view.sessions(matching: ArchiveSessionFilter(exerciseNameQuery: "跑步"))), ["s1"])
        XCTAssertEqual(try view.sessions(matching: ArchiveSessionFilter(exerciseNameQuery: "不存在")), [])
        // Whitespace only is "no query", not "match nothing".
        XCTAssertEqual(keys(try view.sessions(matching: ArchiveSessionFilter(exerciseNameQuery: "  "))).count, 3)
        // A name that only an exercise with no training record carries finds nothing.
        XCTAssertEqual(try view.sessions(matching: ArchiveSessionFilter(exerciseNameQuery: "未使用")), [])
        XCTAssertEqual(try view.exercises(nameQuery: "辅助").map(\.key), ["e2"])
    }

    func testNameSearchIsUnavailableWithoutExerciseInfo() throws {
        let modules = F.modules(exerciseInfo: false)
        let view = content(trendSnapshot(modules: modules, withInfo: false))
        XCTAssertFalse(view.isNameSearchAvailable)
        XCTAssertThrowsError(try view.sessions(matching: ArchiveSessionFilter(exerciseNameQuery: "卧推"))) {
            XCTAssertEqual($0 as? ArchiveViewerError, .moduleNotIncluded)
        }
        XCTAssertThrowsError(try view.exercises(nameQuery: "卧推")) {
            XCTAssertEqual($0 as? ArchiveViewerError, .moduleNotIncluded)
        }
        // The other filters and the placeholder list still work.
        XCTAssertEqual(keys(try view.sessions(matching: ArchiveSessionFilter(trainingFocus: [.chest]))), ["s1"])
        XCTAssertEqual(try view.exercises().map(\.placeholderNumber), [1, 2, 3])
        XCTAssertTrue(try view.exercises().allSatisfy { $0.info == nil })
    }

    // MARK: Trends and personal records (D-009)

    /// Re-builds the same sessions the way the Coach side stores them: random session and
    /// exercise-entry IDs, a catalog-style exercise ID, ordinary `TrainingSet`s.
    private func coachSide(
        _ snapshot: ArchiveSnapshot
    ) -> (sessions: [CompletedSession], exerciseID: [String: StableExerciseID], keyBySessionID: [StableUUID: String]) {
        var exerciseID: [String: StableExerciseID] = [:]
        for exercise in snapshot.exercises {
            exerciseID[exercise.key] = try! StableExerciseID("coach-catalog-\(UUID().uuidString)")
        }
        var keyBySessionID: [StableUUID: String] = [:]
        let sessions = snapshot.sessions.map { archived -> CompletedSession in
            let sessionID = StableUUID(UUID())
            keyBySessionID[sessionID] = archived.key
            var order: UInt32 = 0
            let exercises = archived.sections.flatMap(\.exercises).map { entry -> SessionExercise in
                let entryID = StableUUID(UUID())
                defer { order += 1 }
                let sets = entry.sets.enumerated().map { index, set in
                    TrainingSet(
                        id: StableUUID(UUID()), sessionExerciseID: entryID, orderIndex: UInt32(index),
                        state: .completed, recordMode: entry.recordMode, weightValue: set.weightValue,
                        repetitionCount: set.repetitionCount, durationSeconds: set.durationSeconds,
                        unit: set.unit, side: set.side, leftValue: set.leftValue, rightValue: set.rightValue,
                        distanceValue: set.distanceValue, speedValue: set.speedValue,
                        resistanceValue: set.resistanceValue, createdAtUTC: archived.completedAtUTC,
                        updatedAtUTC: archived.completedAtUTC, completedAtUTC: archived.completedAtUTC
                    )
                }
                return SessionExercise(
                    id: entryID, sessionID: sessionID, orderIndex: order, sourceKind: .builtIn,
                    sourceID: exerciseID[entry.exerciseKey], displayNameSnapshot: try! NormalizedName("示例动作"),
                    recordModeSnapshot: entry.recordMode, actionPrivateNote: nil, sets: sets
                )
            }
            return CompletedSession(
                id: sessionID, studentID: StableUUID(UUID()), studentDisplayName: try! NormalizedName("示例学员"),
                startedAtUTC: archived.completedAtUTC, completedAtUTC: archived.completedAtUTC,
                trainingFocus: archived.trainingFocus,
                notes: SessionNotes(privateCoachNote: nil, studentFacingSummary: nil, actionPrivateNotes: [:]),
                exercises: exercises,
                statistics: SessionStatistics(
                    completedSetCount: 0, displayedDurationSeconds: .zero, ordinaryTrainingVolume: nil),
                revision: 0, latestReport: nil
            )
        }
        return (sessions, exerciseID, keyBySessionID)
    }

    private struct PointShape: Equatable {
        let key: String?
        let completedAtUTC: Date
        let mode: RecordMode
        let maxWeight: DecimalValue?
        let bestReps: DecimalValue?
        let bestDuration: DecimalValue?
        let bestDistance: DecimalValue?
        let volume: DecimalValue?
        let weightDelta: DecimalValue?
        let asymmetry: DecimalValue?

        init(_ point: Comparison.SetTrendPoint, key: String?) {
            self.key = key
            completedAtUTC = point.completedAtUTC
            mode = point.recordMode
            maxWeight = point.maxWeight
            bestReps = point.bestReps
            bestDuration = point.bestDurationSeconds
            bestDistance = point.bestDistance
            volume = point.volume
            weightDelta = point.weightDelta
            asymmetry = point.asymmetry
        }
    }

    private struct RecordShape: Equatable {
        let highestWeight: DecimalValue?
        let highestWeightKey: String?
        let repsAtWeight: [DecimalValue]
        let repsAtWeightKey: String?
        let longestDuration: DecimalValue?
        let longestDistance: DecimalValue?

        init(_ set: Comparison.PersonalRecordSet, key: (StableUUID) -> String?) {
            highestWeight = set.highestWeight?.weight
            highestWeightKey = set.highestWeight.flatMap { key($0.sessionID) }
            repsAtWeight = set.mostRepsAtWeight.map { [$0.weight, $0.reps] } ?? []
            repsAtWeightKey = set.mostRepsAtWeight.flatMap { key($0.sessionID) }
            longestDuration = set.longestDuration?.seconds
            longestDistance = set.longestDistance?.distance
        }
    }

    func testAdapterMatchesTheCoachSideComparisonForOrdinaryAssistedAndCardioExercises() throws {
        let snapshot = trendSnapshot()
        let view = content(snapshot)
        let coach = coachSide(snapshot)
        let cases: [(String, RecordMode, Comparison.LoadDirection)] = [
            ("e1", .weightReps, .increaseIsImprovement),
            ("e2", .weightReps, .decreaseIsImprovement),
            ("e3", .cardio, .increaseIsImprovement),
        ]
        for (key, mode, direction) in cases {
            let coachID = try XCTUnwrap(coach.exerciseID[key])
            let expectedTrend = Comparison.exerciseTrend(
                exerciseID: coachID, recordMode: mode, across: coach.sessions, loadDirection: direction
            ).map { PointShape($0, key: nil) }
            let actualTrend = try view.trend(forExerciseKey: key, recordMode: mode).map { PointShape($0, key: nil) }
            XCTAssertFalse(actualTrend.isEmpty, key)
            XCTAssertEqual(actualTrend, expectedTrend, "trend of \(key)")

            let expectedRecords = RecordShape(
                Comparison.personalRecords(
                    exerciseID: coachID, recordMode: mode, across: coach.sessions, loadDirection: direction),
                key: { coach.keyBySessionID[$0] }
            )
            let actualRecords = RecordShape(
                try view.personalRecords(forExerciseKey: key, recordMode: mode),
                key: { view.sessionKey(for: $0) }
            )
            XCTAssertEqual(actualRecords, expectedRecords, "records of \(key)")
        }
    }

    func testAssistedExerciseUsesTheLowestLoadAsItsBest() throws {
        let view = content(trendSnapshot())
        XCTAssertEqual(view.loadDirection(forExerciseKey: "e2"), .decreaseIsImprovement)
        XCTAssertEqual(view.loadDirection(forExerciseKey: "e1"), .increaseIsImprovement)
        let assisted = try view.personalRecords(forExerciseKey: "e2", recordMode: .weightReps)
        XCTAssertEqual(assisted.highestWeight?.weight, dec("20"))
        XCTAssertEqual(view.sessionKey(for: try XCTUnwrap(assisted.highestWeight).sessionID), "s2")
        let ordinary = try view.personalRecords(forExerciseKey: "e1", recordMode: .weightReps)
        XCTAssertEqual(ordinary.highestWeight?.weight, dec("70"))
        // Per-session value of the assisted trend is the lowest assisted weight of that session.
        let trend = try view.trend(forExerciseKey: "e2", recordMode: .weightReps)
        XCTAssertEqual(trend.map(\.maxWeight), [dec("30"), dec("20"), dec("25")])
    }

    func testTrendsAreComputedOnlyFromArchiveSessionsWithArchiveLocalIdentity() throws {
        let snapshot = trendSnapshot()
        let view = content(snapshot)
        // Only sessions that contain the exercise contribute: e3 appears in s1 alone.
        XCTAssertEqual(try view.trend(forExerciseKey: "e3", recordMode: .cardio).count, 1)
        // The same exercise in another record mode is a different series (never combined).
        XCTAssertEqual(try view.trend(forExerciseKey: "e1", recordMode: .cardio).count, 0)
        XCTAssertEqual(view.recordModes(forExerciseKey: "e1"), [.weightReps])
        XCTAssertEqual(view.recordModes(forExerciseKey: "e3"), [.cardio])
        // Derived identities are deterministic, carry only the archive-local key and contain no UUID
        // that exists anywhere in the snapshot's own content.
        XCTAssertEqual(
            ArchiveComparisonAdapter.exerciseID(forKey: "e1"), ArchiveComparisonAdapter.exerciseID(forKey: "e1"))
        XCTAssertEqual(ArchiveComparisonAdapter.exerciseID(forKey: "e1").rawValue, "archive.exercise.e1")
        XCTAssertNotEqual(
            ArchiveComparisonAdapter.exerciseID(forKey: "e1"), ArchiveComparisonAdapter.exerciseID(forKey: "e2"))
        let first = ArchiveComparisonAdapter(snapshot: snapshot).completedSessions()
        let second = ArchiveComparisonAdapter(snapshot: snapshot).completedSessions()
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.id), snapshot.sessions.map { ArchiveComparisonAdapter.sessionID(forKey: $0.key) })
        XCTAssertTrue(
            first.flatMap(\.exercises).allSatisfy { $0.sourceID?.rawValue.hasPrefix("archive.exercise.") == true })
    }

    func testTrendsModuleIsNotSelectableWithoutTrainingRecords() throws {
        // The module set itself refuses trends without training records.
        XCTAssertThrowsError(
            try ArchiveModuleSet(
                displayName: false, sex: false, bodyData: false, trainingRecords: false,
                trends: true, summaries: true, exerciseInfo: false)
        ) { XCTAssertEqual($0 as? ArchiveSnapshotError, .moduleDependencyViolation) }

        // An archive without training records offers neither trends nor records nor sessions.
        let noRecords = content(F.summariesOnlySnapshot())
        XCTAssertFalse(noRecords.isTrendsAvailable)
        XCTAssertFalse(noRecords.hasTrainingRecords)
        XCTAssertThrowsError(try noRecords.trendExercises()) {
            XCTAssertEqual($0 as? ArchiveViewerError, .moduleNotIncluded)
        }
        XCTAssertThrowsError(try noRecords.trend(forExerciseKey: "e1", recordMode: .weightReps)) {
            XCTAssertEqual($0 as? ArchiveViewerError, .moduleNotIncluded)
        }
        XCTAssertThrowsError(try noRecords.sessions()) {
            XCTAssertEqual($0 as? ArchiveViewerError, .moduleNotIncluded)
        }

        // Training records without the trends module: browsing works, trends do not.
        let recordsOnly = content(trendSnapshot(modules: F.modules(trends: false)))
        XCTAssertFalse(recordsOnly.isTrendsAvailable)
        XCTAssertEqual(try recordsOnly.sessions().count, 3)
        XCTAssertThrowsError(try recordsOnly.personalRecords(forExerciseKey: "e1", recordMode: .weightReps)) {
            XCTAssertEqual($0 as? ArchiveViewerError, .moduleNotIncluded)
        }

        let full = content(trendSnapshot())
        XCTAssertTrue(full.isTrendsAvailable)
        XCTAssertEqual(try full.trendExercises().map(\.key), ["e1", "e2", "e3"], "unused e4 is not offered")
    }

    // MARK: Display settings (M2-FR-032)

    private func settings(
        _ weight: ArchiveDisplaySettings.WeightUnit = .kg,
        _ length: ArchiveDisplaySettings.LengthUnit = .cm
    ) -> ArchiveDisplayConverter {
        ArchiveDisplayConverter(settings: ArchiveDisplaySettings(weightUnit: weight, lengthUnit: length))
    }

    func testDisplayConversionChangesOnlyTheShownValueNotTheStoredOne() throws {
        let snapshot = F.fullSnapshot()
        let view = content(snapshot)
        let before = view.snapshot
        let metric = try XCTUnwrap(view.bodyMetrics().first { $0.key == "m1" })
        let measurement = try XCTUnwrap(try view.measurements(forMetricKey: "m1").first)
        XCTAssertEqual(measurement.value, dec("70.5"))

        let kg = settings(.kg).measurement(measurement, of: metric)
        XCTAssertEqual(kg, ArchiveDisplayQuantity(value: dec("70.5"), unit: "kg"))
        let lb = settings(.lb).measurement(measurement, of: metric)
        XCTAssertEqual(lb, ArchiveDisplayQuantity(value: dec("155.43"), unit: "lb"))

        XCTAssertEqual(view.snapshot, before)
        XCTAssertEqual(try view.measurements(forMetricKey: "m1").first?.value, dec("70.5"))
        XCTAssertEqual(try view.measurements(forMetricKey: "m1").map(\.enteredUnit), ["kg", "kg"])
    }

    func testBuiltInLengthsConvertAndPercentagesDoNot() throws {
        let height = try ArchiveBodyMetric(key: "m1", kind: .builtIn(.height))
        let fat = try ArchiveBodyMetric(key: "m2", kind: .builtIn(.bodyFatPercent))
        let heightValue = ArchiveBodyMeasurement(metricKey: "m1", localDay: F.day(2026, 9, 1), value: dec("170"), enteredUnit: "cm")
        let fatValue = ArchiveBodyMeasurement(metricKey: "m2", localDay: F.day(2026, 9, 1), value: dec("18.5"), enteredUnit: "%")
        XCTAssertEqual(
            settings(.kg, .inch).measurement(heightValue, of: height),
            ArchiveDisplayQuantity(value: dec("66.93"), unit: "in"))
        XCTAssertEqual(
            settings(.kg, .cm).measurement(heightValue, of: height),
            ArchiveDisplayQuantity(value: dec("170"), unit: "cm"))
        XCTAssertEqual(
            settings(.lb, .inch).measurement(fatValue, of: fat),
            ArchiveDisplayQuantity(value: dec("18.5"), unit: "%"))
    }

    func testCustomMetricsKeepTheUnitTheyWereEnteredIn() throws {
        let custom = try ArchiveBodyMetric(key: "m2", kind: .custom, name: "示例围度", unit: "cm")
        let neck = ArchiveBodyMeasurement(metricKey: "m2", localDay: F.day(2026, 9, 8), value: dec("34"), enteredUnit: "cm")
        let pounds = ArchiveBodyMeasurement(metricKey: "m2", localDay: F.day(2026, 9, 9), value: dec("10"), enteredUnit: "kg")
        for converter in [settings(.lb, .inch), settings(.kg, .cm)] {
            XCTAssertEqual(
                converter.measurement(neck, of: custom), ArchiveDisplayQuantity(value: dec("34"), unit: "cm"))
            XCTAssertEqual(
                converter.measurement(pounds, of: custom), ArchiveDisplayQuantity(value: dec("10"), unit: "kg"))
        }
    }

    func testSetWeightsConvertBetweenKilogramsAndPounds() {
        XCTAssertEqual(
            settings(.lb).weight(dec("60"), storedUnit: .kilograms),
            ArchiveDisplayQuantity(value: dec("132.28"), unit: "lb"))
        XCTAssertEqual(
            settings(.kg).weight(dec("60"), storedUnit: .kilograms),
            ArchiveDisplayQuantity(value: dec("60"), unit: "kg"))
        XCTAssertEqual(
            settings(.kg).weight(dec("100"), storedUnit: .pounds),
            ArchiveDisplayQuantity(value: dec("45.36"), unit: "kg"))
        XCTAssertEqual(
            settings(.lb).weight(dec("100"), storedUnit: .pounds),
            ArchiveDisplayQuantity(value: dec("100"), unit: "lb"))
        XCTAssertEqual(
            settings(.lb).weight(dec("30"), storedUnit: .seconds), ArchiveDisplayQuantity(value: dec("30"), unit: ""))
    }

    // MARK: Store-backed use cases

    private func makeStore() -> ArchiveSnapshotStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveViewerQuery-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(ArchiveSnapshotStore.directoryName, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        return ArchiveSnapshotStore(rootURL: root)
    }

    func testLoadReturnsTheCommittedSnapshotAndNoArchiveWhenEmpty() async throws {
        let store = makeStore()
        let useCases = ArchiveViewerUseCases(store: store)
        do {
            _ = try await useCases.load()
            XCTFail("expected noArchive")
        } catch {
            XCTAssertEqual(error as? ArchiveViewerError, .noArchive)
        }
        let snapshot = F.fullSnapshot()
        try store.commit(snapshot: snapshot)
        let loaded = try await useCases.load()
        XCTAssertEqual(loaded.snapshot, snapshot)
        XCTAssertEqual(loaded.sourceLabel, ArchiveIdentityService.shortLabel(forSourceID: F.sourceID))
        XCTAssertEqual(loaded.studentDisplayName, "测试学员甲")
    }

    func testDisplaySettingsPersistAndNeverTouchTheArchive() async throws {
        let store = makeStore()
        let useCases = ArchiveViewerUseCases(store: store)
        XCTAssertEqual(useCases.displaySettings(), .defaults)
        XCTAssertThrowsError(try useCases.updateDisplaySettings(ArchiveDisplaySettings(weightUnit: .lb))) {
            XCTAssertEqual($0 as? ArchiveViewerError, .noArchive)
        }

        let snapshot = F.fullSnapshot()
        try store.commit(snapshot: snapshot)
        let chosen = ArchiveDisplaySettings(weightUnit: .lb, lengthUnit: .inch, density: .compact)
        try useCases.updateDisplaySettings(chosen)
        XCTAssertEqual(ArchiveViewerUseCases(store: store).displaySettings(), chosen)
        let reloaded = try await useCases.load()
        XCTAssertEqual(reloaded.snapshot, snapshot)
    }

    // MARK: No write surface (plan §5, M2-FR-033/034)

    func testViewerSourcesHoldNoCoachUseCasesAndNoArchiveWriteCalls() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("FineCoachApp/Core/Application/Archive")
        for name in ["ArchiveViewerUseCases.swift", "ArchiveComparisonAdapter.swift"] {
            let text = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            for forbidden in [
                "HistoryUseCases", "ExerciseLibraryUseCases", "StudentUseCases", "BodyDataUseCases",
                "PersistenceWriter", "Repository", ".commit(", "deleteAll", "atomicReplace",
            ] {
                XCTAssertFalse(text.contains(forbidden), "\(name) must not reference \(forbidden)")
            }
        }
    }
}
