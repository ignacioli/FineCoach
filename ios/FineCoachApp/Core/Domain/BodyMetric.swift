import Foundation

/// The unit family a `BodyMetricDefinition` measures in (data-model §2.8,
/// M1B-FR-025/D-005). Built-in metrics are always `weight`, `length`, or
/// `percent` -- their `currentUnit` is fixed and display conversions are pure
/// functions (see `BodyMeasurement`). Custom metrics are always `customUnit`
/// and store whatever free-form unit string the coach chose.
public enum BodyMetricUnitRuleKind: String, Codable, Sendable {
    case weight
    case length
    case percent
    case customUnit
}

public enum BodyMetricKind: String, Codable, Sendable {
    case builtIn
    case custom
}

public enum BodyMetricLifecycle: String, Codable, Sendable {
    case active
    case archived
}

/// One of the exact 8 built-in metrics (D-006). This set MUST NOT be added to
/// or removed from -- coaches add anything else as a custom metric instead.
/// Identity is a fixed UUID per case (matching `BodyMetricDefinitionMO.id`'s
/// `UUID` attribute type) so built-ins can be stored/looked up exactly like
/// custom metrics, with no separate ID representation.
public enum BuiltInBodyMetric: String, CaseIterable, Sendable {
    case height
    case weight
    case bodyFatPercent
    case chest
    case waist
    case hip
    case upperArm
    case thigh

    /// Fixed, never-changing UUIDs -- one per built-in, seeded once and
    /// never regenerated (a regenerated id would orphan every existing
    /// measurement pointing at it).
    public var id: StableUUID {
        switch self {
        case .height: return StableUUID(UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!)
        case .weight: return StableUUID(UUID(uuidString: "00000000-0000-0000-0000-00000000B002")!)
        case .bodyFatPercent: return StableUUID(UUID(uuidString: "00000000-0000-0000-0000-00000000B003")!)
        case .chest: return StableUUID(UUID(uuidString: "00000000-0000-0000-0000-00000000B004")!)
        case .waist: return StableUUID(UUID(uuidString: "00000000-0000-0000-0000-00000000B005")!)
        case .hip: return StableUUID(UUID(uuidString: "00000000-0000-0000-0000-00000000B006")!)
        case .upperArm: return StableUUID(UUID(uuidString: "00000000-0000-0000-0000-00000000B007")!)
        case .thigh: return StableUUID(UUID(uuidString: "00000000-0000-0000-0000-00000000B008")!)
        }
    }

    public static func matching(id: StableUUID) -> BuiltInBodyMetric? {
        allCases.first { $0.id == id }
    }

    public var displayName: String {
        switch self {
        case .height: return "身高"
        case .weight: return "体重"
        case .bodyFatPercent: return "体脂率"
        case .chest: return "胸围"
        case .waist: return "腰围"
        case .hip: return "臀围"
        case .upperArm: return "上臂围"
        case .thigh: return "大腿围"
        }
    }

    public var unitRuleKind: BodyMetricUnitRuleKind {
        switch self {
        case .weight: return .weight
        case .bodyFatPercent: return .percent
        case .height, .chest, .waist, .hip, .upperArm, .thigh: return .length
        }
    }

    /// Fixed canonical-storage unit for this built-in (M1B-FR-025/D-005): the
    /// value on every `BodyMeasurement` for this metric is ALWAYS stored in
    /// this unit; kg/lb and cm/in are display-only conversions computed from
    /// it, never written back.
    public var canonicalUnit: String {
        switch unitRuleKind {
        case .weight: return "kg"
        case .length: return "cm"
        case .percent: return "%"
        case .customUnit: return ""
        }
    }

    public func makeDefinition(now: Date) throws -> BodyMetricDefinition {
        try BodyMetricDefinition(
            id: id,
            studentID: nil,
            kind: .builtIn,
            name: displayName,
            unitRuleKind: unitRuleKind,
            currentUnit: canonicalUnit,
            lifecycle: .active,
            createdAtUTC: now,
            updatedAtUTC: now
        )
    }

