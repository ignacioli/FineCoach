import CoreData
import Foundation

enum SessionSectionManagedObjectMapping {
    static let entityName = "SessionSectionMO"

    static func apply(_ section: SessionSection, to object: NSManagedObject) {
        object.setValue(section.id.rawValue, forKey: "id")
        object.setValue(section.ownerKind.rawValue, forKey: "ownerKind")
        object.setValue(section.ownerID.rawValue, forKey: "ownerID")
        object.setValue(section.name.value, forKey: "name")
        object.setValue(Int32(section.orderIndex), forKey: "orderIndex")
    }

    static func makeSection(from object: NSManagedObject) throws -> SessionSection {
        guard let rawID = object.value(forKey: "id") as? UUID,
            let ownerKindRaw = object.value(forKey: "ownerKind") as? String,
            let ownerKind = SessionSectionOwnerKind(rawValue: ownerKindRaw),
            let ownerID = object.value(forKey: "ownerID") as? UUID,
            let name = object.value(forKey: "name") as? String
        else {
            throw DomainError.incompatibleInput
        }
        let orderIndex = UInt32(truncatingIfNeeded: object.value(forKey: "orderIndex") as? Int32 ?? 0)
        return SessionSection(
            id: StableUUID(rawID),
            ownerKind: ownerKind,
            ownerID: StableUUID(ownerID),
            name: try NormalizedName(name),
            orderIndex: orderIndex
        )
    }

    static func fetchSection(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func requireSection(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject {
        guard let object = try fetchSection(id: id, in: context) else {
            throw DomainError.notFound
        }
        return object
    }

    static func fetchSections(
        ownerKind: SessionSectionOwnerKind,
        ownerID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(
            format: "ownerKind == %@ AND ownerID == %@",
            ownerKind.rawValue,
            ownerID as CVarArg
        )
        request.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
        return try context.fetch(request)
    }
}

/// Persistence for `SessionSection` (data-model §2.7, T031). One entity
/// shared by both owner kinds (`session`/`template`) -- there is no Core
/// Data relationship from `SessionSectionMO` to either `SessionMO` or
/// `TrainingTemplateMO`, only the plain `ownerKind`/`ownerID` attributes, so
/// deleting a Template (or a Session) never cascades into this table by
/// accident; callers own cleaning up their owned rows explicitly.
public struct CoreDataSessionSectionRepository: Sendable {
    private let writer: PersistenceWriter

    public init(writer: PersistenceWriter) {
        self.writer = writer
    }

    public func sections(ownerKind: SessionSectionOwnerKind, ownerID: StableUUID) async throws -> [SessionSection] {
        try await writer.read { context in
            try SessionSectionManagedObjectMapping.fetchSections(
                ownerKind: ownerKind,
                ownerID: ownerID.rawValue,
                in: context
            ).map { try SessionSectionManagedObjectMapping.makeSection(from: $0) }
        }
    }

    @discardableResult
    public func upsert(_ section: SessionSection) async throws -> SessionSection {
        try await writer.transaction { context in
            let object =
                try SessionSectionManagedObjectMapping.fetchSection(id: section.id.rawValue, in: context)
                ?? NSEntityDescription.insertNewObject(
                    forEntityName: SessionSectionManagedObjectMapping.entityName,
                    into: context
                )
            SessionSectionManagedObjectMapping.apply(section, to: object)
            return try SessionSectionManagedObjectMapping.makeSection(from: object)
        }
    }

    public func upsertAll(_ sections: [SessionSection]) async throws {
        guard !sections.isEmpty else {
            return
        }
        try await writer.transaction { context in
            for section in sections {
                let object =
                    try SessionSectionManagedObjectMapping.fetchSection(id: section.id.rawValue, in: context)
                    ?? NSEntityDescription.insertNewObject(
                        forEntityName: SessionSectionManagedObjectMapping.entityName,
                        into: context
                    )
                SessionSectionManagedObjectMapping.apply(section, to: object)
            }
        }
    }

    public func delete(id: StableUUID) async throws {
        try await writer.transaction { context in
            if let object = try SessionSectionManagedObjectMapping.fetchSection(id: id.rawValue, in: context) {
                context.delete(object)
            }
        }
    }

    /// Deletes every Section owned by (`ownerKind`, `ownerID`) -- used when a
    /// Template is deleted (M1B-FR-019/D-009: the Template's OWN Sections go
    /// away with it; Sections belonging to Sessions that already applied
    /// the template are a completely separate set of rows with a different
    /// `ownerID`, so they are never touched by this call).
    public func deleteAll(ownerKind: SessionSectionOwnerKind, ownerID: StableUUID) async throws {
        try await writer.transaction { context in
            let objects = try SessionSectionManagedObjectMapping.fetchSections(
                ownerKind: ownerKind,
                ownerID: ownerID.rawValue,
                in: context
            )
            for object in objects {
                context.delete(object)
            }
        }
    }
}
