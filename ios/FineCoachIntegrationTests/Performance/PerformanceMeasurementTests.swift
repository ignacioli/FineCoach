#if DEBUG
    import XCTest

    @testable import FineCoach

    @MainActor
    final class PerformanceMeasurementTests: XCTestCase {
        private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        private let sessionID = StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        private let exerciseID = StableUUID(UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        func testRecoverySearchAndSetConfirmMeetP95Budgets() async throws {
            let environment = try makeUseCases()
            _ = try await environment.studentUseCases.create(
                draft: StudentDraft(displayName: "林青", sex: .female)
            )
            _ = try await environment.sessionUseCases.startOrOpen(studentID: studentID)
            _ = try await environment.sessionUseCases.addSessionOnlyExercise(
                displayName: "课中深蹲",
                recordMode: .weightReps
            )
            let seeded = try await environment.sessionUseCases.addSet(
                exerciseID: exerciseID,
                input: weightRepsInput()
            )
            let firstSetID = try XCTUnwrap(seeded.exercises.first?.sets.last?.id)
            _ = try await environment.sessionUseCases.confirmSet(setID: firstSetID)

            let recovery = try await sample(warmup: 5, count: 30) {
                _ = try await environment.sessionUseCases.reconcileOnLaunch()
            }
            XCTAssertLessThanOrEqual(
                recovery.p95Milliseconds,
                1_000,
                "recovery P95 must be ≤ 1 s; samples=\(recovery.milliseconds)"
            )

            try await environment.exerciseUseCases.seedIfNeeded()
            let search = try await sample(warmup: 5, count: 30) {
                _ = try await environment.exerciseUseCases.search(query: "深蹲")
            }
            XCTAssertLessThanOrEqual(
                search.p95Milliseconds,
                200,
                "exercise search P95 must be ≤ 200 ms; samples=\(search.milliseconds)"
            )

            var confirmMilliseconds: [Double] = []
            confirmMilliseconds.reserveCapacity(30)
            for index in 0..<(5 + 30) {
                let added = try await environment.sessionUseCases.addSet(
                    exerciseID: exerciseID,
                    input: weightRepsInput()
                )
                let setID = try XCTUnwrap(added.exercises.first?.sets.last?.id)
                let started = ContinuousClock.now
                _ = try await environment.sessionUseCases.confirmSet(setID: setID)
                let elapsed = Self.milliseconds(ContinuousClock.now - started)
                if index >= 5 {
                    confirmMilliseconds.append(elapsed)
                }
            }
            let confirm = SampleSummary(milliseconds: confirmMilliseconds)
            XCTAssertLessThanOrEqual(
                confirm.p95Milliseconds,
                100,
                "set confirm P95 must be ≤ 100 ms; samples=\(confirm.milliseconds)"
            )

            print(
                "T116 samples recovery_p50=\(recovery.p50Milliseconds) recovery_p95=\(recovery.p95Milliseconds) search_p50=\(search.p50Milliseconds) search_p95=\(search.p95Milliseconds) confirm_p50=\(confirm.p50Milliseconds) confirm_p95=\(confirm.p95Milliseconds)"
            )
            try await environment.controller.shutdownForTesting()
        }

        private func sample(
            warmup: Int,
            count: Int,
            work: () async throws -> Void
        ) async throws -> SampleSummary {
            for _ in 0..<warmup {
                try await work()
            }
            var milliseconds: [Double] = []
            milliseconds.reserveCapacity(count)
            for _ in 0..<count {
                let started = ContinuousClock.now
                try await work()
                milliseconds.append(Self.milliseconds(ContinuousClock.now - started))
            }
            return SampleSummary(milliseconds: milliseconds)
        }

        private static func milliseconds(_ duration: Duration) -> Double {
            let parts = duration.components
            return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
        }

        private func weightRepsInput() -> TrainingSetInput {
            TrainingSetInput(
                recordMode: .weightReps,
                weightValue: "0",
                repetitionCount: "5",
                unit: .kilograms
            )
        }

        private func makeUseCases() throws -> Environment {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let controller = try PersistenceController(storeURL: storeURL)
            let clock = TestClock(utcDate: now)
            var ids = [studentID.rawValue, sessionID.rawValue, exerciseID.rawValue]
            ids.append(
                contentsOf: (0..<80).map { index in
                    UUID(uuidString: String(format: "cccccccc-cccc-4ccc-8ccc-%012x", index))!
                })
            let generator = TestIDGenerator(ids: ids)
            return Environment(
                directory: directory,
                controller: controller,
                studentUseCases: StudentUseCases(
                    repository: CoreDataStudentRepository(writer: controller.writer),
                    clock: clock,
                    ids: generator
                ),
                sessionUseCases: ActiveSessionUseCases(
                    sessionRepository: CoreDataSessionRepository(writer: controller.writer),
                    studentRepository: CoreDataStudentRepository(writer: controller.writer),
                    exerciseRepository: CoreDataExerciseRepository(writer: controller.writer),
                    recoveryStore: ActiveSessionRecoveryStore(
                        url: directory.url.appendingPathComponent("active-session-recovery-v1.json"),
                        protectedFileStore: ProtectedFileStore()
                    ),
                    storeGenerationUUID: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
                    clock: clock,
                    ids: generator
                ),
                exerciseUseCases: ExerciseLibraryUseCases(
                    repository: CoreDataExerciseRepository(writer: controller.writer),
                    clock: clock,
                    ids: generator
                )
            )
        }

        private struct Environment {
            let directory: TemporaryProtectedDirectory
            let controller: PersistenceController
            let studentUseCases: StudentUseCases
            let sessionUseCases: ActiveSessionUseCases
            let exerciseUseCases: ExerciseLibraryUseCases
        }

        private struct SampleSummary {
            let milliseconds: [Double]

            var p50Milliseconds: Double { percentile(0.50) }
            var p95Milliseconds: Double { percentile(0.95) }

            private func percentile(_ p: Double) -> Double {
                let sorted = milliseconds.sorted()
                guard !sorted.isEmpty else {
                    return 0
                }
                let rank = p * Double(sorted.count - 1)
                let lower = Int(rank.rounded(.down))
                let upper = min(sorted.count - 1, lower + 1)
                let weight = rank - Double(lower)
                return sorted[lower] * (1 - weight) + sorted[upper] * weight
            }
        }
    }
#else
    import FineCoach
    import XCTest

    final class PerformanceMeasurementTests: XCTestCase {
        func testReleaseKeepsPerformanceSignpostSurface() {
            XCTAssertEqual(RecordMode.weightReps.rawValue, "weightReps")
        }
    }
#endif
