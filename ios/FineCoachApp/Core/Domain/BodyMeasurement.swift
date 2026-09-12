import Foundation

/// A single recorded value of a `BodyMetricDefinition` on a local calendar
/// day (data-model §2.9). `(studentID, metricID, localCalendarDay)` is
/// UNIQUE -- re-entering on the same local day EDITS that day's existing
/// record rather than creating a duplicate (enforced by
/// `BodyMeasurementDayIndex` below at the Domain level, and by a Core Data
/// unique constraint + upsert at the Persistence level, T038).
///
/// Unit semantics (M1B-FR-025/D-005), the single most important invariant
/// here:
/// - Built-in metrics: `value` is the ONE canonical stored value. kg<->lb and
///   cm<->in are pure DISPLAY conversions computed from it -- see
///   `BuiltInUnitConversion` below. There is deliberately no API on this type
///   that writes a converted value back into `value`.
/// - Custom metrics: `value` and `enteredUnit` are stored together exactly as
///   entered, and are immutable once saved except through the same-day edit
///   path (a brand-new `BodyMeasurement` value for that day, still tagged
///   with whatever unit was entered AT THAT TIME). There is intentionally NO
///   method anywhere in this file that takes "a new unit" plus existing
///   measurements and returns "reinterpreted measurements" -- that operation
///   does not exist, by design.
public struct BodyMeasurement: Hashable, Codable, Sendable, Identifiable {
    public let id: StableUUID
    public let studentID: StableUUID
    public let metricID: StableUUID
    public let localCalendarDay: LocalDate
    public let value: DecimalValue
    public let enteredUnit: String
    public let createdAtUTC: Date
    public let updatedAtUTC: Date

    public init(
        id: StableUUID,
        studentID: StableUUID,
        metricID: StableUUID,
        localCalendarDay: LocalDate,
        value: DecimalValue,
        enteredUnit: String,
        createdAtUTC: Date,
        updatedAtUTC: Date
    ) throws {
        let trimmedUnit = enteredUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUnit.isEmpty else {
            throw DomainError.invalidUnit
        }
        self.id = id
        self.studentID = studentID
        self.metricID = metricID
        self.localCalendarDay = localCalendarDay
        self.value = value
        self.enteredUnit = trimmedUnit
        self.createdAtUTC = createdAtUTC
        self.updatedAtUTC = updatedAtUTC
    }

    /// Derives `localCalendarDay` from `instant` via the injected
    /// `LocalCalendarProvider`'s `Calendar` (M1B-FR-026/T007a) -- callers
    /// MUST NOT pass `Date()`/`Calendar.current` derived days directly.
    public static func recordedNow(
        id: StableUUID,
        studentID: StableUUID,
        metricID: StableUUID,
        instant: Date,
        calendar: Calendar,
        value: DecimalValue,
        enteredUnit: String
    ) throws -> BodyMeasurement {
        try BodyMeasurement(
            id: id,
            studentID: studentID,
            metricID: metricID,
            localCalendarDay: LocalDate(date: instant, calendar: calendar),
            value: value,
            enteredUnit: enteredUnit,
            createdAtUTC: instant,
            updatedAtUTC: instant
        )
    }

    /// Same-day re-entry = EDIT semantics: keeps `id`/`createdAtUTC`, replaces
    /// `value`/`enteredUnit`/`updatedAtUTC`. Callers MUST use this (rather
    /// than constructing a fresh `BodyMeasurement`) when a measurement
    /// already exists for `(studentID, metricID, localCalendarDay)` -- this
    /// is the one edit path, mirroring `recordIdempotentAdjustment`'s
    /// "fetch by key, replace in place" idiom.
    public func editingSameDay(value: DecimalValue, enteredUnit: String, now: Date) throws -> BodyMeasurement {
        try BodyMeasurement(
            id: id,
            studentID: studentID,
            metricID: metricID,
            localCalendarDay: localCalendarDay,
            value: value,
            enteredUnit: enteredUnit,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: now
        )
    }
}

