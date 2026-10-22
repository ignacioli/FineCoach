#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// M1A-FR-018 (2026-10-22 revision): each Student owns at most one
    /// in-progress Session, and different Students' Sessions are independent.
    final class PerStudentSessionIntegrationTests: XCTestCase {
        private let now = Date(timeIntervalSince1970: 1_700_000_000)
        private let studentA = StableUUID(UUID(uuidString: "aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa")!)
        private let studentB = StableUUID(UUID(uuidString: "bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb")!)
        private let generationUUID = UUID(uuidString: "cccccccc-3333-4333-8333-cccccccccccc")!
        private let recoveryFileStem = "active-session-recovery-v1"

        private struct Environment {
            let directory: TemporaryProtectedDirectory
            let storeURL: URL
            let recoveryURL: URL
            let controller: PersistenceController
            let clock: TestClock
            let students: StudentUseCases
            let sessions: ActiveSessionUseCases
            let appointments: AppointmentUseCases
            let credits: CreditLedgerUseCases
            let settlement: SessionCreditSettlement
        }

        // MARK: - §5.1 / §5.2

        func testTwoStudentsTrainIndependentlyAndKeepTheirOwnTimers() async throws {
            let environment = try makeEnvironment()
            try await createStudents(environment)

            let firstA = try await environment.sessions.startOrOpen(studentID: studentA)
            environment.clock.advance(seconds: 60)
            let firstB = try await environment.sessions.startOrOpen(studentID: studentB)

            XCTAssertEqual(firstA.studentID, studentA)
            XCTAssertEqual(firstB.studentID, studentB)
            XCTAssertNotEqual(firstA.id, firstB.id)
            XCTAssertEqual(firstA.startedAtUTC, now)
            XCTAssertEqual(firstB.startedAtUTC, now.addingTimeInterval(60))

            let loadedAfterStartingB = try await environment.sessions.loadActive(studentID: studentA)
            let afterStartingB = try XCTUnwrap(loadedAfterStartingB)
            XCTAssertEqual(afterStartingB.id, firstA.id)
            XCTAssertEqual(afterStartingB.startedAtUTC, firstA.startedAtUTC)
            XCTAssertEqual(afterStartingB.revision, firstA.revision)
            XCTAssertEqual(afterStartingB.state, .inProgress)
            let inProgressCount = try await countSessions(state: "inProgress", environment: environment)
            XCTAssertEqual(inProgressCount, 2)
            try await environment.controller.shutdownForTesting()
        }

        func testStartingAgainForTheSameStudentReturnsHisOwnSession() async throws {
            let environment = try makeEnvironment()
            try await createStudents(environment)

            let first = try await environment.sessions.startOrOpen(studentID: studentA)
            let second = try await environment.sessions.startOrOpen(studentID: studentA)
            let other = try await environment.sessions.startOrOpen(studentID: studentB)

            XCTAssertEqual(second.id, first.id)
            XCTAssertEqual(second.studentID, studentA)
            XCTAssertEqual(other.studentID, studentB)
            XCTAssertNotEqual(other.id, first.id)
            let totalSessions = try await countSessions(environment: environment)
            XCTAssertEqual(totalSessions, 2)
            try await environment.controller.shutdownForTesting()
        }

        func testFinishedSessionDoesNotRemainInTheSingleSessionCompatibilityIndex() async throws {
            let environment = try makeEnvironment()
            try await createStudents(environment)

            let first = try await environment.sessions.startOrOpen(studentID: studentA)
            let withExercise = try await environment.sessions.addSessionOnlyExercise(
                sessionID: first.id,
                displayName: "杠铃深蹲",
                recordMode: .weightReps
            )
            let exerciseID = try XCTUnwrap(withExercise.exercises.last?.id)
            let withSet = try await environment.sessions.addSet(
                sessionID: first.id,
                exerciseID: exerciseID,
                input: TrainingSetInput(
                    recordMode: .weightReps,
                    weightValue: "40",
                    repetitionCount: "8",
                    unit: .kilograms
                )
            )
            let setID = try XCTUnwrap(withSet.exercises.last?.sets.last?.id)
            _ = try await environment.sessions.confirmSet(sessionID: first.id, setID: setID)
            _ = try await environment.sessions.finish(sessionID: first.id)

            let next = try await environment.sessions.startOrOpen(studentID: studentA)
            // Deliberately use the compatibility overload: the finished Session
            // must no longer be part of the "sole known Session" set.
            let updated = try await environment.sessions.addSessionOnlyExercise(
                displayName: "哑铃卧推",
                recordMode: .weightReps
            )
            XCTAssertEqual(updated.id, next.id)
            XCTAssertEqual(updated.exercises.last?.displayNameSnapshot.value, "哑铃卧推")
            try await environment.controller.shutdownForTesting()
        }

        // MARK: - §5.3

        func testAlternatingSetsStayWithTheirSessionAndFinishingOneDoesNotAffectTheOther() async throws {
            let environment = try makeEnvironment()
            try await createStudents(environment)
            let packageA = try await environment.credits.createActivePackage(
                studentID: studentA,
                name: "十次课",
                totalCredits: 5,
                startDate: nil,
                endDate: nil
            )
            let packageB = try await environment.credits.createActivePackage(
                studentID: studentB,
                name: "十次课",
                totalCredits: 5,
                startDate: nil,
                endDate: nil
            )

            let sessionA = try await environment.sessions.startOrOpen(studentID: studentA)
            let sessionB = try await environment.sessions.startOrOpen(studentID: studentB)
            let exerciseA = try await addExerciseAndConfirmSet(
                environment,
                sessionID: sessionA.id,
                name: "杠铃深蹲"
            )
            let exerciseB = try await addExerciseAndConfirmSet(
                environment,
                sessionID: sessionB.id,
                name: "哑铃卧推"
            )

            let loadedA = try await environment.sessions.loadActive(sessionID: sessionA.id)
            let loadedB = try await environment.sessions.loadActive(sessionID: sessionB.id)
            let storedA = try XCTUnwrap(loadedA)
            let storedB = try XCTUnwrap(loadedB)
            XCTAssertEqual(storedA.exercises.map(\.id), [exerciseA])
            XCTAssertEqual(storedB.exercises.map(\.id), [exerciseB])
            XCTAssertEqual(storedA.exercises.first?.displayNameSnapshot.value, "杠铃深蹲")
            XCTAssertEqual(storedB.exercises.first?.displayNameSnapshot.value, "哑铃卧推")
            XCTAssertEqual(storedA.completedSetCount, 1)
            XCTAssertEqual(storedB.completedSetCount, 1)

            let finishedA = try await environment.sessions.finish(sessionID: sessionA.id)
            XCTAssertEqual(finishedA.state, .completed)
            let reopenedA = try await environment.sessions.loadActive(sessionID: sessionA.id)
            XCTAssertNil(reopenedA)

            let loadedAfterAFinishedB = try await environment.sessions.loadActive(sessionID: sessionB.id)
            let afterAFinishedB = try XCTUnwrap(loadedAfterAFinishedB)
            XCTAssertEqual(afterAFinishedB.id, sessionB.id)
            XCTAssertEqual(afterAFinishedB.state, .inProgress)
            XCTAssertEqual(afterAFinishedB.exercises.map(\.id), [exerciseB])
            XCTAssertEqual(afterAFinishedB.completedSetCount, 1)

            try await environment.settlement.debitAdhocSession(
                packageID: packageA.id,
                sessionID: finishedA.id
            )
            let balanceA = try await environment.credits.balance(packageID: packageA.id)
            let balanceB = try await environment.credits.balance(packageID: packageB.id)
            XCTAssertEqual(balanceA, 4)
            XCTAssertEqual(balanceB, 5)
            try await environment.controller.shutdownForTesting()
        }

        // MARK: - §5.4

        func testRestartRestoresEveryInProgressSessionWithItsOwnElapsedTime() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let recoveryURL = directory.url.appendingPathComponent("\(recoveryFileStem).json")
            let firstEnvironment = try makeEnvironment(
                directory: directory,
                storeURL: storeURL,
                recoveryURL: recoveryURL
            )
            try await createStudents(firstEnvironment)

            let sessionA = try await firstEnvironment.sessions.startOrOpen(studentID: studentA)
            _ = try await addExerciseAndConfirmSet(
                firstEnvironment,
                sessionID: sessionA.id,
                name: "杠铃深蹲"
            )
            firstEnvironment.clock.advance(seconds: 120)
            let sessionB = try await firstEnvironment.sessions.startOrOpen(studentID: studentB)
            _ = try await addExerciseAndConfirmSet(
                firstEnvironment,
                sessionID: sessionB.id,
                name: "哑铃卧推"
            )
            try await firstEnvironment.controller.shutdownForTesting()

            let reopened = try makeEnvironment(
                directory: directory,
                storeURL: storeURL,
                recoveryURL: recoveryURL
            )
            reopened.clock.advance(seconds: 120)
            _ = try await reopened.sessions.reconcileOnLaunch()

            let loadedRestoredA = try await reopened.sessions.loadActive(studentID: studentA)
            let loadedRestoredB = try await reopened.sessions.loadActive(studentID: studentB)
            let restoredA = try XCTUnwrap(loadedRestoredA)
            let restoredB = try XCTUnwrap(loadedRestoredB)
            XCTAssertEqual(restoredA.id, sessionA.id)
            XCTAssertEqual(restoredB.id, sessionB.id)
            XCTAssertEqual(restoredA.state, .inProgress)
            XCTAssertEqual(restoredB.state, .inProgress)
            XCTAssertEqual(restoredA.exercises.first?.displayNameSnapshot.value, "杠铃深蹲")
            XCTAssertEqual(restoredB.exercises.first?.displayNameSnapshot.value, "哑铃卧推")
            XCTAssertEqual(restoredA.completedSetCount, 1)
            XCTAssertEqual(restoredB.completedSetCount, 1)
            XCTAssertEqual(restoredA.elapsedSeconds, try DecimalValue.seconds(120))
            XCTAssertEqual(restoredB.elapsedSeconds, try DecimalValue.seconds(0))
            try await reopened.controller.shutdownForTesting()
        }

        // MARK: - §5.6

        func testStartingFromAnAppointmentOpensThatStudentsOwnSessionAndLinksIt() async throws {
            let environment = try makeEnvironment()
            try await createStudents(environment)
            let sessionA = try await environment.sessions.startOrOpen(studentID: studentA)

            let appointment = try await environment.appointments.createSingle(
                studentID: studentB,
                date: try LocalDate(year: 2023, month: 11, day: 14),
                startTime: try LocalTime(hour: 9, minute: 0),
                overrideConflict: false
            )
            let sessionB = try await environment.appointments.startTraining(appointmentID: appointment.id)
            XCTAssertEqual(sessionB.studentID, studentB)
            XCTAssertNotEqual(sessionB.id, sessionA.id)

            let linked = try await environment.appointments.appointment(id: appointment.id)
            XCTAssertEqual(linked.linkedSessionID, sessionB.id)
            XCTAssertEqual(linked.status, .inProgress)
            let loadedUntouchedA = try await environment.sessions.loadActive(studentID: studentA)
            let untouchedA = try XCTUnwrap(loadedUntouchedA)
            XCTAssertEqual(untouchedA.id, sessionA.id)
            try await environment.controller.shutdownForTesting()
        }

        // MARK: - Legacy data migration

        func testLaunchMigratesLegacyActivePointerAndSingleRecoverySnapshot() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let recoveryURL = directory.url.appendingPathComponent("\(recoveryFileStem).json")
            let firstEnvironment = try makeEnvironment(
                directory: directory,
                storeURL: storeURL,
                recoveryURL: recoveryURL
            )
            try await createStudents(firstEnvironment)
            let started = try await firstEnvironment.sessions.startOrOpen(studentID: studentA)
            let withExercise = try await firstEnvironment.sessions.addSessionOnlyExercise(
                sessionID: started.id,
                displayName: "杠铃深蹲",
                recordMode: .weightReps
            )
            firstEnvironment.clock.advance(seconds: 300)
            let latest = try await firstEnvironment.sessions.addSet(
                sessionID: started.id,
                exerciseID: try XCTUnwrap(withExercise.exercises.last?.id),
                input: TrainingSetInput(
                    recordMode: .weightReps,
                    weightValue: "40",
                    repetitionCount: "8",
                    unit: .kilograms
                )
            )

            // Rewrite the pointer to the pre-2026-10-22 `"active"` key.
            try await firstEnvironment.controller.writer.transaction { context in
                let request = NSFetchRequest<NSManagedObject>(entityName: "ActiveSessionPointerMO")
                let pointers = try context.fetch(request)
                XCTAssertEqual(pointers.count, 1)
                pointers.first?.setValue(ActiveSessionPointerKey.singleton, forKey: "singletonKey")
            }
            // Replace the per-Session snapshot with the old single snapshot file.
            let recoveryFiles = try FileManager.default.contentsOfDirectory(atPath: directory.url.path)
            for name in recoveryFiles
            where name.hasPrefix("\(recoveryFileStem).") && name != "\(recoveryFileStem).json" {
                try FileManager.default.removeItem(at: directory.url.appendingPathComponent(name))
            }
            let legacySnapshot = try ActiveSessionRecoverySnapshot(
                storeGenerationUUID: generationUUID,
                session: latest
            )
            _ = try ProtectedFileStore().atomicReplace(
                data: try legacySnapshot.encoded(),
                at: recoveryURL,
                policy: .business
            )
            try await firstEnvironment.controller.shutdownForTesting()

            let reopened = try makeEnvironment(
                directory: directory,
                storeURL: storeURL,
                recoveryURL: recoveryURL
            )
            _ = try await reopened.sessions.reconcileOnLaunch()

            let migratedPointer = try await pointerKeys(in: reopened.controller.writer)
            XCTAssertEqual(migratedPointer, [ActiveSessionPointerKey.student(studentA)])
            XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryURL.path))
            let loadedRestored = try await reopened.sessions.loadActive(studentID: studentA)
            let restored = try XCTUnwrap(loadedRestored)
            XCTAssertEqual(restored.id, latest.id)
            XCTAssertEqual(restored.exercises.first?.displayNameSnapshot.value, "杠铃深蹲")
            XCTAssertEqual(restored.exercises.first?.sets.first?.state, .draft)
            try await reopened.controller.shutdownForTesting()
        }

        // MARK: - Helpers

        private func makeEnvironment(
            directory providedDirectory: TemporaryProtectedDirectory? = nil,
            storeURL providedStoreURL: URL? = nil,
            recoveryURL providedRecoveryURL: URL? = nil
        ) throws -> Environment {
            let directory: TemporaryProtectedDirectory
            if let providedDirectory {
                directory = providedDirectory
            } else {
                directory = try TemporaryProtectedDirectory()
            }
            let storeURL = providedStoreURL ?? directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let recoveryURL =
                providedRecoveryURL ?? directory.url.appendingPathComponent("\(recoveryFileStem).json")
            let controller = try PersistenceController(storeURL: storeURL)
            let clock = TestClock(utcDate: now)
            let studentRepository = CoreDataStudentRepository(writer: controller.writer)
            let sessionRepository = CoreDataSessionRepository(writer: controller.writer)
            let students = StudentUseCases(
                repository: studentRepository,
                clock: clock,
                ids: TestIDGenerator(ids: [studentA.rawValue, studentB.rawValue])
            )
            let sessions = ActiveSessionUseCases(
                sessionRepository: sessionRepository,
                studentRepository: studentRepository,
                exerciseRepository: CoreDataExerciseRepository(writer: controller.writer),
                sectionRepository: CoreDataSessionSectionRepository(writer: controller.writer),
                recoveryStore: ActiveSessionRecoveryStore(
                    url: recoveryURL,
                    protectedFileStore: ProtectedFileStore()
                ),
                storeGenerationUUID: generationUUID,
                clock: clock,
                ids: SystemIDGenerator()
            )
            let calendarProvider = TestCalendarProvider(timeZone: TimeZone(identifier: "UTC")!)
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
                ids: SystemIDGenerator()
            )
            let credits = CreditLedgerUseCases(
                repository: CoreDataCoursePackageRepository(writer: controller.writer),
                clock: clock,
                ids: SystemIDGenerator()
            )
            let history = HistoryUseCases(
                sessionRepository: sessionRepository,
                clock: clock,
                ids: SystemIDGenerator()
            )
            return Environment(
                directory: directory,
                storeURL: storeURL,
                recoveryURL: recoveryURL,
                controller: controller,
                clock: clock,
                students: students,
                sessions: sessions,
                appointments: appointments,
                credits: credits,
                settlement: SessionCreditSettlement(
                    appointments: appointments,
                    credits: credits,
                    history: history
                )
            )
        }

        private func createStudents(_ environment: Environment) async throws {
            _ = try await environment.students.create(
                draft: StudentDraft(displayName: "林青", sex: .female)
            )
            _ = try await environment.students.create(
                draft: StudentDraft(displayName: "周宁", sex: .male)
            )
        }

        private func addExerciseAndConfirmSet(
            _ environment: Environment,
            sessionID: StableUUID,
            name: String
        ) async throws -> StableUUID {
            let withExercise = try await environment.sessions.addSessionOnlyExercise(
                sessionID: sessionID,
                displayName: name,
                recordMode: .weightReps
            )
            let exerciseID = try XCTUnwrap(withExercise.exercises.last?.id)
            let withSet = try await environment.sessions.addSet(
                sessionID: sessionID,
                exerciseID: exerciseID,
                input: TrainingSetInput(
                    recordMode: .weightReps,
                    weightValue: "40",
                    repetitionCount: "8",
                    unit: .kilograms
                )
            )
            let setID = try XCTUnwrap(withSet.exercises.last?.sets.last?.id)
            _ = try await environment.sessions.confirmSet(sessionID: sessionID, setID: setID)
            return exerciseID
        }

        private func countSessions(
            state: String? = nil,
            environment: Environment
        ) async throws -> Int {
            try await environment.controller.writer.read { context in
                let request = NSFetchRequest<NSManagedObject>(entityName: "SessionMO")
                if let state {
                    request.predicate = NSPredicate(format: "state == %@", state)
                }
                return try context.count(for: request)
            }
        }

        private func pointerKeys(in writer: PersistenceWriter) async throws -> [String] {
            try await writer.read { context in
                let request = NSFetchRequest<NSManagedObject>(entityName: "ActiveSessionPointerMO")
                return try context.fetch(request).compactMap {
                    $0.value(forKey: "singletonKey") as? String
                }.sorted()
            }
        }
    }
#else
    import FineCoach
    import XCTest

    final class PerStudentSessionIntegrationTests: XCTestCase {
        func testReleaseKeepsPerStudentSessionDomainSurface() {
            XCTAssertEqual(ActiveSessionPointerKey.singleton, "active")
            XCTAssertEqual(
                ActiveSessionPointerKey.student(
                    StableUUID(UUID(uuidString: "aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa")!)
                ),
                "AAAAAAAA-1111-4111-8111-AAAAAAAAAAAA"
            )
        }
    }
#endif
