#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    final class StudentPersistenceTests: XCTestCase {
        private let firstID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        private let secondID = StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        func testFullFieldRoundTripAndRestartSearch() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let clock = TestClock(utcDate: now)
            let ids = TestIDGenerator(ids: [firstID.rawValue, secondID.rawValue])

            do {
                let controller = try PersistenceController(storeURL: storeURL)
                let useCases = StudentUseCases(
                    repository: CoreDataStudentRepository(writer: controller.writer),
                    clock: clock,
                    ids: ids
                )
                let created = try await useCases.create(
                    draft: StudentDraft(
                        displayName: "林青",
                        sex: .female,
                        trainingGoal: "提升基础力量",
                        injuryNotes: "合成测试备注：保持动作节奏。",
                        privateCoachNote: "晚班",
                        phone: "13800001111",
                        wechatID: "linqing_test"
                    )
                )
                XCTAssertEqual(created.id, firstID)
                try await controller.shutdownForTesting()
            }

            let reopened = try PersistenceController(storeURL: storeURL)
            let useCases = StudentUseCases(
                repository: CoreDataStudentRepository(writer: reopened.writer),
                clock: clock,
                ids: ids
            )
            let found = try await useCases.searchActive(query: "林")
            XCTAssertEqual(found.count, 1)
            let student = try XCTUnwrap(found.first)
            XCTAssertEqual(student.id, firstID)
            XCTAssertEqual(student.displayName.value, "林青")
            XCTAssertEqual(student.sex, .female)
            XCTAssertEqual(student.trainingGoal?.value, "提升基础力量")
            XCTAssertEqual(student.injuryNotes?.value, "合成测试备注：保持动作节奏。")
            XCTAssertEqual(student.privateCoachNote?.value, "晚班")
            XCTAssertEqual(student.phone?.value, "13800001111")
            XCTAssertEqual(student.wechatID?.value, "linqing_test")
            try await reopened.shutdownForTesting()
        }

        func testSameDisplayNamePersistsAsDistinctStableIDs() async throws {
            let environment = try makeUseCases(ids: [firstID.rawValue, secondID.rawValue])
            _ = try await environment.useCases.create(
                draft: StudentDraft(displayName: "林林", sex: .other, privateCoachNote: "工作室午班")
            )
            _ = try await environment.useCases.create(
                draft: StudentDraft(displayName: "林林", sex: .female, privateCoachNote: "晚间私教")
            )

            let results = try await environment.useCases.searchActive(query: "林林")
            XCTAssertEqual(results.map(\.id), [firstID, secondID])
            XCTAssertEqual(Set(results.map(\.privateCoachNote?.value)), ["工作室午班", "晚间私教"])
            try await environment.controller.shutdownForTesting()
        }

        func testArchiveIsHiddenFromActiveSearchAndCanBeRestored() async throws {
            let environment = try makeUseCases(ids: [firstID.rawValue])
            let created = try await environment.useCases.create(
                draft: StudentDraft(displayName: "周宁", sex: .male)
            )
            _ = try await environment.useCases.archive(id: created.id)
            let hidden = try await environment.useCases.searchActive(query: "")
            XCTAssertTrue(hidden.isEmpty)
            let archived = try await environment.useCases.listArchived()
            XCTAssertEqual(archived.map(\.id), [firstID])
            XCTAssertFalse(archived[0].canStartSession())

            _ = try await environment.useCases.restore(id: created.id)
            let restored = try await environment.useCases.searchActive(query: "周")
            XCTAssertEqual(restored.map(\.id), [firstID])
            let remainingArchived = try await environment.useCases.listArchived()
            XCTAssertTrue(remainingArchived.isEmpty)
            try await environment.controller.shutdownForTesting()
        }

        func testDeleteBlockedByInProgressSessionRollsBackManagedData() async throws {
            let environment = try makeUseCases(ids: [firstID.rawValue])
            let created = try await environment.useCases.create(
                draft: StudentDraft(displayName: "林青", sex: .female)
            )
            try await insertSession(
                studentID: created.id.rawValue,
                sessionID: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
                state: "inProgress",
                writer: environment.controller.writer
            )

            do {
                try await environment.useCases.delete(id: created.id, confirmedDisplayName: "林青")
                XCTFail("Expected in-progress delete to fail")
            } catch DomainError.invalidState {
                // expected
            }

            let remaining = try await environment.useCases.student(id: created.id)
            XCTAssertEqual(remaining.displayName.value, "林青")
            let impact = try await environment.useCases.deletionImpact(id: created.id)
            XCTAssertTrue(impact.hasInProgressSession)
            try await environment.controller.shutdownForTesting()
        }

        func testConfirmedDeleteCascadesManagedSessionsAndMismatchedNameKeepsData() async throws {
            let environment = try makeUseCases(ids: [firstID.rawValue])
            let created = try await environment.useCases.create(
                draft: StudentDraft(displayName: "林青", sex: .female, trainingGoal: "提升基础力量")
            )
            try await insertSession(
                studentID: created.id.rawValue,
                sessionID: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!,
                state: "completed",
                writer: environment.controller.writer
            )

            do {
                try await environment.useCases.delete(id: created.id, confirmedDisplayName: "别人")
                XCTFail("Expected confirmation mismatch to fail")
            } catch DomainError.invalidState {
                // expected
            }
            let stillPresent = try await environment.useCases.student(id: created.id)
            XCTAssertEqual(stillPresent.id, created.id)
            let remainingSessions = try await sessionCount(
                studentID: created.id.rawValue,
                writer: environment.controller.writer
            )
            XCTAssertEqual(remainingSessions, 1)

            try await environment.useCases.delete(id: created.id, confirmedDisplayName: " 林青 ")
            do {
                _ = try await environment.useCases.student(id: created.id)
                XCTFail("Deleted student should not remain as a business row")
            } catch DomainError.notFound {
                // expected
            }
            let cascaded = try await sessionCount(
                studentID: created.id.rawValue,
                writer: environment.controller.writer
            )
            XCTAssertEqual(cascaded, 0)
            try await environment.controller.shutdownForTesting()
        }

        func testWriterSaveFailureRollsBackStudentCreate() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let injector = TestFaultInjector(failingPoints: [.persistenceWriterSave])
            let controller = try PersistenceController(
                storeURL: storeURL,
                faultInjectionBoundary: FaultInjectionBoundary(injector: injector)
            )
            let useCases = StudentUseCases(
                repository: CoreDataStudentRepository(writer: controller.writer),
                clock: TestClock(utcDate: now),
                ids: TestIDGenerator(ids: [firstID.rawValue])
            )

            do {
                _ = try await useCases.create(draft: StudentDraft(displayName: "林青", sex: .female))
                XCTFail("Expected injected save failure")
            } catch FaultInjectionError.injected(.persistenceWriterSave) {
                // expected
            }

            try await controller.shutdownForTesting()
            let healthy = try PersistenceController(storeURL: storeURL)
            let healthyUseCases = StudentUseCases(
                repository: CoreDataStudentRepository(writer: healthy.writer),
                clock: TestClock(utcDate: now),
                ids: TestIDGenerator(ids: [secondID.rawValue])
            )
            let healthyResults = try await healthyUseCases.searchActive(query: "")
            XCTAssertTrue(healthyResults.isEmpty)
            try await healthy.shutdownForTesting()
        }

        private struct Environment {
            let directory: TemporaryProtectedDirectory
            let controller: PersistenceController
            let useCases: StudentUseCases
        }

        private func makeUseCases(ids: [UUID]) throws -> Environment {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let controller = try PersistenceController(storeURL: storeURL)
            let useCases = StudentUseCases(
                repository: CoreDataStudentRepository(writer: controller.writer),
                clock: TestClock(utcDate: now),
                ids: TestIDGenerator(ids: ids)
            )
            return Environment(directory: directory, controller: controller, useCases: useCases)
        }

        private func insertSession(
            studentID: UUID,
            sessionID: UUID,
            state: String,
            writer: PersistenceWriter
        ) async throws {
            let timestamp = now
            try await writer.transaction { context in
                let request = NSFetchRequest<NSManagedObject>(entityName: "StudentMO")
                request.predicate = NSPredicate(format: "id == %@", studentID as CVarArg)
                request.fetchLimit = 1
                guard let student = try context.fetch(request).first else {
                    throw DomainError.notFound
                }
                let session = NSEntityDescription.insertNewObject(forEntityName: "SessionMO", into: context)
                session.setValue(sessionID, forKey: "id")
                session.setValue(studentID, forKey: "studentID")
                session.setValue(state, forKey: "state")
                session.setValue(timestamp, forKey: "startedAtUTC")
                session.setValue(timestamp, forKey: "lastCheckpointUTC")
                session.setValue(Decimal(0), forKey: "elapsedSeconds")
                session.setValue(false, forKey: "durationNeedsReview")
                session.setValue(Int64(1), forKey: "revision")
                session.setValue(timestamp, forKey: "createdAtUTC")
                session.setValue(timestamp, forKey: "updatedAtUTC")
                if state == "completed" {
                    session.setValue(timestamp, forKey: "completedAtUTC")
                }
                session.setValue(student, forKey: "student")
            }
        }

        private func sessionCount(studentID: UUID, writer: PersistenceWriter) async throws -> Int {
            try await writer.read { context in
                let request = NSFetchRequest<NSManagedObject>(entityName: "SessionMO")
                request.predicate = NSPredicate(format: "studentID == %@", studentID as CVarArg)
                return try context.count(for: request)
            }
        }
    }
#else
    import XCTest
    import FineCoach

    final class StudentPersistenceTests: XCTestCase {
        func testReleaseKeepsStudentDomainSurfaceWithoutFaultInjection() {
            XCTAssertEqual(StudentSex.female.rawValue, "female")
        }
    }
#endif
