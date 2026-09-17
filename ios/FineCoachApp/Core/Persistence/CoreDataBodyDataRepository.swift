import CoreData
import Foundation

/// Persistence for custom `BodyMetricDefinition`s and every `BodyMeasurement`
/// (data-model §2.8/§2.9, T038). The 8 built-in metrics are never persisted
/// here (see `BodyMetricManagedObjectMapping`) -- callers merge
/// `BuiltInBodyMetric.allDefinitions()` with `customMetrics(studentID:)`
/// results at the Application layer (`BodyDataUseCases`). All writes go
/// through the existing single serial `PersistenceWriter` -- no second write
/// path is introduced.
public struct CoreDataBodyDataRepository: Sendable {
    private let writer: PersistenceWriter

    public init(writer: PersistenceWriter) {
        self.writer = writer
    }

    // MARK: - Custom metric definitions

    /// Fetch-by-normalized-name, no-op-if-owned-by-same-metric idiom mirroring
    /// `ExerciseNameClaim`: throws `.conflict` if an ACTIVE custom metric with
    /// this name already exists for a DIFFERENT metric id, never silently
    /// renames.
    @discardableResult
    public func createCustomMetric(_ metric: BodyMetricDefinition) async throws -> BodyMetricDefinition {
        guard metric.kind == .custom, let studentID = metric.studentID else {
            throw DomainError.incompatibleInput
        }
        return try await writer.transaction { context in
            if let existing = try BodyMetricManagedObjectMapping.fetchMetricByNormalizedName(
                studentID: studentID.rawValue,
                normalizedName: metric.normalizedName,
                in: context
            ) {
                let existingMetric = try BodyMetricManagedObjectMapping.makeMetric(from: existing)
                if existingMetric.id == metric.id {
                    return existingMetric
                }
                if existingMetric.lifecycle == .active {
                    throw DomainError.conflict
                }
            }
            let object = NSEntityDescription.insertNewObject(
                forEntityName: BodyMetricManagedObjectMapping.metricEntityName,
                into: context
            )
            try BodyMetricManagedObjectMapping.apply(metric, to: object)
            return try BodyMetricManagedObjectMapping.makeMetric(from: object)
        }
    }

    @discardableResult
    public func updateCustomMetric(_ metric: BodyMetricDefinition) async throws -> BodyMetricDefinition {
        guard metric.kind == .custom, let studentID = metric.studentID else {
            throw DomainError.incompatibleInput
        }
        return try await writer.transaction { context in
            if let existing = try BodyMetricManagedObjectMapping.fetchMetricByNormalizedName(
                studentID: studentID.rawValue,
                normalizedName: metric.normalizedName,
                in: context
            ) {
                let existingMetric = try BodyMetricManagedObjectMapping.makeMetric(from: existing)
                if existingMetric.id != metric.id, existingMetric.lifecycle == .active {
                    throw DomainError.conflict
                }
            }
            let object = try BodyMetricManagedObjectMapping.requireMetric(id: metric.id.rawValue, in: context)
            try BodyMetricManagedObjectMapping.apply(metric, to: object)
            return try BodyMetricManagedObjectMapping.makeMetric(from: object)
        }
    }

    public func customMetrics(studentID: StableUUID) async throws -> [BodyMetricDefinition] {
        try await writer.read { context in
            try BodyMetricManagedObjectMapping.fetchMetrics(studentID: studentID.rawValue, in: context)
                .map { try BodyMetricManagedObjectMapping.makeMetric(from: $0) }
        }
    }

    public func customMetric(id: StableUUID) async throws -> BodyMetricDefinition {
        try await writer.read { context in
            try BodyMetricManagedObjectMapping.makeMetric(
                from: BodyMetricManagedObjectMapping.requireMetric(id: id.rawValue, in: context)
            )
        }
    }

    public func measurementCount(metricID: StableUUID) async throws -> Int {
        try await writer.read { context in
            try BodyMetricManagedObjectMapping.countMeasurements(metricID: metricID.rawValue, in: context)
        }
    }

    /// Permanently deletes the custom metric row. Callers MUST already hold a
    /// `BodyMetricDefinition.DeletionEligibility` token proving zero
    /// measurements exist (M1B-FR-023/D-009) -- this repository re-validates
    /// the count itself inside the SAME transaction as a backstop against a
    /// stale token (a measurement recorded between the count check and this
    /// call), never trusting the token alone.
    public func deleteCustomMetric(
        id: StableUUID,
        eligibility: BodyMetricDefinition.DeletionEligibility
    ) async throws {
        guard eligibility.authorizes(deletionOf: id) else {
            throw DomainError.invalidState
        }
        try await writer.transaction { context in
            let object = try BodyMetricManagedObjectMapping.requireMetric(id: id.rawValue, in: context)
            let count = try BodyMetricManagedObjectMapping.countMeasurements(metricID: id.rawValue, in: context)
            guard count == 0 else {
                throw DomainError.conflict
            }
            context.delete(object)
        }
    }

