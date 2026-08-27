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

    @discardableResult
    func secureStoreArtifacts() throws -> [URL: FileProtectionAudit] {
        guard !inMemory else {
            return [:]
        }
        return try protectedFileStore.secureSQLiteStoreArtifacts(at: storeURL)
    }
}
