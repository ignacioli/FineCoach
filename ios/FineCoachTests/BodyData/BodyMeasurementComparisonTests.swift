import FineCoach
import XCTest

/// Covers T035/T036 invariants: same-day upsert-as-edit semantics (including
/// a cross-timezone midnight boundary via the injected `LocalCalendarProvider`
/// test double, T007a), built-in vs custom unit-change semantics, deletion
/// removing a point from any derived trend, incompatible-trainingFocus
/// Sessions never merging, assisted-weight-decrease reading as improvement
/// without entering the plain-weight ranking, and the no-1RM/no-composite-
/// score prohibition (M1B-FR-025/027/028/029, D-005/D-007).
final class BodyMeasurementComparisonTests: XCTestCase {
    private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    private let metricID = StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Same-day upsert-as-edit (M1B-FR-025/D-005)

    func testReEnteringOnSameLocalDayEditsRatherThanDuplicates() throws {
        var index = BodyMeasurementDayIndex()
        let day = try LocalDate(year: 2026, month: 9, day: 12)

        let first = try index.upsert(
            studentID: studentID,
            metricID: metricID,
            localCalendarDay: day,
            value: try DecimalValue("70"),
            enteredUnit: "kg",
            newID: makeID(1),
            now: now
        )
        let second = try index.upsert(
            studentID: studentID,
            metricID: metricID,
            localCalendarDay: day,
            value: try DecimalValue("71"),
            enteredUnit: "kg",
            newID: makeID(2),
            now: now.addingTimeInterval(60)
        )

        XCTAssertEqual(index.measurements.count, 1, "re-entry on the same local day must edit, never duplicate")
        XCTAssertEqual(second.id, first.id, "editing keeps the original identity")
        XCTAssertEqual(index.history(studentID: studentID, metricID: metricID).first?.value.canonicalString, "71")
    }

