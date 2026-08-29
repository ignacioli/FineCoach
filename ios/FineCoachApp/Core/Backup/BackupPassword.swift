import Foundation

public struct BackupPassword: Equatable, Sendable {
    public let utf8: Data

    public init(creating raw: String) throws {
        let canonical = raw.precomposedStringWithCanonicalMapping
        guard Array(canonical).count >= 8 else {
            throw BackupError.invalidPassword
        }
        self.utf8 = Data(canonical.utf8)
    }

    public init(importing raw: String) throws {
        let canonical = raw.precomposedStringWithCanonicalMapping
        self.utf8 = Data(canonical.utf8)
    }
}
