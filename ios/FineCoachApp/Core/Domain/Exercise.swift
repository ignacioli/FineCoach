import Foundation

public enum ExerciseKind: String, Codable, Sendable {
    case builtIn
    case custom
}

public enum ExerciseLifecycle: String, Codable, Sendable {
    case active
    case archived
}

public enum ExerciseClaimScope: String, Codable, Sendable {
    case activeCatalog
    case currentSession
}

public enum ExerciseNameNormalizer {
    public static func normalized(_ rawValue: String) throws -> String {
        try NormalizedName(rawValue).value
    }
}

public struct ExerciseCatalogItem: Hashable, Codable, Sendable, Identifiable {
    public let id: StableExerciseID
    public let kind: ExerciseKind
    public let canonicalName: NormalizedName
    public let normalizedName: String
    public let recordMode: RecordMode
    public let metadataVersion: String
    public let lifecycle: ExerciseLifecycle
    /// A built-in item removed from the shipped catalog remains addressable by
    /// id for old sessions and templates, but is omitted from browse flows.
    public let isRetired: Bool
    public let provenanceRef: String?
    public let createdAtUTC: Date
    public let updatedAtUTC: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case canonicalName
        case normalizedName
        case recordMode
        case metadataVersion
        case lifecycle
        case isRetired
        case provenanceRef
        case createdAtUTC
        case updatedAtUTC
    }

    public init(
        id: StableExerciseID,
        kind: ExerciseKind,
        canonicalName: NormalizedName,
        recordMode: RecordMode,
        metadataVersion: String,
        lifecycle: ExerciseLifecycle,
        provenanceRef: String?,
        createdAtUTC: Date,
        updatedAtUTC: Date,
        isRetired: Bool = false
    ) throws {
        self.id = id
        self.kind = kind
        self.canonicalName = canonicalName
        self.normalizedName = canonicalName.value
        self.recordMode = recordMode
        self.metadataVersion = metadataVersion
        self.lifecycle = lifecycle
        self.isRetired = isRetired
        self.provenanceRef = provenanceRef
        self.createdAtUTC = createdAtUTC
        self.updatedAtUTC = updatedAtUTC
        if kind == .builtIn && provenanceRef == nil {
            throw DomainError.incompatibleInput
        }
        if kind == .custom && provenanceRef != nil {
            throw DomainError.incompatibleInput
        }
    }

    /// `isRetired` was added after the first backup payload. Older backups do
    /// not contain the key and remain readable as active catalog items.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(StableExerciseID.self, forKey: .id),
            kind: container.decode(ExerciseKind.self, forKey: .kind),
            canonicalName: container.decode(NormalizedName.self, forKey: .canonicalName),
            recordMode: container.decode(RecordMode.self, forKey: .recordMode),
            metadataVersion: container.decode(String.self, forKey: .metadataVersion),
            lifecycle: container.decode(ExerciseLifecycle.self, forKey: .lifecycle),
            provenanceRef: container.decodeIfPresent(String.self, forKey: .provenanceRef),
            createdAtUTC: container.decode(Date.self, forKey: .createdAtUTC),
            updatedAtUTC: container.decode(Date.self, forKey: .updatedAtUTC),
            isRetired: container.decodeIfPresent(Bool.self, forKey: .isRetired) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(canonicalName, forKey: .canonicalName)
        try container.encode(normalizedName, forKey: .normalizedName)
        try container.encode(recordMode, forKey: .recordMode)
        try container.encode(metadataVersion, forKey: .metadataVersion)
        try container.encode(lifecycle, forKey: .lifecycle)
        try container.encode(isRetired, forKey: .isRetired)
        try container.encodeIfPresent(provenanceRef, forKey: .provenanceRef)
        try container.encode(createdAtUTC, forKey: .createdAtUTC)
        try container.encode(updatedAtUTC, forKey: .updatedAtUTC)
    }

    public static func makeBuiltIn(
        id: StableExerciseID,
        canonicalName: String,
        recordMode: RecordMode,
        metadataVersion: String,
        provenanceRef: String,
        now: Date,
        isRetired: Bool = false
    ) throws -> ExerciseCatalogItem {
        try ExerciseCatalogItem(
            id: id,
            kind: .builtIn,
            canonicalName: NormalizedName(canonicalName),
            recordMode: recordMode,
            metadataVersion: metadataVersion,
            lifecycle: .active,
            provenanceRef: provenanceRef,
            createdAtUTC: now,
            updatedAtUTC: now,
            isRetired: isRetired
        )
    }

    public static func makeCustom(
        id: StableExerciseID,
        canonicalName: String,
        recordMode: RecordMode,
        now: Date
    ) throws -> ExerciseCatalogItem {
        try ExerciseCatalogItem(
            id: id,
            kind: .custom,
            canonicalName: NormalizedName(canonicalName),
            recordMode: recordMode,
            metadataVersion: "custom.1",
            lifecycle: .active,
            provenanceRef: nil,
            createdAtUTC: now,
            updatedAtUTC: now,
            isRetired: false
        )
    }

    public func updatingCustom(canonicalName: String, recordMode: RecordMode, now: Date) throws
        -> ExerciseCatalogItem
    {
        guard kind == .custom, lifecycle == .active else {
            throw DomainError.invalidState
        }
        return try ExerciseCatalogItem(
            id: id,
            kind: kind,
            canonicalName: NormalizedName(canonicalName),
            recordMode: recordMode,
            metadataVersion: metadataVersion,
            lifecycle: lifecycle,
            provenanceRef: provenanceRef,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: now,
            isRetired: false
        )
    }

    public func archived(now: Date) throws -> ExerciseCatalogItem {
        guard kind == .custom, lifecycle == .active else {
            throw DomainError.invalidState
        }
        return try ExerciseCatalogItem(
            id: id,
            kind: kind,
            canonicalName: canonicalName,
            recordMode: recordMode,
            metadataVersion: metadataVersion,
            lifecycle: .archived,
            provenanceRef: provenanceRef,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: now,
            isRetired: false
        )
    }

    public func restored(now: Date) throws -> ExerciseCatalogItem {
        guard kind == .custom, lifecycle == .archived else {
            throw DomainError.invalidState
        }
        return try ExerciseCatalogItem(
            id: id,
            kind: kind,
            canonicalName: canonicalName,
            recordMode: recordMode,
            metadataVersion: metadataVersion,
            lifecycle: .active,
            provenanceRef: provenanceRef,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: now,
            isRetired: false
        )
    }
}

