import CoreData
import Foundation

enum ExerciseManagedObjectMapping {
    static let catalogEntityName = "ExerciseCatalogMO"
    static let claimEntityName = "ExerciseNameClaimMO"
    static let preferenceEntityName = "ExercisePreferenceMO"

    static func apply(_ item: ExerciseCatalogItem, to object: NSManagedObject) {
        object.setValue(item.id.rawValue, forKey: "id")
        object.setValue(item.kind.rawValue, forKey: "kind")
        object.setValue(item.canonicalName.value, forKey: "canonicalName")
        object.setValue(item.normalizedName, forKey: "normalizedName")
        object.setValue(item.recordMode.rawValue, forKey: "recordMode")
        object.setValue(item.metadataVersion, forKey: "metadataVersion")
        object.setValue(item.lifecycle.rawValue, forKey: "lifecycle")
        object.setValue(item.provenanceRef, forKey: "provenanceRef")
        object.setValue(item.createdAtUTC, forKey: "createdAtUTC")
        object.setValue(item.updatedAtUTC, forKey: "updatedAtUTC")
    }

    static func apply(_ claim: ExerciseNameClaim, to object: NSManagedObject) {
        object.setValue(claim.normalizedName, forKey: "normalizedName")
        object.setValue(claim.ownerKind.rawValue, forKey: "ownerKind")
        object.setValue(claim.ownerID.rawValue, forKey: "ownerID")
        object.setValue(claim.scope.rawValue, forKey: "scope")
    }

    static func apply(_ preference: ExercisePreference, to object: NSManagedObject) {
        object.setValue(preference.exerciseID.rawValue, forKey: "exerciseID")
        object.setValue(preference.alias?.value, forKey: "alias")
        object.setValue(preference.isFavorite, forKey: "isFavorite")
        object.setValue(preference.isHidden, forKey: "isHidden")
    }

    static func makeCatalogItem(from object: NSManagedObject) throws -> ExerciseCatalogItem {
        guard let rawID = object.value(forKey: "id") as? String else {
            throw DomainError.incompatibleInput
        }
        guard let kindRaw = object.value(forKey: "kind") as? String,
            let kind = ExerciseKind(rawValue: kindRaw)
        else {
            throw DomainError.incompatibleInput
        }
        guard let canonicalName = object.value(forKey: "canonicalName") as? String else {
            throw DomainError.incompatibleInput
        }
        guard let modeRaw = object.value(forKey: "recordMode") as? String,
            let recordMode = RecordMode(rawValue: modeRaw)
        else {
            throw DomainError.incompatibleInput
        }
        guard let metadataVersion = object.value(forKey: "metadataVersion") as? String else {
            throw DomainError.incompatibleInput
        }
        guard let lifecycleRaw = object.value(forKey: "lifecycle") as? String,
            let lifecycle = ExerciseLifecycle(rawValue: lifecycleRaw)
        else {
            throw DomainError.incompatibleInput
        }
        guard let createdAtUTC = object.value(forKey: "createdAtUTC") as? Date,
            let updatedAtUTC = object.value(forKey: "updatedAtUTC") as? Date
        else {
            throw DomainError.incompatibleInput
        }
        return try ExerciseCatalogItem(
            id: StableExerciseID(rawID),
            kind: kind,
            canonicalName: NormalizedName(canonicalName),
            recordMode: recordMode,
            metadataVersion: metadataVersion,
            lifecycle: lifecycle,
            provenanceRef: object.value(forKey: "provenanceRef") as? String,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC
        )
    }

    static func makeClaim(from object: NSManagedObject) throws -> ExerciseNameClaim {
        guard let normalizedName = object.value(forKey: "normalizedName") as? String else {
            throw DomainError.incompatibleInput
        }
        guard let ownerKindRaw = object.value(forKey: "ownerKind") as? String,
            let ownerKind = ExerciseSourceKind(rawValue: ownerKindRaw)
        else {
            throw DomainError.incompatibleInput
        }
        guard let ownerID = object.value(forKey: "ownerID") as? String else {
            throw DomainError.incompatibleInput
        }
        guard let scopeRaw = object.value(forKey: "scope") as? String,
            let scope = ExerciseClaimScope(rawValue: scopeRaw)
        else {
            throw DomainError.incompatibleInput
        }
        return try ExerciseNameClaim(
            normalizedName: normalizedName,
            ownerKind: ownerKind,
            ownerID: StableExerciseID(ownerID),
            scope: scope
        )
    }

