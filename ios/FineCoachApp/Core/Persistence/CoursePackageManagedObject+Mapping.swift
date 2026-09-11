import CoreData
import Foundation

enum CoursePackageManagedObjectMapping {
    static let entityName = "CoursePackageMO"
    static let claimEntityName = "ActiveCoursePackageClaimMO"

    static func apply(_ package: CoursePackage, to object: NSManagedObject) {
        object.setValue(package.id.rawValue, forKey: "id")
        object.setValue(package.studentID.rawValue, forKey: "studentID")
        object.setValue(package.name?.value, forKey: "name")
        object.setValue(Int32(package.totalCredits), forKey: "totalCredits")
        object.setValue(Int32(package.remainingCreditsCache), forKey: "remainingCredits")
        object.setValue(package.startDate?.canonicalString, forKey: "startDate")
        object.setValue(package.endDate?.canonicalString, forKey: "endDate")
        object.setValue(package.status.rawValue, forKey: "status")
        object.setValue(package.createdAtUTC, forKey: "createdAtUTC")
        object.setValue(package.updatedAtUTC, forKey: "updatedAtUTC")
    }

    static func makePackage(from object: NSManagedObject) throws -> CoursePackage {
        guard let rawID = object.value(forKey: "id") as? UUID,
            let studentID = object.value(forKey: "studentID") as? UUID,
            let totalCredits = object.value(forKey: "totalCredits") as? Int32,
            let remainingCredits = object.value(forKey: "remainingCredits") as? Int32,
            let statusRaw = object.value(forKey: "status") as? String,
            let status = CoursePackageStatus(rawValue: statusRaw),
            let createdAtUTC = object.value(forKey: "createdAtUTC") as? Date,
            let updatedAtUTC = object.value(forKey: "updatedAtUTC") as? Date
        else {
            throw DomainError.incompatibleInput
        }
        let name = try (object.value(forKey: "name") as? String).map { try ValidatedText($0, allowEmpty: true) }
        let startDate = try (object.value(forKey: "startDate") as? String).map { try LocalDate(canonicalString: $0) }
        let endDate = try (object.value(forKey: "endDate") as? String).map { try LocalDate(canonicalString: $0) }

        return try CoursePackage(
            id: StableUUID(rawID),
            studentID: StableUUID(studentID),
            name: name,
            totalCredits: Int(totalCredits),
            remainingCreditsCache: Int(remainingCredits),
            startDate: startDate,
            endDate: endDate,
            status: status,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC
        )
    }

    static func fetchPackage(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func requirePackage(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject {
        guard let object = try fetchPackage(id: id, in: context) else {
            throw DomainError.notFound
        }
        return object
    }

    static func fetchPackages(studentID: UUID, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "studentID == %@", studentID as CVarArg)
        request.sortDescriptors = [
            NSSortDescriptor(key: "createdAtUTC", ascending: false)
        ]
        return try context.fetch(request)
    }

    // MARK: - Active-package uniqueness claim (mirrors ExerciseNameClaim, T023)

    static func fetchActiveClaim(studentID: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: claimEntityName)
        request.predicate = NSPredicate(format: "studentID == %@", studentID as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func insertClaim(studentID: UUID, packageID: UUID, in context: NSManagedObjectContext) {
        let object = NSEntityDescription.insertNewObject(forEntityName: claimEntityName, into: context)
        object.setValue(studentID, forKey: "studentID")
        object.setValue(packageID, forKey: "packageID")
    }

    // MARK: - CreditAdjustment ledger (data-model §2.4)

    static let adjustmentEntityName = "CreditAdjustmentMO"

    static func apply(_ adjustment: CreditAdjustment, to object: NSManagedObject) {
        object.setValue(adjustment.id.rawValue, forKey: "id")
        object.setValue(adjustment.packageID.rawValue, forKey: "packageID")
        object.setValue(adjustment.direction.rawValue, forKey: "direction")
        object.setValue(Int32(adjustment.amount), forKey: "amount")
        object.setValue(adjustment.reasonKind.rawValue, forKey: "reasonKind")
        object.setValue(adjustment.reasonText?.value, forKey: "reasonText")
        object.setValue(adjustment.linkedSessionID?.rawValue, forKey: "linkedSessionID")
        object.setValue(adjustment.linkedAppointmentID?.rawValue, forKey: "linkedAppointmentID")
        object.setValue(adjustment.sourceEventKey, forKey: "sourceEventKey")
        object.setValue(adjustment.createdAtUTC, forKey: "createdAtUTC")
    }

    static func makeAdjustment(from object: NSManagedObject) throws -> CreditAdjustment {
        guard let rawID = object.value(forKey: "id") as? UUID,
            let packageID = object.value(forKey: "packageID") as? UUID,
            let directionRaw = object.value(forKey: "direction") as? String,
            let direction = CreditDirection(rawValue: directionRaw),
            let amount = object.value(forKey: "amount") as? Int32,
            let reasonKindRaw = object.value(forKey: "reasonKind") as? String,
            let reasonKind = CreditReasonKind(rawValue: reasonKindRaw),
            let sourceEventKey = object.value(forKey: "sourceEventKey") as? String,
            let createdAtUTC = object.value(forKey: "createdAtUTC") as? Date
        else {
            throw DomainError.incompatibleInput
        }
        let reasonText = try (object.value(forKey: "reasonText") as? String).map {
            try ValidatedText($0, allowEmpty: true)
        }
        let linkedSessionID = (object.value(forKey: "linkedSessionID") as? UUID).map { StableUUID($0) }
        let linkedAppointmentID = (object.value(forKey: "linkedAppointmentID") as? UUID).map { StableUUID($0) }

        return try CreditAdjustment(
            id: StableUUID(rawID),
            packageID: StableUUID(packageID),
            direction: direction,
            amount: Int(amount),
            reasonKind: reasonKind,
            reasonText: reasonText,
            linkedSessionID: linkedSessionID,
            linkedAppointmentID: linkedAppointmentID,
            sourceEventKey: sourceEventKey,
            createdAtUTC: createdAtUTC
        )
    }

    static func fetchAdjustment(sourceEventKey: String, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: adjustmentEntityName)
        request.predicate = NSPredicate(format: "sourceEventKey == %@", sourceEventKey)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func fetchAdjustments(packageID: UUID, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: adjustmentEntityName)
        request.predicate = NSPredicate(format: "packageID == %@", packageID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAtUTC", ascending: true)]
        return try context.fetch(request)
    }
}
