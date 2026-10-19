import CoreData
import Foundation

enum HistoryReportManagedObjectMapping {
    static let reportEntityName = "ShareReportMO"
    static let sessionEntityName = "SessionMO"

    static func apply(_ report: ShareReport, modules: ShareReportModuleSelection?, to object: NSManagedObject) {
        object.setValue(report.id.rawValue, forKey: "id")
        object.setValue(report.sessionID.rawValue, forKey: "sessionID")
        object.setValue(Int64(report.generatedForRevision), forKey: "generatedForRevision")
        object.setValue(report.freshness.rawValue, forKey: "freshness")
        object.setValue(report.createdAtUTC, forKey: "createdAtUTC")
        object.setValue(report.handedToSystemAtUTC, forKey: "handedToSystemAtUTC")
        object.setValue(encodeModules(modules), forKey: "selectedModules")
    }

    static func makeReport(from object: NSManagedObject) throws -> ShareReport {
        guard let rawID = object.value(forKey: "id") as? UUID,
            let sessionID = object.value(forKey: "sessionID") as? UUID
        else {
            throw DomainError.incompatibleInput
        }
        guard let freshnessRaw = object.value(forKey: "freshness") as? String,
            let freshness = ShareReportFreshness(rawValue: freshnessRaw)
        else {
            throw DomainError.incompatibleInput
        }
        guard let createdAtUTC = object.value(forKey: "createdAtUTC") as? Date else {
            throw DomainError.incompatibleInput
        }
        let revision = object.value(forKey: "generatedForRevision") as? Int64 ?? 0
        return ShareReport(
            id: StableUUID(rawID),
            sessionID: StableUUID(sessionID),
            generatedForRevision: UInt64(max(0, revision)),
            freshness: freshness,
            createdAtUTC: createdAtUTC,
            handedToSystemAtUTC: object.value(forKey: "handedToSystemAtUTC") as? Date
        )
    }

    static func fetchReport(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: reportEntityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func reports(sessionID: UUID, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: reportEntityName)
        request.predicate = NSPredicate(format: "sessionID == %@", sessionID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAtUTC", ascending: false)]
        return try context.fetch(request)
    }

    static func latestReport(sessionID: UUID, in context: NSManagedObjectContext) throws -> ShareReport? {
        let objects = try reports(sessionID: sessionID, in: context)
        let mapped = try objects.map { try makeReport(from: $0) }
        if let current = mapped.first(where: { $0.freshness == .current }) {
            return current
        }
        return mapped.first
    }

    static func markCurrentReportsStale(sessionID: UUID, in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: reportEntityName)
        request.predicate = NSPredicate(
            format: "sessionID == %@ AND freshness == %@",
            sessionID as CVarArg,
            ShareReportFreshness.current.rawValue
        )
        for object in try context.fetch(request) {
            let stale = try makeReport(from: object).markingStale()
            apply(stale, modules: decodeModules(object.value(forKey: "selectedModules") as? Data), to: object)
        }
    }

    static func upsertReport(
        _ report: ShareReport,
        modules: ShareReportModuleSelection?,
        in context: NSManagedObjectContext
    ) throws -> ShareReport {
        let sessionObject = try SessionManagedObjectMapping.requireSession(id: report.sessionID.rawValue, in: context)
        if report.freshness == .current {
            try markCurrentReportsStale(sessionID: report.sessionID.rawValue, in: context)
        }
        let object =
            try fetchReport(id: report.id.rawValue, in: context)
            ?? NSEntityDescription.insertNewObject(forEntityName: reportEntityName, into: context)
        apply(report, modules: modules, to: object)
        object.setValue(sessionObject, forKey: "session")
        return try makeReport(from: object)
    }

    static func updateReport(_ report: ShareReport, in context: NSManagedObjectContext) throws -> ShareReport {
        guard let object = try fetchReport(id: report.id.rawValue, in: context) else {
            throw DomainError.notFound
        }
        apply(
            report,
            modules: decodeModules(object.value(forKey: "selectedModules") as? Data),
            to: object
        )
        return try makeReport(from: object)
    }

    static func completedSessionIDs(studentID: UUID, in context: NSManagedObjectContext) throws -> [UUID] {
        let request = NSFetchRequest<NSManagedObject>(entityName: sessionEntityName)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND state == %@",
            studentID as CVarArg,
            SessionState.completed.rawValue
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: "completedAtUTC", ascending: false),
            NSSortDescriptor(key: "startedAtUTC", ascending: false),
        ]
        return try context.fetch(request).compactMap { $0.value(forKey: "id") as? UUID }
    }

    static func completedSessionIDs(in context: NSManagedObjectContext) throws -> [UUID] {
        let request = NSFetchRequest<NSManagedObject>(entityName: sessionEntityName)
        request.predicate = NSPredicate(format: "state == %@", SessionState.completed.rawValue)
        request.sortDescriptors = [
            NSSortDescriptor(key: "completedAtUTC", ascending: false),
            NSSortDescriptor(key: "startedAtUTC", ascending: false),
        ]
        return try context.fetch(request).compactMap { $0.value(forKey: "id") as? UUID }
    }

    static func loadCompletedSession(id: UUID, in context: NSManagedObjectContext) throws -> CompletedSession {
        let sessionObject = try SessionManagedObjectMapping.requireSession(id: id, in: context)
        let session = try SessionManagedObjectMapping.loadAggregate(from: sessionObject, in: context)
        guard session.state == .completed else {
            throw DomainError.invalidState
        }
        let student = try StudentManagedObjectMapping.requireStudent(id: session.studentID.rawValue, in: context)
        guard let displayName = student.value(forKey: "displayName") as? String else {
            throw DomainError.incompatibleInput
        }
        let completed = try CompletedSession.make(
            from: session,
            studentDisplayName: NormalizedName(displayName)
        )
        let report = try latestReport(sessionID: id, in: context)
        return completed.attaching(latestReport: report)
    }

    private static func encodeModules(_ modules: ShareReportModuleSelection?) -> Data? {
        guard let modules else {
            return nil
        }
        return try? JSONEncoder().encode(modules)
    }

    private static func decodeModules(_ data: Data?) -> ShareReportModuleSelection? {
        guard let data else {
            return nil
        }
        return try? JSONDecoder().decode(ShareReportModuleSelection.self, from: data)
    }
}
