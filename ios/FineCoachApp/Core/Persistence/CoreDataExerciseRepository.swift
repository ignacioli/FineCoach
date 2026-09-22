import CoreData
import Foundation

public struct CoreDataExerciseRepository: Sendable {
    private let writer: PersistenceWriter

    public init(writer: PersistenceWriter) {
        self.writer = writer
    }

    public func seedPlaceholderCatalogIfNeeded(now: Date) async throws {
        try await writer.transaction { context in
            let existingCount = try ExerciseManagedObjectMapping.builtInCatalogCount(in: context)
            if Self.builtInCatalogCountRange.contains(existingCount) {
                return
            }
            if existingCount > 0 {
                try Self.removeBuiltInCatalog(in: context)
            }
            let catalog = try PlaceholderExerciseCatalogLoader.loadFromBundle(Bundle.main)
            try Self.insertLoadedBuiltInCatalog(catalog, now: now, in: context)
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
                let facet = PlaceholderExerciseCatalogLoader.facet(forExerciseID: item.id.rawValue)
                if !normalizedQuery.isEmpty,
                    !Self.matches(
                        item: item,
                        preference: preference,
                        facet: facet,
                        query: normalizedQuery
                    )
                {
                    continue
                }
                entries.append(
                    ExerciseLibraryEntry(
                        item: item,
                        preference: preference,
                        primaryMuscleGroup: item.kind == .builtIn ? facet?.primaryMuscleGroup : nil,
                        equipmentClass: item.kind == .builtIn ? facet?.equipmentClass : nil
                    )
                )
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
        isHidden: Bool?,
        isAssisted: Bool? = nil
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
            let updated = current.updating(
                alias: aliasUpdate,
                isFavorite: isFavorite,
                isHidden: isHidden,
                isAssisted: isAssisted
            )
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

    public func reapSessionScopeClaims(keepingOwnerIDs: Set<String>) async throws {
        try await writer.transaction { context in
            for object in try ExerciseManagedObjectMapping.fetchClaims(scope: .currentSession, in: context) {
                let ownerID = object.value(forKey: "ownerID") as? String ?? ""
                if !keepingOwnerIDs.contains(ownerID) {
                    context.delete(object)
                }
            }
        }
    }

    public func releaseSessionScopeClaims() async throws {
        try await reapSessionScopeClaims(keepingOwnerIDs: [])
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

    private static let builtInCatalogCountRange = 100...150

    private static func insertLoadedBuiltInCatalog(
        _ catalog: PlaceholderExerciseCatalog,
        now: Date,
        in context: NSManagedObjectContext
    ) throws {
        let distributable = ExerciseProvenanceValidator.validate(
            catalog.provenance,
            gate: .distributable
        )
        guard distributable.isAccepted else {
            throw DomainError.incompatibleInput
        }
        let development = ExerciseProvenanceValidator.validate(
            catalog.provenance,
            gate: .developmentPlaceholder
        )
        if development.isAccepted {
            throw DomainError.incompatibleInput
        }
        guard builtInCatalogCountRange.contains(catalog.exercises.count) else {
            throw DomainError.incompatibleInput
        }
        let recordIDs = Set(catalog.provenance.records.map(\.recordID))
        var seenIDs = Set<String>()
        var seenNames = Set<String>()
        for loaded in catalog.exercises {
            guard recordIDs.contains(loaded.provenanceRef) else {
                throw DomainError.incompatibleInput
            }
            guard seenIDs.insert(loaded.id).inserted else {
                throw DomainError.incompatibleInput
            }
            let normalized = try ExerciseNameNormalizer.normalized(loaded.canonicalName)
            guard seenNames.insert(normalized).inserted else {
                throw DomainError.conflict
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

    private static func removeBuiltInCatalog(in context: NSManagedObjectContext) throws {
        for object in try ExerciseManagedObjectMapping.fetchBuiltInCatalogItems(in: context) {
            let item = try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
            for claim in try ExerciseManagedObjectMapping.fetchClaims(
                ownerID: item.id.rawValue,
                in: context
            ) {
                context.delete(claim)
            }
            if let preference = try ExerciseManagedObjectMapping.fetchPreference(
                exerciseID: item.id.rawValue,
                in: context
            ) {
                context.delete(preference)
            }
            context.delete(object)
        }
    }

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
        facet: ExerciseCatalogBrowseFacet?,
        query: String
    ) -> Bool {
        if contains(item.canonicalName.value, query: query) {
            return true
        }
        if let alias = preference?.alias?.value, contains(alias, query: query) {
            return true
        }
        if item.kind == .builtIn, let facet {
            if contains(facet.primaryMuscleGroup, query: query)
                || contains(facet.equipmentClass, query: query)
            {
                return true
            }
        }
        return false
    }

    private static func contains(_ value: String, query: String) -> Bool {
        value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
