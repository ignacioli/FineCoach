import CoreData
import Foundation

public struct ExerciseCatalogSyncResult: Equatable, Sendable {
    public let insertedCount: Int
    public let updatedCount: Int
    public let retiredCount: Int
    public let hiddenByCustomClaimCount: Int

    public init(
        insertedCount: Int,
        updatedCount: Int,
        retiredCount: Int,
        hiddenByCustomClaimCount: Int
    ) {
        self.insertedCount = insertedCount
        self.updatedCount = updatedCount
        self.retiredCount = retiredCount
        self.hiddenByCustomClaimCount = hiddenByCustomClaimCount
    }
}

public struct CoreDataExerciseRepository: Sendable {
    private let writer: PersistenceWriter

    public init(writer: PersistenceWriter) {
        self.writer = writer
    }

    public func seedPlaceholderCatalogIfNeeded(now: Date) async throws {
        let catalog = try PlaceholderExerciseCatalogLoader.loadFromBundle(Bundle.main)
        _ = try await syncBuiltInCatalog(catalog, now: now)
    }

    /// Synchronizes the shipped built-in catalog in one writer transaction.
    /// The decoded catalog is supplied by the caller so migration, rollback and
    /// backup-restore tests can exercise the same path without replacing the
    /// application bundle.
    @discardableResult
    public func syncBuiltInCatalog(
        _ catalog: PlaceholderExerciseCatalog,
        now: Date
    ) async throws -> ExerciseCatalogSyncResult {
        try Self.validateCatalog(catalog)
        return try await writer.transaction { context in
            try Self.synchronize(catalog, now: now, in: context)
        }
    }

