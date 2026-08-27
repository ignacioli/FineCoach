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
