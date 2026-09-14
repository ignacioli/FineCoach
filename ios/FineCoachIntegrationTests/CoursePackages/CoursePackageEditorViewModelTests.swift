#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// Bug fix: creating a new course package used to silently end the
    /// Student's existing active package with zero confirmation (Save called
    /// straight through to `createActivePackage`, which atomically ends the
    /// current active package per M1B-FR-012). These tests prove the UI-layer
    /// fix at the ViewModel level: when the Student already has an active
    /// package, `save()` must stop at `isConfirmingEndActive` and must NOT
    /// call through to `createActivePackage` until the coach explicitly
    /// confirms via `confirmEndActiveAndSave()`. When there is no existing
    /// active package, `save()` must behave exactly as before -- no added
    /// friction.
    final class CoursePackageEditorViewModelTests: XCTestCase {
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        private struct Environment {
            let directory: TemporaryProtectedDirectory
            let controller: PersistenceController
            let studentID: StableUUID
            let useCases: CreditLedgerUseCases
        }

        private func makeEnvironment(ids: [UUID]) async throws -> Environment {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let controller = try PersistenceController(storeURL: storeURL)
            let clock = TestClock(utcDate: now)

            let studentRepository = CoreDataStudentRepository(writer: controller.writer)
            let studentID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000002")!
            let studentUseCases = StudentUseCases(
                repository: studentRepository,
                clock: clock,
                ids: TestIDGenerator(ids: [studentID])
            )
            let student = try await studentUseCases.create(draft: StudentDraft(displayName: "王芳", sex: .female))

            let useCases = CreditLedgerUseCases(
                repository: CoreDataCoursePackageRepository(writer: controller.writer),
                clock: clock,
                ids: TestIDGenerator(ids: ids)
            )

            return Environment(directory: directory, controller: controller, studentID: student.id, useCases: useCases)
        }

        func testSaveWithNoExistingActivePackageCreatesImmediatelyWithoutConfirmation() async throws {
            let packageID = UUID(uuidString: "11111111-1111-4111-8111-111111111112")!
            let env = try await makeEnvironment(ids: [packageID])

            let viewModel = await CoursePackageEditorViewModel(
                studentID: env.studentID,
                useCases: env.useCases,
                today: LocalDate(date: now, calendar: Calendar(identifier: .gregorian))
            )
            await MainActor.run { viewModel.totalCredits = 10 }

            await viewModel.loadExistingActivePackage()
            await MainActor.run {
                XCTAssertNil(viewModel.existingActivePackage, "no active package exists yet for this Student")
            }

            await viewModel.save()

            let didSave = await viewModel.didSave
            let isConfirming = await viewModel.isConfirmingEndActive
            XCTAssertTrue(didSave, "save() with no existing active package must create immediately")
            XCTAssertFalse(isConfirming, "no confirmation step should ever appear in the common case")

            let packages = try await env.useCases.packages(studentID: env.studentID)
            XCTAssertEqual(packages.count, 1)

            try await env.controller.shutdownForTesting()
        }

        func testSaveWithExistingActivePackageRequiresConfirmationBeforeCreating() async throws {
            let firstPackageID = UUID(uuidString: "22222222-2222-4222-8222-222222222223")!
            let secondPackageID = UUID(uuidString: "33333333-3333-4333-8333-333333333334")!
            let env = try await makeEnvironment(ids: [firstPackageID, secondPackageID])

            // Seed an existing active package for this Student.
            let firstPackage = try await env.useCases.createActivePackage(
                studentID: env.studentID,
                name: "旧课包",
                totalCredits: 8,
                startDate: nil,
                endDate: nil
            )
            XCTAssertEqual(firstPackage.status, .active)

            let viewModel = await CoursePackageEditorViewModel(
                studentID: env.studentID,
                useCases: env.useCases,
                today: LocalDate(date: now, calendar: Calendar(identifier: .gregorian))
            )
            await MainActor.run {
                viewModel.name = "新课包"
                viewModel.totalCredits = 12
            }

            await viewModel.loadExistingActivePackage()
            let loadedActive = await viewModel.existingActivePackage
            XCTAssertEqual(loadedActive?.id, firstPackage.id, "loadExistingActivePackage must find the Student's active package")
            let loadedBalance = await viewModel.existingActivePackageBalance
            XCTAssertEqual(loadedBalance, 8, "balance shown must be the ledger-derived balance, not a stale cache")

            // save() must stop at the confirmation step and must NOT call
            // through to createActivePackage yet.
            await viewModel.save()

            let isConfirmingAfterSave = await viewModel.isConfirmingEndActive
            let didSaveAfterSave = await viewModel.didSave
            XCTAssertTrue(isConfirmingAfterSave, "an existing active package must require explicit confirmation")
            XCTAssertFalse(didSaveAfterSave, "save() must not create the new package before confirmation")

            let packagesBeforeConfirm = try await env.useCases.packages(studentID: env.studentID)
            XCTAssertEqual(packagesBeforeConfirm.count, 1, "no second package must exist before the coach confirms")
            XCTAssertEqual(packagesBeforeConfirm.first?.status, .active, "the original package must still be active")

            // Only after the coach's explicit confirmation does the atomic
            // end-then-create actually happen.
            await viewModel.confirmEndActiveAndSave()

            let isConfirmingAfterConfirm = await viewModel.isConfirmingEndActive
            let didSaveAfterConfirm = await viewModel.didSave
            XCTAssertFalse(isConfirmingAfterConfirm)
            XCTAssertTrue(didSaveAfterConfirm, "confirmEndActiveAndSave() must create the new package")

            let packagesAfterConfirm = try await env.useCases.packages(studentID: env.studentID)
            XCTAssertEqual(packagesAfterConfirm.count, 2, "the old package must be retained, never deleted")
            let endedPackage = packagesAfterConfirm.first { $0.id == firstPackage.id }
            XCTAssertEqual(endedPackage?.status, .ended, "the original active package must have been ended")
            let newPackage = packagesAfterConfirm.first { $0.id != firstPackage.id }
            XCTAssertEqual(newPackage?.status, .active)
            XCTAssertEqual(newPackage?.totalCredits, 12)

            try await env.controller.shutdownForTesting()
        }

        /// M1B-FR-012 (updated): an existing active package that has already
        /// EXPIRED as of today MUST end silently -- no confirmation dialog --
        /// because it is no longer "in effect" for the coach to lose.
        func testSaveWithExpiredExistingActivePackageCreatesImmediatelyWithoutConfirmation() async throws {
            let firstPackageID = UUID(uuidString: "44444444-4444-4444-8444-444444444445")!
            let secondPackageID = UUID(uuidString: "55555555-5555-4555-8555-555555555556")!
            let env = try await makeEnvironment(ids: [firstPackageID, secondPackageID])

            // `now` is 2023-11-14T22:13:20Z; an endDate of 2023-01-01 is
            // unambiguously in the past regardless of time zone.
            let expiredEndDate = try LocalDate(canonicalString: "2023-01-01")
            let firstPackage = try await env.useCases.createActivePackage(
                studentID: env.studentID,
                name: "过期旧课包",
                totalCredits: 5,
                startDate: nil,
                endDate: expiredEndDate
            )
            XCTAssertEqual(firstPackage.status, .active)

            let viewModel = await CoursePackageEditorViewModel(
                studentID: env.studentID,
                useCases: env.useCases,
                today: LocalDate(date: now, calendar: Calendar(identifier: .gregorian))
            )
            await MainActor.run { viewModel.totalCredits = 12 }

            await viewModel.loadExistingActivePackage()
            let loadedBalance = await viewModel.existingActivePackageBalance
            XCTAssertEqual(loadedBalance, 5, "the expired package still has credits left -- expiry, not balance, is why no dialog is needed")

            await viewModel.save()

            let isConfirming = await viewModel.isConfirmingEndActive
            let didSave = await viewModel.didSave
            XCTAssertFalse(isConfirming, "an expired active package must not require confirmation")
            XCTAssertTrue(didSave, "save() must create immediately when the existing active package is expired")

            let packages = try await env.useCases.packages(studentID: env.studentID)
            XCTAssertEqual(packages.count, 2, "the old package must be retained, never deleted")
            let ended = packages.first { $0.id == firstPackage.id }
            XCTAssertEqual(ended?.status, .ended)
            let created = packages.first { $0.id != firstPackage.id }
            XCTAssertEqual(created?.status, .active)
            XCTAssertEqual(created?.totalCredits, 12)

            try await env.controller.shutdownForTesting()
        }

        /// M1B-FR-012 (updated): an existing active package with zero
        /// remaining credits MUST end silently -- no confirmation dialog --
        /// even though it has not expired by date.
        func testSaveWithZeroBalanceExistingActivePackageCreatesImmediatelyWithoutConfirmation() async throws {
            let firstPackageID = UUID(uuidString: "66666666-6666-4666-8666-666666666667")!
            let adjustmentID = UUID(uuidString: "77777777-7777-4777-8777-777777777778")!
            let secondPackageID = UUID(uuidString: "88888888-8888-4888-8888-888888888889")!
            let env = try await makeEnvironment(ids: [firstPackageID, adjustmentID, secondPackageID])

            let firstPackage = try await env.useCases.createActivePackage(
                studentID: env.studentID,
                name: "已刷完旧课包",
                totalCredits: 3,
                startDate: nil,
                endDate: nil
            )
            _ = try await env.useCases.recordManualCorrection(
                packageID: firstPackage.id,
                direction: .debit,
                amount: 3,
                reasonText: "test setup: exhaust balance"
            )

            let viewModel = await CoursePackageEditorViewModel(
                studentID: env.studentID,
                useCases: env.useCases,
                today: LocalDate(date: now, calendar: Calendar(identifier: .gregorian))
            )
            await MainActor.run { viewModel.totalCredits = 12 }

            await viewModel.loadExistingActivePackage()
            let loadedBalance = await viewModel.existingActivePackageBalance
            XCTAssertEqual(loadedBalance, 0, "balance must be fully exhausted for this scenario")

            await viewModel.save()

            let isConfirming = await viewModel.isConfirmingEndActive
            let didSave = await viewModel.didSave
            XCTAssertFalse(isConfirming, "a zero-balance active package must not require confirmation")
            XCTAssertTrue(didSave, "save() must create immediately when the existing active package has zero balance")

            let packages = try await env.useCases.packages(studentID: env.studentID)
            XCTAssertEqual(packages.count, 2, "the old package must be retained, never deleted")
            let ended = packages.first { $0.id == firstPackage.id }
            XCTAssertEqual(ended?.status, .ended)
            let created = packages.first { $0.id != firstPackage.id }
            XCTAssertEqual(created?.status, .active)
            XCTAssertEqual(created?.totalCredits, 12)

            try await env.controller.shutdownForTesting()
        }
    }
#else
    import XCTest

    final class CoursePackageEditorViewModelTests: XCTestCase {
        func testReleaseBuildSkipsDebugOnlyIntegrationCoverage() {
            XCTAssertTrue(true)
        }
    }
#endif
