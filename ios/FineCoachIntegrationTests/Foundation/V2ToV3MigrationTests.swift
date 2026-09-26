#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// T075: proves a V2 store fixture (the pre-Revision-1.2 M1-B schema, with
    /// free-text Session/Template training focus and weekday-based recurrence)
    /// opens cleanly under the bundled CURRENT (V3) model via Core Data
    /// lightweight/inferred migration -- and that the two intentionally-
    /// discarded columns (SessionMO/TrainingTemplateMO.trainingFocus,
    /// RecurrenceSeriesMO.weekdaysMask) are genuinely gone (not silently kept
    /// under the old name) while their replacement columns default to empty,
    /// never fabricated from the old value (data-model §3/§7, D-013/D-014,
    /// product-owner decision 2026-09-24/25). All other V2 data -- unrelated
    /// Student/Session/Appointment fields, the Appointment<->RecurrenceSeries
    /// relationship -- survives byte-for-byte.
    final class V2ToV3MigrationTests: XCTestCase {
        private let studentID = UUID(uuidString: "21111111-1111-4111-8111-111111111111")!
        private let sessionID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        private let templateID = UUID(uuidString: "23333333-3333-4333-8333-333333333333")!
        private let seriesID = UUID(uuidString: "24444444-4444-4444-8444-444444444444")!
        private let appointmentID = UUID(uuidString: "25555555-5555-4555-8555-555555555555")!
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        private struct MigratedSnapshot: Equatable, Sendable {
            let studentDisplayName: String?
            let sessionState: String?
            let sessionTrainingFocusMask: Int32?
            let templateName: String?
            let templateTrainingFocusMask: Int32?
            let appointmentStudentID: UUID?
            let appointmentTrainingFocusMask: Int32?
            let appointmentSeriesID: UUID?
            let seriesIntervalDays: Int32?
            let seriesStudentID: UUID?
        }

        func testV2StoreFixtureOpensUnderV3WithOldFocusAndWeekdaysColumnsGoneAndDataIntact() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")

            try makeV2Fixture(at: storeURL)

            let controller = try PersistenceController(storeURL: storeURL)
            let studentID = studentID
            let sessionID = sessionID
            let templateID = templateID
            let seriesID = seriesID
            let appointmentID = appointmentID

            let snapshot = try await controller.writer.read { context -> MigratedSnapshot in
                func fetchOne(_ entityName: String, id: UUID) throws -> NSManagedObject? {
                    let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
                    request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                    request.fetchLimit = 1
                    return try context.fetch(request).first
                }

                let student = try fetchOne("StudentMO", id: studentID)
                let session = try fetchOne("SessionMO", id: sessionID)
                let template = try fetchOne("TrainingTemplateMO", id: templateID)
                let series = try fetchOne("RecurrenceSeriesMO", id: seriesID)
                let appointment = try fetchOne("AppointmentMO", id: appointmentID)

                return MigratedSnapshot(
                    studentDisplayName: student?.value(forKey: "displayName") as? String,
                    sessionState: session?.value(forKey: "state") as? String,
                    // Reading the NEW key only -- the old "trainingFocus" String
                    // column no longer exists post-migration; reading it would
                    // throw an unrecognized-key exception, which is exactly the
                    // point (there is nothing to silently fall back to).
                    sessionTrainingFocusMask: session?.value(forKey: "trainingFocusMask") as? Int32,
                    templateName: template?.value(forKey: "name") as? String,
                    templateTrainingFocusMask: template?.value(forKey: "trainingFocusMask") as? Int32,
                    appointmentStudentID: appointment?.value(forKey: "studentID") as? UUID,
                    appointmentTrainingFocusMask: appointment?.value(forKey: "trainingFocusMask") as? Int32,
                    appointmentSeriesID: appointment?.value(forKey: "seriesID") as? UUID,
                    seriesIntervalDays: series?.value(forKey: "intervalDays") as? Int32,
                    seriesStudentID: series?.value(forKey: "studentID") as? UUID
                )
            }

            XCTAssertEqual(snapshot.studentDisplayName, "赵敏")
            XCTAssertEqual(snapshot.sessionState, "completed")
            // The V2 fixture's free-text trainingFocus ("核心力量") is discarded,
            // not converted -- the new mask column defaults to empty (0).
            XCTAssertEqual(snapshot.sessionTrainingFocusMask, 0)
            XCTAssertEqual(snapshot.templateName, "核心模板")
            XCTAssertEqual(snapshot.templateTrainingFocusMask, 0)
            XCTAssertEqual(snapshot.appointmentStudentID, studentID)
            // Appointment.trainingFocusMask is a pure T073 addition (V2 had no
            // Appointment training-focus field at all) -- also defaults empty.
            XCTAssertEqual(snapshot.appointmentTrainingFocusMask, 0)
            // Appointment<->RecurrenceSeries relationship survives migration.
            XCTAssertEqual(snapshot.appointmentSeriesID, seriesID)
            XCTAssertEqual(snapshot.seriesStudentID, studentID)
            // The V2 fixture's weekdaysMask (Monday+Wednesday = 0b101 = 5) is
            // gone; intervalDays defaults to 7 (everyWeek), never derived from
            // the discarded weekday bitmask (no weekdays->intervalDays
            // conversion code exists, D-014).
            XCTAssertEqual(snapshot.seriesIntervalDays, 7)

            try await controller.shutdownForTesting()
        }

        // MARK: - V2 fixture construction

        private func makeV2Fixture(at storeURL: URL) throws {
            let v2Model = try PersistenceController.loadModelVersionForMigrationTesting(named: "FineCoachV2")
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v2Model)
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: nil
            )
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator

            try context.performAndWait {
                let student = NSEntityDescription.insertNewObject(forEntityName: "StudentMO", into: context)
                student.setValue(studentID, forKey: "id")
                student.setValue("赵敏", forKey: "displayName")
                student.setValue("female", forKey: "sex")
                student.setValue("active", forKey: "lifecycle")
                student.setValue(now, forKey: "createdAtUTC")
                student.setValue(now, forKey: "updatedAtUTC")

                let session = NSEntityDescription.insertNewObject(forEntityName: "SessionMO", into: context)
                session.setValue(sessionID, forKey: "id")
                session.setValue(studentID, forKey: "studentID")
                session.setValue("completed", forKey: "state")
                session.setValue(now, forKey: "startedAtUTC")
                session.setValue(now, forKey: "lastCheckpointUTC")
                session.setValue(NSDecimalNumber(string: "1800"), forKey: "elapsedSeconds")
                session.setValue(false, forKey: "durationNeedsReview")
                session.setValue("核心力量", forKey: "trainingFocus")
                session.setValue(Int64(1), forKey: "revision")
                session.setValue(now, forKey: "createdAtUTC")
                session.setValue(now, forKey: "updatedAtUTC")
                session.setValue(now, forKey: "completedAtUTC")
                session.setValue(student, forKey: "student")

                let template = NSEntityDescription.insertNewObject(forEntityName: "TrainingTemplateMO", into: context)
                template.setValue(templateID, forKey: "id")
                template.setValue("核心模板", forKey: "name")
                template.setValue("核心力量", forKey: "trainingFocus")
                template.setValue(now, forKey: "createdAtUTC")
                template.setValue(now, forKey: "updatedAtUTC")

                let series = NSEntityDescription.insertNewObject(forEntityName: "RecurrenceSeriesMO", into: context)
                series.setValue(seriesID, forKey: "id")
                series.setValue(studentID, forKey: "studentID")
                // Monday (bit 0) + Wednesday (bit 2) = 0b101 = 5, the OLD
                // weekdaysMask encoding -- must not survive as intervalDays.
                series.setValue(Int32(5), forKey: "weekdaysMask")
                series.setValue("repeatCount", forKey: "terminationKind")
                series.setValue(Int32(4), forKey: "repeatCount")
                series.setValue("09:00", forKey: "defaultStartTime")
                series.setValue(Int32(60), forKey: "defaultDurationMinutes")
                series.setValue(true, forKey: "defaultReminderEnabled")
                series.setValue(Int32(60), forKey: "defaultReminderLeadMinutes")
                series.setValue("active", forKey: "status")
                series.setValue(now, forKey: "createdAtUTC")
                series.setValue(now, forKey: "updatedAtUTC")

                let appointment = NSEntityDescription.insertNewObject(forEntityName: "AppointmentMO", into: context)
                appointment.setValue(appointmentID, forKey: "id")
                appointment.setValue(studentID, forKey: "studentID")
                appointment.setValue(seriesID, forKey: "seriesID")
                appointment.setValue("2026-01-05", forKey: "date")
                appointment.setValue("09:00", forKey: "startTime")
                appointment.setValue(Int32(60), forKey: "durationMinutes")
                appointment.setValue("scheduled", forKey: "status")
                appointment.setValue(false, forKey: "isDetachedException")
                appointment.setValue(true, forKey: "reminderEnabled")
                appointment.setValue(Int32(60), forKey: "reminderLeadMinutes")
                appointment.setValue(now, forKey: "createdAtUTC")
                appointment.setValue(now, forKey: "updatedAtUTC")
                appointment.setValue(series, forKey: "series")

                try context.save()
            }

            context.reset()
            for store in coordinator.persistentStores {
                try coordinator.remove(store)
            }
        }
    }
#endif
