import CoreData
import Foundation

enum StudentManagedObjectMapping {
    static let entityName = "StudentMO"
    static let sessionEntityName = "SessionMO"
    static let settingEntityName = "AppSettingMO"
    static let onboardingCompletedKey = "onboarding.completed"
    /// M2 archive identity setting keys (data-model §3). Values never reach logs or UI.
    static let archiveSourceIDKey = "archive.sourceID"
    static let archiveStudentIDKeyPrefix = "archive.studentID."

    static func archiveStudentIDKey(for studentID: UUID) -> String {
        archiveStudentIDKeyPrefix + studentID.uuidString
    }

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

    /// Every Student's in-progress Session, oldest start first (M1A-FR-018
    /// revision: more than one Student may be training at the same time).
    static func inProgressSessions(in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: sessionEntityName)
        request.predicate = NSPredicate(format: "state == %@", "inProgress")
        request.sortDescriptors = [
            NSSortDescriptor(key: "startedAtUTC", ascending: true),
            NSSortDescriptor(key: "id", ascending: true),
        ]
        return try context.fetch(request)
    }

    static func inProgressSession(studentID: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: sessionEntityName)
        request.predicate = NSPredicate(format: "studentID == %@ AND state == %@", studentID as CVarArg, "inProgress")
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// Compatibility for the single-session call sites and tests.
    static func inProgressSession(in context: NSManagedObjectContext) throws -> NSManagedObject? {
        try inProgressSessions(in: context).first
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
        _ = try SessionManagedObjectMapping.upsertAggregate(
            Session.start(
                id: StableUUID(sessionID),
                studentID: StableUUID(studentID),
                now: now
            ),
            in: context
        )
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
        session.setValue(NSDecimalNumber(decimal: 1800), forKey: "elapsedSeconds")
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

    static func fetchSetting(key: String, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: settingEntityName)
        request.predicate = NSPredicate(format: "key == %@", key)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func settingValue(key: String, in context: NSManagedObjectContext) throws -> String? {
        try fetchSetting(key: key, in: context)?.value(forKey: "typedValue") as? String
    }

    /// Inserts or updates one `AppSettingMO` row through the existing setting mechanism.
    static func writeSetting(key: String, value: String, in context: NSManagedObjectContext) throws {
        let object =
            try fetchSetting(key: key, in: context)
            ?? NSEntityDescription.insertNewObject(forEntityName: settingEntityName, into: context)
        object.setValue(key, forKey: "key")
        object.setValue(value, forKey: "typedValue")
        object.setValue(Int64(1), forKey: "schemaVersion")
    }

    static func removeSetting(key: String, in context: NSManagedObjectContext) throws {
        if let object = try fetchSetting(key: key, in: context) {
            context.delete(object)
        }
    }

    /// Every `(key, typedValue)` whose key starts with `prefix`, in key order.
    static func settings(withKeyPrefix prefix: String, in context: NSManagedObjectContext) throws -> [(
        key: String, value: String
    )] {
        let request = NSFetchRequest<NSManagedObject>(entityName: settingEntityName)
        request.predicate = NSPredicate(format: "key BEGINSWITH %@", prefix)
        return try context.fetch(request).compactMap { object in
            guard let key = object.value(forKey: "key") as? String,
                let value = object.value(forKey: "typedValue") as? String
            else {
                return nil
            }
            return (key, value)
        }
        .sorted { $0.key < $1.key }
    }

    private static func optionalStoredText(_ rawValue: String?) throws -> ValidatedText? {
        guard let rawValue else {
            return nil
        }
        return try Student.optionalText(rawValue)
    }
}
