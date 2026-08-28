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
    public let provenanceRef: String?
    public let createdAtUTC: Date
    public let updatedAtUTC: Date

    public init(
        id: StableExerciseID,
        kind: ExerciseKind,
        canonicalName: NormalizedName,
        recordMode: RecordMode,
        metadataVersion: String,
        lifecycle: ExerciseLifecycle,
        provenanceRef: String?,
        createdAtUTC: Date,
        updatedAtUTC: Date
    ) throws {
        self.id = id
        self.kind = kind
        self.canonicalName = canonicalName
        self.normalizedName = canonicalName.value
        self.recordMode = recordMode
        self.metadataVersion = metadataVersion
        self.lifecycle = lifecycle
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

    public static func makeBuiltIn(
        id: StableExerciseID,
        canonicalName: String,
        recordMode: RecordMode,
        metadataVersion: String,
        provenanceRef: String,
        now: Date
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
            updatedAtUTC: now
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
            updatedAtUTC: now
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
            updatedAtUTC: now
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
            updatedAtUTC: now
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
            updatedAtUTC: now
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

    public init(
        exerciseID: StableExerciseID,
        alias: NormalizedName? = nil,
        isFavorite: Bool = false,
        isHidden: Bool = false
    ) {
        self.exerciseID = exerciseID
        self.alias = alias
        self.isFavorite = isFavorite
        self.isHidden = isHidden
    }

    public func updating(
        alias: NormalizedName?? = nil,
        isFavorite: Bool? = nil,
        isHidden: Bool? = nil
    ) -> ExercisePreference {
        ExercisePreference(
            exerciseID: exerciseID,
            alias: alias ?? self.alias,
            isFavorite: isFavorite ?? self.isFavorite,
            isHidden: isHidden ?? self.isHidden
        )
    }
}

public struct ExerciseLibraryEntry: Hashable, Codable, Sendable, Identifiable {
    public let item: ExerciseCatalogItem
    public let preference: ExercisePreference?

    public var id: StableExerciseID { item.id }

    public var displayedName: String {
        if let alias = preference?.alias?.value, !alias.isEmpty {
            return alias
        }
        return item.canonicalName.value
    }

    public init(item: ExerciseCatalogItem, preference: ExercisePreference?) {
        self.item = item
        self.preference = preference
    }
}
