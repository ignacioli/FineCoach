#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// M1-A regression coverage: `ActiveSessionViewModel.confirmSet`/`beginEditingSet`+
    /// `saveEditingSet`/`removeSet` MUST address a specific set by its explicit
    /// `StableUUID`, never by `exercise.sets.last`. Before the fix, confirming/editing/
    /// deleting one of two co-existing draft sets out of creation order left the
    /// other one stuck with no way to reach it from the UI. These tests drive the
    /// real `ActiveSessionViewModel` (not just the already-id-addressed use-case
    /// layer) against a real persistence-backed `ActiveSessionUseCases`, matching
    /// this target's existing session-flow test style.
    @MainActor
    final class ActiveSessionSetRowInteractionTests: XCTestCase {
        private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        private let sessionID = StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        private let exerciseID = StableUUID(UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        func testConfirmingOutOfOrderOnlyAffectsTheExplicitlyAddressedSet() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await makeLoadedViewModel(environment: environment)

            viewModel.weight = "40"
            viewModel.reps = "10"
            await viewModel.addDraftSet()
            viewModel.weight = "60"
            viewModel.reps = "8"
            await viewModel.addDraftSet()

            let exerciseAfterAdds = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID }))
            XCTAssertEqual(exerciseAfterAdds.sets.count, 2, "expected two independent draft sets")
            let firstSet = try XCTUnwrap(exerciseAfterAdds.sets.first)
            let secondSet = try XCTUnwrap(exerciseAfterAdds.sets.last)
            XCTAssertEqual(firstSet.state, .draft)
            XCTAssertEqual(secondSet.state, .draft)

            // Confirm the SECOND set first -- the exact scenario that used to be
            // impossible (old code always resolved to `.sets.last`, which
            // happened to already be the second set, masking the bug for THIS
            // direction) and, more importantly, must leave the first set
            // untouched.
            await viewModel.confirmSet(setID: secondSet.id)

            let afterFirstConfirm = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID }))
            let stillDraftFirst = try XCTUnwrap(afterFirstConfirm.sets.first { $0.id == firstSet.id })
            let confirmedSecond = try XCTUnwrap(afterFirstConfirm.sets.first { $0.id == secondSet.id })
            XCTAssertEqual(stillDraftFirst.state, .draft, "confirming set #2 must not affect set #1")
            XCTAssertEqual(confirmedSecond.state, .completed)
            XCTAssertEqual(stillDraftFirst.weightValue?.canonicalString, try DecimalValue("40").canonicalString)

            // Now confirm the FIRST set -- this is the case that was truly
            // broken before the fix: with two drafts present, there was no UI
            // path at all to address the earlier one once a later one existed.
            await viewModel.confirmSet(setID: firstSet.id)

            let afterSecondConfirm = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID }))
            let confirmedFirst = try XCTUnwrap(afterSecondConfirm.sets.first { $0.id == firstSet.id })
            let stillConfirmedSecond = try XCTUnwrap(afterSecondConfirm.sets.first { $0.id == secondSet.id })
            XCTAssertEqual(confirmedFirst.state, .completed)
            XCTAssertEqual(stillConfirmedSecond.state, .completed, "confirming set #1 must not affect set #2")
            XCTAssertEqual(viewModel.session?.completedSetCount, 2)

            try await environment.controller.shutdownForTesting()
        }

        func testEditingOutOfOrderOnlyAffectsTheExplicitlyAddressedSet() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await makeLoadedViewModel(environment: environment)

            viewModel.weight = "40"
            viewModel.reps = "10"
            await viewModel.addDraftSet()
            viewModel.weight = "60"
            viewModel.reps = "8"
            await viewModel.addDraftSet()

            let exercise = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID }))
            let firstSet = try XCTUnwrap(exercise.sets.first)
            let secondSet = try XCTUnwrap(exercise.sets.last)

            // Edit the FIRST set (the earlier one) while a later set already
            // exists -- must land on set #1's own fields, addressed by id, and
            // must not touch set #2 at all.
            viewModel.beginEditingSet(firstSet)
            XCTAssertEqual(viewModel.weight, "40", "inline edit must pre-fill from the addressed set, not the last one")
            viewModel.weight = "45"
            await viewModel.saveEditingSet()

            let afterEdit = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID }))
            let editedFirst = try XCTUnwrap(afterEdit.sets.first { $0.id == firstSet.id })
            let untouchedSecond = try XCTUnwrap(afterEdit.sets.first { $0.id == secondSet.id })
            XCTAssertEqual(editedFirst.weightValue?.canonicalString, try DecimalValue("45").canonicalString)
            XCTAssertEqual(untouchedSecond.weightValue?.canonicalString, try DecimalValue("60").canonicalString)
            XCTAssertNil(viewModel.editingSetID, "saving must collapse the inline editor")

            try await environment.controller.shutdownForTesting()
        }

        func testRemovingOutOfOrderOnlyAffectsTheExplicitlyAddressedSet() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await makeLoadedViewModel(environment: environment)

            viewModel.weight = "40"
            viewModel.reps = "10"
            await viewModel.addDraftSet()
            viewModel.weight = "60"
            viewModel.reps = "8"
            await viewModel.addDraftSet()

            let exercise = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID }))
            let firstSet = try XCTUnwrap(exercise.sets.first)
            let secondSet = try XCTUnwrap(exercise.sets.last)

            await viewModel.removeSet(setID: firstSet.id)

            let afterDelete = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID }))
            XCTAssertEqual(afterDelete.sets.map(\.id), [secondSet.id], "only the addressed set must be removed")

            try await environment.controller.shutdownForTesting()
        }

        /// P0-D14: 「保存」 on a completed set is its confirmation; the set
        /// stays completed and no rest starts.
        func testSavingAnEditedCompletedSetKeepsItCompletedWithoutRest() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await makeLoadedViewModel(environment: environment)

            viewModel.weight = "40"
            viewModel.reps = "10"
            await viewModel.confirmActiveDraftSet()
            let recorded = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID })?.sets.last)
            viewModel.dismissRest()

            viewModel.beginEditingSet(recorded)
            viewModel.weight = "42.5"
            await viewModel.saveEditingSet()

            let saved = try XCTUnwrap(
                viewModel.session?.exercises.first(where: { $0.id == exerciseID })?.sets.first { $0.id == recorded.id }
            )
            XCTAssertEqual(saved.state, .completed)
            XCTAssertEqual(saved.weightValue?.canonicalString, "42.5")
            XCTAssertEqual(viewModel.session?.completedSetCount, 1)
            XCTAssertNil(viewModel.restTimer, "saving an edit must not start a rest")
            XCTAssertNil(viewModel.editingSetID)

            try await environment.controller.shutdownForTesting()
        }

        /// P0-D11: the entry area only confirms; the just-recorded row offers
        /// 「撤销」, which deletes that set, ends the rest and puts its values
        /// back into the form.
        func testUndoRemovesTheJustConfirmedSetAndRestoresItsValues() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await makeLoadedViewModel(environment: environment)

            viewModel.weight = "40"
            viewModel.reps = "10"
            await viewModel.confirmActiveDraftSet()

            let recorded = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID })?.sets.last)
            XCTAssertEqual(recorded.state, .completed)
            XCTAssertEqual(viewModel.undoableSetID, recorded.id)
            XCTAssertNotNil(viewModel.restTimer)

            viewModel.weight = ""
            viewModel.reps = ""
            await viewModel.undoRecentSet()

            let afterUndo = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID }))
            XCTAssertTrue(afterUndo.sets.isEmpty, "undo must delete the just-recorded set")
            XCTAssertNil(viewModel.undoableSetID)
            XCTAssertNil(viewModel.restTimer, "undo must end the rest the set started")
            XCTAssertEqual(viewModel.weight, "40")
            XCTAssertEqual(viewModel.reps, "10")

            try await environment.controller.shutdownForTesting()
        }

        func testDeletingTheUndoableSetWithdrawsTheUndo() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await makeLoadedViewModel(environment: environment)

            viewModel.weight = "40"
            viewModel.reps = "10"
            await viewModel.confirmActiveDraftSet()
            let recorded = try XCTUnwrap(viewModel.undoableSetID)

            await viewModel.removeSet(setID: recorded)

            XCTAssertNil(viewModel.undoableSetID)

            try await environment.controller.shutdownForTesting()
        }

        // MARK: - Environment

        private struct Environment {
            let directory: TemporaryProtectedDirectory
            let controller: PersistenceController
            let studentUseCases: StudentUseCases
            let sessionUseCases: ActiveSessionUseCases
        }

        private func makeEnvironment() throws -> Environment {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let controller = try PersistenceController(storeURL: storeURL)
            let clock = TestClock(utcDate: now)
            let ids = TestIDGenerator(ids: [
                studentID.rawValue,
                sessionID.rawValue,
                exerciseID.rawValue,
                UUID(), UUID(), UUID(), UUID(), UUID(), UUID(), UUID(), UUID(),
            ])
            let studentRepository = CoreDataStudentRepository(writer: controller.writer)
            let sessionRepository = CoreDataSessionRepository(writer: controller.writer)
            return Environment(
                directory: directory,
                controller: controller,
                studentUseCases: StudentUseCases(
                    repository: studentRepository,
                    clock: clock,
                    ids: ids
                ),
                sessionUseCases: ActiveSessionUseCases(
                    sessionRepository: sessionRepository,
                    studentRepository: studentRepository,
                    exerciseRepository: CoreDataExerciseRepository(writer: controller.writer),
                    sectionRepository: CoreDataSessionSectionRepository(writer: controller.writer),
                    recoveryStore: ActiveSessionRecoveryStore(
                        url: directory.url.appendingPathComponent("active-session-recovery-v1.json"),
                        protectedFileStore: ProtectedFileStore()
                    ),
                    storeGenerationUUID: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
                    clock: clock,
                    ids: ids
                )
            )
        }

        private func makeLoadedViewModel(environment: Environment) async throws -> ActiveSessionViewModel {
            _ = try await environment.studentUseCases.create(
                draft: StudentDraft(displayName: "林青", sex: .female)
            )
            _ = try await environment.sessionUseCases.startOrOpen(studentID: studentID)
            _ = try await environment.sessionUseCases.addSessionOnlyExercise(
                displayName: "杠铃深蹲",
                recordMode: .weightReps
            )
            let viewModel = ActiveSessionViewModel(studentID: studentID, useCases: environment.sessionUseCases)
            await viewModel.load()
            viewModel.selectedExerciseID = exerciseID
            return viewModel
        }
    }
#else
    import XCTest

    final class ActiveSessionSetRowInteractionTests: XCTestCase {
        func testReleaseBuildSkipsTestableOnlyCoverage() {
            XCTAssertTrue(true)
        }
    }
#endif
