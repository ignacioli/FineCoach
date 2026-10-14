#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// Experience P0-D1/D2/D3 through the real `ActiveSessionViewModel` and
    /// persistence: the bottom form starts from this Student's last
    /// performance, keeps the confirmed values for the next set, refills
    /// (instead of clearing) after an inline edit, and a confirmed set starts
    /// the rest countdown. Prefilled values never become a set on their own
    /// (M1A-FR-022).
    @MainActor
    final class ActiveSessionSetEntryPrefillTests: XCTestCase {
        private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        func testFirstSetIsPrefilledFromLastSessionAndNeedsAConfirm() async throws {
            let environment = try makeEnvironment()
            try await completePreviousSession(environment, weight: "60", reps: "8")

            let viewModel = try await startSession(environment, exercises: ["杠铃深蹲"])
            let exercise = try XCTUnwrap(viewModel.currentExercise)

            XCTAssertEqual(viewModel.weight, "60")
            XCTAssertEqual(viewModel.reps, "8")
            XCTAssertEqual(viewModel.lastPerformance(for: exercise)?.sets.count, 1)
            XCTAssertTrue(exercise.sets.isEmpty, "prefill must not create a set before the coach confirms")
            XCTAssertNil(viewModel.restTimer)

            try await environment.controller.shutdownForTesting()
        }

        func testConfirmKeepsValuesStartsRestAndStepsAdjustTheNextSet() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await startSession(environment, exercises: ["杠铃深蹲"])
            viewModel.weight = "100"
            viewModel.reps = "5"

            await viewModel.confirmActiveDraftSet()
            XCTAssertEqual(viewModel.weight, "100", "confirming must keep the values for the next set")
            XCTAssertEqual(viewModel.reps, "5")
            XCTAssertEqual(viewModel.restTimer?.remainingSeconds(at: now), 120)

            viewModel.step(.weight, up: true)
            await viewModel.confirmActiveDraftSet()
            let sets = try XCTUnwrap(viewModel.currentExercise?.sets)
            XCTAssertEqual(sets.map(\.state), [.completed, .completed])
            XCTAssertEqual(sets.map { $0.weightValue?.canonicalString }, ["100", "102.5"])

            viewModel.dismissRest()
            XCTAssertNil(viewModel.restTimer)

            try await environment.controller.shutdownForTesting()
        }

        func testInlineEditAndExerciseSwitchRefillInsteadOfClearing() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await startSession(environment, exercises: ["杠铃深蹲", "哑铃卧推"])
            let squat = try XCTUnwrap(viewModel.session?.exercises.first)
            let bench = try XCTUnwrap(viewModel.session?.exercises.last)

            viewModel.selectExercise(squat.id)
            viewModel.weight = "80"
            viewModel.reps = "6"
            await viewModel.confirmActiveDraftSet()
            let firstSquatSet = try XCTUnwrap(viewModel.currentExercise?.sets.first)

            viewModel.beginEditingSet(firstSquatSet)
            viewModel.reps = "7"
            await viewModel.saveEditingSet()
            XCTAssertEqual(viewModel.weight, "80", "after an inline edit the form refills from the latest set")
            XCTAssertEqual(viewModel.reps, "7")

            viewModel.selectExercise(bench.id)
            XCTAssertEqual(viewModel.weight, "", "an exercise with no history starts empty")
            viewModel.selectExercise(squat.id)
            XCTAssertEqual(viewModel.weight, "80", "switching back refills from that exercise's latest set")

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
            let ids = TestIDGenerator(ids: [studentID.rawValue] + (0..<40).map { _ in UUID() })
            let studentRepository = CoreDataStudentRepository(writer: controller.writer)
            return Environment(
                directory: directory,
                controller: controller,
                studentUseCases: StudentUseCases(repository: studentRepository, clock: clock, ids: ids),
                sessionUseCases: ActiveSessionUseCases(
                    sessionRepository: CoreDataSessionRepository(writer: controller.writer),
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

        private func ensureStudent(_ environment: Environment) async throws {
            if (try? await environment.studentUseCases.student(id: studentID)) == nil {
                _ = try await environment.studentUseCases.create(
                    draft: StudentDraft(displayName: "林青", sex: .female)
                )
            }
        }

        private func completePreviousSession(_ environment: Environment, weight: String, reps: String) async throws {
            try await ensureStudent(environment)
            _ = try await environment.sessionUseCases.startOrOpen(studentID: studentID)
            let session = try await environment.sessionUseCases.addSessionOnlyExercise(
                displayName: "杠铃深蹲",
                recordMode: .weightReps
            )
            let exerciseID = try XCTUnwrap(session.exercises.last?.id)
            let withSet = try await environment.sessionUseCases.addSet(
                exerciseID: exerciseID,
                input: TrainingSetInput(
                    recordMode: .weightReps,
                    weightValue: weight,
                    repetitionCount: reps,
                    unit: .kilograms
                )
            )
            let setID = try XCTUnwrap(withSet.exercises.last?.sets.last?.id)
            _ = try await environment.sessionUseCases.confirmSet(setID: setID)
            _ = try await environment.sessionUseCases.finish()
        }

        private func startSession(_ environment: Environment, exercises: [String]) async throws -> ActiveSessionViewModel {
            try await ensureStudent(environment)
            _ = try await environment.sessionUseCases.startOrOpen(studentID: studentID)
            for name in exercises {
                _ = try await environment.sessionUseCases.addSessionOnlyExercise(displayName: name, recordMode: .weightReps)
            }
            let viewModel = ActiveSessionViewModel(
                studentID: studentID,
                useCases: environment.sessionUseCases,
                now: { [now] in now }
            )
            await viewModel.load()
            return viewModel
        }
    }
#else
    import XCTest

    final class ActiveSessionSetEntryPrefillTests: XCTestCase {
        func testReleaseBuildSkipsTestableOnlyCoverage() {
            XCTAssertTrue(true)
        }
    }
#endif
