import CoreData
import Foundation

enum StudentManagedObjectMapping {
    static let entityName = "StudentMO"
    static let sessionEntityName = "SessionMO"
    static let settingEntityName = "AppSettingMO"
    static let onboardingCompletedKey = "onboarding.completed"

    static func apply(_ student: Student, to object: NSManagedObject) {
        object.setValue(student.id.rawValue, forKey: "id")
        object.setValue(student.displayName.value, forKey: "displayName")
        object.setValue(student.sex.rawValue, forKey: "sex")
        object.setValue(student.trainingGoal?.value, forKey: "trainingGoal")
        object.setValue(student.injuryNotes?.value, forKey: "injuryNotes")
        object.setValue(student.privateCoachNote?.value, forKey: "privateCoachNote")
        object.setValue(student.phone?.value, forKey: "phone")
        object.setValue(student.wechatID?.value, forKey: "wechatID")
        object.setValue(student.lifecycle.rawValue, forKey: "lifecycle")
        object.setValue(student.createdAtUTC, forKey: "createdAtUTC")
        object.setValue(student.updatedAtUTC, forKey: "updatedAtUTC")
    }

    static func makeStudent(from object: NSManagedObject) throws -> Student {
        guard let rawID = object.value(forKey: "id") as? UUID else {
            throw DomainError.incompatibleInput
        }
        guard let displayName = object.value(forKey: "displayName") as? String else {
            throw DomainError.incompatibleInput
        }
        guard let sexRaw = object.value(forKey: "sex") as? String,
            let sex = StudentSex(rawValue: sexRaw)
        else {
            throw DomainError.incompatibleInput
        }
        guard let lifecycleRaw = object.value(forKey: "lifecycle") as? String,
            let lifecycle = StudentLifecycle(rawValue: lifecycleRaw)
        else {
            throw DomainError.incompatibleInput
        }
        guard let createdAtUTC = object.value(forKey: "createdAtUTC") as? Date,
            let updatedAtUTC = object.value(forKey: "updatedAtUTC") as? Date
        else {
            throw DomainError.incompatibleInput
        }

        return try Student(
            id: StableUUID(rawID),
            displayName: NormalizedName(displayName),
            sex: sex,
            trainingGoal: try optionalStoredText(object.value(forKey: "trainingGoal") as? String),
            injuryNotes: try optionalStoredText(object.value(forKey: "injuryNotes") as? String),
            privateCoachNote: try optionalStoredText(object.value(forKey: "privateCoachNote") as? String),
            phone: try optionalStoredText(object.value(forKey: "phone") as? String),
            wechatID: try optionalStoredText(object.value(forKey: "wechatID") as? String),
            lifecycle: lifecycle,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC
        )
    }

    static func fetchStudent(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func requireStudent(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject {
        guard let object = try fetchStudent(id: id, in: context) else {
            throw DomainError.notFound
        }
        return object
    }

    static func hasInProgressSession(studentID: UUID, in context: NSManagedObjectContext) throws -> Bool {
        let request = NSFetchRequest<NSManagedObject>(entityName: sessionEntityName)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND state == %@",
            studentID as CVarArg,
            "inProgress"
        )
        request.fetchLimit = 1
        return try context.count(for: request) > 0
    }

    static func hasGlobalInProgressSession(in context: NSManagedObjectContext) throws -> Bool {
        let request = NSFetchRequest<NSManagedObject>(entityName: sessionEntityName)
        request.predicate = NSPredicate(format: "state == %@", "inProgress")
        request.fetchLimit = 1
        return try context.count(for: request) > 0
    }

    static func inProgressSession(in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: sessionEntityName)
        request.predicate = NSPredicate(format: "state == %@", "inProgress")
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func sessionCount(studentID: UUID, in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: sessionEntityName)
        request.predicate = NSPredicate(format: "studentID == %@", studentID as CVarArg)
        return try context.count(for: request)
    }

    static func insertInProgressSession(
        studentID: UUID,
        sessionID: UUID,
        now: Date,
        into context: NSManagedObjectContext
    ) throws {
        let student = try requireStudent(id: studentID, in: context)
        let session = NSEntityDescription.insertNewObject(forEntityName: sessionEntityName, into: context)
        session.setValue(sessionID, forKey: "id")
        session.setValue(studentID, forKey: "studentID")
        session.setValue("inProgress", forKey: "state")
        session.setValue(now, forKey: "startedAtUTC")
        session.setValue(now, forKey: "lastCheckpointUTC")
        session.setValue(Decimal(0), forKey: "elapsedSeconds")
        session.setValue(false, forKey: "durationNeedsReview")
        session.setValue(Int64(1), forKey: "revision")
        session.setValue(now, forKey: "createdAtUTC")
        session.setValue(now, forKey: "updatedAtUTC")
        session.setValue(student, forKey: "student")
    }

    static func insertCompletedSession(
        studentID: UUID,
        sessionID: UUID,
        now: Date,
        into context: NSManagedObjectContext
    ) throws {
        let student = try requireStudent(id: studentID, in: context)
        let session = NSEntityDescription.insertNewObject(forEntityName: sessionEntityName, into: context)
        session.setValue(sessionID, forKey: "id")
        session.setValue(studentID, forKey: "studentID")
        session.setValue("completed", forKey: "state")
        session.setValue(now, forKey: "startedAtUTC")
        session.setValue(now, forKey: "lastCheckpointUTC")
        session.setValue(Decimal(1800), forKey: "elapsedSeconds")
        session.setValue(false, forKey: "durationNeedsReview")
        session.setValue(Int64(2), forKey: "revision")
        session.setValue(now, forKey: "createdAtUTC")
        session.setValue(now, forKey: "updatedAtUTC")
        session.setValue(now, forKey: "completedAtUTC")
        session.setValue(student, forKey: "student")
    }

    static func onboardingCompleted(in context: NSManagedObjectContext) throws -> Bool {
        let request = NSFetchRequest<NSManagedObject>(entityName: settingEntityName)
        request.predicate = NSPredicate(format: "key == %@", onboardingCompletedKey)
        request.fetchLimit = 1
        guard let object = try context.fetch(request).first else {
            return false
        }
        return (object.value(forKey: "typedValue") as? String) == "true"
    }

    static func setOnboardingCompleted(in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: settingEntityName)
        request.predicate = NSPredicate(format: "key == %@", onboardingCompletedKey)
        request.fetchLimit = 1
        let object =
            try context.fetch(request).first
            ?? NSEntityDescription.insertNewObject(forEntityName: settingEntityName, into: context)
        object.setValue(onboardingCompletedKey, forKey: "key")
        object.setValue("true", forKey: "typedValue")
        object.setValue(Int64(1), forKey: "schemaVersion")
    }

    private static func optionalStoredText(_ rawValue: String?) throws -> ValidatedText? {
        guard let rawValue else {
            return nil
        }
        return try Student.optionalText(rawValue)
    }
}