    // MARK: - Measurements (upsert-as-edit on (studentID, metricID, localCalendarDay))

    /// The single write path for every measurement entry, mirroring
    /// `recordIdempotentAdjustment`'s "fetch by key inside one transaction,
    /// edit in place if present, else insert" shape. Same-day re-entry always
    /// edits; it never creates a second row for the same key.
    public func recordMeasurement(
        studentID: StableUUID,
        metricID: StableUUID,
        localCalendarDay: LocalDate,
        value: DecimalValue,
        enteredUnit: String,
        newID: StableUUID,
        now: Date
    ) async throws -> BodyMeasurement {
        try await writer.transaction { context in
            if let existing = try BodyMetricManagedObjectMapping.fetchMeasurement(
                studentID: studentID.rawValue,
                metricID: metricID.rawValue,
                localCalendarDay: localCalendarDay.canonicalString,
                in: context
            ) {
                let existingMeasurement = try BodyMetricManagedObjectMapping.makeMeasurement(from: existing)
                let edited = try existingMeasurement.editingSameDay(value: value, enteredUnit: enteredUnit, now: now)
                BodyMetricManagedObjectMapping.apply(edited, to: existing)
                return edited
            }
            let created = try BodyMeasurement(
                id: newID,
                studentID: studentID,
                metricID: metricID,
                localCalendarDay: localCalendarDay,
                value: value,
                enteredUnit: enteredUnit,
                createdAtUTC: now,
                updatedAtUTC: now
            )
            let object = NSEntityDescription.insertNewObject(
                forEntityName: BodyMetricManagedObjectMapping.measurementEntityName,
                into: context
            )
            BodyMetricManagedObjectMapping.apply(created, to: object)
            return created
        }
    }

    /// Deletes one measurement. There is no separate trend/cache object to
    /// update -- the next read of `history`/any derived `Comparison` simply
    /// no longer sees this point (data-model §2.10).
    public func deleteMeasurement(id: StableUUID) async throws {
        try await writer.transaction { context in
            let object = try BodyMetricManagedObjectMapping.requireMeasurement(id: id.rawValue, in: context)
            context.delete(object)
        }
    }

    /// Deletes every measurement recorded for this Student+Metric in ONE
    /// transaction (the "clear all records" entry point for a custom metric
    /// the coach wants to delete but which still has history) -- never one
    /// transaction per row. Deliberately does NOT touch the metric
    /// definition itself; `deleteCustomMetricIfUnused` re-validates the
    /// (now-zero) count as its own backstop before permanently deleting the
    /// definition (M1B-FR-023/D-009).
    public func deleteAllMeasurements(studentID: StableUUID, metricID: StableUUID) async throws {
        try await writer.transaction { context in
            let objects = try BodyMetricManagedObjectMapping.fetchMeasurements(
                studentID: studentID.rawValue,
                metricID: metricID.rawValue,
                in: context
            )
            for object in objects {
                context.delete(object)
            }
        }
    }

    public func history(studentID: StableUUID, metricID: StableUUID) async throws -> [BodyMeasurement] {
        try await writer.read { context in
            try BodyMetricManagedObjectMapping.fetchMeasurements(
                studentID: studentID.rawValue,
                metricID: metricID.rawValue,
                in: context
            ).map { try BodyMetricManagedObjectMapping.makeMeasurement(from: $0) }
        }
    }

    /// One most-recent-day measurement PER metric for this Student, keyed by
    /// `metricID` -- a single batch fetch (all of this Student's
    /// measurements, sorted newest-day-first) grouped in memory, rather than
    /// one query per metric (avoids N+1; measurement volume per Student is
    /// small enough that this in-memory grouping is the simplest reliable
    /// approach). Metrics with zero recorded measurements are simply absent
    /// from the result -- never synthesized.
    public func latestMeasurements(studentID: StableUUID) async throws -> [StableUUID: BodyMeasurement] {
        try await writer.read { context in
            let objects = try BodyMetricManagedObjectMapping.fetchMeasurements(
                studentID: studentID.rawValue,
                in: context
            )
            var result: [StableUUID: BodyMeasurement] = [:]
            for object in objects {
                let measurement = try BodyMetricManagedObjectMapping.makeMeasurement(from: object)
                // `objects` is sorted newest-day-first, so the first
                // occurrence seen per metricID is already its latest.
                if result[measurement.metricID] == nil {
                    result[measurement.metricID] = measurement
                }
            }
            return result
        }
    }
}

extension BodyMetricManagedObjectMapping {
    static func requireMeasurement(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject {
        guard let object = try fetchMeasurement(id: id, in: context) else {
            throw DomainError.notFound
        }
        return object
    }
}
