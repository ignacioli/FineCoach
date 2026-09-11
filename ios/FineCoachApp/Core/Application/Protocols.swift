import Foundation

public struct MonotonicInstant: Hashable, Codable, Sendable, Comparable {
    public let nanoseconds: UInt64

    public init(nanoseconds: UInt64) {
        self.nanoseconds = nanoseconds
    }

    public static let zero = MonotonicInstant(nanoseconds: 0)

    public static func < (lhs: MonotonicInstant, rhs: MonotonicInstant) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }

    public func elapsedNanoseconds(since earlier: MonotonicInstant) -> UInt64? {
        guard nanoseconds >= earlier.nanoseconds else {
            return nil
        }
        return nanoseconds - earlier.nanoseconds
    }
}

public protocol Clock: Sendable {
    func nowUTC() -> Date
    func nowMonotonic() -> MonotonicInstant
}

public protocol IDGenerator: Sendable {
    func makeID() -> UUID
}

public protocol SecureRandomSource: Sendable {
    func randomBytes(count: Int) throws -> Data
}

public protocol FileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func readData(from url: URL) throws -> Data
    func writeData(_ data: Data, to url: URL) throws
    func removeItem(at url: URL) throws
    func replaceItem(at url: URL, withItemAt replacementURL: URL) throws
}

public struct RendererRequest: Hashable, Sendable {
    public let identifier: String
    public let payload: Data

    public init(identifier: String, payload: Data = Data()) {
        self.identifier = identifier
        self.payload = payload
    }
}

public protocol Renderer: Sendable {
    func render(_ request: RendererRequest) throws -> [Data]
}

public protocol Repository: Sendable {
    associatedtype Snapshot: Sendable

    func load() async throws -> Snapshot?
    func save(_ snapshot: Snapshot) async throws
}

public protocol TransactionRepository: Sendable {
    func transaction<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T
}

/// Injectable local-day/time-zone port (M1-B T007a): overdue judgement and
/// `localCalendarDay` derivation MUST go through this rather than
/// `Calendar.current`/`TimeZone.current` directly, so tests are deterministic
/// across time zones (adversarial A4).
public protocol LocalCalendarProvider: Sendable {
    func currentCalendar() -> Calendar
}

/// Mirrors `UNAuthorizationStatus` without importing UserNotifications outside
/// the notification adapter (M1-B T012). Domain/Application code that only
/// needs to branch on "is reminding currently possible" depends on this port
/// instead of a real permission prompt, so save-still-succeeds-on-denial paths
/// (D-004) are unit-testable without a device.
public enum NotificationAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
}

public protocol NotificationAuthorizationProvider: Sendable {
    func currentStatus() async -> NotificationAuthorizationStatus
}