    /// All 8 built-in definitions, in the fixed display order used by list UI.
    public static func allDefinitions(now: Date) throws -> [BodyMetricDefinition] {
        try allCases.map { try $0.makeDefinition(now: now) }
    }
}

/// A named, trackable body metric (data-model §2.8): one of the 8 fixed
/// built-ins (global, `studentID == nil`), or a coach-defined custom metric
/// scoped to one Student (`studentID != nil`). `id` never encodes `name` so
/// renaming a custom metric never breaks history.
public struct BodyMetricDefinition: Hashable, Codable, Sendable, Identifiable {
    public let id: StableUUID
    /// `nil` for built-ins (global, shared by every Student); required and
    /// non-nil for custom metrics.
    public let studentID: StableUUID?
    public let kind: BodyMetricKind
    public let name: NormalizedName
    public let unitRuleKind: BodyMetricUnitRuleKind
    /// Required for custom metrics: the default unit pre-filled for NEW
    /// measurements going forward. Changing this on an existing custom
    /// metric MUST NOT alter any measurement already saved (M1B-FR-025) --
    /// there is deliberately no method on this type or on `BodyMeasurement`
    /// that reinterprets past measurements when this changes.
    public let currentUnit: String
    public let lifecycle: BodyMetricLifecycle
    public let createdAtUTC: Date
    public let updatedAtUTC: Date

    public var normalizedName: String { name.value }

    public init(
        id: StableUUID,
        studentID: StableUUID?,
        kind: BodyMetricKind,
        name: String,
        unitRuleKind: BodyMetricUnitRuleKind,
        currentUnit: String,
        lifecycle: BodyMetricLifecycle,
        createdAtUTC: Date,
        updatedAtUTC: Date
    ) throws {
        self.id = id
        self.studentID = studentID
        self.kind = kind
        self.name = try NormalizedName(name)
        self.unitRuleKind = unitRuleKind
        let trimmedUnit = currentUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentUnit = trimmedUnit
        self.lifecycle = lifecycle
        self.createdAtUTC = createdAtUTC
        self.updatedAtUTC = updatedAtUTC

        switch kind {
        case .builtIn:
            guard unitRuleKind != .customUnit else {
                throw DomainError.incompatibleInput
            }
            guard studentID == nil else {
                throw DomainError.incompatibleInput
            }
        case .custom:
            guard unitRuleKind == .customUnit else {
                throw DomainError.incompatibleInput
            }
            guard studentID != nil else {
                throw DomainError.incompatibleInput
            }
            guard !trimmedUnit.isEmpty else {
                throw DomainError.emptyText
            }
        }
    }

    public static func makeCustom(
        id: StableUUID,
        studentID: StableUUID,
        name: String,
        unit: String,
        now: Date
    ) throws -> BodyMetricDefinition {
        try BodyMetricDefinition(
            id: id,
            studentID: studentID,
            kind: .custom,
            name: name,
            unitRuleKind: .customUnit,
            currentUnit: unit,
            lifecycle: .active,
            createdAtUTC: now,
            updatedAtUTC: now
        )
    }

    /// Changes the default unit pre-filled for NEW measurements only. Does
    /// NOT touch, reinterpret, or convert any existing `BodyMeasurement` --
    /// those keep their own stored `enteredUnit` forever (M1B-FR-025).
    public func changingCurrentUnit(_ newUnit: String, now: Date) throws -> BodyMetricDefinition {
        guard kind == .custom, lifecycle == .active else {
            throw DomainError.invalidState
        }
        return try BodyMetricDefinition(
            id: id,
            studentID: studentID,
            kind: kind,
            name: name.value,
            unitRuleKind: unitRuleKind,
            currentUnit: newUnit,
            lifecycle: lifecycle,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: now
        )
    }

