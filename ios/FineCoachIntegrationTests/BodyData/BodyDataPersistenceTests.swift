#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// Covers the batch "latest value per metric" query backing the Body
    /// Data list screen's new "latest recorded value" row, and the
    /// "clear all records for a metric" entry point that unblocks deleting
    /// a custom metric definition that used to have history.
    final class BodyDataPersistenceTests: XCTestCase {
        private let now = Date(timeIntervalSince1970: 1_700_000_000)

        private struct Environment {
            let directory: TemporaryProtectedDirectory
            let controller: PersistenceController
            let studentID: StableUUID
            let useCases: BodyDataUseCases
        }

        private func makeEnvironment(ids: [UUID]) async throws -> Environment {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let controller = try PersistenceController(storeURL: storeURL)
            let clock = TestClock(utcDate: now)
            let calendarProvider = TestCalendarProvider(timeZone: TimeZone(identifier: "UTC")!)
            let idGenerator = TestIDGenerator(ids: ids)
            let studentRepository = CoreDataStudentRepository(writer: controller.writer)
            let studentIDGen = TestIDGenerator(ids: [UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!])
            let studentUseCases = StudentUseCases(repository: studentRepository, clock: clock, ids: studentIDGen)
            let student = try await studentUseCases.create(
                draft: StudentDraft(displayName: "林青", sex: .female)
            )

            let useCases = BodyDataUseCases(
                repository: CoreDataBodyDataRepository(writer: controller.writer),
                clock: clock,
                calendarProvider: calendarProvider,
                ids: idGenerator
            )

            return Environment(
                directory: directory,
                controller: controller,
                studentID: student.id,
                useCases: useCases
            )
        }

        private func utcInstant(year: Int, month: Int, day: Int) throws -> Date {
            try XCTUnwrap(
                DateComponents(
                    calendar: Calendar(identifier: .gregorian),
                    timeZone: TimeZone(identifier: "UTC"),
                    year: year, month: month, day: day, hour: 12
                ).date
            )
        }

        // MARK: - List screen (T069k, 06 artwork)

        func testListGroupsBuiltInsPerArtworkAndShowsDashWithUnitWhenUnrecorded() async throws {
            let env = try await makeEnvironment(
                ids: (0..<3).map { UUID(uuidString: "33333333-3333-4333-8333-33333333333\($0)")! })
            let defaults = try XCTUnwrap(UserDefaults(suiteName: "T069k-\(UUID().uuidString)"))
            let preferences = await BodyDataUnitPreferences(defaults: defaults)
            _ = try await env.useCases.recordMeasurement(
                studentID: env.studentID, metricID: BuiltInBodyMetric.weight.id, value: "68.5", enteredUnit: "kg",
                at: try utcInstant(year: 2026, month: 1, day: 1)
            )
            let viewModel = await BodyDataListViewModel(
                studentID: env.studentID, useCases: env.useCases, unitPreferences: preferences
            )
            await viewModel.reload()

            let basic = await viewModel.basicMetrics
            let girth = await viewModel.girthMetrics
            XCTAssertEqual(
                basic.map(\.id),
                [
                    BuiltInBodyMetric.weight.id, BuiltInBodyMetric.bodyFatPercent.id, BuiltInBodyMetric.height.id,
                ])
            XCTAssertEqual(
                girth.map(\.id),
                [
                    BuiltInBodyMetric.chest.id, BuiltInBodyMetric.waist.id, BuiltInBodyMetric.hip.id,
                    BuiltInBodyMetric.upperArm.id, BuiltInBodyMetric.thigh.id,
                ])

            let weight = await viewModel.latestDisplay(for: basic[0])
            XCTAssertEqual(weight.value, "68.5")
            XCTAssertEqual(weight.unit, "kg")
            let bodyFat = await viewModel.latestDisplay(for: basic[1])
            XCTAssertEqual(bodyFat.value, "—")
            XCTAssertEqual(bodyFat.unit, "%")
            let summary = await viewModel.unitSummary
            XCTAssertEqual(summary, "单位 · kg / cm")
        }

        // MARK: - Batch "latest per metric" query

        func testLatestMeasurementsReturnsNewestDayPerMetricInOneBatchCall() async throws {
            let env = try await makeEnvironment(
                ids: (0..<5).map { UUID(uuidString: "11111111-1111-4111-8111-11111111111\($0)")! })
            let weightID = BuiltInBodyMetric.weight.id
            let heightID = BuiltInBodyMetric.height.id

            _ = try await env.useCases.recordMeasurement(
                studentID: env.studentID, metricID: weightID, value: "70", enteredUnit: "kg",
                at: try utcInstant(year: 2026, month: 1, day: 1)
            )
            _ = try await env.useCases.recordMeasurement(
                studentID: env.studentID, metricID: weightID, value: "71.5", enteredUnit: "kg",
                at: try utcInstant(year: 2026, month: 1, day: 10)
            )
            _ = try await env.useCases.recordMeasurement(
                studentID: env.studentID, metricID: weightID, value: "70.8", enteredUnit: "kg",
                at: try utcInstant(year: 2026, month: 1, day: 5)
            )
            _ = try await env.useCases.recordMeasurement(
                studentID: env.studentID, metricID: heightID, value: "180", enteredUnit: "cm",
                at: try utcInstant(year: 2026, month: 1, day: 3)
            )

            let latest = try await env.useCases.latestMeasurements(studentID: env.studentID)

            XCTAssertEqual(latest.count, 2, "one entry per metric that has ANY recorded measurement")
            XCTAssertEqual(
                latest[weightID]?.value.canonicalString, "71.5",
                "must return the chronologically newest day (2026-01-10), not first- or last-inserted"
            )
            XCTAssertEqual(latest[heightID]?.value.canonicalString, "180")

            // A metric with zero recorded measurements is simply absent.
            XCTAssertNil(latest[BuiltInBodyMetric.waist.id])

            try await env.controller.shutdownForTesting()
        }

        // MARK: - "Clear all records" entry point (Fix 3-1)

        func testDeleteAllMeasurementsClearsEveryRecordAndUnblocksMetricDeletion() async throws {
            let customMetricID = UUID(uuidString: "22222222-2222-4222-8222-222222222220")!
            let measurementIDs = (1...3).map { UUID(uuidString: "22222222-2222-4222-8222-22222222222\($0)")! }
            let env = try await makeEnvironment(ids: [customMetricID] + measurementIDs)

            let metric = try await env.useCases.createCustomMetric(
                studentID: env.studentID, name: "握力", unit: "kg"
            )

            _ = try await env.useCases.recordMeasurement(
                studentID: env.studentID, metricID: metric.id, value: "30", enteredUnit: "kg",
                at: try utcInstant(year: 2026, month: 1, day: 1)
            )
            _ = try await env.useCases.recordMeasurement(
                studentID: env.studentID, metricID: metric.id, value: "31", enteredUnit: "kg",
                at: try utcInstant(year: 2026, month: 1, day: 2)
            )

            let beforeClear = try await env.useCases.history(studentID: env.studentID, metricID: metric.id)
            XCTAssertEqual(beforeClear.count, 2)

            // Deleting the metric definition must be refused while it still
            // has measurements (M1B-FR-023/D-009, unchanged behavior).
            do {
                try await env.useCases.deleteCustomMetricIfUnused(id: metric.id)
                XCTFail("must refuse to delete a metric definition that still has measurements")
            } catch DomainError.conflict {
                // expected
            }

            try await env.useCases.deleteAllMeasurements(studentID: env.studentID, metricID: metric.id)

            let afterClear = try await env.useCases.history(studentID: env.studentID, metricID: metric.id)
            XCTAssertTrue(afterClear.isEmpty, "clearing must remove every recorded measurement for this metric")

            // Now that history is empty, the existing zero-measurement
            // deletion path succeeds without any further code changes.
            try await env.useCases.deleteCustomMetricIfUnused(id: metric.id)

            try await env.controller.shutdownForTesting()
        }

        func testDeleteAllMeasurementsNeverTouchesOtherMetricsOrStudents() async throws {
            let customMetricID = UUID(uuidString: "33333333-3333-4333-8333-333333333330")!
            let measurementIDs = (1...2).map { UUID(uuidString: "33333333-3333-4333-8333-33333333333\($0)")! }
            let env = try await makeEnvironment(ids: [customMetricID] + measurementIDs)

            let targetMetric = try await env.useCases.createCustomMetric(
                studentID: env.studentID, name: "握力", unit: "kg"
            )
            _ = try await env.useCases.recordMeasurement(
                studentID: env.studentID, metricID: targetMetric.id, value: "30", enteredUnit: "kg",
                at: try utcInstant(year: 2026, month: 1, day: 1)
            )
            // A different, untouched metric on the SAME Student.
            _ = try await env.useCases.recordMeasurement(
                studentID: env.studentID, metricID: BuiltInBodyMetric.weight.id, value: "70", enteredUnit: "kg",
                at: try utcInstant(year: 2026, month: 1, day: 1)
            )

            try await env.useCases.deleteAllMeasurements(studentID: env.studentID, metricID: targetMetric.id)

            let targetHistory = try await env.useCases.history(studentID: env.studentID, metricID: targetMetric.id)
            XCTAssertTrue(targetHistory.isEmpty)
            let otherHistory = try await env.useCases.history(
                studentID: env.studentID, metricID: BuiltInBodyMetric.weight.id)
            XCTAssertEqual(otherHistory.count, 1, "clearing one metric's records must never touch another metric's")

            try await env.controller.shutdownForTesting()
        }

        // MARK: - B2 Δ3 single-row undo

        func testMeasurementUndoRestoresOriginalPositionAndIdentity() async throws {
            let customMetricID = UUID(uuidString: "44444444-4444-4444-8444-444444444440")!
            let measurementIDs = (1...2).map {
                UUID(uuidString: "44444444-4444-4444-8444-44444444444\($0)")!
            }
            let env = try await makeEnvironment(ids: [customMetricID] + measurementIDs)
            let metric = try await env.useCases.createCustomMetric(
                studentID: env.studentID, name: "握力", unit: "kg"
            )
            let older = try utcInstant(year: 2026, month: 1, day: 1)
            let newer = try utcInstant(year: 2026, month: 1, day: 2)
            let first = try await env.useCases.recordMeasurement(
                studentID: env.studentID, metricID: metric.id, value: "30", enteredUnit: "kg", at: older
            )
            let second = try await env.useCases.recordMeasurement(
                studentID: env.studentID, metricID: metric.id, value: "31", enteredUnit: "kg", at: newer
            )

            let viewModel = await BodyMeasurementEntryViewModel(
                studentID: env.studentID, metricID: metric.id, useCases: env.useCases
            )
            await viewModel.reload()
            let initialIDs = await viewModel.history.map(\.id)
            XCTAssertEqual(initialIDs, [second.id, first.id])

            await viewModel.deleteMeasurement(second)
            let pending = await viewModel.pendingDeletion
            XCTAssertEqual(pending?.measurement.id, second.id)
            XCTAssertEqual(pending?.originalIndex, 0)
            let pendingIDs = await viewModel.history.map(\.id)
            XCTAssertEqual(pendingIDs, [first.id])

            await viewModel.undoPendingDeletion()
            let restoredPending = await viewModel.pendingDeletion
            XCTAssertNil(restoredPending)
            let restoredIDs = await viewModel.history.map(\.id)
            XCTAssertEqual(restoredIDs, [second.id, first.id])

            let persisted = try await env.useCases.history(studentID: env.studentID, metricID: metric.id)
            XCTAssertEqual(Set(persisted.map(\.id)), Set([first.id, second.id]))
            try await env.controller.shutdownForTesting()
        }

        func testMeasurementDeletionFinalizesOnInterruptionAndUsesSingleUndoWindow() async throws {
            let customMetricID = UUID(uuidString: "55555555-5555-4555-8555-555555555550")!
            let measurementID = UUID(uuidString: "55555555-5555-4555-8555-555555555551")!
            let env = try await makeEnvironment(ids: [customMetricID, measurementID])
            let metric = try await env.useCases.createCustomMetric(
                studentID: env.studentID, name: "体重", unit: "kg"
            )
            let measurement = try await env.useCases.recordMeasurement(
                studentID: env.studentID,
                metricID: metric.id,
                value: "68.5",
                enteredUnit: "kg",
                at: try utcInstant(year: 2026, month: 1, day: 2)
            )
            let viewModel = await BodyMeasurementEntryViewModel(
                studentID: env.studentID, metricID: metric.id, useCases: env.useCases
            )
            await viewModel.reload()

            await viewModel.deleteMeasurement(measurement)
            let pendingCount = await viewModel.history.count
            XCTAssertEqual(pendingCount, 0)
            let persistedDuringWindow = try await env.useCases.history(
                studentID: env.studentID, metricID: metric.id
            )
            XCTAssertEqual(
                persistedDuringWindow.count, 1,
                "the persisted row remains recoverable during the undo window"
            )

            await viewModel.finalizePendingDeletion()
            let finalizedPending = await viewModel.pendingDeletion
            XCTAssertNil(finalizedPending)
            let finalizedHistory = await viewModel.history
            XCTAssertTrue(finalizedHistory.isEmpty)
            let persistedAfterFinalize = try await env.useCases.history(
                studentID: env.studentID, metricID: metric.id
            )
            XCTAssertTrue(persistedAfterFinalize.isEmpty)
            let bodyUndoWindow = await BodyMeasurementEntryViewModel.undoWindow
            XCTAssertEqual(bodyUndoWindow, FCUndoRow.undoWindow)
            try await env.controller.shutdownForTesting()
        }
    }
#endif
