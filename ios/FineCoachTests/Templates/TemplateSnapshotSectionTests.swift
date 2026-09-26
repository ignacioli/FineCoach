import FineCoach
import XCTest

/// T033: unit coverage for US3 (SC-004, AC-011) -- template deep-snapshot
/// application, save-as-template field exclusion, unified Section+Exercise
/// ordering, the mandatory non-empty-Section-deletion disposition, and the
/// cardio completion threshold (D-008).
final class TemplateSnapshotSectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let later = Date(timeIntervalSince1970: 1_700_100_000)
    private let studentID = StableUUID(UUID(uuidString: "A1111111-1111-4111-8111-111111111111")!)
    private let sessionID = StableUUID(UUID(uuidString: "A2222222-2222-4222-8222-222222222222")!)
    private let templateID = StableUUID(UUID(uuidString: "A3333333-3333-4333-8333-333333333333")!)
    private let squatExerciseID = StableUUID(UUID(uuidString: "A4444444-4444-4444-8444-444444444444")!)
    private let plankExerciseID = StableUUID(UUID(uuidString: "A5555555-5555-4555-8555-555555555555")!)
    private let sourceSectionID = StableUUID(UUID(uuidString: "A6666666-6666-4666-8666-666666666666")!)
    private let squatSetID = StableUUID(UUID(uuidString: "A7777777-7777-4777-8777-777777777777")!)

    // MARK: - Fixtures

    private func makeCompletedSession(privateNote: String, summary: String) throws -> Session {
        let squatSet = TrainingSet(
            id: squatSetID,
            sessionExerciseID: squatExerciseID,
            orderIndex: 0,
            state: .completed,
            recordMode: .weightReps,
            weightValue: try DecimalValue("60"),
            repetitionCount: try DecimalValue("5"),
            durationSeconds: nil,
            unit: .kilograms,
            side: .none,
            leftValue: nil,
            rightValue: nil,
            createdAtUTC: now,
            updatedAtUTC: now,
            completedAtUTC: now
        )
        let squat = SessionExercise(
            id: squatExerciseID,
            sessionID: sessionID,
            orderIndex: 0,
            sourceKind: .sessionOnly,
            sourceID: nil,
            displayNameSnapshot: try NormalizedName("深蹲"),
            recordModeSnapshot: .weightReps,
            actionPrivateNote: try ValidatedText("SUPER-SECRET-EXERCISE-NOTE"),
            sectionID: sourceSectionID,
            sets: [squatSet]
        )
        let plank = SessionExercise(
            id: plankExerciseID,
            sessionID: sessionID,
            orderIndex: 1,
            sourceKind: .sessionOnly,
            sourceID: nil,
            displayNameSnapshot: try NormalizedName("平板支撑"),
            recordModeSnapshot: .duration,
            actionPrivateNote: nil,
            sectionID: nil,
            sets: []
        )
        return Session(
            id: sessionID,
            studentID: studentID,
            state: .completed,
            startedAtUTC: now,
            lastCheckpointUTC: now,
            elapsedSeconds: .zero,
            interruptionStartedAtUTC: nil,
            durationNeedsReview: false,
            coachAdjustedDurationSeconds: nil,
            trainingFocus: [],
            studentFacingSummary: try ValidatedText(summary),
            privateCoachNote: try ValidatedText(privateNote),
            revision: 1,
            createdAtUTC: now,
            updatedAtUTC: now,
            completedAtUTC: now,
            exercises: [squat, plank]
        )
    }

    private func makeSourceSection() throws -> SessionSection {
        SessionSection(
            id: sourceSectionID,
            ownerKind: .session,
            ownerID: sessionID,
            name: try NormalizedName("热身"),
            orderIndex: 0
        )
    }

    // MARK: - M1B-FR-018: save-as-template field exclusion

    func testSnapshotFromSessionExcludesStudentIdentityAndPrivateFields() throws {
        let privateNote = "COACH-PRIVATE-NOTE-MUST-NOT-LEAK"
        let summary = "STUDENT-FACING-SUMMARY-MUST-NOT-LEAK"
        let session = try makeCompletedSession(privateNote: privateNote, summary: summary)
        let section = try makeSourceSection()

        let (exercises, sections) = TrainingTemplate.snapshotFromSession(
            session,
            existingSessionSections: [section],
            newTemplateID: templateID,
            newExerciseIDGenerator: { UUID() },
            newSectionIDGenerator: { UUID() }
        )

        // Structural: neither type HAS a field for any of these -- assert
        // that holds even under encoding, so a future careless field
        // addition that forgot to read from the right place would be
        // caught here too.
        let encoder = JSONEncoder()
        for exercise in exercises {
            let data = try encoder.encode(exercise)
            let json = String(data: data, encoding: .utf8) ?? ""
            XCTAssertFalse(json.contains(privateNote))
            XCTAssertFalse(json.contains(summary))
            XCTAssertFalse(json.contains("SUPER-SECRET-EXERCISE-NOTE"))
            XCTAssertFalse(json.contains(studentID.rawValue.uuidString))
        }
        for section in sections {
            let data = try encoder.encode(section)
            let json = String(data: data, encoding: .utf8) ?? ""
            XCTAssertFalse(json.contains(privateNote))
            XCTAssertFalse(json.contains(summary))
        }

        // Positive: the ordered Exercise list + planned Set shape WAS copied.
        XCTAssertEqual(exercises.count, 2)
        let copiedSquat = try XCTUnwrap(exercises.first { $0.displayNameSnapshot.value == "深蹲" })
        XCTAssertEqual(copiedSquat.plannedSets.count, 1)
        XCTAssertEqual(copiedSquat.plannedSets[0].weightValue?.canonicalString, try DecimalValue("60").canonicalString)
        XCTAssertEqual(copiedSquat.plannedSets[0].repetitionCount?.canonicalString, try DecimalValue("5").canonicalString)
        XCTAssertNotNil(copiedSquat.sectionID)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.name.value, "热身")
        XCTAssertEqual(sections.first?.ownerKind, .template)
    }

    // MARK: - M1B-FR-019/D-009: apply = independent deep-value snapshot

    func testApplyingTemplatePreFillsPendingSetsAndIsUnaffectedByLaterTemplateEdits() throws {
        let sourceSession = try makeCompletedSession(privateNote: "x", summary: "y")
        let sourceSection = try makeSourceSection()
        var (templateExercises, templateSections) = TrainingTemplate.snapshotFromSession(
            sourceSession,
            existingSessionSections: [sourceSection],
            newTemplateID: templateID,
            newExerciseIDGenerator: { UUID() },
            newSectionIDGenerator: { UUID() }
        )

        let targetSession = Session.start(id: StableUUID(UUID()), studentID: studentID, now: now)
        var generatedIDs: [UUID] = []
        func nextID() -> UUID {
            let id = UUID()
            generatedIDs.append(id)
            return id
        }

        let result = try TrainingTemplate.applying(
            exercises: templateExercises,
            sections: templateSections,
            to: targetSession,
            existingSessionSections: [],
            newExerciseIDGenerator: nextID,
            newSetIDGenerator: nextID,
            newSectionIDGenerator: nextID,
            now: now
        )

        // All applied Sets MUST be pending (M1B-FR-019).
        let appliedSets = result.session.exercises.flatMap(\.sets)
        XCTAssertFalse(appliedSets.isEmpty)
        XCTAssertTrue(appliedSets.allSatisfy { $0.state == .pending })
        XCTAssertEqual(result.session.completedSetCount, 0)

        // No reference back to the template: neither type carries a
        // templateID field, so nothing to even check for equality against --
        // this compiles precisely because SessionExercise/TrainingSet have
        // no such property.
        XCTAssertEqual(result.session.exercises.count, templateExercises.count)
        XCTAssertEqual(result.newSections.count, templateSections.count)

        // Unsectioned + sectioned Exercises coexist with an unambiguous
        // combined order (unique orderIndex across the union).
        let allOrderIndices = result.session.exercises.map(\.orderIndex) + result.newSections.map(\.orderIndex)
        XCTAssertEqual(Set(allOrderIndices).count, allOrderIndices.count)

        // Snapshot the applied Session's exercises/sets before "editing" the
        // template.
        let snapshotBeforeTemplateChange = result.session.exercises

        // Simulate editing/deleting the source template: mutate the LOCAL
        // arrays that were fed into `applying` (the only thing a template
        // edit/delete could ever act on) -- this MUST NOT be reachable from
        // the already-applied Session, because `applying` already returned
        // a fully independent value copy.
        templateExercises = []
        templateSections = []

        XCTAssertEqual(result.session.exercises, snapshotBeforeTemplateChange)
        XCTAssertFalse(result.session.exercises.isEmpty)
    }

    // MARK: - Unified order axis (T028)

    func testUnsectionedExercisesAndSectionsShareUnifiedUniqueOrder() throws {
        let sectionA = StableUUID(UUID())
        let sectionB = StableUUID(UUID())
        let exerciseA = StableUUID(UUID())
        let exerciseB = StableUUID(UUID())
        let exerciseC = StableUUID(UUID())

        let axis: [SessionSectionAxisItem] = [
            .exercise(exerciseA),
            .section(sectionA),
            .exercise(exerciseB),
            .section(sectionB),
            .exercise(exerciseC),
        ]
        let (sectionOrder, exerciseOrder) = try SessionSectionOrdering.renumbering(axis)

        XCTAssertEqual(exerciseOrder[exerciseA], 0)
        XCTAssertEqual(sectionOrder[sectionA], 1)
        XCTAssertEqual(exerciseOrder[exerciseB], 2)
        XCTAssertEqual(sectionOrder[sectionB], 3)
        XCTAssertEqual(exerciseOrder[exerciseC], 4)

        let allValues = Array(sectionOrder.values) + Array(exerciseOrder.values)
        XCTAssertEqual(Set(allValues).count, allValues.count)

        // Duplicate id in the axis MUST be rejected, not silently renumbered.
        XCTAssertThrowsError(try SessionSectionOrdering.renumbering([.exercise(exerciseA), .exercise(exerciseA)])) {
            XCTAssertEqual($0 as? DomainError, .conflict)
        }

        XCTAssertThrowsError(
            try SessionSectionOrdering.validateUnique(sectionOrderIndices: [0, 1], exerciseOrderIndices: [1])
        ) {
            XCTAssertEqual($0 as? DomainError, .conflict)
        }
        XCTAssertNoThrow(
            try SessionSectionOrdering.validateUnique(sectionOrderIndices: [0, 2], exerciseOrderIndices: [1, 3])
        )
    }

    // MARK: - M1B-FR-020/021: non-empty Section deletion requires a disposition

    func testDeletingNonEmptySectionRequiresDispositionAndMoveKeepsExercisesInSession() throws {
        let section = try makeSourceSection()
        let otherSection = SessionSection(
            id: StableUUID(UUID()),
            ownerKind: .session,
            ownerID: sessionID,
            name: try NormalizedName("其他"),
            orderIndex: 1
        )
        let memberIDs: Set<StableUUID> = [squatExerciseID]

        // Choosing "move elsewhere" MUST leave the Exercises in place
        // (nothing to delete) and relocate them to the target Section.
        let moveResolution = try SessionSectionOrdering.resolveSectionDeletion(
            sectionID: section.id,
            exerciseIDsInSection: memberIDs,
            disposition: .moveExercisesTo(sectionID: otherSection.id),
            existingSections: [section, otherSection]
        )
        XCTAssertTrue(moveResolution.exerciseIDsToDelete.isEmpty)
        XCTAssertEqual(moveResolution.relocatedSectionID, otherSection.id)
        XCTAssertFalse(moveResolution.survivingSections.contains { $0.id == section.id })
        XCTAssertTrue(moveResolution.survivingSections.contains { $0.id == otherSection.id })

        // With the Exercise now moved out, the (now-empty) Section is
        // trivially deletable -- re-resolving with an empty membership set
        // for the SAME disposition kind still succeeds and deletes nothing.
        let emptyResolution = try SessionSectionOrdering.resolveSectionDeletion(
            sectionID: section.id,
            exerciseIDsInSection: [],
            disposition: .deleteWithExercises,
            existingSections: [section, otherSection]
        )
        XCTAssertTrue(emptyResolution.exerciseIDsToDelete.isEmpty)

        // Choosing "delete with exercises" on the ORIGINAL non-empty Section
        // returns exactly its member ids for deletion.
        let deleteResolution = try SessionSectionOrdering.resolveSectionDeletion(
            sectionID: section.id,
            exerciseIDsInSection: memberIDs,
            disposition: .deleteWithExercises,
            existingSections: [section, otherSection]
        )
        XCTAssertEqual(deleteResolution.exerciseIDsToDelete, memberIDs)
        XCTAssertNil(deleteResolution.relocatedSectionID)

        // Deleting a Section that doesn't exist is a hard error, not a
        // silent no-op.
        XCTAssertThrowsError(
            try SessionSectionOrdering.resolveSectionDeletion(
                sectionID: StableUUID(UUID()),
                exerciseIDsInSection: [],
                disposition: .deleteWithExercises,
                existingSections: [section]
            )
        ) {
            XCTAssertEqual($0 as? DomainError, .notFound)
        }
    }

    // MARK: - M1B-FR-022/D-008: cardio completion threshold

    func testCardioCompletionRequiresDurationAndDistanceButSpeedAndResistanceAreOptional() throws {
        // duration only -- missing distance MUST NOT complete.
        let durationOnly = try TrainingSet.makeDraft(
            id: StableUUID(UUID()),
            sessionExerciseID: squatExerciseID,
            orderIndex: 0,
            input: TrainingSetInput(recordMode: .cardio, durationSeconds: "600", unit: .seconds),
            now: now
        )
        XCTAssertThrowsError(try durationOnly.confirmed(now: later)) {
            XCTAssertEqual($0 as? DomainError, .invalidNumber)
        }

        // distance only -- missing duration MUST NOT complete.
        let distanceOnly = try TrainingSet.makeDraft(
            id: StableUUID(UUID()),
            sessionExerciseID: squatExerciseID,
            orderIndex: 0,
            input: TrainingSetInput(recordMode: .cardio, unit: .seconds, distanceValue: "5"),
            now: now
        )
        XCTAssertThrowsError(try distanceOnly.confirmed(now: later)) {
            XCTAssertEqual($0 as? DomainError, .invalidNumber)
        }

        // duration>0 AND distance>0, no speed/resistance -- MUST complete.
        let minimal = try TrainingSet.makeDraft(
            id: StableUUID(UUID()),
            sessionExerciseID: squatExerciseID,
            orderIndex: 0,
            input: TrainingSetInput(recordMode: .cardio, durationSeconds: "600", unit: .seconds, distanceValue: "5"),
            now: now
        ).confirmed(now: later)
        XCTAssertEqual(minimal.state, .completed)
        XCTAssertTrue(minimal.contributesToStatistics)
        XCTAssertNil(minimal.speedValue)
        XCTAssertNil(minimal.resistanceValue)

        // duration>0 AND distance>0, WITH speed/resistance -- also completes,
        // and preserves the optional fields (never required, never dropped).
        let full = try TrainingSet.makeDraft(
            id: StableUUID(UUID()),
            sessionExerciseID: squatExerciseID,
            orderIndex: 0,
            input: TrainingSetInput(
                recordMode: .cardio,
                durationSeconds: "600",
                unit: .seconds,
                distanceValue: "5",
                speedValue: "0.5",
                resistanceValue: "3"
            ),
            now: now
        ).confirmed(now: later)
        XCTAssertEqual(full.state, .completed)
        XCTAssertEqual(full.speedValue?.canonicalString, try DecimalValue("0.5").canonicalString)
        XCTAssertEqual(full.resistanceValue?.canonicalString, try DecimalValue("3").canonicalString)

        // duration<=0 with distance>0 MUST NOT complete either.
        let zeroDuration = try TrainingSet.makeDraft(
            id: StableUUID(UUID()),
            sessionExerciseID: squatExerciseID,
            orderIndex: 0,
            input: TrainingSetInput(recordMode: .cardio, durationSeconds: "0", unit: .seconds, distanceValue: "5"),
            now: now
        )
        XCTAssertThrowsError(try zeroDuration.confirmed(now: later)) {
            XCTAssertEqual($0 as? DomainError, .invalidNumber)
        }

        // Existing weightReps/reps/duration modes MUST reject cardio fields
        // being set at all (purely additive, mode purity preserved).
        let contaminated = try TrainingSet.makeDraft(
            id: StableUUID(UUID()),
            sessionExerciseID: squatExerciseID,
            orderIndex: 0,
            input: TrainingSetInput(
                recordMode: .duration,
                durationSeconds: "10",
                unit: .seconds,
                distanceValue: "1"
            ),
            now: now
        )
        XCTAssertThrowsError(try contaminated.confirmed(now: later)) {
            XCTAssertEqual($0 as? DomainError, .invalidMode)
        }
    }
}