    public func searchActive(query: String, includeHidden: Bool = false) async throws -> [ExerciseLibraryEntry] {
        try await writer.read { context in
            let objects = try ExerciseManagedObjectMapping.fetchActiveCatalogItems(in: context)
            let preferences = try Self.preferencesByExerciseID(in: context)
            let customClaimNames = try Self.activeCustomClaimNames(in: context)
            let sessionClaimNames = try Self.activeSessionClaimNames(in: context)
            let normalizedQuery =
                query
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping
            let normalizedPinyinQuery = ExercisePinyinSearch.normalizedQuery(normalizedQuery)
            var entries: [ExerciseLibraryEntry] = []
            entries.reserveCapacity(objects.count)
            for object in objects {
                let item = try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
                let preference = preferences[item.id.rawValue]
                if item.lifecycle != .active || item.isRetired
                    || (item.kind == .builtIn
                        && (customClaimNames.contains(item.normalizedName)
                            || sessionClaimNames.contains(item.normalizedName)))
                {
                    continue
                }
                if !includeHidden, preference?.isHidden == true {
                    continue
                }
                let facet = PlaceholderExerciseCatalogLoader.facet(forExerciseID: item.id.rawValue)
                if !normalizedQuery.isEmpty,
                    !Self.matches(
                        item: item,
                        preference: preference,
                        facet: facet,
                        query: normalizedQuery,
                        pinyinQuery: normalizedPinyinQuery
                    )
                {
                    continue
                }
                entries.append(
                    ExerciseLibraryEntry(
                        item: item,
                        preference: preference,
                        primaryMuscleGroup: item.kind == .builtIn ? facet?.primaryMuscleGroup : nil,
                        equipmentClass: item.kind == .builtIn ? facet?.equipmentClass : nil,
                        secondaryMuscleGroups: item.kind == .builtIn ? facet?.secondaryMuscleGroups ?? [] : [],
                        isUnilateralByDefault: item.kind == .builtIn && facet?.isUnilateral == true
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

    /// Loads an item for the visible exercise selector. Historical and
    /// template callers must continue to use `catalogItem(id:)`, which is an
    /// id-only read and intentionally does not apply browse visibility rules.
    public func selectableCatalogItem(id: StableExerciseID) async throws -> ExerciseCatalogItem {
        try await writer.read { context in
            let object = try ExerciseManagedObjectMapping.requireCatalogItem(id: id.rawValue, in: context)
            let item = try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
            guard item.lifecycle == .active, !item.isRetired else {
                throw DomainError.invalidState
            }
            let preference = try ExerciseManagedObjectMapping.fetchPreference(
                exerciseID: id.rawValue,
                in: context
            ).map { try ExerciseManagedObjectMapping.makePreference(from: $0) }
            guard preference?.isHidden != true else {
                throw DomainError.invalidState
            }
            if item.kind == .builtIn {
                let customNames = try Self.activeCustomClaimNames(in: context)
                let sessionNames = try Self.activeSessionClaimNames(in: context)
                guard !customNames.contains(item.normalizedName), !sessionNames.contains(item.normalizedName) else {
                    throw DomainError.invalidState
                }
            }
            return item
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
            try Self.acquireCustomNameClaim(item.normalizedName, ownerID: item.id, in: context)
            let object = try ExerciseManagedObjectMapping.upsertCatalogItem(item, in: context)
            try Self.reconcileBuiltInClaims(in: context)
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
            try Self.acquireCustomNameClaim(updated.normalizedName, ownerID: updated.id, in: context)
            if current.normalizedName != updated.normalizedName {
                try ExerciseManagedObjectMapping.deleteClaim(
                    normalizedName: current.normalizedName,
                    ownerID: current.id.rawValue,
                    in: context
                )
            }
            ExerciseManagedObjectMapping.apply(updated, to: object)
            try Self.reconcileBuiltInClaims(in: context)
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
            try Self.reconcileBuiltInClaims(in: context)
            return try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
        }
    }

    public func restoreCustom(id: StableExerciseID, now: Date) async throws -> ExerciseCatalogItem {
        try await writer.transaction { context in
            let object = try ExerciseManagedObjectMapping.requireCatalogItem(id: id.rawValue, in: context)
            let current = try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
            let restored = try current.restored(now: now)
            try Self.acquireCustomNameClaim(restored.normalizedName, ownerID: restored.id, in: context)
            ExerciseManagedObjectMapping.apply(restored, to: object)
            try Self.reconcileBuiltInClaims(in: context)
            return try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
        }
    }

    public func setPreference(
        exerciseID: StableExerciseID,
        alias: String?,
        isFavorite: Bool?,
        isHidden: Bool?,
        isAssisted: Bool? = nil,
        isUnilateral: Bool? = nil
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
                isAssisted: isAssisted,
                isUnilateral: isUnilateral
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
            try Self.reconcileBuiltInClaims(in: context)
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
            try Self.reconcileBuiltInClaims(in: context)
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

    public func hasBuiltInCatalog() async throws -> Bool {
        try await writer.read { context in
            try ExerciseManagedObjectMapping.hasBuiltInCatalog(in: context)
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

    private static func validateCatalog(_ catalog: PlaceholderExerciseCatalog) throws {
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
        guard !catalog.exercises.isEmpty else {
            throw DomainError.incompatibleInput
        }
        guard !catalog.metadataVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainError.incompatibleInput
        }
        let recordIDs = Set(catalog.provenance.records.map(\.recordID))
        guard recordIDs.count == catalog.provenance.records.count,
            catalog.provenance.records.count == catalog.exercises.count
        else {
            throw DomainError.incompatibleInput
        }
        var seenIDs = Set<String>()
        var seenNames = Set<String>()
        var seenRecordIDs = Set<String>()
        for loaded in catalog.exercises {
            let id = try StableExerciseID(loaded.id)
            guard recordIDs.contains(loaded.provenanceRef) else {
                throw DomainError.incompatibleInput
            }
            guard seenIDs.insert(id.rawValue).inserted else {
                throw DomainError.incompatibleInput
            }
            guard seenRecordIDs.insert(loaded.provenanceRef).inserted else {
                throw DomainError.conflict
            }
            let normalized = try ExerciseNameNormalizer.normalized(loaded.canonicalName)
            guard seenNames.insert(normalized).inserted else {
                throw DomainError.conflict
            }
            guard ExerciseCatalogBrowse.muscleGroupOrder.contains(loaded.primaryMuscleGroup ?? ""),
                ExerciseCatalogBrowse.equipmentClassOrder.contains(loaded.equipmentClass ?? "")
            else {
                throw DomainError.incompatibleInput
            }
            guard
                (loaded.secondaryMuscleGroups ?? []).allSatisfy({
                    ExerciseCatalogBrowse.muscleGroupOrder.contains($0)
                })
            else {
                throw DomainError.incompatibleInput
            }
        }
    }

    private static func synchronize(
        _ catalog: PlaceholderExerciseCatalog,
        now: Date,
        in context: NSManagedObjectContext
    ) throws -> ExerciseCatalogSyncResult {
        let existingObjects = try ExerciseManagedObjectMapping.fetchBuiltInCatalogItems(in: context)
        var existingByID: [String: NSManagedObject] = [:]
        for object in existingObjects {
            guard let id = object.value(forKey: "id") as? String else {
                throw DomainError.incompatibleInput
            }
            existingByID[id] = object
        }

        var insertedCount = 0
        var updatedCount = 0
        var retiredCount = 0
        for loaded in catalog.exercises {
            let id = try StableExerciseID(loaded.id)
            let retired = loaded.retired ?? false
            if let object = existingByID.removeValue(forKey: id.rawValue) {
                let current = try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
                guard current.kind == .builtIn else {
                    throw DomainError.conflict
                }
                let changed =
                    current.canonicalName.value != loaded.canonicalName
                    || current.recordMode != loaded.recordMode
                    || current.metadataVersion != catalog.metadataVersion
                    || current.provenanceRef != loaded.provenanceRef
                    || current.isRetired != retired
                let updated = try ExerciseCatalogItem(
                    id: id,
                    kind: .builtIn,
                    canonicalName: NormalizedName(loaded.canonicalName),
                    recordMode: loaded.recordMode,
                    metadataVersion: catalog.metadataVersion,
                    lifecycle: .active,
                    provenanceRef: loaded.provenanceRef,
                    createdAtUTC: current.createdAtUTC,
                    updatedAtUTC: changed ? now : current.updatedAtUTC,
                    isRetired: retired
                )
                if changed {
                    updatedCount += 1
                    if retired {
                        retiredCount += 1
                    }
                }
                ExerciseManagedObjectMapping.apply(updated, to: object)
            } else {
                if let existing = try ExerciseManagedObjectMapping.fetchCatalogItem(id: id.rawValue, in: context) {
                    let current = try ExerciseManagedObjectMapping.makeCatalogItem(from: existing)
                    guard current.kind == .builtIn else {
                        throw DomainError.conflict
                    }
                }
                let item = try ExerciseCatalogItem.makeBuiltIn(
                    id: id,
                    canonicalName: loaded.canonicalName,
                    recordMode: loaded.recordMode,
                    metadataVersion: catalog.metadataVersion,
                    provenanceRef: loaded.provenanceRef,
                    now: now,
                    isRetired: retired
                )
                _ = try ExerciseManagedObjectMapping.upsertCatalogItem(item, in: context)
                insertedCount += 1
                if retired {
                    retiredCount += 1
                }
            }
        }

        // Keep removed built-ins addressable by id while making them invisible
        // to browse flows. Their old name and timestamps stay intact.
        for object in existingByID.values {
            let current = try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
            guard !current.isRetired else {
                continue
            }
            let retired = try ExerciseCatalogItem(
                id: current.id,
                kind: .builtIn,
                canonicalName: current.canonicalName,
                recordMode: current.recordMode,
                metadataVersion: current.metadataVersion,
                lifecycle: .active,
                provenanceRef: current.provenanceRef,
                createdAtUTC: current.createdAtUTC,
                updatedAtUTC: now,
                isRetired: true
            )
            ExerciseManagedObjectMapping.apply(retired, to: object)
            retiredCount += 1
            updatedCount += 1
        }

        let hiddenByCustomClaimCount = try reconcileBuiltInClaims(in: context)
        return ExerciseCatalogSyncResult(
            insertedCount: insertedCount,
            updatedCount: updatedCount,
            retiredCount: retiredCount,
            hiddenByCustomClaimCount: hiddenByCustomClaimCount
        )
    }

    private static func acquireCustomNameClaim(
        _ normalizedName: String,
        ownerID: StableExerciseID,
        in context: NSManagedObjectContext
    ) throws {
        // Preserve the established custom exercise contract: a custom create
        // or rename still conflicts with an existing built-in claim.
        try ExerciseManagedObjectMapping.acquireUnifiedClaim(
            try ExerciseNameClaim(
                normalizedName: normalizedName,
                ownerKind: .custom,
                ownerID: ownerID,
                scope: .activeCatalog
            ),
            in: context
        )
    }

    private static func activeCustomClaimNames(in context: NSManagedObjectContext) throws -> Set<String> {
        Set(
            try ExerciseManagedObjectMapping.fetchClaims(
                ownerKind: .custom,
                scope: .activeCatalog,
                in: context
            ).compactMap { $0.value(forKey: "normalizedName") as? String }
        )
    }

    private static func activeSessionClaimNames(in context: NSManagedObjectContext) throws -> Set<String> {
        Set(
            try ExerciseManagedObjectMapping.fetchClaims(
                ownerKind: .sessionOnly,
                scope: .currentSession,
                in: context
            ).compactMap { $0.value(forKey: "normalizedName") as? String }
        )
    }

    @discardableResult
    static func reconcileBuiltInClaims(in context: NSManagedObjectContext) throws -> Int {
        let customNames = try activeCustomClaimNames(in: context)
        let sessionNames = try activeSessionClaimNames(in: context)
        var desiredClaims: [String: ExerciseNameClaim] = [:]
        var hiddenCount = 0
        for object in try ExerciseManagedObjectMapping.fetchBuiltInCatalogItems(in: context) {
            let item = try ExerciseManagedObjectMapping.makeCatalogItem(from: object)
            guard item.lifecycle == .active, !item.isRetired else {
                continue
            }
            if customNames.contains(item.normalizedName) || sessionNames.contains(item.normalizedName) {
                hiddenCount += 1
                continue
            }
            let claim = try ExerciseNameClaim(
                normalizedName: item.normalizedName,
                ownerKind: .builtIn,
                ownerID: item.id,
                scope: .activeCatalog
            )
            desiredClaims[claim.normalizedName] = claim
        }

        var retainedOwnerIDs = Set<String>()
        for claimObject in try ExerciseManagedObjectMapping.fetchClaims(
            ownerKind: .builtIn,
            scope: .activeCatalog,
            in: context
        ) {
            let existing = try ExerciseManagedObjectMapping.makeClaim(from: claimObject)
            if desiredClaims[existing.normalizedName]?.ownerID == existing.ownerID {
                retainedOwnerIDs.insert(existing.ownerID.rawValue)
            } else {
                context.delete(claimObject)
            }
        }

        for desired in desiredClaims.values where !retainedOwnerIDs.contains(desired.ownerID.rawValue) {
            if let existingObject = try ExerciseManagedObjectMapping.fetchClaim(
                normalizedName: desired.normalizedName,
                in: context
            ) {
                let existing = try ExerciseManagedObjectMapping.makeClaim(from: existingObject)
                if existing.ownerID == desired.ownerID, existing.scope == desired.scope {
                    continue
                }
                if existing.ownerKind == .custom, existing.scope == .activeCatalog {
                    // The custom claim is the source of truth for the local
                    // visibility rule and is never replaced by a built-in.
                    continue
                }
                if existing.ownerKind == .sessionOnly, existing.scope == .currentSession {
                    // An in-progress Session-only exercise temporarily owns
                    // this name; the built-in remains hidden until release.
                    continue
                }
                guard existing.ownerKind == .builtIn, existing.scope == .activeCatalog else {
                    // A future non-catalog claim belongs to another active
                    // workflow. Do not silently release it; this unapproved
                    // collision must abort the transaction.
                    throw DomainError.conflict
                }
                context.delete(existingObject)
            }
            try ExerciseManagedObjectMapping.acquireUnifiedClaim(desired, in: context)
        }
        return hiddenCount
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
        query: String,
        pinyinQuery: String
    ) -> Bool {
        if contains(item.canonicalName.value, query: query) {
            return true
        }
        if pinyinMatches(item: item, value: item.canonicalName.value, query: pinyinQuery) {
            return true
        }
        if let alias = preference?.alias?.value, contains(alias, query: query) {
            return true
        }
        if let alias = preference?.alias?.value,
            pinyinMatches(item: item, value: alias, query: pinyinQuery)
        {
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

    private static func pinyinMatches(
        item: ExerciseCatalogItem,
        value: String,
        query: String
    ) -> Bool {
        guard !query.isEmpty else {
            return false
        }
        let tokens: ExercisePinyinSearchTokens
        if item.kind == .builtIn,
            let cached = PlaceholderExerciseCatalogLoader.pinyinTokens(forExerciseID: item.id.rawValue),
            cached.sourceValue == value
        {
            tokens = cached
        } else {
            tokens = ExercisePinyinSearch.tokens(for: value)
        }
        return ExercisePinyinSearch.matches(tokens: tokens, normalizedQuery: query)
    }

    private static func contains(_ value: String, query: String) -> Bool {
        value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
