#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// Cardio's duration field is entered/displayed in minutes while
    /// `TrainingSet.durationSeconds` storage (Core Data, `Comparison`,
    /// `ShareReportDTO`) remains in seconds. These tests pin the conversion
    /// at the ViewModel boundary: `addDraftSet()`/`currentInput(for:)` must
    /// convert minutes -> seconds on write, and `beginEditingSet(_:)` must
    /// convert seconds -> minutes on read, without touching any other
    /// record mode's duration field (`.duration`, e.g. isometric holds,
    /// stays in seconds both ways).
    @MainActor
    final class ActiveSessionCardioDurationConversionTests: XCTestCase {
        private let studentID = StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
        private let sessionID = StableUUID(UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!)
        private let exerciseID = StableUUID(UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!)
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        func testAddingACardioSetConvertsMinutesInputToSecondsStorage() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await makeLoadedCardioViewModel(environment: environment)

            viewModel.duration = "5"
            viewModel.distance = "3"
            await viewModel.addDraftSet()

            let exercise = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID }))
            let set = try XCTUnwrap(exercise.sets.first)
            XCTAssertEqual(
                set.durationSeconds?.canonicalString, try DecimalValue("300").canonicalString,
                "5 minutes entered must be stored as 300 seconds, not 5 seconds"
            )

            try await environment.controller.shutdownForTesting()
        }

        func testAddingACardioSetHandlesFractionalMinutes() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await makeLoadedCardioViewModel(environment: environment)

            viewModel.duration = "1.5"
            viewModel.distance = "1"
            await viewModel.addDraftSet()

            let exercise = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID }))
            let set = try XCTUnwrap(exercise.sets.first)
            XCTAssertEqual(
                set.durationSeconds?.canonicalString, try DecimalValue("90").canonicalString,
                "1.5 minutes must round-trip to 90 seconds without truncation"
            )

            try await environment.controller.shutdownForTesting()
        }

        func testEditingAnExistingCardioSetDisplaysStoredSecondsAsMinutes() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await makeLoadedCardioViewModel(environment: environment)

            viewModel.duration = "10"
            viewModel.distance = "5"
            await viewModel.addDraftSet()
            let exercise = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID }))
            let set = try XCTUnwrap(exercise.sets.first)
            XCTAssertEqual(set.durationSeconds?.canonicalString, try DecimalValue("600").canonicalString)

            viewModel.beginEditingSet(set)

            XCTAssertEqual(
                viewModel.duration, "10",
                "editing a set stored as 600 seconds must pre-fill the minutes field as 10, not 600"
            )

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
                    storeGenerationUUID: UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!,
                    clock: clock,
                    ids: ids
                )
            )
        }

        private func makeLoadedCardioViewModel(environment: Environment) async throws -> ActiveSessionViewModel {
            _ = try await environment.studentUseCases.create(
                draft: StudentDraft(displayName: "陈涛", sex: .male)
            )
            _ = try await environment.sessionUseCases.startOrOpen(studentID: studentID)
            _ = try await environment.sessionUseCases.addSessionOnlyExercise(
                displayName: "越野跑",
                recordMode: .cardio
            )
            let viewModel = ActiveSessionViewModel(studentID: studentID, useCases: environment.sessionUseCases)
            await viewModel.load()
            viewModel.selectedExerciseID = exerciseID
            return viewModel
        }
    }
#else
    import XCTest

    final class ActiveSessionCardioDurationConversionTests: XCTestCase {
        func testReleaseBuildSkipsTestableOnlyCoverage() {
            XCTAssertTrue(true)
        }
    }
#endif
