// fictional-data: fixed S2 parity scenarios; isolated temporary Core Data stores only.
import CryptoKit
import Foundation
import XCTest

@testable import FineCoach

@MainActor
final class S2SharedVectorTests: XCTestCase {
    func testCount() async throws { try await run("s2-recurrence-count") }
    func testEndDate() async throws { try await run("s2-recurrence-end-date") }
    func testLimit() async throws { try await run("s2-recurrence-limit") }
    func testThisOnly() async throws { try await run("s2-this-only") }
    func testThisAndFuture() async throws { try await run("s2-this-and-future") }
    func testOverdue() async throws { try await run("s2-overdue-persists") }
    func testAbandon() async throws { try await run("s1-empty-session-abandon-restores-appointment") }
    func testAbsent() async throws { try await run("s2-absent-credit-idempotent") }
    func testReminders() async throws { try await run("s2-reminder-tiers") }
    func testNotification() async throws { try await run("s2-notification-content") }

    private func digest(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
    private func run(_ id: String) async throws {
        let manifestURL = VectorFiles.root.appendingPathComponent("s2-manifest.json")
        let manifest = try VectorFiles.decoded(manifestURL)
        let entries = try XCTUnwrap(manifest["vectors"] as? [[String: Any]])
        XCTAssertEqual(manifest["count"] as? Int, 10)
        XCTAssertEqual(entries.count, 10)
        XCTAssertEqual(Set(entries.compactMap { $0["id"] as? String }).count, 10)
        let entry = try XCTUnwrap(entries.first { $0["id"] as? String == id })
        let file = VectorFiles.root.appendingPathComponent(try XCTUnwrap(entry["path"] as? String))
        XCTAssertTrue(file.standardizedFileURL.path.hasPrefix(VectorFiles.root.standardizedFileURL.path + "/"))
        XCTAssertEqual(try digest(file), entry["sha256"] as? String)
        let root = try VectorFiles.decoded(file)
        XCTAssertEqual(root["id"] as? String, id)
        let given = try XCTUnwrap(root["given"] as? [String: Any])
        let clock = try XCTUnwrap(given["clock"] as? [String: String])
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: try XCTUnwrap(clock["now"])))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: try XCTUnwrap(given["timeZone"] as? String)))
        let args = try XCTUnwrap(given["state"] as? [String: Any])
        let op = try XCTUnwrap(entry["iosAdapter"] as? String)
        XCTAssertEqual(entry["androidAdapter"] as? String, op)
        let actual = try await scenario(op, args, now, calendar)
        try SharedVectorRunner(conformance: false).run(
            Data(contentsOf: file), filename: file.lastPathComponent, extraOps: [op]
        ) { dispatched, resolved in
            guard dispatched == op, NSDictionary(dictionary: resolved).isEqual(to: args) else {
                throw VectorFailure(kind: "format", field: "/when/args", id: id)
            }
            return actual
        }
        try VectorFiles.report(file)
        print("S2-MANIFEST sha256=\(try digest(manifestURL)) count=10")
    }
    private func scenario(_ op: String, _ a: [String: Any], _ now: Date, _ calendar: Calendar) async throws -> Any {
        let ids = S2VectorIDs()
        func id() -> StableUUID { StableUUID(ids.makeID()) }
        func date(_ value: Any?) throws -> LocalDate {
            let d = try XCTUnwrap(value as? [String: Int])
            return try LocalDate(year: XCTUnwrap(d["year"]), month: XCTUnwrap(d["month"]), day: XCTUnwrap(d["day"]))
        }
        let day = try LocalDate(year: 2026, month: 3, day: 8)
        let appointment = try Appointment(
            id: id(), studentID: id(), seriesID: id(), date: day,
            startTime: LocalTime(hour: 1, minute: 0), createdAtUTC: now, updatedAtUTC: now)
        switch op {
        case "appointment.recurrence":
            let first = try date(a["first"])
            let termination: RecurrenceTermination
            if let count = a["count"] as? Int {
                termination = .repeatCount(count)
            } else {
                termination = .endDate(try date(a["end"]))
            }
            try RecurrenceSeries.validateMaterializationBound(
                termination: termination, firstOccurrenceDate: first, calendar: calendar)
            let dates = RecurrenceSeries.materializedDates(
                intervalDays: try XCTUnwrap(RecurrenceInterval(rawValue: try XCTUnwrap(a["interval"] as? Int))),
                firstOccurrenceDate: first, termination: termination, calendar: calendar)
            return ["dates": dates.map(\.canonicalString)]
        case "appointment.limit":
            let terms: [RecurrenceTermination] =
                try XCTUnwrap(a["counts"] as? [Int]).map { .repeatCount($0) }
                + XCTUnwrap(a["spans"] as? [Int]).map { .endDate(day.addingDays($0, calendar: calendar)) }
            return [
                "valid": terms.map { term in
                    do {
                        try RecurrenceSeries.validateMaterializationBound(
                            termination: term, firstOccurrenceDate: day, calendar: calendar)
                        return true
                    } catch { return false }
                }
            ]
        case "appointment.detached":
            let updated = try appointment.reschedulingDetached(
                startTime: LocalTime(hour: 11, minute: 30), reminderEnabled: false, now: now)
            return [
                "detached": updated.isDetachedException, "sameSeries": updated.seriesID == appointment.seriesID,
                "time": "\(updated.startTime.hour):\(String(format: "%02d", updated.startTime.minute))",
                "lead": updated.reminderLeadMinutes!.rawValue, "enabled": updated.reminderEnabled,
            ]
        case "appointment.overdue":
            return [
                "beforeEnd": appointment.isOverdue(now: now.addingTimeInterval(-0.001), calendar: calendar),
                "atEnd": appointment.isOverdue(now: now, calendar: calendar),
                "nextDay": appointment.isOverdue(now: now.addingTimeInterval(86400), calendar: calendar),
                "status": appointment.status.rawValue,
            ]
        case "appointment.reminders":
            let disabled = try Appointment(
                id: id(), studentID: appointment.studentID, seriesID: nil, date: day,
                startTime: appointment.startTime, reminderEnabled: false, reminderLeadMinutes: nil, createdAtUTC: now,
                updatedAtUTC: now)
            return [
                "minutes": ReminderLeadMinutes.allCases.map(\.rawValue),
                "default": appointment.reminderLeadMinutes!.rawValue,
                "disabledLead": disabled.reminderLeadMinutes as Any? ?? NSNull(),
            ]
        case "appointment.notification":
            return [
                "title": AppointmentNotificationContentBuilder.title(),
                "body": AppointmentNotificationContentBuilder.body(
                    startInstant: appointment.startInstant(calendar: calendar), calendar: calendar),
            ]
        default: break
        }
        let directory = try TemporaryProtectedDirectory()
        let persistence = try PersistenceController(storeURL: directory.url.appendingPathComponent("s2-vector.sqlite"))
        do {
            let students = CoreDataStudentRepository(writer: persistence.writer)
            let clock = TestClock(utcDate: now)
            let student = try await StudentUseCases(repository: students, clock: clock, ids: ids).create(
                draft: StudentDraft(displayName: "虚构排课", sex: .female))
            let active = ActiveSessionUseCases(
                sessionRepository: CoreDataSessionRepository(writer: persistence.writer), studentRepository: students,
                exerciseRepository: CoreDataExerciseRepository(writer: persistence.writer),
                sectionRepository: CoreDataSessionSectionRepository(writer: persistence.writer),
                recoveryStore: ActiveSessionRecoveryStore(url: directory.url.appendingPathComponent("recovery.json")),
                storeGenerationUUID: ids.makeID(), clock: clock, ids: ids)
            let repo = CoreDataAppointmentRepository(writer: persistence.writer)
            let provider = TestCalendarProvider(timeZone: calendar.timeZone)
            let cases = AppointmentUseCases(
                appointmentRepository: repo, studentRepository: students, activeSession: active,
                notifications: NotificationScheduler(
                    notificationCenter: FakeNotificationScheduling(), calendarProvider: provider), clock: clock,
                calendarProvider: provider, ids: ids)
            let actual: [String: Any]
            switch op {
            case "appointment.future":
                let rows = try await cases.createRecurring(
                    studentID: student.id,
                    draft: RecurringAppointmentDraft(
                        intervalDays: .everyOtherDay, termination: .repeatCount(5),
                        firstOccurrenceDate: day.addingDays(-1, calendar: calendar),
                        startTime: LocalTime(hour: 9, minute: 0)), overrideConflict: false)
                let detached = try await cases.rescheduleSingle(
                    appointmentID: rows[3].id, startTime: LocalTime(hour: 12, minute: 0), overrideConflict: false)
                let resolved = try await cases.cancel(appointmentID: rows[4].id, reason: nil)
                _ = try await cases.updateTrainingFocus(appointmentID: rows[2].id, trainingFocus: [.back])
                let changed = try await cases.applyThisAndFuture(
                    seriesID: XCTUnwrap(rows[0].seriesID), boundaryDate: rows[1].date,
                    startTime: LocalTime(hour: 11, minute: 30), boundaryTrainingFocus: [.thighs], overrideConflict: true
                )
                let old = try await cases.series(id: XCTUnwrap(rows[0].seriesID))
                let past = try await cases.appointment(id: rows[0].id)
                let savedDetached = try await cases.appointment(id: detached.id)
                let savedResolved = try await cases.appointment(id: resolved.id)
                let allRows = try await repo.appointments(studentID: student.id)
                let skippedDates: Set<LocalDate> = [detached.date, resolved.date]
                actual = [
                    "pastUnchanged": past == rows[0], "detachedUnchanged": savedDetached == detached,
                    "resolvedUnchanged": savedResolved == resolved, "oldEnded": old.status == .ended,
                    "totalAppointmentCount": allRows.count,
                    "replacementAppointmentCount": try await repo.appointments(
                        seriesID: XCTUnwrap(changed.first?.seriesID)
                    ).count,
                    "scheduledOnSkippedDates": allRows.filter {
                        skippedDates.contains($0.date) && $0.status == .scheduled && !$0.isDetachedException
                    }.count,
                    "times": changed.prefix(2).map {
                        "\($0.startTime.hour):\(String(format: "%02d", $0.startTime.minute))"
                    },
                    "focus": changed.prefix(2).map { $0.trainingFocus.map(\.rawValue).sorted() },
                ]
            case "appointment.abandon":
                let row = try await cases.createSingle(
                    studentID: student.id, date: day, startTime: LocalTime(hour: 9, minute: 0), overrideConflict: false)
                let session = try await cases.startTraining(appointmentID: row.id)
                _ = try await active.abandonEmpty(sessionID: session.id)
                let restored = try await cases.abandonEmptySession(appointmentID: row.id)
                actual = [
                    "status": restored.status.rawValue, "linkedSession": restored.linkedSessionID as Any? ?? NSNull(),
                ]
            case "appointment.absent":
                let credits = CreditLedgerUseCases(
                    repository: CoreDataCoursePackageRepository(writer: persistence.writer), clock: clock, ids: ids)
                let package = try await credits.createActivePackage(
                    studentID: student.id, name: nil, totalCredits: 5, startDate: nil, endDate: nil)
                let row = try await cases.createSingle(
                    studentID: student.id, date: day, startTime: LocalTime(hour: 9, minute: 0), overrideConflict: false)
                _ = try await cases.markAbsent(appointmentID: row.id, creditChoice: .charged)
                let first = try await credits.applyAbsence(
                    packageID: package.id, appointmentID: row.id, creditChoice: .charged)
                let second = try await credits.applyAbsence(
                    packageID: package.id, appointmentID: row.id, creditChoice: .charged)
                actual = [
                    "balance": try await credits.balance(packageID: package.id),
                    "ledgerCount": try await credits.adjustments(packageID: package.id).count,
                    "sameID": first?.id == second?.id,
                ]
            default: throw S2AdapterError.unmapped
            }
            try await persistence.shutdownForTesting()
            return actual
        } catch {
            try await persistence.shutdownForTesting()
            throw error
        }
    }
}
private enum S2AdapterError: Error { case unmapped }
private final class S2VectorIDs: IDGenerator, @unchecked Sendable {
    private var index: UInt64 = 2000
    private let lock = NSLock()
    func makeID() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        index += 1
        return UUID(uuidString: String(format: "72000000-0000-4000-8000-%012llx", index))!
    }
}