    static func makePreference(from object: NSManagedObject) throws -> ExercisePreference {
        guard let exerciseID = object.value(forKey: "exerciseID") as? String else {
            throw DomainError.incompatibleInput
        }
        let alias: NormalizedName?
        if let rawAlias = object.value(forKey: "alias") as? String,
            !rawAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            alias = try NormalizedName(rawAlias)
        } else {
            alias = nil
        }
        let isFavorite = object.value(forKey: "isFavorite") as? Bool ?? false
        let isHidden = object.value(forKey: "isHidden") as? Bool ?? false
        return try ExercisePreference(
            exerciseID: StableExerciseID(exerciseID),
            alias: alias,
            isFavorite: isFavorite,
            isHidden: isHidden
        )
    }

    static func fetchCatalogItem(id: String, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: catalogEntityName)
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func fetchCatalogItem(normalizedName: String, in context: NSManagedObjectContext) throws
        -> NSManagedObject?
    {
        let request = NSFetchRequest<NSManagedObject>(entityName: catalogEntityName)
        request.predicate = NSPredicate(format: "normalizedName == %@", normalizedName)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func requireCatalogItem(id: String, in context: NSManagedObjectContext) throws -> NSManagedObject {
        guard let object = try fetchCatalogItem(id: id, in: context) else {
            throw DomainError.notFound
        }
        return object
    }

    static func hasBuiltInCatalog(in context: NSManagedObjectContext) throws -> Bool {
        try builtInCatalogCount(in: context) > 0
    }

    static func builtInCatalogCount(in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: catalogEntityName)
        request.predicate = NSPredicate(format: "kind == %@", ExerciseKind.builtIn.rawValue)
        return try context.count(for: request)
    }

    static func fetchBuiltInCatalogItems(in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: catalogEntityName)
        request.predicate = NSPredicate(format: "kind == %@", ExerciseKind.builtIn.rawValue)
        return try context.fetch(request)
    }

    static func fetchClaim(normalizedName: String, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: claimEntityName)
        request.predicate = NSPredicate(format: "normalizedName == %@", normalizedName)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func fetchClaims(ownerID: String, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: claimEntityName)
        request.predicate = NSPredicate(format: "ownerID == %@", ownerID)
        return try context.fetch(request)
    }

    static func fetchClaims(scope: ExerciseClaimScope, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: claimEntityName)
        request.predicate = NSPredicate(format: "scope == %@", scope.rawValue)
        return try context.fetch(request)
    }

    static func fetchPreference(exerciseID: String, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: preferenceEntityName)
        request.predicate = NSPredicate(format: "exerciseID == %@", exerciseID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func fetchPreferences(in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: preferenceEntityName)
        return try context.fetch(request)
    }

    static func fetchActiveCatalogItems(in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: catalogEntityName)
        request.predicate = NSPredicate(format: "lifecycle == %@", ExerciseLifecycle.active.rawValue)
        request.sortDescriptors = [
            NSSortDescriptor(key: "canonicalName", ascending: true),
            NSSortDescriptor(key: "id", ascending: true),
        ]
        return try context.fetch(request)
    }

    static func upsertCatalogItem(_ item: ExerciseCatalogItem, in context: NSManagedObjectContext) throws
        -> NSManagedObject
    {
        let object =
            try fetchCatalogItem(id: item.id.rawValue, in: context)
            ?? NSEntityDescription.insertNewObject(forEntityName: catalogEntityName, into: context)
        apply(item, to: object)
        return object
    }

    static func upsertPreference(_ preference: ExercisePreference, in context: NSManagedObjectContext) throws
        -> NSManagedObject
    {
        let object =
            try fetchPreference(exerciseID: preference.exerciseID.rawValue, in: context)
            ?? NSEntityDescription.insertNewObject(forEntityName: preferenceEntityName, into: context)
        apply(preference, to: object)
        if let catalog = try fetchCatalogItem(id: preference.exerciseID.rawValue, in: context) {
            object.setValue(catalog, forKey: "exercise")
        }
        return object
    }

    static func acquireUnifiedClaim(_ claim: ExerciseNameClaim, in context: NSManagedObjectContext) throws {
        if let existing = try fetchClaim(normalizedName: claim.normalizedName, in: context) {
            let current = try makeClaim(from: existing)
            if current.ownerID == claim.ownerID && current.scope == claim.scope {
                return
            }
            throw DomainError.conflict
        }
        let object = NSEntityDescription.insertNewObject(forEntityName: claimEntityName, into: context)
        apply(claim, to: object)
    }

    static func deleteClaims(ownerID: String, in context: NSManagedObjectContext) throws {
        for object in try fetchClaims(ownerID: ownerID, in: context) {
            context.delete(object)
        }
    }

    static func deleteClaims(scope: ExerciseClaimScope, in context: NSManagedObjectContext) throws {
        for object in try fetchClaims(scope: scope, in: context) {
            context.delete(object)
        }
    }

    static func deleteClaim(
        normalizedName: String,
        ownerID: String,
        in context: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: claimEntityName)
        request.predicate = NSPredicate(
            format: "normalizedName == %@ AND ownerID == %@",
            normalizedName,
            ownerID
        )
        for object in try context.fetch(request) {
            context.delete(object)
        }
    }
}
