import CoreData
import Foundation

enum AppointmentManagedObjectMapping {
    static let entityName = "AppointmentMO"

    static func apply(_ appointment: Appointment, to object: NSManagedObject) {
        object.setValue(appointment.id.rawValue, forKey: "id")
        object.setValue(appointment.studentID.rawValue, forKey: "studentID")
        object.setValue(appointment.seriesID?.rawValue, forKey: "seriesID")
        object.setValue(appointment.date.canonicalString, forKey: "date")
        object.setValue(appointment.startTime.canonicalString, forKey: "startTime")
        object.setValue(Int32(appointment.durationMinutes), forKey: "durationMinutes")
        object.setValue(appointment.status.rawValue, forKey: "status")
        object.setValue(appointment.absentCreditChoice?.rawValue, forKey: "absentCreditChoice")
        object.setValue(appointment.cancellationReason?.value, forKey: "cancellationReason")
        object.setValue(appointment.isDetachedException, forKey: "isDetachedException")
        object.setValue(appointment.reminderEnabled, forKey: "reminderEnabled")
        object.setValue(
            appointment.reminderLeadMinutes.map { Int32($0.rawValue) },
            forKey: "reminderLeadMinutes"
        )
        object.setValue(appointment.linkedSessionID?.rawValue, forKey: "linkedSessionID")
        object.setValue(BodyPartCoding.mask(appointment.trainingFocus), forKey: "trainingFocusMask")
        object.setValue(appointment.createdAtUTC, forKey: "createdAtUTC")
        object.setValue(appointment.updatedAtUTC, forKey: "updatedAtUTC")
    }

    static func makeAppointment(from object: NSManagedObject) throws -> Appointment {
        guard let rawID = object.value(forKey: "id") as? UUID,
            let studentID = object.value(forKey: "studentID") as? UUID,
            let dateString = object.value(forKey: "date") as? String,
            let startTimeString = object.value(forKey: "startTime") as? String,
            let durationMinutes = object.value(forKey: "durationMinutes") as? Int32,
            let statusRaw = object.value(forKey: "status") as? String,
            let status = AppointmentStatus(rawValue: statusRaw),
            let isDetachedException = object.value(forKey: "isDetachedException") as? Bool,
            let reminderEnabled = object.value(forKey: "reminderEnabled") as? Bool,
            let createdAtUTC = object.value(forKey: "createdAtUTC") as? Date,
            let updatedAtUTC = object.value(forKey: "updatedAtUTC") as? Date
        else {
            throw DomainError.incompatibleInput
        }

        let seriesID = (object.value(forKey: "seriesID") as? UUID).map { StableUUID($0) }
        let absentCreditChoice = (object.value(forKey: "absentCreditChoice") as? String)
            .flatMap(AbsentCreditChoice.init(rawValue:))
        let cancellationReason = try (object.value(forKey: "cancellationReason") as? String)
            .map { try ValidatedText($0, allowEmpty: true) }
        let reminderLeadMinutes = (object.value(forKey: "reminderLeadMinutes") as? Int32)
            .flatMap { ReminderLeadMinutes(rawValue: Int($0)) }
        let linkedSessionID = (object.value(forKey: "linkedSessionID") as? UUID).map { StableUUID($0) }
        let trainingFocus = BodyPartCoding.parts(fromMask: object.value(forKey: "trainingFocusMask") as? Int32 ?? 0)

        return try Appointment(
            id: StableUUID(rawID),
            studentID: StableUUID(studentID),
            seriesID: seriesID,
            date: try LocalDate(canonicalString: dateString),
            startTime: try LocalTime(canonicalString: startTimeString),
            durationMinutes: Int(durationMinutes),
            status: status,
            absentCreditChoice: absentCreditChoice,
            cancellationReason: cancellationReason,
            isDetachedException: isDetachedException,
            reminderEnabled: reminderEnabled,
            reminderLeadMinutes: reminderLeadMinutes,
            linkedSessionID: linkedSessionID,
            trainingFocus: trainingFocus,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC
        )
    }

    static func fetchAppointment(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func requireAppointment(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject {
        guard let object = try fetchAppointment(id: id, in: context) else {
            throw DomainError.notFound
        }
        return object
    }

    /// Every scheduled/in-progress appointment (any student), used for overlap
    /// conflict checks (M1B-FR-006) -- overlap is coach-wide, not per-student.
    static func fetchActiveAppointments(
        excludingID: UUID?,
        in context: NSManagedObjectContext
    ) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        var predicates = [NSPredicate(format: "status IN %@", ["scheduled", "inProgress"])]
        if let excludingID {
            predicates.append(NSPredicate(format: "id != %@", excludingID as CVarArg))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return try context.fetch(request)
    }

    static func fetchAppointments(
        studentID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "studentID == %@", studentID as CVarArg)
        request.sortDescriptors = [
            NSSortDescriptor(key: "date", ascending: true),
            NSSortDescriptor(key: "startTime", ascending: true),
        ]
        return try context.fetch(request)
    }

    static func fetchAppointments(
        seriesID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "seriesID == %@", seriesID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        return try context.fetch(request)
    }

    /// All appointments touching the local calendar-day window [dayStart, nextDayStart)
    /// -- callers pass canonical LocalDate strings so this stays timezone-agnostic here;
    /// the actual local-day boundary is computed by the caller via the injected calendar.
    static func fetchAppointments(
        dateStrings: [String],
        in context: NSManagedObjectContext
    ) throws -> [NSManagedObject] {
        guard !dateStrings.isEmpty else {
            return []
        }
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "date IN %@", dateStrings)
        request.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: true)]
        return try context.fetch(request)
    }
}
