import CoreData
import Foundation

public struct CoreDataExerciseRepository: Sendable {
    private let writer: PersistenceWriter

    public init(writer: PersistenceWriter) {
        self.writer = writer
    }

    public func seedPlaceholderCatalogIfNeeded(now: Date) async throws {
        try await writer.transaction { context in
            if try ExerciseManagedObjectMapping.hasBuiltInCatalog(in: context) {
                return
            }
            let catalog: PlaceholderExerciseCatalog
            do {
                catalog = try PlaceholderExerciseCatalogLoader.loadFromBundle(Bundle.main)
            } catch {
                #if DEBUG
                    try Self.insertDebugPlaceholderCatalog(now: now, in: context)
                    return
                #else
                    throw error
                #endif
            }
            try Self.insertLoadedPlaceholderCatalog(catalog, now: now, in: context)
        }
    }

    public func searchActive(query: String, includeHidden: Bool = false) async throws -> [ExerciseLibraryEntry] {
        try await writer.read { context in
            let objects = try ExerciseManagedObjectMapping.fetchActiveCatalogItems(in: context)
            let preferences = try Self.preferencesByExerciseID(in: context)
            let normalizedQuery =
                query
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping
            var entries: [ExerciseLibraryEntry] = []
            entries.reserveCapacity(objects.count)
            for object in objects {
                let item = try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
                let preference = preferences[item.id.rawValue]
                if !includeHidden, preference?.isHidden == true {
                    continue
                }
                if !normalizedQuery.isEmpty,
                    !Self.matches(item: item, preference: preference, query: normalizedQuery)
                {
                    continue
                }
                entries.append(ExerciseLibraryEntry(item: item, preference: preference))
            }
            return entries
        }
    }

    public func catalogItem(id: StableExerciseID) async throws -> ExerciseCatalogItem {
        try await writer.read { context in
            let object = try ExerciseManagedObjectMapping.requireCatalogItem(id: id.rawValue, in: context)
            return try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
        }
    }

    public func createCustom(
        name: String,
        recordMode: RecordMode,
        id: StableExerciseID,
        now: Date
    ) async throws -> ExerciseCatalogItem {
        try await writer.transaction { context in
            if try ExerciseManagedObjectMapping.fetchCatalogItem(id: id.rawValue, in: context) != nil {
                throw DomainError.conflict
            }
            let item = try ExerciseCatalogItem.makeCustom(
                id: id,
                canonicalName: name,
                recordMode: recordMode,
                now: now
            )
            try ExerciseManagedObjectMapping.acquireUnifiedClaim(
                try ExerciseNameClaim(
                    normalizedName: item.normalizedName,
                    ownerKind: .custom,
                    ownerID: item.id,
                    scope: .activeCatalog
                ),
                in: context
            )
            let object = try ExerciseManagedObjectMapping.upsertCatalogItem(item, in: context)
            return try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
        }
    }

    public func updateCustom(
        id: StableExerciseID,
        name: String,
        recordMode: RecordMode,
        now: Date
    ) async throws -> ExerciseCatalogItem {
        try await writer.transaction { context in
            let object = try ExerciseManagedObjectMapping.requireCatalogItem(id: id.rawValue, in: context)
            let current = try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
            let updated = try current.updatingCustom(canonicalName: name, recordMode: recordMode, now: now)
            try ExerciseManagedObjectMapping.acquireUnifiedClaim(
                try ExerciseNameClaim(
                    normalizedName: updated.normalizedName,
                    ownerKind: .custom,
                    ownerID: updated.id,
                    scope: .activeCatalog
                ),
                in: context
            )
            if current.normalizedName != updated.normalizedName {
                try ExerciseManagedObjectMapping.deleteClaim(
                    normalizedName: current.normalizedName,
                    ownerID: current.id.rawValue,
                    in: context
                )
            }
            ExerciseManagedObjectMapping.apply(updated, to: object)
            return try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
        }
    }

