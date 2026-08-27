import Combine
import CoreData
import Foundation

@MainActor
public final class AppEnvironment: ObservableObject {
    private let persistenceController: PersistenceController?
    public let persistenceWriter: PersistenceWriter?
    public let startupErrorDescription: String?

    public var isStorageAvailable: Bool {
        persistenceController != nil && persistenceWriter != nil
    }

    public static func bootstrap() -> AppEnvironment {
        do {
            return try AppEnvironment()
        } catch {
            return AppEnvironment(failure: error)
        }
    }

    public init(rootURL: URL? = nil) throws {
        let fileManager = FileManager.default
        let root: URL
        if let rootURL {
            root = rootURL.standardizedFileURL
        } else {
            guard
                let applicationSupport = fileManager.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first
            else {
                throw PersistenceControllerError.storeLoadFailed
            }
            root = applicationSupport.appendingPathComponent("FineCoach", isDirectory: true)
        }

        let directory = StoreGenerationDirectory(rootURL: root)
        let protectedStore = ProtectedFileStore(fileManager: fileManager)
        try protectedStore.prepareDirectory(at: directory.rootURL, policy: .business)
        try protectedStore.prepareDirectory(at: directory.generationsURL, policy: .business)
        try protectedStore.prepareDirectory(at: directory.flowURL, policy: .business)
        let pointerStore = CurrentGenerationPointerStore(
            url: directory.currentPointerURL,
            fileManager: fileManager,
            protectedFileStore: protectedStore
        )
        let metadataStore = StoreGenerationMetadataStore(
            directory: directory,
            fileManager: fileManager,
            protectedFileStore: protectedStore
        )

        let pointerExists = fileManager.fileExists(atPath: directory.currentPointerURL.path)
        if pointerExists {
            try protectedStore.apply(policy: .business, to: directory.currentPointerURL)
        }

        let controller: PersistenceController
        if let existing = try pointerStore.read() {
            let generationURL = directory.generationURL(for: existing.generationUUID)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: generationURL.path, isDirectory: &isDirectory),
                isDirectory.boolValue,
                fileManager.fileExists(atPath: directory.databaseURL(for: existing.generationUUID).path)
            else {
                throw StoreGenerationError.invalidGeneration
            }
            try protectedStore.apply(policy: .business, to: generationURL)
            try protectedStore.apply(
                policy: .business,
                to: directory.metadataURL(for: existing.generationUUID)
            )
            _ = try protectedStore.secureSQLiteStoreArtifacts(
                at: directory.databaseURL(for: existing.generationUUID)
            )
            let metadata = try metadataStore.validate(generationUUID: existing.generationUUID)
            guard metadata.validationState == .current else {
                throw StoreGenerationError.metadataMismatch
            }
            controller = try PersistenceController(
                storeURL: directory.databaseURL(for: existing.generationUUID),
                protectedFileStore: protectedStore
            )
        } else {
            let existingGenerations = try fileManager.contentsOfDirectory(
                at: directory.generationsURL,
                includingPropertiesForKeys: nil
            )
            guard existingGenerations.isEmpty else {
                throw StoreGenerationError.pointerMismatch
            }
            let generationUUID = UUID()
            let newPointer = try CurrentGenerationPointer(generationUUID: generationUUID)
            try protectedStore.prepareDirectory(
                at: directory.generationURL(for: generationUUID),
                policy: .business
            )
            controller = try PersistenceController(
                storeURL: directory.databaseURL(for: generationUUID),
                protectedFileStore: protectedStore
            )
            let metadata = try StoreGenerationMetadata(
                generationUUID: generationUUID,
                createdAtUTC: Date(),
                validationState: .current
            )
            try metadataStore.write(metadata)
            try pointerStore.replace(with: newPointer)
        }
        self.persistenceController = controller
        self.persistenceWriter = controller.writer
        self.startupErrorDescription = nil
    }

    private init(failure: Error) {
        self.persistenceController = nil
        self.persistenceWriter = nil
        self.startupErrorDescription = (failure as? LocalizedError)?.errorDescription ?? "本地存储暂不可用。"
    }
}

extension AppEnvironment {
    public static var unavailableForPreview: AppEnvironment {
        AppEnvironment(failure: PersistenceControllerError.storeLoadFailed)
    }
}