    public func renamed(_ newName: String, now: Date) throws -> BodyMetricDefinition {
        guard kind == .custom, lifecycle == .active else {
            throw DomainError.invalidState
        }
        return try BodyMetricDefinition(
            id: id,
            studentID: studentID,
            kind: kind,
            name: newName,
            unitRuleKind: unitRuleKind,
            currentUnit: currentUnit,
            lifecycle: lifecycle,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: now
        )
    }

    /// Archiving keeps every historical `BodyMeasurement` readable -- this is
    /// a lifecycle transition ONLY, it never touches measurement rows.
    public func archived(now: Date) throws -> BodyMetricDefinition {
        guard kind == .custom, lifecycle == .active else {
            throw DomainError.invalidState
        }
        return try BodyMetricDefinition(
            id: id,
            studentID: studentID,
            kind: kind,
            name: name.value,
            unitRuleKind: unitRuleKind,
            currentUnit: currentUnit,
            lifecycle: .archived,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: now
        )
    }

    public func restored(now: Date) throws -> BodyMetricDefinition {
        guard kind == .custom, lifecycle == .archived else {
            throw DomainError.invalidState
        }
        return try BodyMetricDefinition(
            id: id,
            studentID: studentID,
            kind: kind,
            name: name.value,
            unitRuleKind: unitRuleKind,
            currentUnit: currentUnit,
            lifecycle: .active,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: now
        )
    }

    /// Proof, by construction, that permanent deletion requires the caller to
    /// have already established zero measurements exist for this metric
    /// (M1B-FR-023/D-009). There is no bare `delete()` -- only this token
    /// factory, and it refuses to mint a token unless `measurementCount == 0`.
    /// The Application/Persistence layer (T037/T038) is responsible for
    /// counting measurements truthfully before calling this.
    public struct DeletionEligibility {
        fileprivate let metricID: StableUUID
    }

    public func deletionEligibility(measurementCount: Int) throws -> DeletionEligibility {
        guard kind == .custom else {
            throw DomainError.invalidState
        }
        guard measurementCount == 0 else {
            throw DomainError.conflict
        }
        return DeletionEligibility(metricID: id)
    }
}

extension BodyMetricDefinition.DeletionEligibility {
    /// Only a repository/use-case that actually counted zero measurements can
    /// obtain a token whose `metricID` matches the metric being deleted.
    public func authorizes(deletionOf id: StableUUID) -> Bool {
        metricID == id
    }
}

/// Per-Student active-custom-metric-name uniqueness (M1B-FR-023): mirrors
/// `ExerciseNameClaim`/`ExerciseNameClaimTable` exactly. Built-in metrics are
/// never subject to this table -- their names are fixed and never conflict
/// with anything. A conflict on `acquire` MUST block the save; it never
/// silently renames.
public struct BodyMetricNameClaim: Hashable, Codable, Sendable {
    public let studentID: StableUUID
    public let normalizedName: String
    public let ownerID: StableUUID

    public init(studentID: StableUUID, normalizedName: String, ownerID: StableUUID) throws {
        self.studentID = studentID
        self.normalizedName = try NormalizedName(normalizedName).value
        self.ownerID = ownerID
    }
}

public struct BodyMetricNameClaimTable: Equatable, Sendable {
    public private(set) var claims: [BodyMetricNameClaim]

    public init(claims: [BodyMetricNameClaim] = []) {
        self.claims = claims
    }

    public func claim(studentID: StableUUID, normalizedName: String) -> BodyMetricNameClaim? {
        claims.first { $0.studentID == studentID && $0.normalizedName == normalizedName }
    }

    public mutating func acquire(_ incoming: BodyMetricNameClaim) throws {
        if let existing = claim(studentID: incoming.studentID, normalizedName: incoming.normalizedName) {
            if existing.ownerID == incoming.ownerID {
                return
            }
            throw DomainError.conflict
        }
        claims.append(incoming)
    }

    public mutating func release(ownerID: StableUUID) {
        claims.removeAll { $0.ownerID == ownerID }
    }
}
