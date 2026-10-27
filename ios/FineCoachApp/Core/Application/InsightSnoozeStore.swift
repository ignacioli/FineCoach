import Foundation

/// Serializes read/modify/write operations; only opaque identifiers and local dates are stored.
public actor InsightSnoozeStore {
    private struct Document: Codable {
        let version: Int
        let entries: [Entry]
    }

    private struct Entry: Codable {
        let key: String
        let until: String
    }

    private let url: URL
    private let files: ProtectedFileStore

    /// The injected directory is the Application Support root, never a business-store generation.
    public init(
        directory: URL = URL.applicationSupportDirectory,
        protectedFileStore: ProtectedFileStore = ProtectedFileStore()
    ) {
        self.url = directory.appendingPathComponent("Insights/snoozes.json")
        self.files = protectedFileStore
    }

    public func activeKeys(now: Date, calendar: Calendar) -> Set<String> {
        Set(entries(now: now, calendar: calendar).map(\.key))
    }

    public func snooze(_ insight: Insight, now: Date, calendar: Calendar) throws {
        var current = entries(now: now, calendar: calendar).filter { $0.key != insight.snoozeKey }
        let until = LocalDate(date: now, calendar: calendar).addingDays(14, calendar: calendar)
        guard Self.isOpaqueKey(insight.snoozeKey) else { throw DomainError.invalidIdentifier }
        current.append(Entry(key: insight.snoozeKey, until: until.canonicalString))
        current.sort { $0.key < $1.key }
        let data = try JSONEncoder().encode(Document(version: 1, entries: current))
        _ = try files.writeData(data, to: url, policy: .business)
    }

    public func unsnooze(_ insight: Insight) throws {
        guard Self.isOpaqueKey(insight.snoozeKey) else { throw DomainError.invalidIdentifier }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try files.readData(from: url)
        guard let document = try? JSONDecoder().decode(Document.self, from: data), document.version == 1 else { return }
        guard document.entries.contains(where: { $0.key == insight.snoozeKey }) else { return }
        let entries = document.entries.filter { $0.key != insight.snoozeKey && Self.isOpaqueKey($0.key) }
        let updated = try JSONEncoder().encode(Document(version: 1, entries: entries))
        _ = try files.writeData(updated, to: url, policy: .business)
    }

    private func entries(now: Date, calendar: Calendar) -> [Entry] {
        guard let data = try? files.readData(from: url),
            let document = try? JSONDecoder().decode(Document.self, from: data), document.version == 1
        else { return [] }
        let today = LocalDate(date: now, calendar: calendar)
        return document.entries.filter {
            guard Self.isOpaqueKey($0.key), let until = try? LocalDate(canonicalString: $0.until),
                until.canonicalString == $0.until,
                LocalDate(date: until.startOfDay(calendar: calendar), calendar: calendar) == until
            else { return false }
            return today < until
        }
    }

    private static func isOpaqueKey(_ key: String) -> Bool {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2, UUID(uuidString: String(parts[1])) != nil else { return false }
        switch parts[0] {
        case "package", "inactive": return parts.count == 2
        case "stagnant": return parts.count == 3 && UUID(uuidString: String(parts[2])) != nil
        default: return false
        }
    }
}
