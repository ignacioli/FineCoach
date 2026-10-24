import XCTest

@testable import FineCoach

final class InsightSnoozeStoreTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }

    func testRoundTripRestartExpiryAndPrivateShape() async throws {
        let directory = try TemporaryProtectedDirectory()
        let store = InsightSnoozeStore(directory: directory.url)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-01T20:00:00Z"))
        let insight = Insight(kind: .packageLow, studentID: StableUUID(UUID()))
        try await store.snooze(insight, now: now, calendar: calendar)
        let reopened = InsightSnoozeStore(directory: directory.url)
        let keys = await reopened.activeKeys(now: now, calendar: calendar)
        XCTAssertEqual(keys, [insight.snoozeKey])
        let today = LocalDate(date: now, calendar: calendar)
        let before = today.addingDays(13, calendar: calendar).startOfDay(calendar: calendar)
        let boundary = today.addingDays(14, calendar: calendar).startOfDay(calendar: calendar)
        let beforeKeys = await reopened.activeKeys(now: before, calendar: calendar)
        let expired = await reopened.activeKeys(now: boundary, calendar: calendar)
        XCTAssertEqual(beforeKeys, keys)
        XCTAssertTrue(expired.isEmpty)
        let other = Insight(kind: .inactive, studentID: StableUUID(UUID()))
        try await reopened.snooze(other, now: boundary, calendar: calendar)
        let data = try Data(contentsOf: directory.url.appendingPathComponent("Insights/snoozes.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "entries"])
        XCTAssertEqual(object["version"] as? Int, 1)
        let entries = try XCTUnwrap(object["entries"] as? [[String: String]])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(Set(try XCTUnwrap(entries.first).keys), ["key", "until"])
        XCTAssertEqual(entries.first?["key"], other.snoozeKey)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(insight.snoozeKey))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).allSatisfy { $0.isASCII })
        let audit = try ProtectedFileStore().audit(url: directory.url.appendingPathComponent("Insights/snoozes.json"))
        XCTAssertTrue(audit.isExcludedFromBackup)
    }

    func testMissingCorruptAndUnknownVersionReadAsEmpty() async throws {
        let directory = try TemporaryProtectedDirectory()
        let store = InsightSnoozeStore(directory: directory.url)
        let now = Date()
        let missing = await store.activeKeys(now: now, calendar: calendar)
        XCTAssertTrue(missing.isEmpty)
        let url = directory.url.appendingPathComponent("Insights/snoozes.json")
        let key = Insight(kind: .inactive, studentID: StableUUID(UUID())).snoozeKey
        let unknown = "{\"version\":99,\"entries\":[{\"key\":\"\(key)\",\"until\":\"2099-01-01\"}]}"
        for content in ["{", unknown] {
            _ = try ProtectedFileStore().writeData(Data(content.utf8), to: url, policy: .business)
            let keys = await store.activeKeys(now: now, calendar: calendar)
            XCTAssertTrue(keys.isEmpty)
        }
    }

    func testWriteFailurePropagates() async throws {
        let directory = try TemporaryProtectedDirectory()
        let occupied = directory.url.appendingPathComponent("occupied")
        try Data().write(to: occupied)
        let store = InsightSnoozeStore(directory: occupied)
        do {
            try await store.snooze(
                Insight(kind: .inactive, studentID: StableUUID(UUID())), now: Date(), calendar: calendar)
            XCTFail("A failed durable write must not report success")
        } catch {
            let keys = await store.activeKeys(now: Date(), calendar: calendar)
            XCTAssertTrue(keys.isEmpty)
        }
    }
}
