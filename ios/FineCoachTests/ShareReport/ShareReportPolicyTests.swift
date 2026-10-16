import FineCoach
import XCTest

final class ShareReportPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    private let sessionID = StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
    private let squatID = StableUUID(UUID(uuidString: "33333333-3333-4333-8333-333333333333")!)
    private let plankID = StableUUID(UUID(uuidString: "44444444-4444-4444-8444-444444444444")!)
    private let pullUpID = StableUUID(UUID(uuidString: "55555555-5555-4555-8555-555555555555")!)
    private let squatSetID = StableUUID(UUID(uuidString: "66666666-6666-4666-8666-666666666666")!)
    private let draftSetID = StableUUID(UUID(uuidString: "77777777-7777-4777-8777-777777777777")!)
    private let pendingSetID = StableUUID(UUID(uuidString: "88888888-8888-4888-8888-888888888888")!)
    private let plankSetID = StableUUID(UUID(uuidString: "99999999-9999-4999-8999-999999999999")!)
    private let pullUpSetID = StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)

    private let studentDisplayName = "林青"
    private let reportNameOverride = "报告用名"
    private let trainingFocusParts: Set<BodyPart> = [.chest, .core]
    private let trainingFocusText = "胸、核心"
    private let studentFacingSummaryText = "合成课后总结"
    private let privateCoachNoteText = "合成教练备注 女 13800001111"
    private let actionPrivateNoteText = "合成动作备注 linqing_test 合成伤病注意事项"
    private let phoneSentinel = "13800001111"
    private let injurySentinel = "合成伤病注意事项"
    private let sexSentinel = "女"

    private static let allowedShareReportDTOPropertyNames: Set<String> = [
        "schemaVersion",
        "studentDisplayName",
        "sessionDateUTC",
        "durationSeconds",
        "trainingFocus",
        "studentFacingSummary",
        "trainingVolume",
        "exercises",
        "personalBests",
    ]

    // T069j (schema 2): catalog-derived icon and body parts per exercise —
    // training-performance presentation data, never the student's body data.
    private static let allowedShareReportExerciseDTOPropertyNames: Set<String> = [
        "displayName",
        "confirmedSets",
        "equipmentIcon",
        "primaryBodyPart",
        "secondaryBodyParts",
    ]

    private static let allowedShareReportSetDTOPropertyNames: Set<String> = [
        "orderIndex",
        "recordMode",
        "weightValue",
        "repetitionCount",
        "durationSeconds",
        "unit",
        "side",
        "leftValue",
        "rightValue",
        "distanceValue",
        "speedValue",
        "resistanceValue",
    ]

    private static let requiredForbiddenIdentifierTokens: [String] = [
        "sex",
        "injury",
        "phone",
        "wechat",
        "privateCoach",
        "actionPrivate",
        "recipient",
        "delivery",
        "sent",
        "revoked",
        "bodyMass",
        "bodyFat",
        "StudentMO",
    ]

    func testAllowlistMirrorMatchesFrozenDTOProperties() throws {
        let completed = try makeCompleted(includingNotes: true, includingUnresolvedSets: false)
        let dto = try ShareReportPolicy.makeDTO(from: completed)
        XCTAssertEqual(dto.schemaVersion, ShareReportPolicy.schemaVersion)
        XCTAssertEqual(ShareReportPolicy.schemaVersion, 2)

        XCTAssertEqual(propertyLabels(dto), Self.allowedShareReportDTOPropertyNames)
        XCTAssertEqual(propertyLabels(dto), ShareReportPolicy.allowedDTOPropertyNames)
        XCTAssertEqual(
            ShareReportPolicy.allowedDTOPropertyNames,
            Self.allowedShareReportDTOPropertyNames
        )
        XCTAssertEqual(Mirror(reflecting: dto).children.count, Self.allowedShareReportDTOPropertyNames.count)

        let exercise = try XCTUnwrap(dto.exercises.first)
        XCTAssertEqual(propertyLabels(exercise), Self.allowedShareReportExerciseDTOPropertyNames)
        XCTAssertEqual(
            Mirror(reflecting: exercise).children.count,
            Self.allowedShareReportExerciseDTOPropertyNames.count
        )

        let trainingSet = try XCTUnwrap(exercise.confirmedSets.first)
        XCTAssertEqual(propertyLabels(trainingSet), Self.allowedShareReportSetDTOPropertyNames)
        XCTAssertEqual(
            Mirror(reflecting: trainingSet).children.count,
            Self.allowedShareReportSetDTOPropertyNames.count
        )

        let standaloneExercise = ShareReportExerciseDTO(displayName: "杠铃深蹲", confirmedSets: [])
        XCTAssertEqual(propertyLabels(standaloneExercise), Self.allowedShareReportExerciseDTOPropertyNames)
        let standaloneSet = ShareReportSetDTO(
            orderIndex: 0,
            recordMode: .weightReps,
            weightValue: nil,
            repetitionCount: nil,
            durationSeconds: nil,
            unit: .kilograms,
            side: .none,
            leftValue: nil,
            rightValue: nil
        )
        XCTAssertEqual(propertyLabels(standaloneSet), Self.allowedShareReportSetDTOPropertyNames)
    }

    // M1B-FR-030: personal bests are off unless the coach opts in for this
    // generation; the default DTO carries none.
    func testPersonalBestsAreAbsentByDefault() throws {
        let completed = try makeCompleted(includingNotes: true, includingUnresolvedSets: false)
        XCTAssertTrue(try ShareReportPolicy.makeDTO(from: completed).personalBests.isEmpty)

        let optedIn = try ShareReportPolicy.makeDTO(
            from: completed,
            personalBests: [
                ShareReportPersonalBestDTO(displayName: "杠铃深蹲", kind: .highestWeight, weightValue: DecimalValue("40"))
            ]
        )
        XCTAssertEqual(optedIn.personalBests.map(\.displayName), ["杠铃深蹲"])
    }

    func testForbiddenIdentifierTokensDoNotAppearOnDTOSurface() throws {
        let listed = ShareReportPolicy.forbiddenIdentifierTokens.map { $0.lowercased() }
        for token in Self.requiredForbiddenIdentifierTokens {
            XCTAssertTrue(
                listed.contains(token.lowercased()),
                "ShareReportPolicy.forbiddenIdentifierTokens must include \(token)"
            )
        }

        let completed = try makeCompleted(includingNotes: true, includingUnresolvedSets: false)
        let dto = try ShareReportPolicy.makeDTO(from: completed)
        let haystack = identifierSurface(dto: dto).lowercased()
        for token in ShareReportPolicy.forbiddenIdentifierTokens {
            XCTAssertFalse(
                haystack.contains(token.lowercased()),
                "forbidden identifier token \(token) appeared in DTO surface"
            )
        }
    }

    func testStudentFacingSummaryIsMappedAndPrivateFieldsAreOmitted() throws {
        let completed = try makeCompleted(includingNotes: true, includingUnresolvedSets: false)
        XCTAssertEqual(completed.notes.privateCoachNote?.value, privateCoachNoteText)
        XCTAssertEqual(completed.notes.studentFacingSummary?.value, studentFacingSummaryText)
        XCTAssertEqual(completed.notes.actionPrivateNotes[squatID]?.value, actionPrivateNoteText)

        let dto = try ShareReportPolicy.makeDTO(from: completed)
        XCTAssertEqual(dto.studentFacingSummary, studentFacingSummaryText)
        XCTAssertEqual(dto.trainingFocus, trainingFocusText)
        XCTAssertEqual(dto.studentDisplayName, studentDisplayName)

        let stringFields = dtoStringFields(dto)
        XCTAssertTrue(stringFields.contains(studentFacingSummaryText))
        XCTAssertFalse(stringFields.contains { $0.contains(privateCoachNoteText) })
        XCTAssertFalse(stringFields.contains { $0.contains(actionPrivateNoteText) })
        XCTAssertFalse(stringFields.contains { $0.contains(phoneSentinel) })
        XCTAssertFalse(stringFields.contains { $0.contains(injurySentinel) })
        XCTAssertFalse(stringFields.contains { $0.contains("linqing_test") })
        XCTAssertFalse(stringFields.contains { $0.contains(sexSentinel) })

        let withoutSummary = try makeCompleted(includingNotes: false, includingUnresolvedSets: false)
        XCTAssertNil(withoutSummary.notes.studentFacingSummary)
        var modules = ShareReportModuleSelection.privacySafeDefaults
        XCTAssertTrue(modules.includeStudentFacingSummary)
        let omitted = try ShareReportPolicy.makeDTO(from: withoutSummary, modules: modules)
        XCTAssertNil(omitted.studentFacingSummary)
    }

    func testTrainingVolumeDefaultsOffAndIsNotSticky() throws {
        XCTAssertTrue(ShareReportModuleSelection.privacySafeDefaults.includeStudentDisplayName)
        XCTAssertNil(ShareReportModuleSelection.privacySafeDefaults.studentDisplayNameOverride)
        XCTAssertTrue(ShareReportModuleSelection.privacySafeDefaults.includeDate)
        XCTAssertTrue(ShareReportModuleSelection.privacySafeDefaults.includeExercisesAndSets)
        XCTAssertTrue(ShareReportModuleSelection.privacySafeDefaults.includeDuration)
        XCTAssertTrue(ShareReportModuleSelection.privacySafeDefaults.includeTrainingFocus)
        XCTAssertTrue(ShareReportModuleSelection.privacySafeDefaults.includeStudentFacingSummary)
        XCTAssertFalse(ShareReportModuleSelection.privacySafeDefaults.includeTrainingVolume)

        let completed = try makeCompleted(includingNotes: true, includingUnresolvedSets: false)
        XCTAssertNotNil(completed.statistics.ordinaryTrainingVolume)

        let defaultDTO = try ShareReportPolicy.makeDTO(from: completed)
        XCTAssertNil(defaultDTO.trainingVolume)
        XCTAssertEqual(
            defaultDTO.durationSeconds?.canonicalString,
            completed.statistics.displayedDurationSeconds.canonicalString
        )
        XCTAssertEqual(defaultDTO.sessionDateUTC, completed.completedAtUTC)

        var enabled = ShareReportModuleSelection.privacySafeDefaults
        enabled.includeTrainingVolume = true
        let enabledDTO = try ShareReportPolicy.makeDTO(from: completed, modules: enabled)
        XCTAssertEqual(
            enabledDTO.trainingVolume?.canonicalString,
            completed.statistics.ordinaryTrainingVolume?.canonicalString
        )
        XCTAssertNotNil(enabledDTO.trainingVolume)

        XCTAssertFalse(ShareReportModuleSelection.privacySafeDefaults.includeTrainingVolume)
        let afterEnabled = try ShareReportPolicy.makeDTO(from: completed)
        XCTAssertNil(afterEnabled.trainingVolume)
        let againWithDefaults = try ShareReportPolicy.makeDTO(
            from: completed,
            modules: .privacySafeDefaults
        )
        XCTAssertNil(againWithDefaults.trainingVolume)
        XCTAssertFalse(ShareReportModuleSelection.privacySafeDefaults.includeTrainingVolume)
    }

    func testNameOverrideHideAndIncompleteSetsDoNotLeakVolume() throws {
        let completed = try makeCompleted(includingNotes: true, includingUnresolvedSets: true)
        XCTAssertEqual(completed.studentDisplayName.value, studentDisplayName)

        var override = ShareReportModuleSelection.privacySafeDefaults
        override.studentDisplayNameOverride = reportNameOverride
        let overrideDTO = try ShareReportPolicy.makeDTO(from: completed, modules: override)
        XCTAssertEqual(overrideDTO.studentDisplayName, reportNameOverride)
        XCTAssertEqual(completed.studentDisplayName.value, studentDisplayName)

        var hidden = ShareReportModuleSelection.privacySafeDefaults
        hidden.includeStudentDisplayName = false
        let hiddenDTO = try ShareReportPolicy.makeDTO(from: completed, modules: hidden)
        XCTAssertNil(hiddenDTO.studentDisplayName)
        XCTAssertEqual(completed.studentDisplayName.value, studentDisplayName)

        let dto = try ShareReportPolicy.makeDTO(from: completed)
        XCTAssertNil(dto.trainingVolume)
        XCTAssertEqual(Set(dto.exercises.map(\.displayName)), ["杠铃深蹲", "平板支撑", "引体向上"])

        let squat = try XCTUnwrap(dto.exercises.first { $0.displayName == "杠铃深蹲" })
        XCTAssertEqual(squat.confirmedSets.count, 1)
        XCTAssertEqual(squat.confirmedSets[0].orderIndex, 0)
        XCTAssertEqual(squat.confirmedSets[0].recordMode, .weightReps)
        XCTAssertEqual(squat.confirmedSets[0].side, .bilateral)
        XCTAssertEqual(squat.confirmedSets[0].weightValue?.canonicalString, try DecimalValue("40").canonicalString)
        XCTAssertEqual(squat.confirmedSets[0].repetitionCount?.canonicalString, try DecimalValue("8").canonicalString)
        XCTAssertEqual(squat.confirmedSets[0].leftValue?.canonicalString, try DecimalValue("10").canonicalString)
        XCTAssertEqual(squat.confirmedSets[0].rightValue?.canonicalString, try DecimalValue("12").canonicalString)

        let plank = try XCTUnwrap(dto.exercises.first { $0.displayName == "平板支撑" })
        XCTAssertEqual(plank.confirmedSets.count, 1)
        XCTAssertEqual(plank.confirmedSets[0].recordMode, .duration)
        XCTAssertEqual(plank.confirmedSets[0].durationSeconds?.canonicalString, try DecimalValue("30").canonicalString)

        let pullUp = try XCTUnwrap(dto.exercises.first { $0.displayName == "引体向上" })
        XCTAssertEqual(pullUp.confirmedSets.count, 1)
        XCTAssertEqual(pullUp.confirmedSets[0].recordMode, .reps)
        XCTAssertEqual(pullUp.confirmedSets[0].repetitionCount?.canonicalString, try DecimalValue("8").canonicalString)

        var withVolume = ShareReportModuleSelection.privacySafeDefaults
        withVolume.includeTrainingVolume = true
        let volumeDTO = try ShareReportPolicy.makeDTO(from: completed, modules: withVolume)
        XCTAssertEqual(
            volumeDTO.trainingVolume?.canonicalString,
            completed.statistics.ordinaryTrainingVolume?.canonicalString
        )
        XCTAssertEqual(Set(volumeDTO.exercises.map(\.displayName)), ["杠铃深蹲", "平板支撑", "引体向上"])
        XCTAssertEqual(volumeDTO.exercises.first { $0.displayName == "平板支撑" }?.confirmedSets.count, 1)
        XCTAssertEqual(volumeDTO.exercises.first { $0.displayName == "引体向上" }?.confirmedSets.count, 1)
    }

    func testSetLineFormatMatchesTrainingSetDisplaySummaryAcrossRecordModes() throws {
        let completed = try makeCompleted(includingNotes: false, includingUnresolvedSets: false)
        let dto = try ShareReportPolicy.makeDTO(from: completed)
        let lines = ShareReportPolicy.previewLines(for: dto)

        var assertedAtLeastOne = false
        for exercise in completed.exercises {
            for trainingSet in exercise.sets.filter(\.contributesToStatistics) {
                let expected = "组\(trainingSet.orderIndex + 1) " + trainingSet.displaySummary
                XCTAssertTrue(
                    lines.contains(expected),
                    "share report line must match TrainingSet.displaySummary format: \(expected)"
                )
                assertedAtLeastOne = true
            }
        }
        XCTAssertTrue(assertedAtLeastOne)
    }

    func testCardioSetCarriesDistanceSpeedResistanceIntoDTOAndSetLine() throws {
        let cardioExerciseID = StableUUID(UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
        let cardioSetID = StableUUID(UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!)

        var session = Session.start(id: sessionID, studentID: studentID, now: now)
        session = try session.addingSessionOnlyExercise(
            id: cardioExerciseID,
            displayName: "动感单车",
            recordMode: .cardio,
            now: now
        )
        session = try session.addingSet(
            exerciseID: cardioExerciseID,
            setID: cardioSetID,
            input: TrainingSetInput(
                recordMode: .cardio,
                durationSeconds: "630",
                unit: .seconds,
                distanceValue: "5.2",
                speedValue: "18.5",
                resistanceValue: "6"
            ),
            now: now
        )
        session = try session.confirmingSet(setID: cardioSetID, now: now)
        session = try session.finished(now: finishNow)
        let completed = try CompletedSession.make(
            from: session,
            studentDisplayName: NormalizedName(studentDisplayName)
        )

        let dto = try ShareReportPolicy.makeDTO(from: completed)
        let exercise = try XCTUnwrap(dto.exercises.first { $0.displayName == "动感单车" })
        let setDTO = try XCTUnwrap(exercise.confirmedSets.first)
        XCTAssertEqual(setDTO.distanceValue?.canonicalString, try DecimalValue("5.2").canonicalString)
        XCTAssertEqual(setDTO.speedValue?.canonicalString, try DecimalValue("18.5").canonicalString)
        XCTAssertEqual(setDTO.resistanceValue?.canonicalString, try DecimalValue("6").canonicalString)

        let trainingSet = try XCTUnwrap(
            completed.exercises.first { $0.displayNameSnapshot.value == "动感单车" }?.sets.first
        )
        let lines = ShareReportPolicy.previewLines(for: dto)
        let expectedLine = "组1 " + trainingSet.displaySummary
        XCTAssertTrue(lines.contains(expectedLine))
        // mm:ss formatting (matches DurationTextParser.formatForEditing), not raw "630s".
        XCTAssertTrue(expectedLine.contains("分"))
        XCTAssertFalse(lines.contains { $0.contains("630s") })
    }

    func testTrainingVolumePreviewLineIncludesKilogramUnit() throws {
        let completed = try makeCompleted(includingNotes: false, includingUnresolvedSets: false)
        var modules = ShareReportModuleSelection.privacySafeDefaults
        modules.includeTrainingVolume = true
        let dto = try ShareReportPolicy.makeDTO(from: completed, modules: modules)
        let volume = try XCTUnwrap(dto.trainingVolume)
        let lines = ShareReportPolicy.previewLines(for: dto)
        XCTAssertTrue(lines.contains("训练容量 \(volume.canonicalString) kg"))
    }

    private var finishNow: Date {
        now.addingTimeInterval(1_800)
    }

    private func makeCompleted(
        includingNotes: Bool,
        includingUnresolvedSets: Bool
    ) throws -> CompletedSession {
        var session = try sessionReadyToComplete(includingUnresolvedSets: includingUnresolvedSets)
        if includingUnresolvedSets {
            session = asCompleted(session, at: finishNow)
        } else {
            session = try session.finished(now: finishNow)
        }
        if includingNotes {
            session = try withThreeNoteKinds(session)
        }
        return try CompletedSession.make(
            from: session,
            studentDisplayName: NormalizedName(studentDisplayName)
        )
    }

    private func sessionReadyToComplete(includingUnresolvedSets: Bool) throws -> Session {
        var session = Session.start(id: sessionID, studentID: studentID, now: now)
        session = try session.addingSessionOnlyExercise(
            id: squatID,
            displayName: "杠铃深蹲",
            recordMode: .weightReps,
            now: now
        )
        session = try session.addingSessionOnlyExercise(
            id: plankID,
            displayName: "平板支撑",
            recordMode: .duration,
            now: now
        )
        session = try session.addingSessionOnlyExercise(
            id: pullUpID,
            displayName: "引体向上",
            recordMode: .reps,
            now: now
        )
        session = try session.addingSet(
            exerciseID: squatID,
            setID: squatSetID,
            input: TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "40",
                repetitionCount: "8",
                unit: .kilograms,
                side: .bilateral,
                leftValue: "10",
                rightValue: "12"
            ),
            now: now
        )
        session = try session.confirmingSet(setID: squatSetID, now: now)

        if includingUnresolvedSets {
            session = try session.addingSet(
                exerciseID: squatID,
                setID: draftSetID,
                input: TrainingSetInput(
                    recordMode: .weightReps,
                    weightValue: "80",
                    repetitionCount: "3",
                    unit: .kilograms
                ),
                now: now
            )
            session = try session.copyingSet(sourceSetID: squatSetID, newSetID: pendingSetID, now: now)
        }

        session = try session.addingSet(
            exerciseID: plankID,
            setID: plankSetID,
            input: TrainingSetInput(
                recordMode: .duration,
                durationSeconds: "30",
                unit: .seconds
            ),
            now: now
        )
        session = try session.confirmingSet(setID: plankSetID, now: now)
        session = try session.addingSet(
            exerciseID: pullUpID,
            setID: pullUpSetID,
            input: TrainingSetInput(
                recordMode: .reps,
                repetitionCount: "8",
                unit: .repetitions
            ),
            now: now
        )
        session = try session.confirmingSet(setID: pullUpSetID, now: now)
        return session.updatingTiming(
            elapsedSeconds: try DecimalValue("1800"),
            lastCheckpointUTC: finishNow,
            interruptionStartedAtUTC: nil,
            durationNeedsReview: false,
            now: finishNow
        )
    }

    private func asCompleted(_ session: Session, at date: Date) -> Session {
        Session(
            id: session.id,
            studentID: session.studentID,
            state: .completed,
            startedAtUTC: session.startedAtUTC,
            lastCheckpointUTC: session.lastCheckpointUTC,
            elapsedSeconds: session.elapsedSeconds,
            interruptionStartedAtUTC: session.interruptionStartedAtUTC,
            durationNeedsReview: session.durationNeedsReview,
            coachAdjustedDurationSeconds: session.coachAdjustedDurationSeconds,
            trainingFocus: session.trainingFocus,
            studentFacingSummary: session.studentFacingSummary,
            privateCoachNote: session.privateCoachNote,
            revision: session.revision,
            createdAtUTC: session.createdAtUTC,
            updatedAtUTC: date,
            completedAtUTC: date,
            exercises: session.exercises
        )
    }

    private func withThreeNoteKinds(_ session: Session) throws -> Session {
        let exercises = try session.exercises.map { exercise -> SessionExercise in
            guard exercise.id == squatID else {
                return exercise
            }
            return SessionExercise(
                id: exercise.id,
                sessionID: exercise.sessionID,
                orderIndex: exercise.orderIndex,
                sourceKind: exercise.sourceKind,
                sourceID: exercise.sourceID,
                displayNameSnapshot: exercise.displayNameSnapshot,
                recordModeSnapshot: exercise.recordModeSnapshot,
                actionPrivateNote: try ValidatedText(actionPrivateNoteText),
                sets: exercise.sets
            )
        }
        return Session(
            id: session.id,
            studentID: session.studentID,
            state: session.state,
            startedAtUTC: session.startedAtUTC,
            lastCheckpointUTC: session.lastCheckpointUTC,
            elapsedSeconds: session.elapsedSeconds,
            interruptionStartedAtUTC: session.interruptionStartedAtUTC,
            durationNeedsReview: session.durationNeedsReview,
            coachAdjustedDurationSeconds: session.coachAdjustedDurationSeconds,
            trainingFocus: trainingFocusParts,
            studentFacingSummary: try ValidatedText(studentFacingSummaryText),
            privateCoachNote: try ValidatedText(privateCoachNoteText),
            revision: session.revision,
            createdAtUTC: session.createdAtUTC,
            updatedAtUTC: session.updatedAtUTC,
            completedAtUTC: session.completedAtUTC,
            exercises: exercises
        )
    }

    private func propertyLabels<T>(_ value: T) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }

    private func identifierSurface(dto: ShareReportDTO) -> String {
        let exercise = dto.exercises.first ?? ShareReportExerciseDTO(displayName: "杠铃深蹲", confirmedSets: [])
        let trainingSet =
            exercise.confirmedSets.first
            ?? ShareReportSetDTO(
                orderIndex: 0,
                recordMode: .weightReps,
                weightValue: nil,
                repetitionCount: nil,
                durationSeconds: nil,
                unit: .kilograms,
                side: .none,
                leftValue: nil,
                rightValue: nil
            )
        let labels =
            propertyLabels(dto).sorted()
            + propertyLabels(exercise).sorted()
            + propertyLabels(trainingSet).sorted()
        let typeNames = [
            String(describing: ShareReportDTO.self),
            String(describing: ShareReportExerciseDTO.self),
            String(describing: ShareReportSetDTO.self),
        ]
        return (labels + typeNames).joined(separator: " ")
    }

    private func dtoStringFields(_ dto: ShareReportDTO) -> [String] {
        [dto.studentDisplayName, dto.trainingFocus, dto.studentFacingSummary].compactMap { $0 }
            + dto.exercises.map(\.displayName)
    }
}
