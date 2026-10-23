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

        /// P0-D8: an exercise saved to the library with 「单侧动作」 on gets
        /// per-side entry. 「每侧重量」 records the same value on both sides;
        /// 「左右不同」 records each side and keeps the heavier as the weight,
        /// and the next set reopens in the same mode.
        func testUnilateralExerciseRecordsPerSideWeights() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await startSession(environment, exercises: [])
            viewModel.exerciseName = "哑铃单臂划船"
            viewModel.recordMode = .weightReps
            viewModel.newExerciseIsUnilateral = true
            await viewModel.saveExerciseToLibrary()
            XCTAssertFalse(viewModel.newExerciseIsUnilateral, "the toggle resets for the next exercise")

            let exercise = try XCTUnwrap(viewModel.currentExercise)
            XCTAssertTrue(viewModel.isUnilateral(exercise))
            XCTAssertTrue(viewModel.usesSideEntry(exercise))
            XCTAssertFalse(viewModel.splitSides)

            viewModel.weight = "12.5"
            viewModel.reps = "10"
            await viewModel.confirmActiveDraftSet()
            let perSide = try XCTUnwrap(viewModel.currentExercise?.sets.last)
            XCTAssertEqual(perSide.side, .bilateral)
            XCTAssertEqual(perSide.leftValue?.canonicalString, "12.5")
            XCTAssertEqual(perSide.rightValue?.canonicalString, "12.5")
            XCTAssertEqual(perSide.weightValue?.canonicalString, "12.5")
            XCTAssertEqual(viewModel.weight, "12.5", "the next set keeps the per-side weight")
            XCTAssertFalse(viewModel.splitSides)

            viewModel.toggleSplitSides(for: exercise)
            XCTAssertTrue(viewModel.splitSides)
            XCTAssertEqual(viewModel.left, "12.5")
            XCTAssertEqual(viewModel.right, "12.5")
            viewModel.stepSide(.right, up: true)
            XCTAssertEqual(viewModel.right, "15")
            await viewModel.confirmActiveDraftSet()
            let split = try XCTUnwrap(viewModel.currentExercise?.sets.last)
            XCTAssertEqual(split.leftValue?.canonicalString, "12.5")
            XCTAssertEqual(split.rightValue?.canonicalString, "15")
            XCTAssertEqual(split.weightValue?.canonicalString, "15", "the set's weight is the heavier side")
            XCTAssertTrue(viewModel.splitSides, "the next set reopens with different sides")
            XCTAssertEqual(viewModel.right, "15")

            viewModel.toggleSplitSides(for: exercise)
            XCTAssertFalse(viewModel.splitSides)
            XCTAssertEqual(viewModel.weight, "15")

            try await environment.controller.shutdownForTesting()
        }

        func testOrdinaryExerciseHasNoSideEntryAndAssistedKeepsTheLighterSide() async throws {
            let environment = try makeEnvironment()
            let viewModel = try await startSession(environment, exercises: ["杠铃深蹲"])
            let exercise = try XCTUnwrap(viewModel.currentExercise)
            XCTAssertFalse(viewModel.usesSideEntry(exercise))

            viewModel.weight = "60"
            viewModel.reps = "5"
            await viewModel.confirmActiveDraftSet()
            XCTAssertEqual(viewModel.currentExercise?.sets.last?.side, SetSide.none)

            XCTAssertEqual(ActiveSessionViewModel.recordedWeight("12.5", "15", assisted: false), "15")
            XCTAssertEqual(ActiveSessionViewModel.recordedWeight("12.5", "15", assisted: true), "12.5")
            XCTAssertEqual(ActiveSessionViewModel.recordedWeight("12.5", "", assisted: false), "")

            try await environment.controller.shutdownForTesting()
        }

        // MARK: - Revision 1.3: rest-end notification copy and per-Session removal

        func testRestNotificationUsesTheConfirmedSetsExerciseAndRemovesOnlyThisSession() async throws {
            let environment = try makeEnvironment()
            let center = FakeNotificationScheduling()
            let viewModel = try await startSession(
                environment,
                exercises: ["杠铃深蹲", "哑铃卧推"],
                notifications: center
            )
            let squat = try XCTUnwrap(
                viewModel.session?.exercises.first { $0.displayNameSnapshot.value == "杠铃深蹲" }
            )
            let bench = try XCTUnwrap(
                viewModel.session?.exercises.first { $0.displayNameSnapshot.value == "哑铃卧推" }
            )
            let sessionID = try XCTUnwrap(viewModel.session?.id)
            let identifier = RestEndNotification.notificationIdentifier(for: sessionID)

            // confirmSet(setID:) while another exercise is selected must use the
            // set's own exercise, not `currentExercise`.
            viewModel.selectExercise(squat.id)
            viewModel.weight = "80"
            viewModel.reps = "5"
            await viewModel.addDraftSet()
            let squatSetID = try XCTUnwrap(viewModel.currentExercise?.sets.last?.id)
            viewModel.selectExercise(bench.id)
            await viewModel.confirmSet(setID: squatSetID)

            let squatCandidate = await waitForScheduled(center, identifier: identifier) {
                $0.body.contains("杠铃深蹲")
            }
            let squatDescriptor = try XCTUnwrap(squatCandidate)
            XCTAssertFalse(squatDescriptor.body.contains("哑铃卧推"))
            XCTAssertFalse(squatDescriptor.body.contains("林青"))
            XCTAssertEqual(squatDescriptor.title, String(localized: "session.rest.notificationTitle"))
            XCTAssertEqual(
                squatDescriptor.userInfo[RestNotificationPayload.sessionIDKey],
                sessionID.rawValue.uuidString.lowercased()
            )
            XCTAssertEqual(
                squatDescriptor.userInfo[RestNotificationPayload.studentIDKey],
                studentID.rawValue.uuidString.lowercased()
            )

            // confirmActiveDraftSet() is the other confirmation entry; the ±15 s
            // reschedule must keep the new exercise's name.
            viewModel.weight = "60"
            viewModel.reps = "8"
            await viewModel.confirmActiveDraftSet()
            let benchCandidate = await waitForScheduled(center, identifier: identifier) {
                $0.body.contains("哑铃卧推")
            }
            let benchDescriptor = try XCTUnwrap(benchCandidate)
            XCTAssertEqual(benchDescriptor.identifier, identifier)

            viewModel.adjustRest(by: RestTimerState.adjustmentStep)
            let adjustedCandidate = await waitForScheduled(center, identifier: identifier) {
                $0.body.contains("哑铃卧推") && $0.fireDate > benchDescriptor.fireDate
            }
            let adjusted = try XCTUnwrap(adjustedCandidate)
            XCTAssertTrue(adjusted.body.contains("哑铃卧推"))

            // Another Student's pending notification must survive this Session's skip.
            let otherSessionID = StableUUID(UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!)
            let otherIdentifier = RestEndNotification.notificationIdentifier(for: otherSessionID)
            try await center.schedule(
                NotificationRequestDescriptor(
                    identifier: otherIdentifier,
                    title: "other",
                    body: "other",
                    fireDate: now.addingTimeInterval(600)
                )
            )
            viewModel.dismissRest()
            let removed = await waitUntilRemoved(center, identifier: identifier)
            XCTAssertTrue(removed)
            let stillPending = await center.scheduled[otherIdentifier]
            XCTAssertNotNil(stillPending, "skipping one Session's rest must not cancel another Session's")

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

        private func startSession(
            _ environment: Environment,
            exercises: [String],
            notifications: (any LocalNotificationScheduling)? = nil
        ) async throws -> ActiveSessionViewModel {
            try await ensureStudent(environment)
            _ = try await environment.sessionUseCases.startOrOpen(studentID: studentID)
            for name in exercises {
                _ = try await environment.sessionUseCases.addSessionOnlyExercise(
                    displayName: name, recordMode: .weightReps)
            }
            let viewModel = ActiveSessionViewModel(
                studentID: studentID,
                useCases: environment.sessionUseCases,
                notifications: notifications,
                now: { [now] in now }
            )
            await viewModel.load()
            return viewModel
        }

        /// The notification work is an async MainActor task; let it run and
        /// return the first scheduled descriptor that matches.
        private func waitForScheduled(
            _ center: FakeNotificationScheduling,
            identifier: String,
            where predicate: (NotificationRequestDescriptor) -> Bool
        ) async -> NotificationRequestDescriptor? {
            for _ in 0..<500 {
                if let descriptor = await center.scheduled[identifier],
                    predicate(descriptor)
                {
                    return descriptor
                }
                await Task.yield()
            }
            return nil
        }

        private func waitUntilRemoved(
            _ center: FakeNotificationScheduling,
            identifier: String
        ) async -> Bool {
            for _ in 0..<500 {
                if await center.scheduled[identifier] == nil {
                    return true
                }
                await Task.yield()
            }
            return false
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
