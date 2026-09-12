import Foundation

/// Orchestrates body metric/measurement lifecycle (T037, M1B-FR-023..026).
/// Every `localCalendarDay` derivation goes through the injected
/// `LocalCalendarProvider`'s `Calendar` (T007a) -- this file MUST NOT call
/// `Date()`/`Calendar.current` directly.
public struct BodyDataUseCases: Sendable {
    private let repository: CoreDataBodyDataRepository
    private let clock: any Clock
    private let calendarProvider: any LocalCalendarProvider
    private let ids: any IDGenerator

    public init(
        repository: CoreDataBodyDataRepository,
        clock: any Clock,
        calendarProvider: any LocalCalendarProvider,
        ids: any IDGenerator
    ) {
        self.repository = repository
        self.clock = clock
        self.calendarProvider = calendarProvider
        self.ids = ids
    }

    /// The 8 fixed built-ins plus this Student's custom metrics (any
    /// lifecycle -- archived ones stay visible here so their history remains
    /// reachable; callers filter to `.active` for "pick a metric to log
    /// today" pickers). Body data may be entirely empty; that is never
    /// treated as an error (M1B-FR-023).
    public func metrics(studentID: StableUUID, now: Date? = nil) async throws -> [BodyMetricDefinition] {
        let builtIns = try BuiltInBodyMetric.allDefinitions(now: now ?? clock.nowUTC())
        let custom = try await repository.customMetrics(studentID: studentID)
        return builtIns + custom.sorted { $0.createdAtUTC < $1.createdAtUTC }
    }

    @discardableResult
    public func createCustomMetric(studentID: StableUUID, name: String, unit: String) async throws
        -> BodyMetricDefinition
    {
        let now = clock.nowUTC()
        let metric = try BodyMetricDefinition.makeCustom(
            id: StableUUID(ids.makeID()),
            studentID: studentID,
            name: name,
            unit: unit,
            now: now
        )
        return try await repository.createCustomMetric(metric)
    }

    @discardableResult
    public func renameCustomMetric(id: StableUUID, name: String) async throws -> BodyMetricDefinition {
        let current = try await repository.customMetric(id: id)
        let renamed = try current.renamed(name, now: clock.nowUTC())
        return try await repository.updateCustomMetric(renamed)
    }

    @discardableResult
    public func changeCurrentUnit(id: StableUUID, unit: String) async throws -> BodyMetricDefinition {
        let current = try await repository.customMetric(id: id)
        // Only affects the default pre-filled unit for NEW measurements --
        // never touches any BodyMeasurement already saved (M1B-FR-025).
        let updated = try current.changingCurrentUnit(unit, now: clock.nowUTC())
        return try await repository.updateCustomMetric(updated)
    }

    @discardableResult
    public func archiveCustomMetric(id: StableUUID) async throws -> BodyMetricDefinition {
        let current = try await repository.customMetric(id: id)
        let archived = try current.archived(now: clock.nowUTC())
        return try await repository.updateCustomMetric(archived)
    }

    @discardableResult
    public func restoreCustomMetric(id: StableUUID) async throws -> BodyMetricDefinition {
        let current = try await repository.customMetric(id: id)
        let restored = try current.restored(now: clock.nowUTC())
        return try await repository.updateCustomMetric(restored)
    }

    /// Permanently deletes a custom metric ONLY IF it truly has zero
    /// measurements -- counts live inside this call (never trusts a stale
    /// caller-supplied count), mints the `DeletionEligibility` token from
    /// that live count, and the repository re-validates the count again
    /// inside its own transaction as a second backstop (M1B-FR-023/D-009).
    public func deleteCustomMetricIfUnused(id: StableUUID) async throws {
        let metric = try await repository.customMetric(id: id)
        let count = try await repository.measurementCount(metricID: id)
        let eligibility = try metric.deletionEligibility(measurementCount: count)
        try await repository.deleteCustomMetric(id: id, eligibility: eligibility)
    }

    /// Records (or, on a same local day, EDITS) a measurement. `instant`
    /// defaults to `clock.nowUTC()`; `localCalendarDay` is always derived
    /// through `calendarProvider.currentCalendar()`.
    @discardableResult
    public func recordMeasurement(
        studentID: StableUUID,
        metricID: StableUUID,
        value: String,
        enteredUnit: String,
        at instant: Date? = nil
    ) async throws -> BodyMeasurement {
        let now = instant ?? clock.nowUTC()
        let calendar = calendarProvider.currentCalendar()
        let day = LocalDate(date: now, calendar: calendar)
        let decimalValue = try DecimalValue(value)
        return try await repository.recordMeasurement(
            studentID: studentID,
            metricID: metricID,
            localCalendarDay: day,
            value: decimalValue,
            enteredUnit: enteredUnit,
            newID: StableUUID(ids.makeID()),
            now: now
        )
    }

    /// Deletion requires the caller (UI) to have already obtained explicit
    /// confirmation -- this use case performs the delete unconditionally
    /// once called, mirroring `DeleteStudentFlow`'s split between the
    /// confirmation UI and the actual deleting call.
    public func deleteMeasurement(id: StableUUID) async throws {
        try await repository.deleteMeasurement(id: id)
    }

    public func history(studentID: StableUUID, metricID: StableUUID) async throws -> [BodyMeasurement] {
        try await repository.history(studentID: studentID, metricID: metricID)
    }
}
