import CoreData
import Foundation

/// Persistence for `TrainingTemplate` + its `TemplateExercise` rows
/// (data-model §2.5/§2.6, T031). All writes go through the existing single
/// serial `PersistenceWriter` -- no second write path is introduced.
public struct CoreDataTemplateRepository: Sendable {
    private let writer: PersistenceWriter

    public init(writer: PersistenceWriter) {
        self.writer = writer
    }

    @discardableResult
    public func createTemplate(_ template: TrainingTemplate) async throws -> TrainingTemplate {
        try await writer.transaction { context in
            let object = NSEntityDescription.insertNewObject(
                forEntityName: TemplateManagedObjectMapping.templateEntityName,
                into: context
            )
            TemplateManagedObjectMapping.apply(template, to: object)
            return try TemplateManagedObjectMapping.makeTemplate(from: object)
        }
    }

    @discardableResult
    public func updateTemplate(_ template: TrainingTemplate) async throws -> TrainingTemplate {
        try await writer.transaction { context in
            let object = try TemplateManagedObjectMapping.requireTemplate(id: template.id.rawValue, in: context)
            TemplateManagedObjectMapping.apply(template, to: object)
            return try TemplateManagedObjectMapping.makeTemplate(from: object)
        }
    }

    public func template(id: StableUUID) async throws -> TrainingTemplate {
        try await writer.read { context in
            let object = try TemplateManagedObjectMapping.requireTemplate(id: id.rawValue, in: context)
            return try TemplateManagedObjectMapping.makeTemplate(from: object)
        }
    }

    /// All templates, most-recently-updated first (T032 template list).
    public func templates() async throws -> [TrainingTemplate] {
        try await writer.read { context in
            try TemplateManagedObjectMapping.fetchTemplates(in: context)
                .map { try TemplateManagedObjectMapping.makeTemplate(from: $0) }
        }
    }

    public func exercises(templateID: StableUUID) async throws -> [TemplateExercise] {
        try await writer.read { context in
            try TemplateManagedObjectMapping.fetchExercises(templateID: templateID.rawValue, in: context)
                .map { try TemplateManagedObjectMapping.makeExercise(from: $0) }
        }
    }

    /// Replaces the full `TemplateExercise` set for a template with
    /// `exercises` in one transaction (rows not present in `exercises` are
    /// deleted, the rest are upserted) -- the single write path every
    /// template-exercise mutation (add/remove/reorder/move/plan-edit) in
    /// `TemplateUseCases` funnels through, mirroring how
    /// `SessionManagedObjectMapping.syncExercises` replaces a Session's
    /// Exercise set.
    public func replaceExercises(templateID: StableUUID, with exercises: [TemplateExercise]) async throws {
        try await writer.transaction { context in
            _ = try TemplateManagedObjectMapping.requireTemplate(id: templateID.rawValue, in: context)
            let existing = try TemplateManagedObjectMapping.fetchExercises(
                templateID: templateID.rawValue,
                in: context
            )
            let desiredIDs = Set(exercises.map(\.id.rawValue))
            for object in existing {
                guard let existingID = object.value(forKey: "id") as? UUID, desiredIDs.contains(existingID) else {
                    context.delete(object)
                    continue
                }
            }
            for exercise in exercises {
                let object =
                    try TemplateManagedObjectMapping.fetchExercise(id: exercise.id.rawValue, in: context)
                    ?? NSEntityDescription.insertNewObject(
                        forEntityName: TemplateManagedObjectMapping.exerciseEntityName,
                        into: context
                    )
                try TemplateManagedObjectMapping.apply(exercise, to: object)
            }
        }
    }

    /// Deletes the Template and its `TemplateExercise` rows ONLY -- this
    /// method never fetches, touches, or deletes anything from `SessionMO`
    /// (M1B-FR-019, D-009). Template-owned `SessionSection` rows are a
    /// separate entity with no Core Data relationship here, so callers MUST
    /// also call `CoreDataSessionSectionRepository.deleteAll(ownerKind:
    /// .template, ownerID:)` -- kept as an explicit second call (both go
    /// through the same single writer, just two transactions) rather than
    /// folded in here, so this repository's own "never touches Session"
    /// guarantee stays visible at a glance.
    public func deleteTemplate(id: StableUUID) async throws {
        try await writer.transaction { context in
            let object = try TemplateManagedObjectMapping.requireTemplate(id: id.rawValue, in: context)
            context.delete(object)
        }
    }
}