public struct ExerciseNameClaim: Hashable, Codable, Sendable {
    public let normalizedName: String
    public let ownerKind: ExerciseSourceKind
    public let ownerID: StableExerciseID
    public let scope: ExerciseClaimScope

    public init(
        normalizedName: String,
        ownerKind: ExerciseSourceKind,
        ownerID: StableExerciseID,
        scope: ExerciseClaimScope
    ) throws {
        let canonical = try ExerciseNameNormalizer.normalized(normalizedName)
        self.normalizedName = canonical
        self.ownerKind = ownerKind
        self.ownerID = ownerID
        self.scope = scope
    }
}

public struct ExerciseNameClaimTable: Equatable, Sendable {
    public private(set) var claims: [ExerciseNameClaim]

    public init(claims: [ExerciseNameClaim] = []) {
        self.claims = claims
    }

    public func claim(matchingNormalizedName name: String) -> ExerciseNameClaim? {
        claims.first { $0.normalizedName == name }
    }

    public mutating func acquire(_ incoming: ExerciseNameClaim) throws {
        if let existing = claim(matchingNormalizedName: incoming.normalizedName) {
            if existing.ownerID == incoming.ownerID && existing.scope == incoming.scope {
                return
            }
            throw DomainError.conflict
        }
        claims.append(incoming)
    }

    public mutating func release(ownerID: StableExerciseID, scope: ExerciseClaimScope? = nil) {
        claims.removeAll { claim in
            claim.ownerID == ownerID && (scope == nil || claim.scope == scope)
        }
    }

    public mutating func release(scope: ExerciseClaimScope) {
        claims.removeAll { $0.scope == scope }
    }
}

public struct ExercisePreference: Hashable, Codable, Sendable {
    public let exerciseID: StableExerciseID
    public let alias: NormalizedName?
    public let isFavorite: Bool
    public let isHidden: Bool
    /// M1B-FR-028: whether this exercise's load is assisted (e.g. an
    /// assisted pull-up machine's counterweight), meaning a LOWER
    /// `weightValue` represents progress rather than a higher one. Purely a
    /// display/interpretation flag -- never changes how a value is stored.
    public let isAssisted: Bool
    /// P0-D8: the coach's override of whether this exercise is trained one
    /// side at a time, which makes the set entry offer per-side weights.
    /// `nil` keeps the library default (`ExerciseLibraryEntry
    /// .isUnilateralByDefault`). Optional so a backup written before this
    /// field decodes unchanged (P0-D12, payloadSchemaVersion stays 3).
    public let isUnilateral: Bool?

    public init(
        exerciseID: StableExerciseID,
        alias: NormalizedName? = nil,
        isFavorite: Bool = false,
        isHidden: Bool = false,
        isAssisted: Bool = false,
        isUnilateral: Bool? = nil
    ) {
        self.exerciseID = exerciseID
        self.alias = alias
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.isAssisted = isAssisted
        self.isUnilateral = isUnilateral
    }

