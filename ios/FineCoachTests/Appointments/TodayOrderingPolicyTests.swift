import FineCoach
import XCTest

final class TodayOrderingPolicyTests: XCTestCase {
    private let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private let today = try! LocalDate(year: 2026, month: 1, day: 5)

    private func makeAppointment(
        idSuffix: String,
        hour: Int,
        minute: Int,
        status: AppointmentStatus = .scheduled,
        date: LocalDate? = nil
    ) -> Appointment {
        try! Appointment(
            id: StableUUID(UUID(uuidString: "22222222-2222-4222-8222-\(idSuffix)")!),
            studentID: studentID,
            seriesID: nil,
            date: date ?? today,
            startTime: try! LocalTime(hour: hour, minute: minute),
            durationMinutes: 60,
            status: status,
            createdAtUTC: now,
            updatedAtUTC: now
        )
    }

    func testOrderingProducesExpectedSectionsAndSequence() throws {
        // now = 09:30 on 2026-01-05 UTC.
        let currentInstant = try LocalDate(year: 2026, month: 1, day: 5)
            .startOfDay(calendar: utc)
            .addingTimeInterval(9.5 * 3600)

        let inProgress = makeAppointment(idSuffix: "222222220001", hour: 8, minute: 0, status: .inProgress)
        let overdue = makeAppointment(idSuffix: "222222220002", hour: 7, minute: 0)
        let nextUp = makeAppointment(idSuffix: "222222220003", hour: 11, minute: 0)
        let laterToday = makeAppointment(idSuffix: "222222220004", hour: 15, minute: 0)
        let completed = makeAppointment(idSuffix: "222222220005", hour: 6, minute: 0, status: .completed)
        let tomorrow = makeAppointment(
            idSuffix: "222222220006",
            hour: 9,
            minute: 0,
            date: try LocalDate(year: 2026, month: 1, day: 6)
        )

        let ordered = TodayOrderingPolicy.order(
            appointments: [laterToday, tomorrow, nextUp, completed, overdue, inProgress],
            today: today,
            now: currentInstant,
            calendar: utc
        )

        XCTAssertEqual(ordered.map(\.appointment.id), [
            inProgress.id, overdue.id, nextUp.id, laterToday.id, completed.id,
        ])
        XCTAssertEqual(ordered.map(\.section), [
            .inProgress, .overdue, .nextUp, .remainingToday, .resolved,
        ])
        XCTAssertFalse(ordered.contains { $0.appointment.id == tomorrow.id })
    }

    func testOnlyEarliestPendingAppointmentIsNextUp() throws {
        let currentInstant = today.startOfDay(calendar: utc)
        let earliest = makeAppointment(idSuffix: "222222220011", hour: 9, minute: 0)
        let later = makeAppointment(idSuffix: "222222220012", hour: 10, minute: 0)

        let ordered = TodayOrderingPolicy.order(
            appointments: [later, earliest],
            today: today,
            now: currentInstant,
            calendar: utc
        )
        XCTAssertEqual(ordered.first?.appointment.id, earliest.id)
        XCTAssertEqual(ordered.first?.section, .nextUp)
        XCTAssertEqual(ordered.last?.appointment.id, later.id)
        XCTAssertEqual(ordered.last?.section, .remainingToday)
    }
}
