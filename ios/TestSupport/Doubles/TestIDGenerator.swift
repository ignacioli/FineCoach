import FineCoach
import Foundation

public final class TestIDGenerator: IDGenerator, @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [UUID]

    public init(ids: [UUID]) {
        self.ids = ids
    }

    public func makeID() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        if ids.isEmpty {
            return UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!
        }
        return ids.removeFirst()
    }
}
