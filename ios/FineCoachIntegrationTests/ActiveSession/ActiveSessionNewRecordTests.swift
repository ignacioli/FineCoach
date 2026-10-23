#if DEBUG
    import XCTest

    @testable import FineCoach

    @MainActor
    final class ActiveSessionNewRecordTests: XCTestCase {
        private struct Harness {
            let directory: TemporaryProtectedDirectory
            let controller: PersistenceController
            let useCases: ActiveSessionUseCases
            let studentID: StableUUID
            let itemID: StableExerciseID
            let clock: TestClock
        }

        private func makeHarness() async throws -> Harness {
            let directory = try TemporaryProtectedDirectory()
            let controller = try PersistenceController(
                storeURL: directory.url.appendingPathComponent("generation/FineCoach.sqlite"))
            let clock = TestClock()
            let ids = TestIDGenerator(ids: (0..<80).map { _ in UUID() })
            let students = CoreDataStudentRepository(writer: controller.writer)
            let exercises = CoreDataExerciseRepository(writer: controller.writer)
            try await exercises.seedPlaceholderCatalogIfNeeded(now: clock.nowUTC())
            let entries = try await exercises.searchActive(query: "")
            let item = try XCTUnwrap(entries.first { $0.item.recordMode == .weightReps })
            let student = try await StudentUseCases(repository: students, clock: clock, ids: ids)
                .create(draft: StudentDraft(displayName: "合成学员", sex: .female))
            let useCases = ActiveSessionUseCases(
                sessionRepository: CoreDataSessionRepository(writer: controller.writer), studentRepository: students,
                exerciseRepository: exercises,
                sectionRepository: CoreDataSessionSectionRepository(writer: controller.writer),
                recoveryStore: ActiveSessionRecoveryStore(
                    url: directory.url.appendingPathComponent("recovery.json"), protectedFileStore: ProtectedFileStore()
                ),
                storeGenerationUUID: UUID(), clock: clock, ids: ids)
            return Harness(
                directory: directory, controller: controller, useCases: useCases, studentID: student.id,
                itemID: item.id, clock: clock)
        }

        private func startSession(_ harness: Harness) async throws -> ActiveSessionViewModel {
            _ = try await harness.useCases.startOrOpen(studentID: harness.studentID)
            _ = try await harness.useCases.addCatalogExercise(itemID: harness.itemID)
            let viewModel = ActiveSessionViewModel(studentID: harness.studentID, useCases: harness.useCases)
            await viewModel.load()
            return viewModel
        }

        @discardableResult
        private func confirm(_ viewModel: ActiveSessionViewModel, weight: String, reps: String) async throws
            -> StableUUID
        {
            viewModel.weight = weight
            viewModel.reps = reps
            await viewModel.confirmActiveDraftSet()
            viewModel.dismissRest()
            return try XCTUnwrap(viewModel.session?.exercises.first?.sets.last?.id)
        }

        /// A finished 80 kg x 5 Session, then a fresh Session on top of it.
        private func makeSessionAfterBaseline() async throws -> (Harness, ActiveSessionViewModel) {
            let harness = try await makeHarness()
            let baseline = try await startSession(harness)
            _ = try await confirm(baseline, weight: "80", reps: "5")
            _ = try await harness.useCases.finish()
            harness.clock.advance(seconds: 60)
            let viewModel = try await startSession(harness)
            return (harness, viewModel)
        }

        func testConfirmationTransfersHolderUndoRemovesItAndReloadRebuildsIt() async throws {
            let (harness, viewModel) = try await makeSessionAfterBaseline()
            let firstID = try await confirm(viewModel, weight: "85", reps: "5")
            XCTAssertEqual(viewModel.recordHolderSetIDs, [firstID])
            XCTAssertEqual(viewModel.strictRecordHolderSetIDs, [firstID])
            XCTAssertEqual(viewModel.confirmationFeedback?.isRecordImprovement, true)
            // Same weight, more reps: the badge moves to this set, but the main
            // metric did not beat the earlier set, so it is not a strict record.
            let repTransferID = try await confirm(viewModel, weight: "85", reps: "8")
            XCTAssertEqual(viewModel.recordHolderSetIDs, [repTransferID])
            XCTAssertTrue(viewModel.strictRecordHolderSetIDs.isEmpty)
            XCTAssertEqual(viewModel.confirmationFeedback?.isRecordImprovement, false)
            let secondID = try await confirm(viewModel, weight: "90", reps: "5")
            XCTAssertEqual(viewModel.recordHolderSetIDs, [secondID])
            XCTAssertEqual(viewModel.strictRecordHolderSetIDs, [secondID])
            XCTAssertEqual(viewModel.confirmationFeedback?.isRecordImprovement, true)
            let lastConfirmation = viewModel.confirmationFeedback
            await viewModel.undoRecentSet()
            XCTAssertEqual(viewModel.recordHolderSetIDs, [repTransferID])
            XCTAssertFalse(viewModel.recordHolderSetIDs.contains(secondID))
            XCTAssertTrue(viewModel.strictRecordHolderSetIDs.isEmpty)
            // Undo is recomputation only: it must not publish another event.
            XCTAssertEqual(viewModel.confirmationFeedback, lastConfirmation)
            let restored = ActiveSessionViewModel(studentID: harness.studentID, useCases: harness.useCases)
            await restored.load()
            XCTAssertEqual(restored.recordHolderSetIDs, viewModel.recordHolderSetIDs)
            XCTAssertEqual(restored.strictRecordHolderSetIDs, viewModel.strictRecordHolderSetIDs)
            XCTAssertNil(restored.confirmationFeedback, "reloading never replays a confirmation haptic")
            XCTAssertNil(viewModel.errorMessage)
            XCTAssertNil(restored.errorMessage)
            try await harness.controller.shutdownForTesting()
        }

        func testConfirmationFeedbackIsTrueOnlyForAStrictMainMetricImprovement() async throws {
            let harness = try await makeHarness()
            // First time doing the exercise: a baseline, so a plain success.
            let first = try await startSession(harness)
            _ = try await confirm(first, weight: "80", reps: "5")
            XCTAssertTrue(first.recordHolderSetIDs.isEmpty)
            XCTAssertEqual(first.confirmationFeedback?.isRecordImprovement, false)
            _ = try await harness.useCases.finish()
            harness.clock.advance(seconds: 60)
            let viewModel = try await startSession(harness)
            XCTAssertNil(viewModel.confirmationFeedback)

            // Equal to history: not a record.
            _ = try await confirm(viewModel, weight: "80", reps: "5")
            XCTAssertEqual(viewModel.confirmationFeedback?.isRecordImprovement, false)

            // Strictly heavier: a record.
            _ = try await confirm(viewModel, weight: "85", reps: "5")
            XCTAssertEqual(viewModel.confirmationFeedback?.isRecordImprovement, true)

            // Same weight, more reps: progress, but not a strict improvement.
            _ = try await confirm(viewModel, weight: "85", reps: "8")
            XCTAssertEqual(viewModel.confirmationFeedback?.isRecordImprovement, false)

            // Heavier again: a strict improvement over every earlier set.
            _ = try await confirm(viewModel, weight: "90", reps: "5")
            XCTAssertEqual(viewModel.confirmationFeedback?.isRecordImprovement, true)
            XCTAssertNil(viewModel.errorMessage)
            try await harness.controller.shutdownForTesting()
        }

        /// README §14.4 / components.md `DS-SET-ROW` 新纪录数值浮起: a confirmed
        /// strict record publishes exactly one float request for that set. A
        /// plain confirmation, progress without a strict main-metric
        /// improvement, or a same-weight repeat never publishes one.
        func testStrictRecordConfirmationPublishesExactlyOneFloatRequest() async throws {
            let (harness, viewModel) = try await makeSessionAfterBaseline()
            XCTAssertNil(viewModel.recordFloatRequest, "a fresh load publishes no float")

            let recordID = try await confirm(viewModel, weight: "85", reps: "5")
            let request = try XCTUnwrap(viewModel.recordFloatRequest)
            XCTAssertEqual(request.setID, recordID)
            XCTAssertEqual(request.sequence, 1)

            // Same weight, more reps: the marker moves to this set, but the
            // main metric did not improve, so nothing floats.
            let transferID = try await confirm(viewModel, weight: "85", reps: "8")
            XCTAssertEqual(viewModel.recordHolderSetIDs, [transferID])
            XCTAssertEqual(
                viewModel.recordFloatRequest, request,
                "a non-record confirmation must not publish or replace a float")

            // Strictly heavier again: a new, distinct request.
            let heavierID = try await confirm(viewModel, weight: "90", reps: "5")
            let next = try XCTUnwrap(viewModel.recordFloatRequest)
            XCTAssertEqual(next.setID, heavierID)
            XCTAssertGreaterThan(next.sequence, request.sequence)

            // Claimed once: the pending request is gone, and replaying the
            // stale claim cannot bring it back (the row never replays).
            viewModel.consumeRecordFloat(sequence: next.sequence)
            XCTAssertNil(viewModel.recordFloatRequest)
            viewModel.consumeRecordFloat(sequence: next.sequence)
            XCTAssertNil(viewModel.recordFloatRequest, "a consumed request is never re-triggered")
            XCTAssertNil(viewModel.errorMessage)
            try await harness.controller.shutdownForTesting()
        }

        /// D-FR-010 / README §14.4: editing, deleting, undoing, restoring and
        /// reloading are recomputation only -- they never publish a float.
        func testRecomputationNeverPublishesARecordFloatRequest() async throws {
            let (harness, viewModel) = try await makeSessionAfterBaseline()
            let setID = try await confirm(viewModel, weight: "85", reps: "5")
            let claimed = try XCTUnwrap(viewModel.recordFloatRequest)
            XCTAssertEqual(claimed.setID, setID)
            viewModel.consumeRecordFloat(sequence: claimed.sequence)
            XCTAssertNil(viewModel.recordFloatRequest)

            // Editing the confirmed set: recomputation only.
            let set = try XCTUnwrap(viewModel.session?.exercises.first?.sets.first)
            viewModel.beginEditingSet(set)
            viewModel.weight = "79"
            viewModel.reps = "5"
            await viewModel.saveEditingSet()
            XCTAssertNil(viewModel.errorMessage)
            XCTAssertNil(viewModel.recordFloatRequest, "editing must not publish a float")

            // Deleting a completed set, then restoring it: neither publishes.
            await viewModel.removeSet(setID: setID)
            XCTAssertNil(viewModel.errorMessage)
            XCTAssertNil(viewModel.recordFloatRequest)
            await viewModel.undoDeletedSet()
            XCTAssertNil(viewModel.errorMessage)
            XCTAssertNil(viewModel.recordFloatRequest)

            // A record confirmation publishes one; undoing it recomputes only.
            let recordID = try await confirm(viewModel, weight: "95", reps: "5")
            let published = try XCTUnwrap(viewModel.recordFloatRequest)
            XCTAssertEqual(published.setID, recordID)
            XCTAssertEqual(viewModel.undoableSetID, recordID)
            await viewModel.undoRecentSet()
            XCTAssertEqual(
                viewModel.recordFloatRequest, published,
                "undoing the confirmed set must not publish another float")

            // An unclaimed request is dropped by a reload, not played later.
            let reloadRecordID = try await confirm(viewModel, weight: "100", reps: "5")
            XCTAssertEqual(viewModel.recordFloatRequest?.setID, reloadRecordID)
            await viewModel.load()
            XCTAssertNil(viewModel.recordFloatRequest, "reloading drops any unclaimed float")
            XCTAssertTrue(viewModel.recordHolderSetIDs.contains(reloadRecordID))

            // Reloading (a new view model on the same session) publishes
            // nothing and has nothing left to replay.
            let restored = ActiveSessionViewModel(studentID: harness.studentID, useCases: harness.useCases)
            await restored.load()
            XCTAssertNil(restored.recordFloatRequest)
            XCTAssertNil(restored.confirmationFeedback)
            try await harness.controller.shutdownForTesting()
        }

        func testEditDeleteAndUndoDoNotPublishAnotherConfirmationEvent() async throws {
            let (harness, viewModel) = try await makeSessionAfterBaseline()
            let setID = try await confirm(viewModel, weight: "85", reps: "5")
            let published = try XCTUnwrap(viewModel.confirmationFeedback)
            XCTAssertTrue(published.isRecordImprovement)

            // Editing the confirmed set recomputes the marks but is not a
            // confirmation (D-FR-012).
            let set = try XCTUnwrap(viewModel.session?.exercises.first?.sets.first)
            viewModel.beginEditingSet(set)
            viewModel.weight = "79"
            viewModel.reps = "5"
            await viewModel.saveEditingSet()
            XCTAssertNil(viewModel.errorMessage)
            XCTAssertTrue(viewModel.recordHolderSetIDs.isEmpty)
            XCTAssertEqual(viewModel.confirmationFeedback, published)

            // Deleting a completed set is also recomputation only.
            await viewModel.removeSet(setID: setID)
            XCTAssertNil(viewModel.errorMessage)
            XCTAssertEqual(viewModel.confirmationFeedback, published)

            // A new confirmation publishes exactly one new event ...
            let newSetID = try await confirm(viewModel, weight: "85", reps: "5")
            let next = try XCTUnwrap(viewModel.confirmationFeedback)
            XCTAssertGreaterThan(next.sequence, published.sequence)
            XCTAssertTrue(next.isRecordImprovement)
            // ... and undoing it does not publish another.
            XCTAssertEqual(viewModel.undoableSetID, newSetID)
            await viewModel.undoRecentSet()
            XCTAssertEqual(viewModel.confirmationFeedback, next)
            try await harness.controller.shutdownForTesting()
        }
    }
#endif