/// Domain-level uniqueness contract for `(studentID, metricID,
/// localCalendarDay)` -- the Persistence layer additionally enforces this
/// with a Core Data unique constraint as a backstop, but this table lets
/// Application-layer code (and tests) reason about "does today already have
/// an entry" without touching Core Data.
public struct BodyMeasurementDayIndex: Equatable, Sendable {
    public private(set) var measurements: [BodyMeasurement]

    public init(measurements: [BodyMeasurement] = []) {
        self.measurements = measurements
    }

    public func existing(
        studentID: StableUUID,
        metricID: StableUUID,
        localCalendarDay: LocalDate
    ) -> BodyMeasurement? {
        measurements.first {
            $0.studentID == studentID && $0.metricID == metricID && $0.localCalendarDay == localCalendarDay
        }
    }

    /// Upsert-as-edit: if a measurement already exists for this Student+
    /// Metric+day, replaces it in place (same `id`); otherwise inserts a new
    /// one. Never creates a second row for the same key.
    public mutating func upsert(
        studentID: StableUUID,
        metricID: StableUUID,
        localCalendarDay: LocalDate,
        value: DecimalValue,
        enteredUnit: String,
        newID: StableUUID,
        now: Date
    ) throws -> BodyMeasurement {
        if let existing = existing(studentID: studentID, metricID: metricID, localCalendarDay: localCalendarDay) {
            let edited = try existing.editingSameDay(value: value, enteredUnit: enteredUnit, now: now)
            measurements.removeAll { $0.id == existing.id }
            measurements.append(edited)
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
        measurements.append(created)
        return created
    }

    /// Deleting removes the point from any derived trend structurally -- there
    /// is no separate trend/cache object anywhere that needs updating, since
    /// trends are always computed live from whatever remains in
    /// `measurements` (data-model §2.10).
    public mutating func delete(id: StableUUID) {
        measurements.removeAll { $0.id == id }
    }

    public func history(
        studentID: StableUUID,
        metricID: StableUUID
    ) -> [BodyMeasurement] {
        measurements
            .filter { $0.studentID == studentID && $0.metricID == metricID }
            .sorted { $0.localCalendarDay < $1.localCalendarDay }
    }
}

/// Pure, read-only display conversions for built-in metrics (M1B-FR-025/
/// D-005). These NEVER write back to storage -- callers get a converted
/// number to *show*, and the canonical `value` on the `BodyMeasurement` is
/// left untouched. There is no "convert and re-save" method anywhere.
public enum BuiltInUnitConversion {
    public enum WeightDisplayUnit: String, CaseIterable, Sendable {
        case kilograms = "kg"
        case pounds = "lb"
    }

    public enum LengthDisplayUnit: String, CaseIterable, Sendable {
        case centimeters = "cm"
        case inches = "in"
    }

    /// `canonicalKilograms` MUST be the metric's canonical stored value (kg).
    public static func weight(canonicalKilograms: DecimalValue, displayedAs unit: WeightDisplayUnit) throws
        -> DecimalValue
    {
        switch unit {
        case .kilograms:
            return canonicalKilograms
        case .pounds:
            return try canonicalKilograms.multiplied(by: DecimalValue("2.2046226218"))
        }
    }

    /// `canonicalCentimeters` MUST be the metric's canonical stored value (cm).
    public static func length(canonicalCentimeters: DecimalValue, displayedAs unit: LengthDisplayUnit) throws
        -> DecimalValue
    {
        switch unit {
        case .centimeters:
            return canonicalCentimeters
        case .inches:
            return try canonicalCentimeters.multiplied(by: DecimalValue("0.3937007874"))
        }
    }

    /// Round-trip helper used by tests to prove the conversion is lossless
    /// (within decimal-string rounding) and, crucially, that it never mutates
    /// the canonical value it was given.
    public static func roundTripKilograms(_ canonicalKilograms: DecimalValue) throws -> DecimalValue {
        let pounds = try weight(canonicalKilograms: canonicalKilograms, displayedAs: .pounds)
        return try DecimalValue(
            NSDecimalNumber(decimal: pounds.decimal)
                .dividing(by: NSDecimalNumber(decimal: DecimalValue("2.2046226218").decimal))
                .stringValue
        )
    }
}