    public func archiveCustom(id: StableExerciseID, now: Date) async throws -> ExerciseCatalogItem {
        try await writer.transaction { context in
            let object = try ExerciseManagedObjectMapping.requireCatalogItem(id: id.rawValue, in: context)
            let current = try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
            let archived = try current.archived(now: now)
            ExerciseManagedObjectMapping.apply(archived, to: object)
            try ExerciseManagedObjectMapping.deleteClaims(ownerID: id.rawValue, in: context)
            return try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
        }
    }

    public func restoreCustom(id: StableExerciseID, now: Date) async throws -> ExerciseCatalogItem {
        try await writer.transaction { context in
            let object = try ExerciseManagedObjectMapping.requireCatalogItem(id: id.rawValue, in: context)
            let current = try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
            let restored = try current.restored(now: now)
            try ExerciseManagedObjectMapping.acquireUnifiedClaim(
                try ExerciseNameClaim(
                    normalizedName: restored.normalizedName,
                    ownerKind: .custom,
                    ownerID: restored.id,
                    scope: .activeCatalog
                ),
                in: context
            )
            ExerciseManagedObjectMapping.apply(restored, to: object)
            return try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
        }
    }

    public func setPreference(
        exerciseID: StableExerciseID,
        alias: String?,
        isFavorite: Bool?,
        isHidden: Bool?
    ) async throws -> ExercisePreference {
        try await writer.transaction { context in
            _ = try ExerciseManagedObjectMapping.requireCatalogItem(id: exerciseID.rawValue, in: context)
            let existing = try ExerciseManagedObjectMapping.fetchPreference(
                exerciseID: exerciseID.rawValue,
                in: context
            )
            let current =
                try existing.map { try ExerciseManagedObjectMapping.makePreference(from: $0) }
                ?? ExercisePreference(exerciseID: exerciseID)
            let aliasUpdate: NormalizedName??
            if let alias {
                let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    aliasUpdate = .some(nil)
                } else {
                    aliasUpdate = .some(try NormalizedName(alias))
                }
            } else {
                aliasUpdate = nil
            }
            let updated = current.updating(alias: aliasUpdate, isFavorite: isFavorite, isHidden: isHidden)
            let object = try ExerciseManagedObjectMapping.upsertPreference(updated, in: context)
            return try ExerciseManagedObjectMapping.makePreference(from: object)
        }
    }

    public func acquireUnifiedClaim(_ claim: ExerciseNameClaim) async throws {
        try await writer.transaction { context in
            try ExerciseManagedObjectMapping.acquireUnifiedClaim(claim, in: context)
        }
    }

    public func releaseClaims(ownerID: StableExerciseID) async throws {
        try await writer.transaction { context in
            try ExerciseManagedObjectMapping.deleteClaims(ownerID: ownerID.rawValue, in: context)
        }
    }

    public func releaseSessionScopeClaims() async throws {
        try await writer.transaction { context in
            try ExerciseManagedObjectMapping.deleteClaims(scope: .currentSession, in: context)
        }
    }

    public func hasCatalogRow(id: StableExerciseID) async throws -> Bool {
        try await writer.read { context in
            try ExerciseManagedObjectMapping.fetchCatalogItem(id: id.rawValue, in: context) != nil
        }
    }

    #if DEBUG
        public func upsertCatalogItemForTesting(_ item: ExerciseCatalogItem) async throws -> ExerciseCatalogItem {
            try await writer.transaction { context in
                let object = try ExerciseManagedObjectMapping.upsertCatalogItem(item, in: context)
                return try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
            }
        }

        public func upsertClaimForTesting(_ claim: ExerciseNameClaim) async throws {
            try await acquireUnifiedClaim(claim)
        }
    #endif

    private static let forbiddenSeedNames: Set<String> = ["杠铃深蹲", "引体向上", "平板支撑"]

    private static let expectedPlaceholderIDs = [
        "fc.placeholder.squat",
        "fc.placeholder.pullup",
        "fc.placeholder.plank",
    ]

    private static let expectedPlaceholderNames: [String: String] = [
        "fc.placeholder.squat": "占位深蹲",
        "fc.placeholder.pullup": "占位引体",
        "fc.placeholder.plank": "占位支撑",
    ]

    private static func insertLoadedPlaceholderCatalog(
        _ catalog: PlaceholderExerciseCatalog,
        now: Date,
        in context: NSManagedObjectContext
    ) throws {
        let development = ExerciseProvenanceValidator.validate(
            catalog.provenance,
            gate: .developmentPlaceholder
        )
        guard development.isAccepted else {
            throw DomainError.incompatibleInput
        }
        let distributable = ExerciseProvenanceValidator.validate(
            catalog.provenance,
            gate: .distributable
        )
        if distributable.isAccepted {
            throw DomainError.incompatibleInput
        }
        for expectedID in expectedPlaceholderIDs {
            guard let loaded = catalog.exercises.first(where: { $0.id == expectedID }) else {
                throw DomainError.incompatibleInput
            }
            let normalized = try ExerciseNameNormalizer.normalized(loaded.canonicalName)
            guard normalized == expectedPlaceholderNames[expectedID] else {
                throw DomainError.incompatibleInput
            }
            guard !forbiddenSeedNames.contains(normalized) else {
                throw DomainError.incompatibleInput
            }
            let item = try ExerciseCatalogItem.makeBuiltIn(
                id: StableExerciseID(loaded.id),
                canonicalName: loaded.canonicalName,
                recordMode: loaded.recordMode,
                metadataVersion: catalog.metadataVersion,
                provenanceRef: loaded.provenanceRef,
                now: now
            )
            try insertBuiltIn(item, in: context)
        }
    }

    #if DEBUG
        private static func insertDebugPlaceholderCatalog(now: Date, in context: NSManagedObjectContext) throws {
            let items = try [
                ExerciseCatalogItem.makeBuiltIn(
                    id: StableExerciseID("fc.placeholder.squat"),
                    canonicalName: "占位深蹲",
                    recordMode: .weightReps,
                    metadataVersion: "placeholder.1",
                    provenanceRef: "placeholder.squat",
                    now: now
                ),
                ExerciseCatalogItem.makeBuiltIn(
                    id: StableExerciseID("fc.placeholder.pullup"),
                    canonicalName: "占位引体",
                    recordMode: .reps,
                    metadataVersion: "placeholder.1",
                    provenanceRef: "placeholder.pullup",
                    now: now
                ),
                ExerciseCatalogItem.makeBuiltIn(
                    id: StableExerciseID("fc.placeholder.plank"),
                    canonicalName: "占位支撑",
                    recordMode: .duration,
                    metadataVersion: "placeholder.1",
                    provenanceRef: "placeholder.plank",
                    now: now
                ),
            ]
            for item in items {
                guard !forbiddenSeedNames.contains(item.normalizedName) else {
                    throw DomainError.incompatibleInput
                }
                try insertBuiltIn(item, in: context)
            }
        }
    #endif

    private static func insertBuiltIn(_ item: ExerciseCatalogItem, in context: NSManagedObjectContext) throws {
        _ = try ExerciseManagedObjectMapping.upsertCatalogItem(item, in: context)
        try ExerciseManagedObjectMapping.acquireUnifiedClaim(
            try ExerciseNameClaim(
                normalizedName: item.normalizedName,
                ownerKind: .builtIn,
                ownerID: item.id,
                scope: .activeCatalog
            ),
            in: context
        )
    }

    private static func preferencesByExerciseID(
        in context: NSManagedObjectContext
    ) throws -> [String: ExercisePreference] {
        var result: [String: ExercisePreference] = [:]
        for object in try ExerciseManagedObjectMapping.fetchPreferences(in: context) {
            let preference = try ExerciseManagedObjectMapping.makePreference(from: object)
            result[preference.exerciseID.rawValue] = preference
        }
        return result
    }

    private static func matches(
        item: ExerciseCatalogItem,
        preference: ExercisePreference?,
        query: String
    ) -> Bool {
        if contains(item.canonicalName.value, query: query) {
            return true
        }
        if let alias = preference?.alias?.value, contains(alias, query: query) {
            return true
        }
        return false
    }

    private static func contains(_ value: String, query: String) -> Bool {
        value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
