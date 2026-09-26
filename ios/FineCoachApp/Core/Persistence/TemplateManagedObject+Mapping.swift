import CoreData
import Foundation

enum TemplateManagedObjectMapping {
    static let templateEntityName = "TrainingTemplateMO"
    static let exerciseEntityName = "TemplateExerciseMO"

    static func apply(_ template: TrainingTemplate, to object: NSManagedObject) {
        object.setValue(template.id.rawValue, forKey: "id")
        object.setValue(template.name.value, forKey: "name")
        object.setValue(BodyPartCoding.mask(template.trainingFocus), forKey: "trainingFocusMask")
        object.setValue(template.createdAtUTC, forKey: "createdAtUTC")
        object.setValue(template.updatedAtUTC, forKey: "updatedAtUTC")
    }

    static func makeTemplate(from object: NSManagedObject) throws -> TrainingTemplate {
        guard let rawID = object.value(forKey: "id") as? UUID,
            let name = object.value(forKey: "name") as? String,
            let createdAtUTC = object.value(forKey: "createdAtUTC") as? Date,
            let updatedAtUTC = object.value(forKey: "updatedAtUTC") as? Date
        else {
            throw DomainError.incompatibleInput
        }
        let trainingFocus = BodyPartCoding.parts(fromMask: object.value(forKey: "trainingFocusMask") as? Int32 ?? 0)
        return try TrainingTemplate(
            id: StableUUID(rawID),
            name: name,
            trainingFocus: trainingFocus,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC
        )
    }

    static func apply(_ exercise: TemplateExercise, to object: NSManagedObject) throws {
        object.setValue(exercise.id.rawValue, forKey: "id")
        object.setValue(exercise.templateID.rawValue, forKey: "templateID")
        object.setValue(exercise.sectionID?.rawValue, forKey: "sectionID")
        object.setValue(Int32(exercise.orderIndex), forKey: "orderIndex")
        object.setValue(exercise.sourceKind.rawValue, forKey: "sourceKind")
        object.setValue(exercise.sourceID?.rawValue, forKey: "sourceID")
        object.setValue(exercise.displayNameSnapshot.value, forKey: "displayNameSnapshot")
        object.setValue(exercise.recordModeSnapshot.rawValue, forKey: "recordModeSnapshot")
        let data = try JSONEncoder().encode(exercise.plannedSets)
        object.setValue(data, forKey: "planSetsData")
    }

    static func makeExercise(from object: NSManagedObject) throws -> TemplateExercise {
        guard let rawID = object.value(forKey: "id") as? UUID,
            let templateID = object.value(forKey: "templateID") as? UUID
        else {
            throw DomainError.incompatibleInput
        }
        guard let sourceKindRaw = object.value(forKey: "sourceKind") as? String,
            let sourceKind = ExerciseSourceKind(rawValue: sourceKindRaw)
        else {
            throw DomainError.incompatibleInput
        }
        guard let displayName = object.value(forKey: "displayNameSnapshot") as? String else {
            throw DomainError.incompatibleInput
        }
        guard let modeRaw = object.value(forKey: "recordModeSnapshot") as? String,
            let recordMode = RecordMode(rawValue: modeRaw)
        else {
            throw DomainError.incompatibleInput
        }
        guard let planSetsData = object.value(forKey: "planSetsData") as? Data else {
            throw DomainError.incompatibleInput
        }
        let orderIndex = UInt32(truncatingIfNeeded: object.value(forKey: "orderIndex") as? Int32 ?? 0)
        let sectionID = (object.value(forKey: "sectionID") as? UUID).map { StableUUID($0) }
        let sourceID: StableExerciseID?
        if let rawSourceID = object.value(forKey: "sourceID") as? String {
            sourceID = try StableExerciseID(rawSourceID)
        } else {
            sourceID = nil
        }
        let plannedSets = try JSONDecoder().decode([TemplatePlannedSet].self, from: planSetsData)
        return TemplateExercise(
            id: StableUUID(rawID),
            templateID: StableUUID(templateID),
            sectionID: sectionID,
            orderIndex: orderIndex,
            sourceKind: sourceKind,
            sourceID: sourceID,
            displayNameSnapshot: try NormalizedName(displayName),
            recordModeSnapshot: recordMode,
            plannedSets: plannedSets
        )
    }

    static func fetchTemplate(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: templateEntityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func requireTemplate(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject {
        guard let object = try fetchTemplate(id: id, in: context) else {
            throw DomainError.notFound
        }
        return object
    }

    static func fetchTemplates(in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: templateEntityName)
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAtUTC", ascending: false)]
        return try context.fetch(request)
    }

    static func fetchExercise(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: exerciseEntityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func fetchExercises(templateID: UUID, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: exerciseEntityName)
        request.predicate = NSPredicate(format: "templateID == %@", templateID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
        return try context.fetch(request)
    }
}
