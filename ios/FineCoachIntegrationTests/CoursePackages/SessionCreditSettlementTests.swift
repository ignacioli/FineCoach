#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// The Session finish path wired to the linked Appointment and the credit
    /// ledger (M1B-FR-013/014/015, AC-010) over the real Core Data stack:
    /// linked completion completes the Appointment and debits once, ad-hoc
    /// finish asks first, expired/zero packages never debit, and the balance
    /// never goes negative.
    @MainActor
    final class SessionCreditSettlementTests: XCTestCase {
        private let now = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14 UTC
        private let studentUUID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-0000000000c1")!

        private struct Environment {
            let directory: TemporaryProtectedDirectory
            let controller: PersistenceController
            let studentID: StableUUID
            let sessions: ActiveSessionUseCases
            let appointments: AppointmentUseCases
            let credits: CreditLedgerUseCases
            let settlement: SessionCreditSettlement
        }

        private func makeEnvironment() async throws -> Environment {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let controller = try PersistenceController(storeURL: storeURL)
            let clock = TestClock(utcDate: now)
            let ids = SystemIDGenerator()
            let calendarProvider = TestCalendarProvider(timeZone: TimeZone(identifier: "UTC")!)
            let studentRepository = CoreDataStudentRepository(writer: controller.writer)
            let student = try await StudentUseCases(
                repository: studentRepository,
                clock: clock,
                ids: TestIDGenerator(ids: [studentUUID])
            ).create(draft: StudentDraft(displayName: "林青", sex: .female))

            let sessionRepository = CoreDataSessionRepository(writer: controller.writer)
            let sessions = ActiveSessionUseCases(
                sessionRepository: sessionRepository,
                studentRepository: studentRepository,
                exerciseRepository: CoreDataExerciseRepository(writer: controller.writer),
                sectionRepository: CoreDataSessionSectionRepository(writer: controller.writer),
                recoveryStore: ActiveSessionRecoveryStore(
                    url: directory.url.appendingPathComponent("active-session-recovery-v1.json"),
                    protectedFileStore: ProtectedFileStore()
                ),
                storeGenerationUUID: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbc1")!,
                clock: clock,
                ids: ids
            )
            let appointments = AppointmentUseCases(
                appointmentRepository: CoreDataAppointmentRepository(writer: controller.writer),
                studentRepository: studentRepository,
                activeSession: sessions,
                notifications: NotificationScheduler(
                    notificationCenter: FakeNotificationScheduling(),
                    calendarProvider: calendarProvider
                ),
                clock: clock,
                calendarProvider: calendarProvider,
                ids: ids
            )
            let credits = CreditLedgerUseCases(
                repository: CoreDataCoursePackageRepository(writer: controller.writer),
                clock: clock,
                ids: ids
            )
            return Environment(
                directory: directory,
                controller: controller,
                studentID: student.id,
                sessions: sessions,
                appointments: appointments,
                credits: credits,
                settlement: SessionCreditSettlement(
                    appointments: appointments,
                    credits: credits,
                    history: HistoryUseCases(sessionRepository: sessionRepository, clock: clock, ids: ids)
                )
            )
        }

        private func makePackage(
            _ env: Environment,
            totalCredits: Int,
            endDate: LocalDate? = nil
        ) async throws -> CoursePackage {
            try await env.credits.createActivePackage(
                studentID: env.studentID,
                name: "十次课",
                totalCredits: totalCredits,
                startDate: nil,
                endDate: endDate
            )
        }

        /// Starts training from a scheduled Appointment (sets `linkedSessionID`).
        private func startFromAppointment(_ env: Environment) async throws -> Appointment {
            let appointment = try await env.appointments.createSingle(
                studentID: env.studentID,
                date: try LocalDate(year: 2023, month: 11, day: 14),
                startTime: try LocalTime(hour: 9, minute: 0),
                overrideConflict: false
            )
            _ = try await env.appointments.startTraining(appointmentID: appointment.id)
            return appointment
        }

        /// One confirmed set, then finish -- the same path as the 结束训练 button.
        private func recordAndFinish(_ env: Environment) async throws -> Session {
            _ = try await env.sessions.startOrOpen(studentID: env.studentID)
            let withExercise = try await env.sessions.addSessionOnlyExercise(
                displayName: "结算测试动作",
                recordMode: .weightReps
            )
            let exerciseID = try XCTUnwrap(withExercise.exercises.last?.id)
            let withSet = try await env.sessions.addSet(
                exerciseID: exerciseID,
                input: TrainingSetInput(recordMode: .weightReps, weightValue: "40", repetitionCount: "8", unit: .kilograms)
            )
            _ = try await env.sessions.confirmSet(setID: try XCTUnwrap(withSet.exercises.last?.sets.last?.id))
            return try await env.sessions.finish()
        }

        // MARK: - Appointment-linked finish

        func testLinkedFinishCompletesAppointmentAndDebitsExactlyOnce() async throws {
            let env = try await makeEnvironment()
            let package = try await makePackage(env, totalCredits: 5)
            let appointment = try await startFromAppointment(env)
            let finished = try await recordAndFinish(env)

            let outcome = try await env.settlement.settleFinishedSession(finished)
            guard case .debited(let debited) = outcome else {
                return XCTFail("expected an automatic debit, got \(outcome)")
            }
            XCTAssertEqual(debited.id, package.id)
            let completed = try await env.appointments.appointment(id: appointment.id)
            XCTAssertEqual(completed.status, .completed)
            XCTAssertEqual(completed.linkedSessionID, finished.id)

            // Settling the same finish again (retry) must not debit twice.
            _ = try await env.settlement.settleFinishedSession(finished)
            let balance = try await env.credits.balance(packageID: package.id)
            XCTAssertEqual(balance, 4)
            let trail = try await env.credits.adjustments(packageID: package.id)
            XCTAssertEqual(trail.count, 1)
            XCTAssertEqual(trail.first?.reasonKind, .sessionComplete)
            XCTAssertEqual(trail.first?.direction, .debit)
            XCTAssertEqual(trail.first?.linkedSessionID, finished.id)
            try await env.controller.shutdownForTesting()
        }

        func testReopenCreditsBackTheLinkedDebitOnceAndSurvivesRestart() async throws {
            let env = try await makeEnvironment()
            let package = try await makePackage(env, totalCredits: 5)
            _ = try await startFromAppointment(env)
            let finished = try await recordAndFinish(env)
            _ = try await env.settlement.settleFinishedSession(finished)

            try await env.credits.creditOnSessionReopen(packageID: package.id, sessionID: finished.id)
            try await env.credits.creditOnSessionReopen(packageID: package.id, sessionID: finished.id)
            let afterReopen = try await env.credits.balance(packageID: package.id)
            XCTAssertEqual(afterReopen, 5)
            try await env.controller.shutdownForTesting()

            let reopened = try PersistenceController(
                storeURL: env.directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            )
            let reopenedCredits = CreditLedgerUseCases(
                repository: CoreDataCoursePackageRepository(writer: reopened.writer),
                clock: TestClock(utcDate: now),
                ids: SystemIDGenerator()
            )
            let afterRestart = try await reopenedCredits.balance(packageID: package.id)
            XCTAssertEqual(afterRestart, 5)
            let trail = try await reopenedCredits.adjustments(packageID: package.id)
            XCTAssertEqual(trail.map(\.reasonKind), [.sessionComplete, .sessionReopen])
            try await reopened.shutdownForTesting()
        }

        func testLinkedFinishWithoutActivePackageStillCompletesAppointment() async throws {
            let env = try await makeEnvironment()
            let appointment = try await startFromAppointment(env)
            let finished = try await recordAndFinish(env)

            let outcome = try await env.settlement.settleFinishedSession(finished)
            XCTAssertEqual(outcome, .noActivePackage)
            let completed = try await env.appointments.appointment(id: appointment.id)
            XCTAssertEqual(completed.status, .completed)
            try await env.controller.shutdownForTesting()
        }

        // MARK: - Ad-hoc finish

        func testAdhocFinishAsksFirstAndDebitsOnlyOnceWhenChosen() async throws {
            let env = try await makeEnvironment()
            let package = try await makePackage(env, totalCredits: 3)
            let finished = try await recordAndFinish(env)

            let outcome = try await env.settlement.settleFinishedSession(finished)
            guard case .adhocChoiceRequired(let offered, let balance) = outcome else {
                return XCTFail("expected the ad-hoc choice, got \(outcome)")
            }
            XCTAssertEqual(offered.id, package.id)
            XCTAssertEqual(balance, 3)
            let beforeChoice = try await env.credits.adjustments(packageID: package.id)
            XCTAssertTrue(beforeChoice.isEmpty, "asking must not debit")

            try await env.settlement.debitAdhocSession(packageID: package.id, sessionID: finished.id)
            try await env.settlement.debitAdhocSession(packageID: package.id, sessionID: finished.id)
            let afterChoice = try await env.credits.balance(packageID: package.id)
            XCTAssertEqual(afterChoice, 2)
            let trail = try await env.credits.adjustments(packageID: package.id)
            XCTAssertEqual(trail.map(\.reasonKind), [.adhocSession])
            XCTAssertEqual(trail.first?.linkedSessionID, finished.id)
            try await env.controller.shutdownForTesting()
        }

        func testAdhocSkipLeavesLedgerUntouched() async throws {
            let env = try await makeEnvironment()
            let package = try await makePackage(env, totalCredits: 3)
            let viewModel = ActiveSessionViewModel(
                studentID: env.studentID,
                useCases: env.sessions,
                creditSettlement: env.settlement
            )
            _ = try await recordAndFinishThroughViewModel(env, viewModel: viewModel)

            guard case .adhocChoice = viewModel.creditPrompt else {
                return XCTFail("expected the ad-hoc prompt, got \(String(describing: viewModel.creditPrompt))")
            }
            viewModel.skipCreditDebit()
            XCTAssertNil(viewModel.creditPrompt)
            let balance = try await env.credits.balance(packageID: package.id)
            XCTAssertEqual(balance, 3)
            let trail = try await env.credits.adjustments(packageID: package.id)
            XCTAssertTrue(trail.isEmpty)
            try await env.controller.shutdownForTesting()
        }

        func testViewModelAdhocDebitClearsPromptAndLinkedFinishNeedsNoPrompt() async throws {
            let env = try await makeEnvironment()
            let package = try await makePackage(env, totalCredits: 3)

            let adhocModel = ActiveSessionViewModel(
                studentID: env.studentID,
                useCases: env.sessions,
                creditSettlement: env.settlement
            )
            _ = try await recordAndFinishThroughViewModel(env, viewModel: adhocModel)
            XCTAssertEqual(adhocModel.session?.state, .completed)
            let resolved = await adhocModel.debitAdhocSession()
            XCTAssertTrue(resolved)
            XCTAssertNil(adhocModel.creditPrompt)
            let afterAdhoc = try await env.credits.balance(packageID: package.id)
            XCTAssertEqual(afterAdhoc, 2)

            let appointment = try await startFromAppointment(env)
            let linkedModel = ActiveSessionViewModel(
                studentID: env.studentID,
                useCases: env.sessions,
                creditSettlement: env.settlement
            )
            _ = try await recordAndFinishThroughViewModel(env, viewModel: linkedModel)
            XCTAssertNil(linkedModel.creditPrompt, "linked completion debits without asking")
            let afterLinked = try await env.credits.balance(packageID: package.id)
            XCTAssertEqual(afterLinked, 1)
            let completed = try await env.appointments.appointment(id: appointment.id)
            XCTAssertEqual(completed.status, .completed)
            try await env.controller.shutdownForTesting()
        }

        // MARK: - Expired / zero balance (M1B-FR-014)

        func testExpiredPackageNeverDebitsForLinkedOrAdhocFinish() async throws {
            let env = try await makeEnvironment()
            let package = try await makePackage(
                env,
                totalCredits: 5,
                endDate: try LocalDate(year: 2023, month: 11, day: 1)
            )
            let appointment = try await startFromAppointment(env)
            let linked = try await recordAndFinish(env)
            let linkedOutcome = try await env.settlement.settleFinishedSession(linked)
            guard case .packageUnusable(_, .expired) = linkedOutcome else {
                return XCTFail("expected the expired notice, got \(linkedOutcome)")
            }
            let completed = try await env.appointments.appointment(id: appointment.id)
            XCTAssertEqual(completed.status, .completed, "an expired package must not block completion")

            let adhoc = try await recordAndFinish(env)
            let adhocOutcome = try await env.settlement.settleFinishedSession(adhoc)
            guard case .packageUnusable(_, .expired) = adhocOutcome else {
                return XCTFail("expected the expired notice, got \(adhocOutcome)")
            }
            let balance = try await env.credits.balance(packageID: package.id)
            XCTAssertEqual(balance, 5)
            let trail = try await env.credits.adjustments(packageID: package.id)
            XCTAssertTrue(trail.isEmpty)
            try await env.controller.shutdownForTesting()
        }

        func testZeroBalanceNeverGoesNegative() async throws {
            let env = try await makeEnvironment()
            let package = try await makePackage(env, totalCredits: 1)
            try await env.credits.recordManualCorrection(
                packageID: package.id,
                direction: .debit,
                amount: 1,
                reasonText: "补录"
            )

            let appointment = try await startFromAppointment(env)
            let linked = try await recordAndFinish(env)
            let linkedOutcome = try await env.settlement.settleFinishedSession(linked)
            guard case .packageUnusable(_, .insufficientBalance) = linkedOutcome else {
                return XCTFail("expected the insufficient-balance notice, got \(linkedOutcome)")
            }
            let completed = try await env.appointments.appointment(id: appointment.id)
            XCTAssertEqual(completed.status, .completed)

            let adhoc = try await recordAndFinish(env)
            let adhocOutcome = try await env.settlement.settleFinishedSession(adhoc)
            guard case .packageUnusable(_, .insufficientBalance) = adhocOutcome else {
                return XCTFail("expected the insufficient-balance notice, got \(adhocOutcome)")
            }
            do {
                try await env.settlement.debitAdhocSession(packageID: package.id, sessionID: adhoc.id)
                XCTFail("a debit at zero balance must be rejected")
            } catch DomainError.invalidState {}
            let balance = try await env.credits.balance(packageID: package.id)
            XCTAssertEqual(balance, 0)
            let trail = try await env.credits.adjustments(packageID: package.id)
            XCTAssertEqual(trail.map(\.reasonKind), [.manualCorrection])
            try await env.controller.shutdownForTesting()
        }

        // MARK: - Launch repair (crash between finish and settlement)

        func testLaunchRepairSettlesAnInterruptedLinkedFinishExactlyOnce() async throws {
            let env = try await makeEnvironment()
            let package = try await makePackage(env, totalCredits: 5)
            let appointment = try await startFromAppointment(env)
            // The process "died" right after the finish write: no settlement ran.
            let finished = try await recordAndFinish(env)
            let stuck = try await env.appointments.appointment(id: appointment.id)
            XCTAssertEqual(stuck.status, .inProgress)

            let firstRepair = await env.settlement.repairInterruptedLinkedSessions()
            XCTAssertEqual(firstRepair, 1)
            let repaired = try await env.appointments.appointment(id: appointment.id)
            XCTAssertEqual(repaired.status, .completed)
            let secondRepair = await env.settlement.repairInterruptedLinkedSessions()
            XCTAssertEqual(secondRepair, 0, "a repaired Appointment is no longer in progress")

            let balance = try await env.credits.balance(packageID: package.id)
            XCTAssertEqual(balance, 4)
            let trail = try await env.credits.adjustments(packageID: package.id)
            XCTAssertEqual(trail.map(\.sourceEventKey), [CreditLedger.sourceEventKey(sessionComplete: finished.id)])
            try await env.controller.shutdownForTesting()
        }

        func testLaunchRepairLeavesSettledLinkedAndUnansweredAdhocSessionsUntouched() async throws {
            let env = try await makeEnvironment()
            let package = try await makePackage(env, totalCredits: 5)
            _ = try await startFromAppointment(env)
            let linked = try await recordAndFinish(env)
            _ = try await env.settlement.settleFinishedSession(linked)
            // Ad-hoc finish whose question was never answered: no debit at launch.
            _ = try await recordAndFinish(env)

            let repairs = await env.settlement.repairInterruptedLinkedSessions()
            XCTAssertEqual(repairs, 0)
            let balance = try await env.credits.balance(packageID: package.id)
            XCTAssertEqual(balance, 4)
            let trail = try await env.credits.adjustments(packageID: package.id)
            XCTAssertEqual(trail.map(\.reasonKind), [.sessionComplete])
            try await env.controller.shutdownForTesting()
        }

        func testLaunchRepairReturnsAnInterruptedAbandonToScheduled() async throws {
            let env = try await makeEnvironment()
            let appointment = try await startFromAppointment(env)
            _ = try await env.sessions.abandonEmpty()

            let repairs = await env.settlement.repairInterruptedLinkedSessions()
            XCTAssertEqual(repairs, 1)
            let restored = try await env.appointments.appointment(id: appointment.id)
            XCTAssertEqual(restored.status, .scheduled)
            XCTAssertNil(restored.linkedSessionID)
            try await env.controller.shutdownForTesting()
        }

        // MARK: - Abandon

        func testAbandoningLinkedEmptySessionReturnsAppointmentToScheduled() async throws {
            let env = try await makeEnvironment()
            let appointment = try await startFromAppointment(env)
            let abandoned = try await env.sessions.abandonEmpty()
            try await env.settlement.settleAbandonedSession(abandoned)
            let restored = try await env.appointments.appointment(id: appointment.id)
            XCTAssertEqual(restored.status, .scheduled)
            XCTAssertNil(restored.linkedSessionID)
            try await env.controller.shutdownForTesting()
        }

        private func recordAndFinishThroughViewModel(
            _ env: Environment,
            viewModel: ActiveSessionViewModel
        ) async throws -> Session {
            await viewModel.load()
            let active = try await env.sessions.addSessionOnlyExercise(
                displayName: "结算测试动作",
                recordMode: .weightReps
            )
            let exerciseID = try XCTUnwrap(active.exercises.last?.id)
            let withSet = try await env.sessions.addSet(
                exerciseID: exerciseID,
                input: TrainingSetInput(recordMode: .weightReps, weightValue: "40", repetitionCount: "8", unit: .kilograms)
            )
            _ = try await env.sessions.confirmSet(setID: try XCTUnwrap(withSet.exercises.last?.sets.last?.id))
            await viewModel.load()
            await viewModel.finishNow()
            XCTAssertNil(viewModel.errorMessage)
            return try XCTUnwrap(viewModel.session)
        }
    }
#else
    import XCTest

    final class SessionCreditSettlementTests: XCTestCase {
        func testReleaseBuildSkipsDebugOnlyIntegrationCoverage() {
            XCTAssertTrue(true)
        }
    }
#endif