    func testCrossTimezoneMidnightBoundaryProducesDistinctLocalDays() throws {
        // 23:30 in UTC+9 is still "today" locally, but the SAME instant is
        // already "tomorrow" in UTC. localCalendarDay MUST be derived via the
        // injected LocalCalendarProvider, never a hardcoded assumption.
        let utcPlus9 = TestCalendarProvider(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        let utc = TestCalendarProvider(timeZone: TimeZone(identifier: "UTC")!)

        // 2026-09-12 23:30 JST == 2026-09-12 14:30 UTC (no day rollover here);
        // pick an instant where JST is past midnight of the next day while
        // UTC is still on the previous day: 2026-09-12 15:30 UTC == 2026-09-13
        // 00:30 JST.
        let instant = try XCTUnwrap(
            DateComponents(
                calendar: Calendar(identifier: .gregorian),
                timeZone: TimeZone(identifier: "UTC"),
                year: 2026, month: 9, day: 12, hour: 15, minute: 30
            ).date
        )

        let jstDay = LocalDate(date: instant, calendar: utcPlus9.currentCalendar())
        let utcDay = LocalDate(date: instant, calendar: utc.currentCalendar())

        XCTAssertEqual(utcDay.canonicalString, "2026-09-12")
        XCTAssertEqual(
            jstDay.canonicalString, "2026-09-13", "the same instant lands on a different local calendar day in JST")
        XCTAssertNotEqual(jstDay, utcDay)

        // Recording the SAME instant under each calendar produces measurements
        // keyed to their own local day -- they must not collide.
        var index = BodyMeasurementDayIndex()
        let recordedJST = try BodyMeasurement.recordedNow(
            id: makeID(1), studentID: studentID, metricID: metricID,
            instant: instant, calendar: utcPlus9.currentCalendar(),
            value: try DecimalValue("70"), enteredUnit: "kg"
        )
        let recordedUTC = try BodyMeasurement.recordedNow(
            id: makeID(2), studentID: studentID, metricID: metricID,
            instant: instant, calendar: utc.currentCalendar(),
            value: try DecimalValue("70"), enteredUnit: "kg"
        )
        _ = try index.upsert(
            studentID: studentID, metricID: metricID, localCalendarDay: recordedJST.localCalendarDay,
            value: recordedJST.value, enteredUnit: recordedJST.enteredUnit, newID: recordedJST.id, now: instant
        )
        _ = try index.upsert(
            studentID: studentID, metricID: metricID, localCalendarDay: recordedUTC.localCalendarDay,
            value: recordedUTC.value, enteredUnit: recordedUTC.enteredUnit, newID: recordedUTC.id, now: instant
        )
        XCTAssertEqual(index.measurements.count, 2, "different local calendar days must never collapse into one row")
    }

    // MARK: - Unit-switch semantics (M1B-FR-025/D-005)

    func testBuiltInUnitConversionIsDisplayOnlyAndRoundTrips() throws {
        let canonicalKg = try DecimalValue("70")
        let pounds = try BuiltInUnitConversion.weight(canonicalKilograms: canonicalKg, displayedAs: .pounds)
        XCTAssertNotEqual(pounds.canonicalString, canonicalKg.canonicalString)

        let roundTripped = try BuiltInUnitConversion.roundTripKilograms(canonicalKg)
        XCTAssertEqual(
            NSDecimalNumber(decimal: roundTripped.decimal).rounding(accordingToBehavior: nil).stringValue,
            NSDecimalNumber(decimal: canonicalKg.decimal).rounding(accordingToBehavior: nil).stringValue
        )
        // Crucially: the canonical value itself is untouched by conversion.
        XCTAssertEqual(canonicalKg.canonicalString, "70")
    }

    /// Covers the fix for M1B-FR-025's display-unit switch: given the SAME
    /// saved canonical value, switching the display unit MUST recompute the
    /// shown number from it -- never a second stored value.
    func testCanonicalWeightConvertsToDisplayedPoundsAndBackWithoutMutation() throws {
        let canonicalKg = try DecimalValue("70")

        let displayedInPounds = try BuiltInUnitConversion.weight(canonicalKilograms: canonicalKg, displayedAs: .pounds)
        // 70 kg ~= 154.32 lb.
        XCTAssertEqual(
            NSDecimalNumber(decimal: displayedInPounds.decimal)
                .rounding(accordingToBehavior: NSDecimalNumberHandler(
                    roundingMode: .plain, scale: 1, raiseOnExactness: false, raiseOnOverflow: false,
                    raiseOnUnderflow: false, raiseOnDivideByZero: false))
                .stringValue,
            "154.3"
        )

        // The inverse of a display-unit entry converts back to the same
        // canonical value the display started from (within decimal rounding).
        let reenteredCanonical = try BuiltInUnitConversion.canonicalKilograms(
            fromDisplayed: displayedInPounds, unit: .pounds)
        XCTAssertEqual(
            NSDecimalNumber(decimal: reenteredCanonical.decimal).rounding(accordingToBehavior: nil).stringValue,
            NSDecimalNumber(decimal: canonicalKg.decimal).rounding(accordingToBehavior: nil).stringValue
        )
        // Still untouched.
        XCTAssertEqual(canonicalKg.canonicalString, "70")
    }

    func testCanonicalLengthConvertsToDisplayedInchesAndBackWithoutMutation() throws {
        let canonicalCm = try DecimalValue("180")

        let displayedInInches = try BuiltInUnitConversion.length(canonicalCentimeters: canonicalCm, displayedAs: .inches)
        // 180 cm ~= 70.87 in.
        XCTAssertEqual(
            NSDecimalNumber(decimal: displayedInInches.decimal)
                .rounding(accordingToBehavior: NSDecimalNumberHandler(
                    roundingMode: .plain, scale: 1, raiseOnExactness: false, raiseOnOverflow: false,
                    raiseOnUnderflow: false, raiseOnDivideByZero: false))
                .stringValue,
            "70.9"
        )

        let reenteredCanonical = try BuiltInUnitConversion.canonicalCentimeters(
            fromDisplayed: displayedInInches, unit: .inches)
        XCTAssertEqual(
            NSDecimalNumber(decimal: reenteredCanonical.decimal).rounding(accordingToBehavior: nil).stringValue,
            NSDecimalNumber(decimal: canonicalCm.decimal).rounding(accordingToBehavior: nil).stringValue
        )
        XCTAssertEqual(canonicalCm.canonicalString, "180")
    }

    /// Fix: display conversions were showing unbounded decimal tails (e.g.
    /// 70kg -> 154.32357982... lb). The DISPLAY value returned by
    /// `weight`/`length` MUST be rounded to 2 decimal places; the canonical
    /// stored value passed in must remain completely untouched.
    func testWeightDisplayConversionIsRoundedToTwoDecimalPlaces() throws {
        let canonicalKg = try DecimalValue("70")
        let pounds = try BuiltInUnitConversion.weight(canonicalKilograms: canonicalKg, displayedAs: .pounds)
        // 70 * 2.2046226218 = 154.323583526 -- rounded to 2dp is 154.32.
        XCTAssertEqual(pounds.canonicalString, "154.32")
        XCTAssertEqual(canonicalKg.canonicalString, "70", "the canonical value itself must never be rounded/mutated")

        // The identity case (no conversion) must still pass through exactly,
        // not get spuriously rounded.
        let identity = try BuiltInUnitConversion.weight(canonicalKilograms: canonicalKg, displayedAs: .kilograms)
        XCTAssertEqual(identity.canonicalString, "70")
    }

    func testLengthDisplayConversionIsRoundedToTwoDecimalPlaces() throws {
        let canonicalCm = try DecimalValue("180")
        let inches = try BuiltInUnitConversion.length(canonicalCentimeters: canonicalCm, displayedAs: .inches)
        // 180 * 0.3937007874 = 70.866141732 -- rounded to 2dp is 70.87.
        XCTAssertEqual(inches.canonicalString, "70.87")
        XCTAssertEqual(canonicalCm.canonicalString, "180", "the canonical value itself must never be rounded/mutated")
    }

    /// The kg/cm identity case (no conversion) MUST pass the value through
    /// unchanged in both directions.
    func testCanonicalConversionIsIdentityForTheCanonicalUnitItself() throws {
        let kg = try DecimalValue("62.5")
        XCTAssertEqual(
            try BuiltInUnitConversion.canonicalKilograms(fromDisplayed: kg, unit: .kilograms).canonicalString,
            "62.5"
        )
        let cm = try DecimalValue("165")
        XCTAssertEqual(
            try BuiltInUnitConversion.canonicalCentimeters(fromDisplayed: cm, unit: .centimeters).canonicalString,
            "165"
        )
    }

    func testCustomMetricCurrentUnitChangeNeverAltersExistingMeasurements() throws {
        let metric = try BodyMetricDefinition.makeCustom(
            id: metricID, studentID: studentID, name: "握力", unit: "kg", now: now
        )
        let measurement = try BodyMeasurement(
            id: makeID(1), studentID: studentID, metricID: metricID,
            localCalendarDay: try LocalDate(year: 2026, month: 9, day: 1),
            value: try DecimalValue("35"), enteredUnit: "kg",
            createdAtUTC: now, updatedAtUTC: now
        )

        let changed = try metric.changingCurrentUnit("lb", now: now.addingTimeInterval(3600))
        XCTAssertEqual(changed.currentUnit, "lb")
        // The existing measurement is a value type untouched by the metric
        // definition change -- still "35 kg", exactly as entered.
        XCTAssertEqual(measurement.value.canonicalString, "35")
        XCTAssertEqual(measurement.enteredUnit, "kg")
    }

    func testNoAPIExistsToReinterpretMeasurementsUnderANewUnit() {
        // Structural proof: `BodyMeasurement` has no DECLARED FUNCTION that
        // takes "a new unit" and returns "reinterpreted measurements" --
        // scanned from non-comment source lines only (doc comments
        // describing the absence, like this file's own, must not trip a
        // false positive).
        let source = codeLines(
            of: "FineCoachApp/Core/Domain/BodyMeasurement.swift"
        )
        let declarationLines = source.filter { $0.contains("func ") || $0.contains("static func ") }
        XCTAssertFalse(
            declarationLines.contains { $0.lowercased().contains("reinterpret") },
            "no reinterpretation function should be declared on BodyMeasurement"
        )
    }

    private func codeLines(of relativePath: String) -> [String] {
        let source = try! String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(relativePath),
            encoding: .utf8
        )
        return source.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    // MARK: - Delete removes the point from any derived trend (data-model §2.10)

    func testDeletingAMeasurementRemovesItFromHistory() throws {
        var index = BodyMeasurementDayIndex()
        let day = try LocalDate(year: 2026, month: 9, day: 12)
        let created = try index.upsert(
            studentID: studentID, metricID: metricID, localCalendarDay: day,
            value: try DecimalValue("70"), enteredUnit: "kg", newID: makeID(1), now: now
        )
        XCTAssertEqual(index.history(studentID: studentID, metricID: metricID).count, 1)
        index.delete(id: created.id)
        XCTAssertTrue(
            index.history(studentID: studentID, metricID: metricID).isEmpty,
            "deleted measurement must vanish from the derived history/trend")
    }

    // MARK: - Session comparison compatibility (M1B-FR-027/D-007)

    func testIncompatibleTrainingFocusSessionsNeverMerge() throws {
        let a = try makeCompletedSession(id: makeUUID(1), trainingFocus: [.arms], exercises: [])
        let b = try makeCompletedSession(id: makeUUID(2), trainingFocus: [], exercises: [])

        let result = Comparison.compareSessions(a, b)
        switch result {
        case .incompatibleTrainingFocus:
            break
        default:
            XCTFail("one empty + one non-empty trainingFocus must be incompatible, got \(result)")
        }
    }

    func testMatchingEmptyTrainingFocusIsCompatible() throws {
        let a = try makeCompletedSession(id: makeUUID(1), trainingFocus: [], exercises: [])
        let b = try makeCompletedSession(id: makeUUID(2), trainingFocus: [], exercises: [])

        let result = Comparison.compareSessions(a, b)
        switch result {
        case .compatible:
            break
        default:
            XCTFail("both nil/empty trainingFocus must be mutually compatible, got \(result)")
        }
    }

    func testIdenticalMultiPartSetsAreCompatibleRegardlessOfConstructionOrder() throws {
        let a = try makeCompletedSession(id: makeUUID(3), trainingFocus: [.chest, .core, .arms], exercises: [])
        let b = try makeCompletedSession(id: makeUUID(4), trainingFocus: [.arms, .chest, .core], exercises: [])

        let result = Comparison.compareSessions(a, b)
        switch result {
        case .compatible:
            break
        default:
            XCTFail("identical body-part sets must be compatible regardless of order, got \(result)")
        }
    }

    func testOverlappingButNotIdenticalSetsAreIncompatible() throws {
        // FR-027 is exact set equality, NOT the FR-026 any-overlap rule --
        // partial overlap must still be incompatible for comparison.
        let a = try makeCompletedSession(id: makeUUID(5), trainingFocus: [.chest, .arms], exercises: [])
        let b = try makeCompletedSession(id: makeUUID(6), trainingFocus: [.arms, .core], exercises: [])

        let result = Comparison.compareSessions(a, b)
        switch result {
        case .incompatibleTrainingFocus:
            break
        default:
            XCTFail("overlapping but non-identical body-part sets must be incompatible, got \(result)")
        }
    }

    // MARK: - Assisted-weight decrease reads as improvement (M1B-FR-028)

    func testAssistedWeightDecreaseIsARepresentableDistinctSignal() {
        // The Domain represents the two directions as distinct enum cases so
        // a caller can never average/combine them into a single ranking axis.
        let increase = Comparison.LoadDirection.increaseIsImprovement
        let decrease = Comparison.LoadDirection.decreaseIsImprovement
        XCTAssertNotEqual(String(describing: increase), String(describing: decrease))

        // Trend points expose the plain weightDelta only -- direction-agnostic
        // -- so the UI/Application layer applies LoadDirection itself, and an
        // assisted-load caller reading a NEGATIVE weightDelta as `decrease
        // IsImprovement` calls that progress, never regression.
        let exerciseID = try! StableExerciseID("assisted-pullup")
        let sessionEarlier = try! makeSessionWithWeight(
            sessionID: makeUUID(10), exerciseID: exerciseID, weight: "40", completedAt: now
        )
        let sessionLater = try! makeSessionWithWeight(
            sessionID: makeUUID(11), exerciseID: exerciseID, weight: "30", completedAt: now.addingTimeInterval(86_400)
        )
        let points = Comparison.exerciseTrend(
            exerciseID: exerciseID, recordMode: .weightReps, across: [sessionEarlier, sessionLater]
        )
        XCTAssertEqual(points.count, 2)
        let delta = points.last?.weightDelta
        XCTAssertNotNil(delta)
        XCTAssertTrue(delta!.decimal < 0, "the plain numeric delta is negative")
        // Applying LoadDirection.decreaseIsImprovement to this negative delta
        // is the caller's job -- Comparison itself never mixes this into
        // `PersonalRecordSet.highestWeight`'s plain "biggest number wins".
        let pr = Comparison.personalRecords(
            exerciseID: exerciseID, recordMode: .weightReps, across: [sessionEarlier, sessionLater])
        XCTAssertEqual(
            pr.highestWeight?.weight.canonicalString, "40",
            "highestWeight is always the plain numeric max, direction-agnostic")
    }

    // MARK: - No estimated 1RM / composite score (M1B-FR-029, hard prohibition)

    func testNoEstimatedOneRepMaxOrCompositeScoreAPIExists() throws {
        // Scanned from DECLARED FUNCTION/TYPE lines only (not doc comments,
        // which legitimately name the prohibition, including in this test's
        // own descriptions elsewhere in this file).
        let declarationLines = codeLines(of: "FineCoachApp/Core/Domain/Comparison.swift")
            .filter {
                $0.contains("func ") || $0.contains("struct ") || $0.contains("case ") || $0.contains("var ")
                    || $0.contains("let ")
            }
        let forbidden = ["1rm", "onerepmax", "estimatedmax", "strengthscore", "compositescore"]
        for token in forbidden {
            XCTAssertFalse(
                declarationLines.contains { $0.lowercased().contains(token) },
                "Comparison.swift must never DECLARE an estimated 1RM or composite/aggregate score (found '\(token)')"
            )
        }
    }

    // MARK: - Helpers

    private func makeID(_ n: Int) -> StableUUID {
        StableUUID(UUID(uuidString: String(format: "aaaaaaaa-0000-4000-8000-%012d", n))!)
    }

    private func makeUUID(_ n: Int) -> StableUUID {
        StableUUID(UUID(uuidString: String(format: "bbbbbbbb-0000-4000-8000-%012d", n))!)
    }

    private func makeCompletedSession(
        id: StableUUID,
        trainingFocus: Set<BodyPart>,
        exercises: [SessionExercise]
    ) throws -> CompletedSession {
        CompletedSession(
            id: id,
            studentID: studentID,
            studentDisplayName: try NormalizedName("学员"),
            startedAtUTC: now,
            completedAtUTC: now,
            trainingFocus: trainingFocus,
            notes: SessionNotes(privateCoachNote: nil, studentFacingSummary: nil, actionPrivateNotes: [:]),
            exercises: exercises,
            statistics: SessionStatistics(
                completedSetCount: 0, displayedDurationSeconds: .zero, ordinaryTrainingVolume: nil),
            revision: 1,
            latestReport: nil
        )
    }

    private func makeSessionWithWeight(
        sessionID: StableUUID,
        exerciseID: StableExerciseID,
        weight: String,
        completedAt: Date
    ) throws -> CompletedSession {
        let set = TrainingSet(
            id: StableUUID(UUID()),
            sessionExerciseID: StableUUID(UUID()),
            orderIndex: 0,
            state: .completed,
            recordMode: .weightReps,
            weightValue: try DecimalValue(weight),
            repetitionCount: try DecimalValue("8"),
            durationSeconds: nil,
            unit: .kilograms,
            side: .none,
            leftValue: nil,
            rightValue: nil,
            createdAtUTC: completedAt,
            updatedAtUTC: completedAt,
            completedAtUTC: completedAt
        )
        let exercise = SessionExercise(
            id: StableUUID(UUID()),
            sessionID: sessionID,
            orderIndex: 0,
            sourceKind: .builtIn,
            sourceID: exerciseID,
            displayNameSnapshot: try NormalizedName("助力引体向上"),
            recordModeSnapshot: .weightReps,
            actionPrivateNote: nil,
            sets: [set]
        )
        return CompletedSession(
            id: sessionID,
            studentID: studentID,
            studentDisplayName: try NormalizedName("学员"),
            startedAtUTC: completedAt,
            completedAtUTC: completedAt,
            trainingFocus: [],
            notes: SessionNotes(privateCoachNote: nil, studentFacingSummary: nil, actionPrivateNotes: [:]),
            exercises: [exercise],
            statistics: SessionStatistics(
                completedSetCount: 1, displayedDurationSeconds: .zero, ordinaryTrainingVolume: nil),
            revision: 1,
            latestReport: nil
        )
    }
}