    public func updating(
        alias: NormalizedName?? = nil,
        isFavorite: Bool? = nil,
        isHidden: Bool? = nil,
        isAssisted: Bool? = nil,
        isUnilateral: Bool? = nil
    ) -> ExercisePreference {
        ExercisePreference(
            exerciseID: exerciseID,
            alias: alias ?? self.alias,
            isFavorite: isFavorite ?? self.isFavorite,
            isHidden: isHidden ?? self.isHidden,
            isAssisted: isAssisted ?? self.isAssisted,
            isUnilateral: isUnilateral ?? self.isUnilateral
        )
    }
}

public struct ExerciseLibraryEntry: Hashable, Codable, Sendable, Identifiable {
    public let item: ExerciseCatalogItem
    public let preference: ExercisePreference?
    public let primaryMuscleGroup: String?
    public let equipmentClass: String?
    /// Catalog secondary parts ("次要：肩、臂", 20 artwork); empty for custom.
    public let secondaryMuscleGroups: [String]
    /// The built-in catalog's `unilateral` flag; `false` for custom
    /// exercises, whose flag lives only in the preference.
    public let isUnilateralByDefault: Bool

    public var id: StableExerciseID { item.id }

    /// P0-D8: whether the set entry offers per-side weights.
    public var isUnilateral: Bool {
        preference?.isUnilateral ?? isUnilateralByDefault
    }

    public var displayedName: String {
        if let alias = preference?.alias?.value, !alias.isEmpty {
            return alias
        }
        return item.canonicalName.value
    }

    public init(
        item: ExerciseCatalogItem,
        preference: ExercisePreference?,
        primaryMuscleGroup: String? = nil,
        equipmentClass: String? = nil,
        secondaryMuscleGroups: [String] = [],
        isUnilateralByDefault: Bool = false
    ) {
        self.item = item
        self.preference = preference
        self.primaryMuscleGroup = primaryMuscleGroup
        self.equipmentClass = equipmentClass
        self.secondaryMuscleGroups = secondaryMuscleGroups
        self.isUnilateralByDefault = isUnilateralByDefault
    }
}

public struct ExerciseCatalogBrowseFacet: Hashable, Sendable {
    public let primaryMuscleGroup: String
    public let equipmentClass: String
    public let secondaryMuscleGroups: [String]
    /// `provenance.json` `unilateral` (P0-D8); absent means `false`.
    public let isUnilateral: Bool

    public init(
        primaryMuscleGroup: String,
        equipmentClass: String,
        secondaryMuscleGroups: [String] = [],
        isUnilateral: Bool = false
    ) {
        self.primaryMuscleGroup = primaryMuscleGroup
        self.equipmentClass = equipmentClass
        self.secondaryMuscleGroups = secondaryMuscleGroups
        self.isUnilateral = isUnilateral
    }
}

public enum ExerciseCatalogBrowse: Sendable {
    public static let muscleGroupOrder = ["胸", "肩", "背", "大腿", "小腿", "臂", "臀", "核心"]
    public static let equipmentClassOrder = [
        "杠铃", "哑铃", "固定器械", "史密斯机", "绳索", "哈克机", "壶铃", "徒手", "悍马机", "弹力带", "悬挂带", "单杠", "其他",
    ]
    public static let customSectionID = "custom"
    public static let uncategorizedSectionID = "uncategorized"

    public struct Section: Identifiable, Hashable, Sendable {
        public let id: String
        public let entries: [ExerciseLibraryEntry]
    }

    public static func sections(
        from entries: [ExerciseLibraryEntry],
        muscleFilter: String?,
        equipmentFilter: String?
    ) -> [Section] {
        let filtersActive = muscleFilter != nil || equipmentFilter != nil
        var result: [Section] = []
        if !filtersActive {
            let custom = entries.filter { $0.item.kind == .custom }
            if !custom.isEmpty {
                result.append(Section(id: customSectionID, entries: custom))
            }
        }

        var grouped: [String: [ExerciseLibraryEntry]] = [:]
        for entry in entries where entry.item.kind == .builtIn {
            if let muscleFilter, entry.primaryMuscleGroup != muscleFilter {
                continue
            }
            if let equipmentFilter, entry.equipmentClass != equipmentFilter {
                continue
            }
            let key = entry.primaryMuscleGroup ?? uncategorizedSectionID
            grouped[key, default: []].append(entry)
        }

        for muscle in muscleGroupOrder {
            if let muscleFilter, muscle != muscleFilter {
                continue
            }
            if let rows = grouped[muscle], !rows.isEmpty {
                result.append(Section(id: muscle, entries: rows))
            }
        }
        if muscleFilter == nil, let leftover = grouped[uncategorizedSectionID], !leftover.isEmpty {
            result.append(Section(id: uncategorizedSectionID, entries: leftover))
        }
        return result
    }
}
