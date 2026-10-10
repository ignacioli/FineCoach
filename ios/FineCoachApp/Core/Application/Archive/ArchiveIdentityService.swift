import CoreData
import CryptoKit
import Foundation

/// The two random identities an archive carries (data-model §3). Neither value is ever logged,
/// shown, or derived from Coach content; the UI shows only `ArchiveIdentityService.shortLabel`.
public struct ArchiveIdentity: Equatable, Sendable {
    public let sourceID: UUID
    public let studentArchiveID: UUID

    public init(sourceID: UUID, studentArchiveID: UUID) {
        self.sourceID = sourceID
        self.studentArchiveID = studentArchiveID
    }
}

/// Generates and reads `archive.sourceID` and `archive.studentID.<Coach student UUID>` in the
/// Coach store's existing setting rows (no Core Data model change). Generation runs in its own
/// transaction so the identities exist before the first export begins (T018).
public struct ArchiveIdentityService: Sendable {
    private let writer: PersistenceWriter
    private let ids: any IDGenerator

    public init(writer: PersistenceWriter, ids: any IDGenerator = SystemIDGenerator()) {
        self.writer = writer
        self.ids = ids
    }

    /// Returns both identities for the student, creating whichever is missing. A stored value
    /// that is not a valid UUID fails closed instead of being overwritten.
    public func ensureIdentity(forStudent studentID: StableUUID) async throws -> ArchiveIdentity {
        let newSourceID = ids.makeID()
        let newStudentArchiveID = ids.makeID()
        return try await writer.transaction { context in
            let source = try Self.ensure(
                key: StudentManagedObjectMapping.archiveSourceIDKey,
                candidate: newSourceID,
                in: context
            )
            let student = try Self.ensure(
                key: StudentManagedObjectMapping.archiveStudentIDKey(for: studentID.rawValue),
                candidate: newStudentArchiveID,
                in: context
            )
            return ArchiveIdentity(sourceID: source, studentArchiveID: student)
        }
    }

    public func sourceID() async throws -> UUID? {
        try await writer.read { context in
            try Self.read(key: StudentManagedObjectMapping.archiveSourceIDKey, in: context)
        }
    }

    public func studentArchiveID(forStudent studentID: StableUUID) async throws -> UUID? {
        try await writer.read { context in
            try Self.read(
                key: StudentManagedObjectMapping.archiveStudentIDKey(for: studentID.rawValue),
                in: context
            )
        }
    }

    /// The four digits shown as 「来源 · NNNN」: SHA-256 of the 16 UUID bytes, first four bytes as
    /// a big-endian integer, modulo 10000, zero-padded.
    public static func shortLabel(forSourceID sourceID: UUID) -> String {
        let bytes = withUnsafeBytes(of: sourceID.uuid) { Array($0) }
        let digest = Array(SHA256.hash(data: bytes))
        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let digits = String(value % 10_000)
        return String(repeating: "0", count: 4 - digits.count) + digits
    }

    private static func read(key: String, in context: NSManagedObjectContext) throws -> UUID? {
        guard let raw = try StudentManagedObjectMapping.settingValue(key: key, in: context) else {
            return nil
        }
        guard let value = UUID(uuidString: raw) else {
            throw DomainError.incompatibleInput
        }
        return value
    }

    private static func ensure(key: String, candidate: UUID, in context: NSManagedObjectContext) throws -> UUID {
        if let existing = try read(key: key, in: context) {
            return existing
        }
        try StudentManagedObjectMapping.writeSetting(key: key, value: candidate.uuidString, in: context)
        return candidate
    }
}
