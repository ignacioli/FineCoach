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
    }
#else
    import XCTest

    final class CoursePackageEditorViewModelTests: XCTestCase {
        func testReleaseBuildSkipsDebugOnlyIntegrationCoverage() {
            XCTAssertTrue(true)
        }
    }
#endif
