import CoreData
import Foundation

public enum PersistenceControllerError: Error, Equatable, LocalizedError, Sendable {
    case modelUnavailable
    case storeLoadFailed

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "本地数据模型不可用。"
        case .storeLoadFailed:
            return "本地数据存储无法打开。"
        }
    }
}

private final class PersistenceBundleMarker: NSObject {}

private final class PersistenceLoadResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    func set(error: Error?) {
        lock.lock()
        storedError = error
        lock.unlock()
    }

    func error() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }
}

public final class PersistenceController: @unchecked Sendable {
    private let container: NSPersistentContainer
    public let writer: PersistenceWriter
    public let storeURL: URL
    private let protectedFileStore: ProtectedFileStore
    private let inMemory: Bool

    public convenience init(
        storeURL: URL,
        model: NSManagedObjectModel? = nil,
        inMemory: Bool = false,
        protectedFileStore: ProtectedFileStore = ProtectedFileStore()
    ) throws {
        try self.init(
            storeURL: storeURL,
            model: model,
            inMemory: inMemory,
            protectedFileStore: protectedFileStore,
            writerPreSaveCheck: {}
        )
    }

    #if DEBUG
        public convenience init(
            storeURL: URL,
            model: NSManagedObjectModel? = nil,
            inMemory: Bool = false,
            protectedFileStore: ProtectedFileStore = ProtectedFileStore(),
            faultInjectionBoundary: FaultInjectionBoundary
        ) throws {
            try self.init(
                storeURL: storeURL,
                model: model,
                inMemory: inMemory,
                protectedFileStore: protectedFileStore,
                writerPreSaveCheck: {
                    try faultInjectionBoundary.check(.persistenceWriterSave)
                }
            )
        }
    #endif

    private init(
        storeURL: URL,
        model: NSManagedObjectModel?,
        inMemory: Bool,
        protectedFileStore: ProtectedFileStore,
        writerPreSaveCheck: @escaping @Sendable () throws -> Void
    ) throws {
        let usedBundledModel = model == nil
        let resolvedModel = try model ?? Self.loadBundledModel()
        self.storeURL = storeURL
        self.protectedFileStore = protectedFileStore
        self.inMemory = inMemory

        if !inMemory {
            do {
                try protectedFileStore.prepareDirectory(
                    at: storeURL.deletingLastPathComponent(),
                    policy: .business
                )
            } catch {
                throw PersistenceControllerError.storeLoadFailed
            }
        }

        if !inMemory, protectedFileStore.fileExists(at: storeURL) {
            let metadata: [String: Any]
            do {
                metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                    ofType: NSSQLiteStoreType,
                    at: storeURL,
                    options: nil
                )
            } catch {
                throw PersistenceControllerError.storeLoadFailed
            }
            // Accept the store if it matches the current model exactly (fast path,
            // no migration needed) OR if it matches ANY known prior model version
            // bundled in FineCoachModel.momd (mergedModel finds a compatible version
            // by scanning all compiled .mom files) -- that is the signal a lightweight
            // migration below can actually succeed. A store matching neither is
            // genuinely foreign/corrupted data and MUST fail closed here, before the
            // container is even constructed, so the existing valid generation is never
            // touched (data-model SS7).
            let matchesCurrentModel = resolvedModel.isConfiguration(
                withName: nil,
                compatibleWithStoreMetadata: metadata
            )
            // Only the real bundled-model path may fall back to "any known prior
            // version" -- a caller that explicitly injects a model (tests, isolated
            // stores) wants that exact model checked, not the app's own momd.
            let matchesKnownPriorVersion =
                usedBundledModel
                && NSManagedObjectModel.mergedModel(
                    from: [Bundle(for: PersistenceBundleMarker.self), Bundle.main],
                    forStoreMetadata: metadata
                ) != nil
            guard matchesCurrentModel || matchesKnownPriorVersion else {
                throw PersistenceControllerError.storeLoadFailed
            }
        }

        let container = NSPersistentContainer(name: "FineCoachModel", managedObjectModel: resolvedModel)
        let description: NSPersistentStoreDescription
        if inMemory {
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
        } else {
            description = NSPersistentStoreDescription(url: storeURL)
            description.type = NSSQLiteStoreType
            description.setOption(
                FileProtectionType.completeUnlessOpen.rawValue as NSString,
                forKey: NSPersistentStoreFileProtectionKey
            )
        }

