#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// T044 (US5, spec section 6.7 / AC-014 / SC-007). Reuses the M1-A
    /// `BackupRoundTripTests` harness shape (temp directories, `PersistenceController`
    /// wiring, `BackupCoordinator` setup) rather than reinventing it, and adds one
    /// fixture per section 6.7 inventory item on top of the M1-A baseline: Appointment
    /// (standalone + one materialized from a RecurrenceSeries), CoursePackage +
    /// CreditAdjustment, TrainingTemplate + TemplateExercise (+ a Template-owned
    /// SessionSection), a Session-owned SessionSection, a custom BodyMetricDefinition +
    /// BodyMeasurement, and the sessions/sets additive fields (cardio distance/speed/
    /// resistance, SessionExercise.sectionID, Session.appointmentID).
    final class M1BBackupRoundTripTests: XCTestCase {
        private let studentID = StableUUID(FictitiousFixtures.student.id)
        private let completedSessionID = StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        private let squatExerciseID = StableUUID(UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
        private let squatSetID = StableUUID(UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!)
        private let cardioExerciseID = StableUUID(UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!)
        private let cardioSetID = StableUUID(UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!)
        private let sessionSectionID = StableUUID(UUID(uuidString: "11111111-2222-4333-8444-555555555555")!)

        private let packageID = StableUUID(UUID(uuidString: "10000000-0000-4000-8000-000000000001")!)
        private let adjustmentID = StableUUID(UUID(uuidString: "10000000-0000-4000-8000-000000000002")!)
        private let seriesID = StableUUID(UUID(uuidString: "20000000-0000-4000-8000-000000000001")!)
        private let seriesAppointmentID = StableUUID(UUID(uuidString: "20000000-0000-4000-8000-000000000002")!)
        private let standaloneAppointmentID = StableUUID(UUID(uuidString: "20000000-0000-4000-8000-000000000003")!)
        private let templateID = StableUUID(UUID(uuidString: "30000000-0000-4000-8000-000000000001")!)
        private let templateExerciseAID = StableUUID(UUID(uuidString: "30000000-0000-4000-8000-000000000002")!)
        private let templateExerciseBID = StableUUID(UUID(uuidString: "30000000-0000-4000-8000-000000000003")!)
        private let templateSectionID = StableUUID(UUID(uuidString: "30000000-0000-4000-8000-000000000004")!)
        private let bodyMetricID = StableUUID(UUID(uuidString: "40000000-0000-4000-8000-000000000001")!)
        private let bodyMeasurementID = StableUUID(UUID(uuidString: "40000000-0000-4000-8000-000000000002")!)

        private let backupFileID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
        private let sourceGenerationID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        private let destinationGenerationID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        private let restoredGenerationID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
        private let now = Date(timeIntervalSince1970: 1_700_000_000)
        private let exportPasswordText = "口令测试甲乙丙丁"
        private let wrongPasswordText = "口令测试戊己庚辛"

        // MARK: - Correct password round trip

        func testFullM1BInventoryRoundTripPreservesEveryFieldAndStableIdentity() async throws {
            let source = try makeHarness(generationUUID: sourceGenerationID, sessionIDs: sessionUseCaseIDs())
            try await seedM1BInventory(on: source)
            let exported = try await exportInventory(from: source)
            try await source.controller.shutdownForTesting()

            let destinationRoot = try TemporaryProtectedDirectory()
            let destination = try makeHarness(
                rootDirectory: destinationRoot,
                generationUUID: destinationGenerationID,
                sessionIDs: []
            )
            try await makeCoordinator(harness: destination, ids: [restoredGenerationID]).restoreReplacingCurrent(
                BackupRestoreRequest(
                    password: try BackupPassword(creating: exportPasswordText),
                    sourceFileURL: exported.fileURL
                )
            )
            try await destination.controller.shutdownForTesting()

            let restored = try makeHarness(rootDirectory: destinationRoot, sessionIDs: [])
            try await assertRestoredM1BInventory(on: restored)
            try await restored.controller.shutdownForTesting()
        }

        // MARK: - Wrong password / corrupted file leave current data unchanged

        func testWrongPasswordRestoreLeavesM1BInventoryUnchanged() async throws {
            let source = try makeHarness(generationUUID: sourceGenerationID, sessionIDs: sessionUseCaseIDs())
            try await seedM1BInventory(on: source)
            let exported = try await exportInventory(from: source)

            do {
                try await makeCoordinator(harness: source, ids: [restoredGenerationID]).restoreReplacingCurrent(
                    BackupRestoreRequest(
                        password: try BackupPassword(creating: wrongPasswordText),
                        sourceFileURL: exported.fileURL
                    )
                )
                XCTFail("Expected authenticationFailed")
            } catch BackupError.authenticationFailed {
                // expected
            }

            try await assertRestoredM1BInventory(on: source)
            try await source.controller.shutdownForTesting()
        }

        func testCorruptedFileRestoreLeavesM1BInventoryUnchanged() async throws {
            let source = try makeHarness(generationUUID: sourceGenerationID, sessionIDs: sessionUseCaseIDs())
            try await seedM1BInventory(on: source)
            let exported = try await exportInventory(from: source)

            var corrupted = try Data(contentsOf: exported.fileURL)
            corrupted = corrupted.prefix(max(0, corrupted.count - 64))
            try corrupted.write(to: exported.fileURL, options: .atomic)

            do {
                try await makeCoordinator(harness: source, ids: [restoredGenerationID]).restoreReplacingCurrent(
                    BackupRestoreRequest(
                        password: try BackupPassword(creating: exportPasswordText),
                        sourceFileURL: exported.fileURL
                    )
                )
                XCTFail("Expected a BackupError on a truncated file")
            } catch is BackupError {
                // expected -- any BackupError is an acceptable fail-closed outcome for a
                // truncated/corrupted container (authenticationFailed or invalidHeader
                // depending on exactly which byte range was truncated).
            }

            try await assertRestoredM1BInventory(on: source)
            try await source.controller.shutdownForTesting()
        }

        // MARK: - Harness (mirrors BackupRoundTripTests.Harness)

        private struct Harness {
            let rootDirectory: TemporaryProtectedDirectory
            let directory: StoreGenerationDirectory
            let generationUUID: UUID
            let storeURL: URL
            let controller: PersistenceController
            let studentUseCases: StudentUseCases
            let sessionUseCases: ActiveSessionUseCases
            let appointmentRepository: CoreDataAppointmentRepository
            let coursePackageRepository: CoreDataCoursePackageRepository
            let templateRepository: CoreDataTemplateRepository
            let sectionRepository: CoreDataSessionSectionRepository
            let bodyDataRepository: CoreDataBodyDataRepository
            let clock: TestClock
        }

        private func sessionUseCaseIDs() -> [UUID] {
            // `StudentUseCases.create` and `ActiveSessionUseCases` share ONE
            // `TestIDGenerator` (mirrors `BackupRoundTripTests`), so the Student's own
            // id (consumed first, by `create`) MUST lead this list.
            [
                studentID.rawValue,
                completedSessionID.rawValue,
                squatExerciseID.rawValue,
                squatSetID.rawValue,
                sessionSectionID.rawValue,
                cardioExerciseID.rawValue,
                cardioSetID.rawValue,
            ]
        }

        private func makeHarness(
            rootDirectory: TemporaryProtectedDirectory? = nil,
            generationUUID: UUID? = nil,
            sessionIDs: [UUID]
        ) throws -> Harness {
            let root = try rootDirectory ?? TemporaryProtectedDirectory()
            let directory = StoreGenerationDirectory(rootURL: root.url)
            try directory.prepare()
            let pointerStore = CurrentGenerationPointerStore(url: directory.currentPointerURL)
            let metadataStore = StoreGenerationMetadataStore(directory: directory)
            let resolvedUUID: UUID
            if let existing = try pointerStore.read() {
                resolvedUUID = existing.generationUUID
            } else {
                resolvedUUID = generationUUID ?? sourceGenerationID
                try ProtectedFileStore().prepareDirectory(
                    at: directory.generationURL(for: resolvedUUID),
                    policy: .business
                )
                try metadataStore.write(
                    try StoreGenerationMetadata(
                        generationUUID: resolvedUUID,
                        createdAtUTC: now,
                        validationState: .current
                    )
                )
                try pointerStore.replace(with: try CurrentGenerationPointer(generationUUID: resolvedUUID))
            }
            let storeURL = directory.databaseURL(for: resolvedUUID)
            let controller = try PersistenceController(storeURL: storeURL)
            let clock = TestClock(utcDate: now)
            let idGenerator = TestIDGenerator(ids: sessionIDs)
            let studentRepository = CoreDataStudentRepository(writer: controller.writer)
            let sectionRepository = CoreDataSessionSectionRepository(writer: controller.writer)
            return Harness(
                rootDirectory: root,
                directory: directory,
                generationUUID: resolvedUUID,
                storeURL: storeURL,
                controller: controller,
                studentUseCases: StudentUseCases(
                    repository: studentRepository,
                    clock: clock,
                    ids: idGenerator
                ),
                sessionUseCases: ActiveSessionUseCases(
                    sessionRepository: CoreDataSessionRepository(writer: controller.writer),
                    studentRepository: studentRepository,
                    exerciseRepository: CoreDataExerciseRepository(writer: controller.writer),
                    sectionRepository: sectionRepository,
                    recoveryStore: ActiveSessionRecoveryStore(
                        url: directory.activeRecoveryURL,
                        protectedFileStore: ProtectedFileStore()
                    ),
                    storeGenerationUUID: resolvedUUID,
                    clock: clock,
                    ids: idGenerator
                ),
                appointmentRepository: CoreDataAppointmentRepository(writer: controller.writer),
                coursePackageRepository: CoreDataCoursePackageRepository(writer: controller.writer),
                templateRepository: CoreDataTemplateRepository(writer: controller.writer),
                sectionRepository: sectionRepository,
                bodyDataRepository: CoreDataBodyDataRepository(writer: controller.writer),
                clock: clock
            )
        }

        private func makeCoordinator(harness: Harness, ids: [UUID]) -> BackupCoordinator {
            BackupCoordinator(
                rootURL: harness.rootDirectory.url,
                writer: harness.controller.writer,
                clock: harness.clock,
                ids: TestIDGenerator(ids: ids)
            )
        }

        private struct ExportedBackup {
            let destination: TemporaryProtectedDirectory
            let result: BackupExportResult
            var fileURL: URL { result.fileURL }
        }

        private func exportInventory(from harness: Harness) async throws -> ExportedBackup {
            let destination = try TemporaryProtectedDirectory()
            let result = try await makeCoordinator(harness: harness, ids: [backupFileID]).exportInventory(
                BackupExportRequest(
                    password: try BackupPassword(creating: exportPasswordText),
                    destinationDirectory: destination.url
                )
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.fileURL.path))
            return ExportedBackup(destination: destination, result: result)
        }

        // MARK: - Fixture seeding (one item per spec §6.7 inventory bullet)

        private func seedM1BInventory(on harness: Harness) async throws {
            _ = try await harness.studentUseCases.create(
                draft: StudentDraft(
                    displayName: FictitiousFixtures.student.displayName,
                    sex: .female,
                    trainingGoal: FictitiousFixtures.student.trainingGoal
                )
            )

            // Session: one weightReps set + one cardio set (distance/speed/resistance),
            // one Exercise moved into a Session-owned Section (sectionID additive field).
            _ = try await harness.sessionUseCases.startOrOpen(studentID: studentID)
            _ = try await harness.sessionUseCases.addSessionOnlyExercise(
                displayName: "杠铃深蹲",
                recordMode: .weightReps
            )
            _ = try await harness.sessionUseCases.addSet(
                exerciseID: squatExerciseID,
                input: TrainingSetInput(recordMode: .weightReps, weightValue: "40", repetitionCount: "8", unit: .kilograms)
            )
            _ = try await harness.sessionUseCases.confirmSet(setID: squatSetID)
            let section = try await harness.sessionUseCases.createSection(name: "热身区")
            XCTAssertEqual(section.id, sessionSectionID)
            _ = try await harness.sessionUseCases.moveExerciseToSection(
                exerciseID: squatExerciseID,
                toSectionID: sessionSectionID
            )
            _ = try await harness.sessionUseCases.addSessionOnlyExercise(
                displayName: "椭圆机",
                recordMode: .cardio
            )
            _ = try await harness.sessionUseCases.addSet(
                exerciseID: cardioExerciseID,
                input: TrainingSetInput(
                    recordMode: .cardio,
                    durationSeconds: "600",
                    unit: .seconds,
                    distanceValue: "3000",
                    speedValue: "5",
                    resistanceValue: "3"
                )
            )
            _ = try await harness.sessionUseCases.confirmSet(setID: cardioSetID)
            let finished = try await harness.sessionUseCases.finish()
            XCTAssertEqual(finished.id, completedSessionID)
            XCTAssertEqual(finished.state, .completed)

            // Appointment: one standalone appointment linked to the completed Session
            // (plus the Session's OWN appointmentID attribute set the other way, so both
            // additive directions round-trip), and one materialized from a RecurrenceSeries.
            let standalone = try Appointment(
                id: standaloneAppointmentID,
                studentID: studentID,
                seriesID: nil,
                date: try LocalDate(year: 2025, month: 3, day: 10),
                startTime: try LocalTime(hour: 9, minute: 0),
                durationMinutes: 60,
                status: .completed,
                reminderEnabled: true,
                reminderLeadMinutes: .thirty,
                linkedSessionID: completedSessionID,
                createdAtUTC: now,
                updatedAtUTC: now
            )
            _ = try await harness.appointmentRepository.create(standalone)
            try await setSessionAppointmentID(
                sessionID: completedSessionID,
                appointmentID: standaloneAppointmentID.rawValue,
                writer: harness.controller.writer
            )

            let series = try RecurrenceSeries(
                id: seriesID,
                studentID: studentID,
                intervalDays: .everyWeek,
                termination: .repeatCount(1),
                defaultStartTime: try LocalTime(hour: 18, minute: 30),
                defaultDurationMinutes: 90,
                defaultReminderEnabled: true,
                defaultReminderLeadMinutes: .sixty,
                createdAtUTC: now,
                updatedAtUTC: now
            )
            let seriesAppointment = try Appointment(
                id: seriesAppointmentID,
                studentID: studentID,
                seriesID: seriesID,
                date: try LocalDate(year: 2025, month: 3, day: 17),
                startTime: try LocalTime(hour: 18, minute: 30),
                durationMinutes: 90,
                status: .scheduled,
                reminderEnabled: true,
                reminderLeadMinutes: .sixty,
                createdAtUTC: now,
                updatedAtUTC: now
            )
            try await harness.appointmentRepository.createSeries(series: series, appointments: [seriesAppointment])

            // CoursePackage + CreditAdjustment (sourceEventKey proves idempotency).
            let package = try CoursePackage(
                id: packageID,
                studentID: studentID,
                name: try ValidatedText("十次卡"),
                totalCredits: 10,
                startDate: try LocalDate(year: 2025, month: 3, day: 1),
                createdAtUTC: now,
                updatedAtUTC: now
            )
            _ = try await harness.coursePackageRepository.activatePackage(package, now: now)
            let capturedAdjustmentID = adjustmentID
            let capturedPackageID = packageID
            let capturedCompletedSessionID = completedSessionID
            let capturedNow = now
            _ = try await harness.coursePackageRepository.recordIdempotentAdjustment(
                packageID: packageID,
                sourceEventKey: "manual-correction-test-1",
                now: now
            ) { _ in
                try CreditAdjustment(
                    id: capturedAdjustmentID,
                    packageID: capturedPackageID,
                    direction: .debit,
                    amount: 1,
                    reasonKind: .manualCorrection,
                    reasonText: try ValidatedText("补记一次训练"),
                    linkedSessionID: capturedCompletedSessionID,
                    sourceEventKey: "manual-correction-test-1",
                    createdAtUTC: capturedNow
                )
            }

            // TrainingTemplate + ordered TemplateExercise (+ a Template-owned Section).
            let template = try TrainingTemplate(
                id: templateID,
                name: "上肢模板",
                trainingFocus: [.arms],
                createdAtUTC: now,
                updatedAtUTC: now
            )
            _ = try await harness.templateRepository.createTemplate(template)
            let templateSection = SessionSection(
                id: templateSectionID,
                ownerKind: .template,
                ownerID: templateID,
                name: try NormalizedName("热身"),
                orderIndex: 0
            )
            _ = try await harness.sectionRepository.upsert(templateSection)
            let plannedSet = TemplatePlannedSet(
                recordMode: .weightReps,
                weightValue: try DecimalValue("20"),
                repetitionCount: try DecimalValue("10"),
                unit: .kilograms
            )
            let templateExerciseA = TemplateExercise(
                id: templateExerciseAID,
                templateID: templateID,
                sectionID: templateSectionID,
                orderIndex: 1,
                sourceKind: .sessionOnly,
                sourceID: nil,
                displayNameSnapshot: try NormalizedName("哑铃推举"),
                recordModeSnapshot: .weightReps,
                plannedSets: [plannedSet]
            )
            let templateExerciseB = TemplateExercise(
                id: templateExerciseBID,
                templateID: templateID,
                sectionID: nil,
                orderIndex: 2,
                sourceKind: .sessionOnly,
                sourceID: nil,
                displayNameSnapshot: try NormalizedName("引体向上"),
                recordModeSnapshot: .reps,
                plannedSets: [TemplatePlannedSet(recordMode: .reps, repetitionCount: try DecimalValue("6"), unit: .repetitions)]
            )
            try await harness.templateRepository.replaceExercises(
                templateID: templateID,
                with: [templateExerciseA, templateExerciseB]
            )

            // Custom BodyMetricDefinition + one BodyMeasurement.
            let metric = try BodyMetricDefinition(
                id: bodyMetricID,
                studentID: studentID,
                kind: .custom,
                name: "臂围",
                unitRuleKind: .customUnit,
                currentUnit: "cm",
                lifecycle: .active,
                createdAtUTC: now,
                updatedAtUTC: now
            )
            _ = try await harness.bodyDataRepository.createCustomMetric(metric)
            _ = try await harness.bodyDataRepository.recordMeasurement(
                studentID: studentID,
                metricID: bodyMetricID,
                localCalendarDay: try LocalDate(year: 2025, month: 3, day: 5),
                value: try DecimalValue("32.5"),
                enteredUnit: "cm",
                newID: bodyMeasurementID,
                now: now
            )
        }

        private func setSessionAppointmentID(
            sessionID: StableUUID,
            appointmentID: UUID,
            writer: PersistenceWriter
        ) async throws {
            try await writer.transaction { context in
                let object = try SessionManagedObjectMapping.requireSession(id: sessionID.rawValue, in: context)
                object.setValue(appointmentID, forKey: "appointmentID")
            }
        }

        private func sessionAppointmentID(sessionID: StableUUID, writer: PersistenceWriter) async throws -> UUID? {
            try await writer.read { context in
                let object = try SessionManagedObjectMapping.requireSession(id: sessionID.rawValue, in: context)
                return object.value(forKey: "appointmentID") as? UUID
            }
        }

        // MARK: - Assertions (field-for-field, stable identity, no duplication)

        private func assertRestoredM1BInventory(on harness: Harness) async throws {
            // Session + additive fields.
            let history = try await HistoryUseCases(
                sessionRepository: CoreDataSessionRepository(writer: harness.controller.writer),
                clock: harness.clock,
                ids: TestIDGenerator(ids: [])
            ).listHistory(studentID: studentID)
            XCTAssertEqual(history.map(\.id), [completedSessionID])
            let completed = try XCTUnwrap(history.first)
            let squat = try XCTUnwrap(completed.exercises.first { $0.id == squatExerciseID })
            XCTAssertEqual(squat.sets.first?.weightValue?.canonicalString, try DecimalValue("40").canonicalString)
            let cardio = try XCTUnwrap(completed.exercises.first { $0.id == cardioExerciseID })
            let cardioSet = try XCTUnwrap(cardio.sets.first)
            XCTAssertEqual(cardioSet.distanceValue?.canonicalString, try DecimalValue("3000").canonicalString)
            XCTAssertEqual(cardioSet.speedValue?.canonicalString, try DecimalValue("5").canonicalString)
            XCTAssertEqual(cardioSet.resistanceValue?.canonicalString, try DecimalValue("3").canonicalString)

            let sessionSections = try await harness.sectionRepository.sections(
                ownerKind: .session,
                ownerID: completedSessionID
            )
            XCTAssertEqual(sessionSections.map(\.id), [sessionSectionID])
            let restoredSessionAppointmentID = try await sessionAppointmentID(
                sessionID: completedSessionID,
                writer: harness.controller.writer
            )
            XCTAssertEqual(restoredSessionAppointmentID, standaloneAppointmentID.rawValue)

            // Appointments + RecurrenceSeries.
            let appointments = try await harness.appointmentRepository.appointments(studentID: studentID)
            XCTAssertEqual(Set(appointments.map(\.id)), [standaloneAppointmentID, seriesAppointmentID])
            let standalone = try XCTUnwrap(appointments.first { $0.id == standaloneAppointmentID })
            XCTAssertEqual(standalone.linkedSessionID, completedSessionID)
            XCTAssertEqual(standalone.status, .completed)
            let seriesAppointment = try XCTUnwrap(appointments.first { $0.id == seriesAppointmentID })
            XCTAssertEqual(seriesAppointment.seriesID, seriesID)
            let restoredSeries = try await harness.appointmentRepository.series(id: seriesID)
            XCTAssertEqual(restoredSeries.intervalDays, .everyWeek)
            XCTAssertEqual(restoredSeries.termination, .repeatCount(1))

            // CoursePackage + CreditAdjustment (idempotency key preserved, balance derivable).
            let packages = try await harness.coursePackageRepository.packages(studentID: studentID)
            XCTAssertEqual(packages.map(\.id), [packageID])
            XCTAssertEqual(packages.first?.status, .active)
            let activePackage = try await harness.coursePackageRepository.activePackage(studentID: studentID)
            XCTAssertEqual(activePackage?.id, packageID)
            let adjustments = try await harness.coursePackageRepository.adjustments(packageID: packageID)
            XCTAssertEqual(adjustments.map(\.id), [adjustmentID])
            XCTAssertEqual(adjustments.first?.sourceEventKey, "manual-correction-test-1")
            let restoredBalance = try await harness.coursePackageRepository.balance(packageID: packageID)
            XCTAssertEqual(restoredBalance, 9)

            // TrainingTemplate + TemplateExercise + Template-owned Section.
            let template = try await harness.templateRepository.template(id: templateID)
            XCTAssertEqual(template.name.value, "上肢模板")
            XCTAssertEqual(template.trainingFocus, [.arms])
            let templateExercises = try await harness.templateRepository.exercises(templateID: templateID)
            XCTAssertEqual(templateExercises.map(\.id), [templateExerciseAID, templateExerciseBID])
            XCTAssertEqual(templateExercises.first?.sectionID, templateSectionID)
            XCTAssertEqual(
                templateExercises.first?.plannedSets.first?.weightValue?.canonicalString,
                try DecimalValue("20").canonicalString
            )
            let templateSections = try await harness.sectionRepository.sections(ownerKind: .template, ownerID: templateID)
            XCTAssertEqual(templateSections.map(\.id), [templateSectionID])

            // Custom BodyMetricDefinition + BodyMeasurement.
            let metrics = try await harness.bodyDataRepository.customMetrics(studentID: studentID)
            XCTAssertEqual(metrics.map(\.id), [bodyMetricID])
            XCTAssertEqual(metrics.first?.name.value, "臂围")
            let measurements = try await harness.bodyDataRepository.history(studentID: studentID, metricID: bodyMetricID)
            XCTAssertEqual(measurements.map(\.id), [bodyMeasurementID])
            XCTAssertEqual(measurements.first?.value.canonicalString, try DecimalValue("32.5").canonicalString)
        }
    }
#else
    import FineCoach
    import XCTest

    final class M1BBackupRoundTripTests: XCTestCase {
        func testReleaseKeepsBackupCoordinatorSurfaceWithoutFaultInjection() {
            XCTAssertEqual(BackupError.authenticationFailed, .authenticationFailed)
        }
    }
#endif
