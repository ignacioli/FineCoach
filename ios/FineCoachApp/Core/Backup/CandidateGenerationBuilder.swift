import CoreData
import Foundation

enum CandidateGenerationBuilder {
    static func apply(
        _ inventory: BackupInventory,
        in context: NSManagedObjectContext
    ) throws -> Session? {
        let inProgress = inventory.inProgressSessions
        guard inProgress.count <= 1 else {
            throw BackupError.invalidState
        }

        for student in inventory.students {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: StudentManagedObjectMapping.entityName,
                into: context
            )
            StudentManagedObjectMapping.apply(student, to: object)
        }
        for item in inventory.catalog {
            _ = try ExerciseManagedObjectMapping.upsertCatalogItem(item, in: context)
        }
        for preference in inventory.preferences {
            _ = try ExerciseManagedObjectMapping.upsertPreference(preference, in: context)
        }
        for claim in inventory.claims {
            try ExerciseManagedObjectMapping.acquireUnifiedClaim(claim, in: context)
        }
        let orderedSessions =
            inventory.sessions.filter { $0.state != .inProgress } + inventory.inProgressSessions
        for session in orderedSessions {
            _ = try SessionManagedObjectMapping.upsertAggregate(session, in: context)
        }
        for record in inventory.reports {
            _ = try HistoryReportManagedObjectMapping.upsertReport(
                record.report,
                modules: record.modules,
                in: context
            )
        }
        for setting in inventory.settings {
            let request = NSFetchRequest<NSManagedObject>(
                entityName: StudentManagedObjectMapping.settingEntityName
            )
            request.predicate = NSPredicate(format: "key == %@", setting.key)
            request.fetchLimit = 1
            let object =
                try context.fetch(request).first
                ?? NSEntityDescription.insertNewObject(
                    forEntityName: StudentManagedObjectMapping.settingEntityName,
                    into: context
                )
            object.setValue(setting.key, forKey: "key")
            object.setValue(setting.typedValue, forKey: "typedValue")
            object.setValue(setting.schemaVersion, forKey: "schemaVersion")
        }

        if let active = inProgress.first {
            return try SessionManagedObjectMapping.loadAggregate(
                from: try SessionManagedObjectMapping.requireSession(id: active.id.rawValue, in: context),
                in: context
            )
        }
        if let pointer = try SessionManagedObjectMapping.fetchPointer(in: context) {
            context.delete(pointer)
        }
        return nil
    }
}
