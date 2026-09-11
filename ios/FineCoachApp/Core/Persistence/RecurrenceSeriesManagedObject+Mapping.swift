import CoreData
import Foundation

enum RecurrenceSeriesManagedObjectMapping {
    static let entityName = "RecurrenceSeriesMO"

    static func weekdaysMask(_ weekdays: Set<Weekday>) -> Int32 {
        weekdays.reduce(into: Int32(0)) { mask, day in
            mask |= Int32(1 << (day.rawValue - 1))
        }
    }

    static func weekdays(fromMask mask: Int32) -> Set<Weekday> {
        Set(Weekday.allCases.filter { mask & Int32(1 << ($0.rawValue - 1)) != 0 })
    }

    static func apply(_ series: RecurrenceSeries, to object: NSManagedObject) {
        object.setValue(series.id.rawValue, forKey: "id")
        object.setValue(series.studentID.rawValue, forKey: "studentID")
        object.setValue(weekdaysMask(series.weekdays), forKey: "weekdaysMask")
        switch series.termination {
        case .endDate(let date):
            object.setValue("endDate", forKey: "terminationKind")
            object.setValue(date.canonicalString, forKey: "endDate")
            object.setValue(nil, forKey: "repeatCount")
        case .repeatCount(let count):
            object.setValue("repeatCount", forKey: "terminationKind")
            object.setValue(nil, forKey: "endDate")
            object.setValue(Int32(count), forKey: "repeatCount")
        }
        object.setValue(series.defaultStartTime.canonicalString, forKey: "defaultStartTime")
        object.setValue(Int32(series.defaultDurationMinutes), forKey: "defaultDurationMinutes")
        object.setValue(series.defaultReminderEnabled, forKey: "defaultReminderEnabled")
        object.setValue(
            series.defaultReminderLeadMinutes.map { Int32($0.rawValue) },
            forKey: "defaultReminderLeadMinutes"
        )
        object.setValue(series.status.rawValue, forKey: "status")
        object.setValue(series.createdAtUTC, forKey: "createdAtUTC")
        object.setValue(series.updatedAtUTC, forKey: "updatedAtUTC")
    }

    static func makeSeries(from object: NSManagedObject) throws -> RecurrenceSeries {
        guard let rawID = object.value(forKey: "id") as? UUID,
            let studentID = object.value(forKey: "studentID") as? UUID,
            let mask = object.value(forKey: "weekdaysMask") as? Int32,
            let terminationKind = object.value(forKey: "terminationKind") as? String,
            let startTimeString = object.value(forKey: "defaultStartTime") as? String,
            let durationMinutes = object.value(forKey: "defaultDurationMinutes") as? Int32,
            let reminderEnabled = object.value(forKey: "defaultReminderEnabled") as? Bool,
            let statusRaw = object.value(forKey: "status") as? String,
            let status = RecurrenceSeriesStatus(rawValue: statusRaw),
            let createdAtUTC = object.value(forKey: "createdAtUTC") as? Date,
            let updatedAtUTC = object.value(forKey: "updatedAtUTC") as? Date
        else {
            throw DomainError.incompatibleInput
        }

        let termination: RecurrenceTermination
        switch terminationKind {
        case "endDate":
            guard let endDateString = object.value(forKey: "endDate") as? String else {
                throw DomainError.incompatibleInput
            }
            termination = .endDate(try LocalDate(canonicalString: endDateString))
        case "repeatCount":
            guard let repeatCount = object.value(forKey: "repeatCount") as? Int32 else {
                throw DomainError.incompatibleInput
            }
            termination = .repeatCount(Int(repeatCount))
        default:
            throw DomainError.incompatibleInput
        }

        let leadMinutes = (object.value(forKey: "defaultReminderLeadMinutes") as? Int32)
            .flatMap { ReminderLeadMinutes(rawValue: Int($0)) }

        return try RecurrenceSeries(
            id: StableUUID(rawID),
            studentID: StableUUID(studentID),
            weekdays: weekdays(fromMask: mask),
            termination: termination,
            defaultStartTime: try LocalTime(canonicalString: startTimeString),
            defaultDurationMinutes: Int(durationMinutes),
            defaultReminderEnabled: reminderEnabled,
            defaultReminderLeadMinutes: leadMinutes,
            status: status,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC
        )
    }

    static func fetchSeries(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func requireSeries(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject {
        guard let object = try fetchSeries(id: id, in: context) else {
            throw DomainError.notFound
        }
        return object
    }
}
