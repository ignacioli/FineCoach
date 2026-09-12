import CoreData
import Foundation

/// Maps `BodyMetricDefinition`/`BodyMeasurement` to
/// `BodyMetricDefinitionMO`/`BodyMeasurementMO` (data-model §2.8/§2.9). ONLY
/// custom metrics are ever persisted here -- the 8 built-ins
/// (`BuiltInBodyMetric`) are fixed Domain constants with fixed UUIDs and are
/// never written to Core Data, so there is nothing to seed/migrate for them.
enum BodyMetricManagedObjectMapping {
    static let metricEntityName = "BodyMetricDefinitionMO"
    static let measurementEntityName = "BodyMeasurementMO"

    // MARK: - BodyMetricDefinition (custom only)

    static func apply(_ metric: BodyMetricDefinition, to object: NSManagedObject) throws {
        guard metric.kind == .custom, let studentID = metric.studentID else {
            throw DomainError.incompatibleInput
        }
        object.setValue(metric.id.rawValue, forKey: "id")
        object.setValue(studentID.rawValue, forKey: "studentID")
        object.setValue(metric.kind.rawValue, forKey: "kind")
        object.setValue(metric.name.value, forKey: "name")
        object.setValue(metric.normalizedName, forKey: "normalizedName")
        object.setValue(metric.unitRuleKind.rawValue, forKey: "unitRuleKind")
        object.setValue(metric.currentUnit, forKey: "currentUnit")
        object.setValue(metric.lifecycle.rawValue, forKey: "lifecycle")
        object.setValue(metric.createdAtUTC, forKey: "createdAtUTC")
        object.setValue(metric.updatedAtUTC, forKey: "updatedAtUTC")
    }

    static func makeMetric(from object: NSManagedObject) throws -> BodyMetricDefinition {
        guard let rawID = object.value(forKey: "id") as? UUID,
            let rawStudentID = object.value(forKey: "studentID") as? UUID,
            let kindRaw = object.value(forKey: "kind") as? String,
            let kind = BodyMetricKind(rawValue: kindRaw),
            let name = object.value(forKey: "name") as? String,
            let unitRuleKindRaw = object.value(forKey: "unitRuleKind") as? String,
            let unitRuleKind = BodyMetricUnitRuleKind(rawValue: unitRuleKindRaw),
            let currentUnit = object.value(forKey: "currentUnit") as? String,
            let lifecycleRaw = object.value(forKey: "lifecycle") as? String,
            let lifecycle = BodyMetricLifecycle(rawValue: lifecycleRaw),
            let createdAtUTC = object.value(forKey: "createdAtUTC") as? Date,
            let updatedAtUTC = object.value(forKey: "updatedAtUTC") as? Date
        else {
            throw DomainError.incompatibleInput
        }
        return try BodyMetricDefinition(
            id: StableUUID(rawID),
            studentID: StableUUID(rawStudentID),
            kind: kind,
            name: name,
            unitRuleKind: unitRuleKind,
            currentUnit: currentUnit,
            lifecycle: lifecycle,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC
        )
    }

    static func fetchMetric(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: metricEntityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func requireMetric(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject {
        guard let object = try fetchMetric(id: id, in: context) else {
            throw DomainError.notFound
        }
        return object
    }

    static func fetchMetricByNormalizedName(
        studentID: UUID,
        normalizedName: String,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: metricEntityName)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND normalizedName == %@",
            studentID as CVarArg,
            normalizedName
        )
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func fetchMetrics(studentID: UUID, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: metricEntityName)
        request.predicate = NSPredicate(format: "studentID == %@", studentID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAtUTC", ascending: true)]
        return try context.fetch(request)
    }

    // MARK: - BodyMeasurement

    static func apply(_ measurement: BodyMeasurement, to object: NSManagedObject) {
        object.setValue(measurement.id.rawValue, forKey: "id")
        object.setValue(measurement.studentID.rawValue, forKey: "studentID")
        object.setValue(measurement.metricID.rawValue, forKey: "metricID")
        object.setValue(measurement.localCalendarDay.canonicalString, forKey: "localCalendarDay")
        object.setValue(measurement.value.canonicalString, forKey: "value")
        object.setValue(measurement.enteredUnit, forKey: "enteredUnit")
        object.setValue(measurement.createdAtUTC, forKey: "createdAtUTC")
        object.setValue(measurement.updatedAtUTC, forKey: "updatedAtUTC")
    }

    static func makeMeasurement(from object: NSManagedObject) throws -> BodyMeasurement {
        guard let rawID = object.value(forKey: "id") as? UUID,
            let rawStudentID = object.value(forKey: "studentID") as? UUID,
            let rawMetricID = object.value(forKey: "metricID") as? UUID,
            let dayString = object.value(forKey: "localCalendarDay") as? String,
            let valueString = object.value(forKey: "value") as? String,
            let enteredUnit = object.value(forKey: "enteredUnit") as? String,
            let createdAtUTC = object.value(forKey: "createdAtUTC") as? Date,
            let updatedAtUTC = object.value(forKey: "updatedAtUTC") as? Date
        else {
            throw DomainError.incompatibleInput
        }
        return try BodyMeasurement(
            id: StableUUID(rawID),
            studentID: StableUUID(rawStudentID),
            metricID: StableUUID(rawMetricID),
            localCalendarDay: try LocalDate(canonicalString: dayString),
            value: try DecimalValue(valueString),
            enteredUnit: enteredUnit,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC
        )
    }

    static func fetchMeasurement(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: measurementEntityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// Fetch-by-key for the `(studentID, metricID, localCalendarDay)` upsert
    /// idiom (mirrors `CoursePackageManagedObjectMapping.fetchAdjustment`'s
    /// fetch-by-`sourceEventKey`).
    static func fetchMeasurement(
        studentID: UUID,
        metricID: UUID,
        localCalendarDay: String,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: measurementEntityName)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND metricID == %@ AND localCalendarDay == %@",
            studentID as CVarArg,
            metricID as CVarArg,
            localCalendarDay
        )
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func fetchMeasurements(
        studentID: UUID,
        metricID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: measurementEntityName)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND metricID == %@", studentID as CVarArg, metricID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "localCalendarDay", ascending: true)]
        return try context.fetch(request)
    }

    static func countMeasurements(metricID: UUID, in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: measurementEntityName)
        request.predicate = NSPredicate(format: "metricID == %@", metricID as CVarArg)
        return try context.count(for: request)
    }
}
