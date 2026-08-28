import Foundation

public enum PersistenceProjectionStatus: Equatable, Sendable {
    case saving
    case saved(revision: UInt64)
    case failed(revision: UInt64, retryable: Bool)
}

public enum RecoveryIsolationReason: String, Equatable, Sendable {
    case generationMismatch
    case corruptSnapshot
    case unknownEnum
    case invariantViolation
    case negativeRevision
}

public enum RecoveryLaunchDecision: Equatable, Sendable {
    case noActiveSession
    case consistent(Session)
    case replay(ActiveSessionRecoverySnapshot)
    case ignoreOlderSnapshot(Session)
    case failClosed(RecoveryIsolationReason)
}

enum RecoveryJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public struct ActiveSessionRecoverySnapshot: Codable, Equatable, Sendable {
    public static let schemaID = "active-session-recovery-v1"

    public let schemaID: String
    public let storeGenerationUUID: UUID
    public let revision: UInt64
    public let session: Session

    public init(storeGenerationUUID: UUID, session: Session) throws {
        self.schemaID = Self.schemaID
        self.storeGenerationUUID = storeGenerationUUID
        self.revision = session.revision
        self.session = session
        try validate()
    }

    public func encoded() throws -> Data {
        try validate()
        return try RecoveryJSON.encoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> ActiveSessionRecoverySnapshot {
        let snapshot: ActiveSessionRecoverySnapshot
        do {
            snapshot = try RecoveryJSON.decoder().decode(ActiveSessionRecoverySnapshot.self, from: data)
        } catch {
            throw DomainError.incompatibleInput
        }
        try snapshot.validate()
        return snapshot
    }

    public func validate() throws {
        guard schemaID == Self.schemaID else {
            throw DomainError.incompatibleInput
        }
        guard revision >= 1, revision == session.revision else {
            throw DomainError.incompatibleInput
        }
    }
}
