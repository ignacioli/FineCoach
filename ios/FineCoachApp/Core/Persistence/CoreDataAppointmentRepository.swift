import CoreData
import Foundation

public struct CoreDataAppointmentRepository: Sendable {
    private let writer: PersistenceWriter

    public init(writer: PersistenceWriter) {
        self.writer = writer
    }

    public func create(_ appointment: Appointment) async throws -> Appointment {
        try await writer.transaction { context in
            if try AppointmentManagedObjectMapping.fetchAppointment(id: appointment.id.rawValue, in: context) != nil {
                throw DomainError.conflict
            }
            let object = NSEntityDescription.insertNewObject(
                forEntityName: AppointmentManagedObjectMapping.entityName,
                into: context
            )
            AppointmentManagedObjectMapping.apply(appointment, to: object)
            return try AppointmentManagedObjectMapping.makeAppointment(from: object)
        }
    }

    /// Inserts a RecurrenceSeries and all of its materialized Appointments in a
    /// single writer transaction, so a partially-materialized series can never
    /// be observed (plan §5: single-writer, no bypass write path).
    public func createSeries(series: RecurrenceSeries, appointments: [Appointment]) async throws {
        try await writer.transaction { context in
            if try RecurrenceSeriesManagedObjectMapping.fetchSeries(id: series.id.rawValue, in: context) != nil {
                throw DomainError.conflict
            }
            let seriesObject = NSEntityDescription.insertNewObject(
                forEntityName: RecurrenceSeriesManagedObjectMapping.entityName,
                into: context
            )
            RecurrenceSeriesManagedObjectMapping.apply(series, to: seriesObject)

            for appointment in appointments {
                let object = NSEntityDescription.insertNewObject(
                    forEntityName: AppointmentManagedObjectMapping.entityName,
                    into: context
                )
                AppointmentManagedObjectMapping.apply(appointment, to: object)
            }
        }
    }

    public func update(_ appointment: Appointment) async throws -> Appointment {
        try await writer.transaction { context in
            let object = try AppointmentManagedObjectMapping.requireAppointment(
                id: appointment.id.rawValue,
                in: context
            )
            AppointmentManagedObjectMapping.apply(appointment, to: object)
            return try AppointmentManagedObjectMapping.makeAppointment(from: object)
        }
    }

    public func appointment(id: StableUUID) async throws -> Appointment {
        try await writer.read { context in
            let object = try AppointmentManagedObjectMapping.requireAppointment(id: id.rawValue, in: context)
            return try AppointmentManagedObjectMapping.makeAppointment(from: object)
        }
    }

    /// Permanent delete, gated on the domain-level "never-started future
    /// misclick" boundary (M1B-FR-008) evaluated against `now`/`calendar` at
    /// transaction time, not a stale read -- mirrors StudentDeletionPolicy's
    /// enforce-inside-the-transaction pattern.
    public func delete(id: StableUUID, now: Date, calendar: Calendar) async throws {
        try await writer.transaction { context in
            let object = try AppointmentManagedObjectMapping.requireAppointment(id: id.rawValue, in: context)
            let appointment = try AppointmentManagedObjectMapping.makeAppointment(from: object)
            guard appointment.canPermanentlyDelete(now: now, calendar: calendar) else {
                throw DomainError.invalidState
            }
            context.delete(object)
        }
    }

    public func activeAppointments(excluding excludedID: StableUUID?) async throws -> [Appointment] {
        try await writer.read { context in
            try AppointmentManagedObjectMapping.fetchActiveAppointments(
                excludingID: excludedID?.rawValue,
                in: context
            )
            .map { try AppointmentManagedObjectMapping.makeAppointment(from: $0) }
        }
    }

    public func appointments(studentID: StableUUID) async throws -> [Appointment] {
        try await writer.read { context in
            try AppointmentManagedObjectMapping.fetchAppointments(studentID: studentID.rawValue, in: context)
                .map { try AppointmentManagedObjectMapping.makeAppointment(from: $0) }
        }
    }

    public func appointments(seriesID: StableUUID) async throws -> [Appointment] {
        try await writer.read { context in
            try AppointmentManagedObjectMapping.fetchAppointments(seriesID: seriesID.rawValue, in: context)
                .map { try AppointmentManagedObjectMapping.makeAppointment(from: $0) }
        }
    }

    public func appointments(localDates: [LocalDate]) async throws -> [Appointment] {
        let dateStrings = localDates.map(\.canonicalString)
        return try await writer.read { context in
            try AppointmentManagedObjectMapping.fetchAppointments(dateStrings: dateStrings, in: context)
                .map { try AppointmentManagedObjectMapping.makeAppointment(from: $0) }
        }
    }

    public func series(id: StableUUID) async throws -> RecurrenceSeries {
        try await writer.read { context in
            let object = try RecurrenceSeriesManagedObjectMapping.requireSeries(id: id.rawValue, in: context)
            return try RecurrenceSeriesManagedObjectMapping.makeSeries(from: object)
        }
    }

    public func updateSeries(_ series: RecurrenceSeries) async throws -> RecurrenceSeries {
        try await writer.transaction { context in
            let object = try RecurrenceSeriesManagedObjectMapping.requireSeries(id: series.id.rawValue, in: context)
            RecurrenceSeriesManagedObjectMapping.apply(series, to: object)
            return try RecurrenceSeriesManagedObjectMapping.makeSeries(from: object)
        }
    }

    /// Truncates the current series ("本次及以后" boundary, spec D-011) and
    /// inserts the replacement series + its materialized appointments, in one
    /// transaction so the two never disagree on disk.
    public func truncateAndReplaceSeries(
        endedSeries: RecurrenceSeries,
        supersededAppointmentIDs: [StableUUID],
        newSeries: RecurrenceSeries,
        newAppointments: [Appointment]
    ) async throws {
        try await writer.transaction { context in
            let endedObject = try RecurrenceSeriesManagedObjectMapping.requireSeries(
                id: endedSeries.id.rawValue,
                in: context
            )
            RecurrenceSeriesManagedObjectMapping.apply(endedSeries, to: endedObject)

            for supersededID in supersededAppointmentIDs {
                if let object = try AppointmentManagedObjectMapping.fetchAppointment(
                    id: supersededID.rawValue,
                    in: context
                ) {
                    context.delete(object)
                }
            }

            let newSeriesObject = NSEntityDescription.insertNewObject(
                forEntityName: RecurrenceSeriesManagedObjectMapping.entityName,
                into: context
            )
            RecurrenceSeriesManagedObjectMapping.apply(newSeries, to: newSeriesObject)

            for appointment in newAppointments {
                let object = NSEntityDescription.insertNewObject(
                    forEntityName: AppointmentManagedObjectMapping.entityName,
                    into: context
                )
                AppointmentManagedObjectMapping.apply(appointment, to: object)
            }
        }
    }
}
