import XCTest

@testable import FineCoach

final class WidgetSnapshotPublisherTests: XCTestCase {
    private final class Events: AppLogging, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [AppLogEvent] = []
        private var reloads = 0
        func info(_ event: AppLogEvent, operation: AppLogOperation) { lock.withLock { values.append(event) } }
        func failure(_ event: AppLogEvent, operation: AppLogOperation, category: AppLogErrorCategory) {
            lock.withLock { values.append(event) }
        }
        func reload() { lock.withLock { reloads += 1 } }
        var recorded: [AppLogEvent] { lock.withLock { values } }
        var reloadCount: Int { lock.withLock { reloads } }
    }

    private func snapshot(version: Int = 1) -> WidgetTodaySnapshot {
        WidgetTodaySnapshot(
            formatVersion: version, localDate: WidgetTodaySnapshot.dateKey(Date(), calendar: .current),
            generatedAtUTC: Date(), entries: [], finishedCount: 0)
    }

    func testAppointmentWritePublishesAllowlistedSnapshotAndAuditedFileBeforeReload() async throws {
        let directory = try TemporaryProtectedDirectory()
        let controller = try PersistenceController(
            storeURL: directory.url.appendingPathComponent("store/FineCoach.sqlite"))
        let students = CoreDataStudentRepository(writer: controller.writer)
        let appointments = CoreDataAppointmentRepository(writer: controller.writer)
        let now = Date()
        let student = try await students.create(
            StudentDraft(displayName: "虚构学员甲", sex: .undisclosed).makeStudent(id: StableUUID(UUID()), now: now))
        let appointment = try await appointments.create(
            Appointment(
                id: StableUUID(UUID()), studentID: student.id, seriesID: nil,
                date: LocalDate(date: now, calendar: .current), startTime: LocalTime(hour: 15, minute: 0),
                createdAtUTC: now, updatedAtUTC: now))
        let url = directory.url.appendingPathComponent("widget-today.json")
        let events = Events()
        let publisher = WidgetSnapshotPublisher(
            rebuild: {
                let values = try await appointments.appointments(localDates: [LocalDate(date: now, calendar: .current)])
                return WidgetTodaySnapshot.build(
                    appointments: values, studentDisplayName: { _ in student.displayName.value }, now: now,
                    calendar: .current)
            }, snapshotURL: { url }, logger: events,
            reload: {
                XCTAssertNotNil(WidgetSnapshotReader.read(at: url))
                XCTAssertEqual(try? ProtectedFileStore().audit(url: url).isExcludedFromBackup, true)
                events.reload()
            })
        await publisher.refresh()
        await publisher.flush()
        let result = try XCTUnwrap(WidgetSnapshotReader.read(at: url))
        XCTAssertEqual(result.entries.map(\.appointmentID), [appointment.id.rawValue.uuidString])
        XCTAssertEqual(result.entries.map(\.studentDisplayName), ["虚构学员甲"])
        let audit = try ProtectedFileStore().audit(url: url)
        XCTAssertTrue(audit.isExcludedFromBackup)
        #if !targetEnvironment(simulator)
            XCTAssertEqual(audit.protectionRawValue, FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
        #endif
        XCTAssertEqual(events.recorded, [.systemEntrySnapshotWritten])
        XCTAssertEqual(events.reloadCount, 1)
        try await controller.shutdownForTesting()
    }

    @MainActor
    func testSnapshotFailureDoesNotChangeSuccessfulAppointmentWrite() async throws {
        let directory = try TemporaryProtectedDirectory()
        let events = Events()
        let publisher = WidgetSnapshotPublisher(
            rebuild: { throw CocoaError(.fileReadUnknown) },
            snapshotURL: { nil }, logger: events, reload: { events.reload() })
        let environment = try AppEnvironment(
            rootURL: directory.url,
            notificationCenter: FakeNotificationScheduling(), widgetSnapshotPublisher: publisher,
            sessionActivityController: NoopSessionActivityController())
        let students = try XCTUnwrap(environment.studentUseCases)
        let appointments = try XCTUnwrap(environment.appointmentUseCases)
        let student = try await students.create(draft: StudentDraft(displayName: "虚构学员甲", sex: .undisclosed))
        let created = try await appointments.createSingle(
            studentID: student.id,
            date: LocalDate(date: Date(), calendar: .current), startTime: LocalTime(hour: 15, minute: 0),
            overrideConflict: true)
        await publisher.flush()
        let saved = try await appointments.appointment(id: created.id)
        XCTAssertEqual(saved, created)
        XCTAssertEqual(events.recorded, [.systemEntrySnapshotFailed])
        XCTAssertEqual(events.reloadCount, 0)
    }

    func testMissingCorruptUnsupportedAndUnreadableSnapshotReturnNoData() throws {
        let directory = try TemporaryProtectedDirectory()
        let url = directory.url.appendingPathComponent("widget-today.json")
        XCTAssertNil(WidgetSnapshotReader.read(at: nil))
        XCTAssertNil(WidgetSnapshotReader.read(at: url))
        try Data("corrupt".utf8).write(to: url)
        XCTAssertNil(WidgetSnapshotReader.read(at: url))
        try JSONEncoder().encode(snapshot(version: 99)).write(to: url)
        XCTAssertNil(WidgetSnapshotReader.read(at: url))
        XCTAssertNil(WidgetSnapshotReader.read(at: directory.url))
    }

    func testMissingContainerOnlyLogsFailureAndNeverReloads() async {
        let value = snapshot()
        let events = Events()
        let publisher = WidgetSnapshotPublisher(
            rebuild: { value }, snapshotURL: { nil }, logger: events, reload: { events.reload() })
        await publisher.refresh()
        await publisher.flush()
        XCTAssertEqual(events.recorded, [.systemEntrySnapshotFailed])
        XCTAssertEqual(events.reloadCount, 0)
    }

    func testRebuildAndFileWriteFailuresOnlyLogFailureAndNeverReload() async throws {
        let directory = try TemporaryProtectedDirectory()
        let value = snapshot()
        let badURL = directory.url.appendingPathComponent("missing/widget-today.json")
        for failRebuild in [false, true] {
            let events = Events()
            let publisher = WidgetSnapshotPublisher(
                rebuild: {
                    if failRebuild { throw CocoaError(.fileReadUnknown) }
                    return value
                }, snapshotURL: { badURL }, logger: events, reload: { events.reload() })
            await publisher.refresh()
            await publisher.flush()
            XCTAssertEqual(events.recorded, [.systemEntrySnapshotFailed])
            XCTAssertEqual(events.reloadCount, 0)
        }
    }

    func testFailedRebuildRemovesThePreviousSnapshotAndReloadsOnce() async throws {
        let directory = try TemporaryProtectedDirectory()
        let url = directory.url.appendingPathComponent("widget-today.json")
        try JSONEncoder().encode(snapshot()).write(to: url)
        let events = Events()
        let publisher = WidgetSnapshotPublisher(
            rebuild: { throw CocoaError(.fileReadUnknown) }, snapshotURL: { url }, logger: events,
            reload: { events.reload() })
        await publisher.refresh()
        await publisher.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(WidgetSnapshotReader.read(at: url))
        XCTAssertEqual(events.recorded, [.systemEntrySnapshotFailed])
        XCTAssertEqual(events.reloadCount, 1)
    }

    func testQueuedRefreshesWriteSeriallyAndLeaveLatestSnapshot() async throws {
        actor Source {
            var count = 0
            func next() -> WidgetTodaySnapshot {
                count += 1
                return WidgetTodaySnapshot(
                    localDate: "2026-10-28", generatedAtUTC: Date(), entries: [], finishedCount: count)
            }
        }
        let source = Source()
        let directory = try TemporaryProtectedDirectory()
        let url = directory.url.appendingPathComponent("widget-today.json")
        let events = Events()
        let publisher = WidgetSnapshotPublisher(
            rebuild: { await source.next() }, snapshotURL: { url }, logger: events, reload: { events.reload() })
        await publisher.refresh()
        await publisher.refresh()
        await publisher.flush()
        XCTAssertEqual(WidgetSnapshotReader.read(at: url)?.finishedCount, 2)
        XCTAssertEqual(events.reloadCount, 2)
        XCTAssertEqual(events.recorded, [.systemEntrySnapshotWritten, .systemEntrySnapshotWritten])
    }
}
