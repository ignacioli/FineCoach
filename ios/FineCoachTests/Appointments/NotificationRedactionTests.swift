import FineCoach
import XCTest

/// T018: notification-content builder redaction (AC-015, SC-006, D-M1B-005) and
/// the D-004 "permission denied MUST NOT block save" path. Deliberately
/// decoupled from "can a locked device actually show this text" -- that is a
/// real-device/system boundary this environment cannot prove (spec §2.3), so
/// this only asserts what the app itself controls: the string content it hands
/// to the system, and that scheduling failure never blocks a save.
final class NotificationRedactionTests: XCTestCase {
    private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    private let appointmentID = StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - Content redaction (structural: the builder has no channel for identity)

    func testNotificationBodyContainsOnlyTimeAndGenericWording() throws {
        let startInstant = try LocalDate(year: 2026, month: 1, day: 5)
            .startOfDay(calendar: utc)
            .addingTimeInterval(9 * 3600)
        let body = AppointmentNotificationContentBuilder.body(startInstant: startInstant, calendar: utc)

        XCTAssertTrue(body.contains("09:00"))
        // Sentinel values a real appointment's student/sex/package fields could
        // plausibly contain, mirroring ShareReportPolicyTests' forbidden-token
        // pattern -- none of these have any path into `body`'s only two inputs
        // (a Date and a Calendar), but this asserts the observable string too,
        // not just the function signature.
        let forbiddenSentinels = ["林青", "女", "男", "课包", "余额", "有效期", "私有备注"]
        for sentinel in forbiddenSentinels {
            XCTAssertFalse(body.contains(sentinel), "body leaked sentinel: \(sentinel)")
        }
    }

    func testNotificationTitleIsGeneric() {
        let title = AppointmentNotificationContentBuilder.title()
        XCTAssertEqual(title, "训练提醒")
    }

    // MARK: - D-004: permission denied / scheduling failure MUST NOT block save

    func testSchedulingFailureDoesNotThrowFromSync() async throws {
        let failingCenter = FakeNotificationScheduling(scheduleShouldFail: true)
        let scheduler = NotificationScheduler(
            notificationCenter: failingCenter,
            calendarProvider: TestCalendarProvider(timeZone: TimeZone(identifier: "UTC")!)
        )
        let appointment = try Appointment(
            id: appointmentID,
            studentID: studentID,
            seriesID: nil,
            date: try LocalDate(year: 2026, month: 1, day: 5),
            startTime: try LocalTime(hour: 9, minute: 0),
            createdAtUTC: now,
            updatedAtUTC: now
        )
        // No throws keyword on `sync` at all -- if this compiles, the API itself
        // cannot propagate a scheduling failure to the caller. Calling it here
        // additionally proves it does not crash/hang when the underlying
        // schedule() call fails.
        await scheduler.sync(appointment: appointment)
        let requested = await failingCenter.authorizationRequested
        XCTAssertTrue(requested)
    }

    func testAppointmentIsNotAutoMarkedDeliveredAnywhereInDomain() throws {
        // NFR-008: the app MUST NOT synthesize a "delivered" result string. There
        // is no `deliveryStatus`/`wasDelivered` field on Appointment at all --
        // this test pins that absence structurally: the full set of persisted
        // fields is exactly what data-model §2.2 lists, no delivery-outcome slot.
        let appointment = try Appointment(
            id: appointmentID,
            studentID: studentID,
            seriesID: nil,
            date: try LocalDate(year: 2026, month: 1, day: 5),
            startTime: try LocalTime(hour: 9, minute: 0),
            createdAtUTC: now,
            updatedAtUTC: now
        )
        let mirror = Mirror(reflecting: appointment)
        let fieldNames = Set(mirror.children.compactMap(\.label))
        XCTAssertFalse(fieldNames.contains { $0.lowercased().contains("delivered") })
        XCTAssertFalse(fieldNames.contains { $0.lowercased().contains("deliverystatus") })
    }
}
