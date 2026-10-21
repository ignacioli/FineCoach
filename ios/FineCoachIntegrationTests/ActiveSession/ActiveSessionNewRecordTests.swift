#if DEBUG
    import XCTest

    @testable import FineCoach

    @MainActor
    final class ActiveSessionNewRecordTests: XCTestCase {
        func testConfirmationTransfersHolderUndoRemovesItAndReloadRebuildsIt() async throws {
            let directory = try TemporaryProtectedDirectory()
            let controller = try PersistenceController(
                storeURL: directory.url.appendingPathComponent("generation/FineCoach.sqlite"))
            let clock = TestClock()
            let ids = TestIDGenerator(ids: (0..<40).map { _ in UUID() })
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
            _ = try await useCases.startOrOpen(studentID: student.id)
            _ = try await useCases.addCatalogExercise(itemID: item.id)
            let first = ActiveSessionViewModel(studentID: student.id, useCases: useCases)
            await first.load()
            first.weight = "80"
            first.reps = "5"
            await first.confirmActiveDraftSet()
            XCTAssertTrue(first.recordHolderSetIDs.isEmpty, "first-time performance is a baseline")
            first.dismissRest()
            _ = try await useCases.finish()
            clock.advance(seconds: 60)
            _ = try await useCases.startOrOpen(studentID: student.id)
            _ = try await useCases.addCatalogExercise(itemID: item.id)
            let viewModel = ActiveSessionViewModel(studentID: student.id, useCases: useCases)
            await viewModel.load()
            viewModel.weight = "85"
            viewModel.reps = "5"
            await viewModel.confirmActiveDraftSet()
            let firstID = try XCTUnwrap(viewModel.session?.exercises.first?.sets.last?.id)
            XCTAssertEqual(viewModel.recordHolderSetIDs, [firstID])
            viewModel.dismissRest()
            viewModel.weight = "90"
            viewModel.reps = "5"
            await viewModel.confirmActiveDraftSet()
            let secondID = try XCTUnwrap(viewModel.session?.exercises.first?.sets.last?.id)
            XCTAssertEqual(viewModel.recordHolderSetIDs, [secondID])
            viewModel.dismissRest()
            await viewModel.undoRecentSet()
            XCTAssertEqual(viewModel.recordHolderSetIDs, [firstID])
            XCTAssertFalse(viewModel.recordHolderSetIDs.contains(secondID))
            let restored = ActiveSessionViewModel(studentID: student.id, useCases: useCases)
            await restored.load()
            XCTAssertEqual(restored.recordHolderSetIDs, viewModel.recordHolderSetIDs)
            XCTAssertNil(viewModel.errorMessage)
            XCTAssertNil(restored.errorMessage)
            try await controller.shutdownForTesting()
        }
    }
#endif
