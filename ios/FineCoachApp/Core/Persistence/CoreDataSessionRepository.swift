import Foundation

public struct CoreDataSessionRepository: Sendable {
    private let writer: PersistenceWriter

    public init(writer: PersistenceWriter) {
        self.writer = writer
    }

    public func loadActive() async throws -> Session? {
        try await writer.read { context in
            guard let object = try SessionManagedObjectMapping.inProgressSession(in: context) else {
                return nil
            }
            return try SessionManagedObjectMapping.loadAggregate(from: object, in: context)
        }
    }

    public func session(id: StableUUID) async throws -> Session {
        try await writer.read { context in
            let object = try SessionManagedObjectMapping.requireSession(id: id.rawValue, in: context)
            return try SessionManagedObjectMapping.loadAggregate(from: object, in: context)
        }
    }

    public func save(_ session: Session) async throws -> Session {
        try await writer.transaction { context in
            if session.state == .inProgress {
                if let existing = try SessionManagedObjectMapping.inProgressSession(in: context),
                    let existingID = existing.value(forKey: "id") as? UUID,
                    existingID != session.id.rawValue
                {
                    throw DomainError.conflict
                }
            }
            return try SessionManagedObjectMapping.upsertAggregate(session, in: context)
        }
    }
}
