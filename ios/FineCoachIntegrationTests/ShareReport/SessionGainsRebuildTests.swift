#if DEBUG
    import XCTest

    @testable import FineCoach

    @MainActor
    final class SessionGainsRebuildTests: XCTestCase {
        func testGainsAndCoachTextSurviveARebuiltStore() async throws {
            let directory = try TemporaryProtectedDirectory()
            let url = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let controller = try PersistenceController(storeURL: url)
            let clock = TestClock()
            let student = try await StudentUseCases(
                repository: CoreDataStudentRepository(writer: controller.writer), clock: clock,
                ids: TestIDGenerator(ids: [UUID()])
            )
            .create(draft: StudentDraft(displayName: "合成学员", sex: .female))
            let exercises = CoreDataExerciseRepository(writer: controller.writer)
            try await exercises.seedPlaceholderCatalogIfNeeded(now: clock.nowUTC())
            let items = try await exercises.searchActive(query: "")
                .filter { $0.item.recordMode == .weightReps }.prefix(2).map(\.item)
            XCTAssertEqual(items.count, 2)
            let repository = CoreDataSessionRepository(writer: controller.writer)
            var lastID: StableUUID?
            for number in 1...10 {
                let now = clock.nowUTC()
                var session = Session.start(id: StableUUID(UUID()), studentID: student.id, now: now)
                for (index, item) in items.enumerated() {
                    let exerciseID = StableUUID(UUID())
                    session = try session.addingCatalogExercise(id: exerciseID, item: item, now: now)
                    let weight = index == 0 ? (number == 10 ? "85" : "80") : (number == 1 ? "100" : "80")
                    let setID = StableUUID(UUID())
                    session = try session.addingSet(
                        exerciseID: exerciseID, setID: setID,
                        input: TrainingSetInput(
                            recordMode: .weightReps, weightValue: weight,
                            repetitionCount: number == 10 ? "7" : "5", unit: .kilograms), now: now)
                    session = try session.confirmingSet(setID: setID, now: now)
                }
                session = try session.finished(now: now.addingTimeInterval(60))
                session = try session.updatingCompletedSummary(
                    trainingFocus: [], privateCoachNote: ValidatedText("合成私人备注"),
                    studentFacingSummary: ValidatedText("合成学员总结"), now: now.addingTimeInterval(61))
                _ = try await repository.save(session)
                lastID = session.id
                clock.advance(seconds: 1000)
            }
            let id = try XCTUnwrap(lastID)
            let historyUseCases = HistoryUseCases(
                sessionRepository: repository, clock: clock,
                ids: TestIDGenerator(ids: []))
            let summary = SessionSummaryViewModel(sessionID: id, useCases: historyUseCases)
            await summary.load()
            XCTAssertNil(summary.errorMessage)
            XCTAssertEqual(summary.gains.records.count, 1)
            XCTAssertEqual(summary.gains.progress.count, 1)
            XCTAssertEqual(summary.gains.milestoneSessionNumber, 10)
            let expected = summary.gains
            let notes = try await repository.completedSession(id: id).notes
            try await controller.shutdownForTesting()

            let rebuilt = try PersistenceController(storeURL: url)
            let rebuiltRepository = CoreDataSessionRepository(writer: rebuilt.writer)
            let detail = SessionDetailViewModel(
                sessionID: id,
                useCases: HistoryUseCases(
                    sessionRepository: rebuiltRepository, clock: clock,
                    ids: TestIDGenerator(ids: [])))
            await detail.load()
            XCTAssertNil(detail.errorMessage)
            XCTAssertEqual(detail.gains, expected)
            let restored = try await rebuiltRepository.completedSession(id: id)
            XCTAssertEqual(restored.notes, notes)
            XCTAssertEqual(restored.notes.studentFacingSummary?.value, "合成学员总结")
            XCTAssertEqual(restored.notes.privateCoachNote?.value, "合成私人备注")
            XCTAssertEqual(summary.studentSummary, "合成学员总结")
            XCTAssertEqual(summary.privateNote, "合成私人备注")
            try await rebuilt.shutdownForTesting()
        }
    }
#endif
