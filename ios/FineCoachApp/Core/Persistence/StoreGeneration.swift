import Foundation

public enum StoreGenerationError: Error, Equatable, LocalizedError, Sendable {
    case metadataMissing
    case metadataMismatch
    case pointerMismatch
    case invalidGeneration

    public var errorDescription: String? {
        switch self {
        case .metadataMissing:
            return "本地存储代次元数据缺失。"
        case .metadataMismatch, .pointerMismatch:
            return "本地存储代次不一致。"
        case .invalidGeneration:
            return "本地存储代次无效。"
        }
    }
}

public enum StoreGenerationValidationState: String, Codable, CaseIterable, Sendable {
    case candidate
    case validated
    case current
    case retired
}

public struct StoreGenerationMetadata: Codable, Equatable, Sendable {
    public static let currentSchemaVersion: UInt16 = 1

    public let generationUUID: UUID
    public let schemaVersion: UInt16
    public let createdAtUTC: Date
    public var validationState: StoreGenerationValidationState

    public init(
        generationUUID: UUID,
        schemaVersion: UInt16 = StoreGenerationMetadata.currentSchemaVersion,
        createdAtUTC: Date,
        validationState: StoreGenerationValidationState
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DomainError.incompatibleInput
        }
        self.generationUUID = generationUUID
        self.schemaVersion = schemaVersion
        self.createdAtUTC = createdAtUTC
        self.validationState = validationState
    }
}

public struct StoreGenerationDirectory: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public var generationsURL: URL {
        rootURL.appendingPathComponent("generations", isDirectory: true)
    }

    public var flowURL: URL {
        rootURL.appendingPathComponent("flows", isDirectory: true)
    }

    public var currentPointerURL: URL {
        rootURL.appendingPathComponent("current-generation.json", isDirectory: false)
    }

    public var activeRecoveryURL: URL {
        rootURL.appendingPathComponent("active-session-recovery-v1.json", isDirectory: false)
    }

    public func recoveryURL(for generationUUID: UUID) -> URL {
        generationURL(for: generationUUID).appendingPathComponent(
            "active-session-recovery-v1.json",
            isDirectory: false
        )
    }

    public var restoreIntentURL: URL {
        rootURL.appendingPathComponent("restore-intent-v1.json", isDirectory: false)
    }

    public func prepare() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: generationsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: flowURL, withIntermediateDirectories: true)
    }

    public func generationURL(for generationUUID: UUID) -> URL {
        generationsURL.appendingPathComponent(
            generationUUID.uuidString.lowercased(),
            isDirectory: true
        )
    }

    public func databaseURL(for generationUUID: UUID) -> URL {
        generationURL(for: generationUUID).appendingPathComponent("FineCoach.sqlite")
    }

    public func metadataURL(for generationUUID: UUID) -> URL {
        generationURL(for: generationUUID).appendingPathComponent("generation-metadata.json")
    }
}

public final class StoreGenerationMetadataStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let directory: StoreGenerationDirectory
    private let protectedFileStore: ProtectedFileStore
    private let writePreflight: @Sendable () throws -> Void

    public convenience init(
        directory: StoreGenerationDirectory,
        fileManager: FileManager = .default,
        protectedFileStore: ProtectedFileStore? = nil
    ) {
        self.init(
            directory: directory,
            fileManager: fileManager,
            protectedFileStore: protectedFileStore,
            writePreflight: {}
        )
    }

    #if DEBUG
        public convenience init(
            directory: StoreGenerationDirectory,
            fileManager: FileManager = .default,
            protectedFileStore: ProtectedFileStore? = nil,
            faultInjectionBoundary: FaultInjectionBoundary
        ) {
            self.init(
                directory: directory,
                fileManager: fileManager,
                protectedFileStore: protectedFileStore,
                writePreflight: {
                    try faultInjectionBoundary.check(.generationMetadataWrite)
                }
            )
        }
    #endif

    private init(
        directory: StoreGenerationDirectory,
        fileManager: FileManager,
        protectedFileStore: ProtectedFileStore?,
        writePreflight: @escaping @Sendable () throws -> Void
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.protectedFileStore = protectedFileStore ?? ProtectedFileStore(fileManager: fileManager)
        self.writePreflight = writePreflight
    }

    public func read(for generationUUID: UUID) throws -> StoreGenerationMetadata? {
        let url = directory.metadataURL(for: generationUUID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(StoreGenerationMetadata.self, from: data)
        guard metadata.generationUUID == generationUUID else {
            throw StoreGenerationError.metadataMismatch
        }
        // Codable decoding does not call the throwing memberwise initializer;
        // enforce the forward-only schema gate explicitly on disk reads.
        guard metadata.schemaVersion == StoreGenerationMetadata.currentSchemaVersion else {
            throw StoreGenerationError.metadataMismatch
        }
        return metadata
    }

    public func write(_ metadata: StoreGenerationMetadata) throws {
        try writePreflight()
        guard metadata.schemaVersion == StoreGenerationMetadata.currentSchemaVersion else {
            throw StoreGenerationError.metadataMismatch
        }
        let url = directory.metadataURL(for: metadata.generationUUID)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try protectedFileStore.atomicReplace(
            data: encoder.encode(metadata),
            at: url,
            policy: .business
        )
    }

    public func create(
        generationUUID: UUID = UUID(),
        createdAtUTC: Date = Date()
    ) throws -> StoreGenerationMetadata {
        let metadata = try StoreGenerationMetadata(
            generationUUID: generationUUID,
            createdAtUTC: createdAtUTC,
            validationState: .candidate
        )
        try write(metadata)
        return metadata
    }

    public func validate(
        generationUUID: UUID,
        expectedSchemaVersion: UInt16 = StoreGenerationMetadata.currentSchemaVersion
    ) throws -> StoreGenerationMetadata {
        guard let metadata = try read(for: generationUUID) else {
            throw StoreGenerationError.metadataMissing
        }
        guard metadata.schemaVersion == expectedSchemaVersion else {
            throw StoreGenerationError.metadataMismatch
        }
        return metadata
    }
}
