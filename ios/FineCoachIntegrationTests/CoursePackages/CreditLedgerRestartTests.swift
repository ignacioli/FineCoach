#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// T026: a single debit/credit round-trip that survives an app restart.
    /// The full AC-010 combination matrix is already proved purely in memory
    /// by `CreditLedgerIdempotencyTests` (T025, unit target) -- this test
    /// does not repeat it (adversarial A3: dedup, not duplicate proof). What
    /// this test alone proves is that the REAL `CoreDataCoursePackageRepository`
    /// persists the ledger correctly, that balance/adjustments survive a
    /// fresh `PersistenceController` opening the same store, that every
    /// change stays traceable after reopening, and that the balance is never
    /// negative.
    final class CreditLedgerRestartTests: XCTestCase {
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        private struct Environment {
            let directory: TemporaryProtectedDirectory
            let controller: PersistenceController
            let studentID: StableUUID
            let creditLedgerUseCases: CreditLedgerUseCases
        }

        private func makeEnvironment(ids: [UUID]) async throws -> Environment {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let controller = try PersistenceController(storeURL: storeURL)
            let clock = TestClock(utcDate: now)
            let idGenerator = TestIDGenerator(ids: ids)

            let studentRepository = CoreDataStudentRepository(writer: controller.writer)
            let studentID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!
            let studentUseCases = StudentUseCases(
                repository: studentRepository,
                clock: clock,
                ids: TestIDGenerator(ids: [studentID])
            )
            let student = try await studentUseCases.create(draft: StudentDraft(displayName: "林青", sex: .female))

            let creditLedgerUseCases = CreditLedgerUseCases(
                repository: CoreDataCoursePackageRepository(writer: controller.writer),
                clock: clock,
                ids: idGenerator
            )

            return Environment(
                directory: directory,
                controller: controller,
                studentID: student.id,
                creditLedgerUseCases: creditLedgerUseCases
            )
        }

        func testDebitPersistsAndSurvivesRestartWithIdempotencyIntact() async throws {
            let packageID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
            let adjustmentID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
            let sessionID = StableUUID(UUID(uuidString: "33333333-3333-4333-8333-333333333333")!)
            let env = try await makeEnvironment(ids: [packageID, adjustmentID])

            let package = try await env.creditLedgerUseCases.createActivePackage(
                studentID: env.studentID,
                name: "十次课",
                totalCredits: 5,
                startDate: nil,
                endDate: nil
            )
            XCTAssertEqual(package.id.rawValue, packageID)
            XCTAssertEqual(package.status, .active)

            let adjustment = try await env.creditLedgerUseCases.debitOnSessionComplete(
                packageID: package.id,
                sessionID: sessionID
            )
            XCTAssertEqual(adjustment.direction, .debit)
            XCTAssertEqual(adjustment.reasonKind, .sessionComplete)
            XCTAssertEqual(adjustment.linkedSessionID, sessionID)

            let balanceBeforeRestart = try await env.creditLedgerUseCases.balance(packageID: package.id)
            XCTAssertEqual(balanceBeforeRestart, 4)
            XCTAssertGreaterThanOrEqual(balanceBeforeRestart, 0)

            try await env.controller.shutdownForTesting()

            // Fresh PersistenceController + repository + use cases over the SAME
            // store file -- simulates the app being relaunched.
            let reopenedController = try PersistenceController(
                storeURL: env.directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            )
            let reopenedUseCases = CreditLedgerUseCases(
                repository: CoreDataCoursePackageRepository(writer: reopenedController.writer),
                clock: TestClock(utcDate: now),
                ids: TestIDGenerator(ids: [])
            )

            let reopenedPackage = try await reopenedUseCases.packages(studentID: env.studentID).first
            let unwrappedPackage = try XCTUnwrap(reopenedPackage)
            XCTAssertEqual(unwrappedPackage.id, package.id)
            XCTAssertEqual(unwrappedPackage.status, .active)

            // Balance survives the restart unchanged.
            let balanceAfterRestart = try await reopenedUseCases.balance(packageID: package.id)
            XCTAssertEqual(balanceAfterRestart, 4)
            XCTAssertGreaterThanOrEqual(balanceAfterRestart, 0)

            // Every change stays traceable after reopening: the same adjustment,
            // with the same linkage, is still on the ledger.
            let reopenedAdjustments = try await reopenedUseCases.adjustments(packageID: package.id)
            XCTAssertEqual(reopenedAdjustments.count, 1)
            let reopenedAdjustment = try XCTUnwrap(reopenedAdjustments.first)
            XCTAssertEqual(reopenedAdjustment.id, adjustment.id)
            XCTAssertEqual(reopenedAdjustment.sourceEventKey, adjustment.sourceEventKey)
            XCTAssertEqual(reopenedAdjustment.linkedSessionID, sessionID)
            XCTAssertEqual(reopenedAdjustment.reasonKind, .sessionComplete)

            // Idempotency survives the restart too: repeating the same
            // session-complete event through a brand-new use-cases instance
            // over the reopened store must not double-debit.
            _ = try await reopenedUseCases.debitOnSessionComplete(packageID: package.id, sessionID: sessionID)
            let balanceAfterRepeat = try await reopenedUseCases.balance(packageID: package.id)
            XCTAssertEqual(balanceAfterRepeat, 4, "repeating the same event after restart must not double-debit")
            let adjustmentsAfterRepeat = try await reopenedUseCases.adjustments(packageID: package.id)
            XCTAssertEqual(adjustmentsAfterRepeat.count, 1)

            try await reopenedController.shutdownForTesting()
        }
    }
#else
    import XCTest

    final class CreditLedgerRestartTests: XCTestCase {
        func testReleaseBuildSkipsDebugOnlyIntegrationCoverage() {
            XCTAssertTrue(true)
        }
    }
#endif
