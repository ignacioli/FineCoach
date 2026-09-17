#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// Cardio's duration field accepts the same `DurationTextParser` text
    /// (e.g. "5分30秒" / "5m30s") as the `.duration` RecordMode, while
    /// `TrainingSet.durationSeconds` storage (Core Data, `Comparison`,
    /// `ShareReportDTO`) remains in whole seconds. These tests pin the
    /// conversion at the ViewModel boundary: `addDraftSet()`/
    /// `currentInput(for:)` must parse mm:ss text -> seconds on write, and
    /// `beginEditingSet(_:)` must format seconds -> mm:ss text on read.
    /// Superseded a prior decimal-minutes-only scheme (a bare "5" meant "5
    /// minutes"); a bare number is now always seconds, matching
    /// `DurationTextParser`'s single, mode-independent convention.
    @MainActor
    final class ActiveSessionCardioDurationConversionTests: XCTestCase {
        private let studentID = StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
        private let sessionID = StableUUID(UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!)
        private let exerciseID = StableUUID(UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!)
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        func testAddingACardioSetParsesMinutesAndSecondsTextToSecondsStorage() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await makeLoadedCardioViewModel(environment: environment)

            viewModel.duration = "5分"
            viewModel.distance = "3"
            await viewModel.addDraftSet()

            let exercise = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID }))
            let set = try XCTUnwrap(exercise.sets.first)
            XCTAssertEqual(
                set.durationSeconds?.canonicalString, try DecimalValue("300").canonicalString,
                "\"5分\" entered must be stored as 300 seconds"
            )

            try await environment.controller.shutdownForTesting()
        }

        func testAddingACardioSetHandlesFullMinutesAndSecondsFormat() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await makeLoadedCardioViewModel(environment: environment)

            viewModel.duration = "1分30秒"
            viewModel.distance = "1"
            await viewModel.addDraftSet()

            let exercise = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID }))
            let set = try XCTUnwrap(exercise.sets.first)
            XCTAssertEqual(
                set.durationSeconds?.canonicalString, try DecimalValue("90").canonicalString,
                "\"1分30秒\" must store as 90 seconds"
            )

            try await environment.controller.shutdownForTesting()
        }

        func testAddingACardioSetAcceptsLatinMinutesSecondsFormat() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await makeLoadedCardioViewModel(environment: environment)

            viewModel.duration = "1m30s"
            viewModel.distance = "1"
            await viewModel.addDraftSet()

            let exercise = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID }))
            let set = try XCTUnwrap(exercise.sets.first)
            XCTAssertEqual(set.durationSeconds?.canonicalString, try DecimalValue("90").canonicalString)

            try await environment.controller.shutdownForTesting()
        }

        func testEditingAnExistingCardioSetDisplaysStoredSecondsAsMinutesAndSeconds() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await makeLoadedCardioViewModel(environment: environment)

            viewModel.duration = "10分"
            viewModel.distance = "5"
            await viewModel.addDraftSet()
            let exercise = try XCTUnwrap(viewModel.session?.exercises.first(where: { $0.id == exerciseID }))
            let set = try XCTUnwrap(exercise.sets.first)
            XCTAssertEqual(set.durationSeconds?.canonicalString, try DecimalValue("600").canonicalString)

            viewModel.beginEditingSet(set)

            XCTAssertEqual(
                viewModel.duration, "10分",
                "editing a set stored as 600 seconds must pre-fill the field as \"10分\", not raw 600"
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