        // Store loading is deliberately synchronous at this boundary. Callers must not
        // observe a partially initialized container, and an existing store must remain
        // the source of truth if migration or model compatibility fails.
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        let loadResult = PersistenceLoadResult()
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            loadResult.set(error: error)
            semaphore.signal()
        }
        semaphore.wait()
        if loadResult.error() != nil {
            throw PersistenceControllerError.storeLoadFailed
        }
        if !inMemory {
            do {
                try protectedFileStore.secureSQLiteStoreArtifacts(at: storeURL)
            } catch {
                throw PersistenceControllerError.storeLoadFailed
            }
        }

        // Construct the NSError merge policy locally; reading Core Data's legacy
        // global singleton is rejected by Swift 6 strict concurrency checking.
        container.viewContext.mergePolicy = NSMergePolicy(merge: .errorMergePolicyType)
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.undoManager = nil
        let writerContext = container.newBackgroundContext()
        writerContext.mergePolicy = NSMergePolicy(merge: .errorMergePolicyType)
        writerContext.undoManager = nil
        self.container = container
        self.writer = PersistenceWriter(
            context: writerContext,
            secureStoreArtifacts: {
                guard !inMemory else {
                    return
                }
                _ = try protectedFileStore.secureSQLiteStoreArtifacts(at: storeURL)
            },
            preSaveCheck: writerPreSaveCheck
        )
    }

    public static func loadBundledModel(bundle: Bundle? = nil) throws -> NSManagedObjectModel {
        var bundles: [Bundle] = []
        if let bundle {
            bundles.append(bundle)
        }
        bundles.append(Bundle(for: PersistenceBundleMarker.self))
        bundles.append(Bundle.main)

        var seenIdentifiers = Set<String>()
        for candidate in bundles {
            let identifier = candidate.bundleURL.path
            guard seenIdentifiers.insert(identifier).inserted else {
                continue
            }
            if let modelURL = candidate.url(forResource: "FineCoachModel", withExtension: "momd"),
                let model = NSManagedObjectModel(contentsOf: modelURL)
            {
                return model
            }
            if let modelURL = candidate.url(forResource: "FineCoachV1", withExtension: "mom"),
                let model = NSManagedObjectModel(contentsOf: modelURL)
            {
                return model
            }
        }
        throw PersistenceControllerError.modelUnavailable
    }

    #if DEBUG
        /// Loads a single named model version (e.g. "FineCoachV1") straight out of the
        /// compiled FineCoachModel.momd bundle, bypassing the "current version" that
        /// loadBundledModel() resolves to. Test-only: lets a migration test build a
        /// fixture store under an older schema before opening it with the current model.
        public static func loadModelVersionForMigrationTesting(
            named versionName: String,
            bundle: Bundle? = nil
        ) throws -> NSManagedObjectModel {
            var bundles: [Bundle] = []
            if let bundle {
                bundles.append(bundle)
            }
            bundles.append(Bundle(for: PersistenceBundleMarker.self))
            bundles.append(Bundle.main)

            var seenIdentifiers = Set<String>()
            for candidate in bundles {
                let identifier = candidate.bundleURL.path
                guard seenIdentifiers.insert(identifier).inserted else {
                    continue
                }
                guard let momdURL = candidate.url(forResource: "FineCoachModel", withExtension: "momd") else {
                    continue
                }
                let versionURL = momdURL.appendingPathComponent("\(versionName).mom")
                if let model = NSManagedObjectModel(contentsOf: versionURL) {
                    return model
                }
            }
            throw PersistenceControllerError.modelUnavailable
        }
    #endif

    @discardableResult
    func secureStoreArtifacts() throws -> [URL: FileProtectionAudit] {
        guard !inMemory else {
            return [:]
        }
        return try protectedFileStore.secureSQLiteStoreArtifacts(at: storeURL)
    }

    func readInventoryBlocking() throws -> BackupInventory {
        var captured: Result<BackupInventory, Error>?
        container.viewContext.performAndWait {
            do {
                captured = .success(try BackupInventoryMapper.collect(in: container.viewContext))
            } catch {
                captured = .failure(error)
            }
        }
        guard let captured else {
            throw PersistenceControllerError.storeLoadFailed
        }
        return try captured.get()
    }

    func detachPersistentStores() throws {
        container.viewContext.performAndWait {
            container.viewContext.reset()
        }
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
    }

    #if DEBUG
        func shutdownForTesting() async throws {
            await writer.resetForTesting()
            try detachPersistentStores()
        }
    #endif
}
