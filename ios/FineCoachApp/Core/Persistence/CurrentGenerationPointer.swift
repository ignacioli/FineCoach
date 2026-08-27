import Foundation

public struct CurrentGenerationPointer: Codable, Equatable, Sendable {
    public static let currentSchemaVersion: UInt16 = 1

    public let generationUUID: UUID
    public let schemaVersion: UInt16

    public init(
        generationUUID: UUID,
        schemaVersion: UInt16 = CurrentGenerationPointer.currentSchemaVersion
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DomainError.incompatibleInput
        }
        self.generationUUID = generationUUID
        self.schemaVersion = schemaVersion
    }
}

public final class CurrentGenerationPointerStore: @unchecked Sendable {
    private let url: URL
    private let fileManager: FileManager
    private let protectedFileStore: ProtectedFileStore
    private let replacePreflight: @Sendable () throws -> Void

    public convenience init(
        url: URL,
        fileManager: FileManager = .default,
        protectedFileStore: ProtectedFileStore? = nil
    ) {
        self.init(
            url: url,
            fileManager: fileManager,
            protectedFileStore: protectedFileStore,
            replacePreflight: {}
        )
    }

    #if DEBUG
        public convenience init(
            url: URL,
            fileManager: FileManager = .default,
            protectedFileStore: ProtectedFileStore? = nil,
            faultInjectionBoundary: FaultInjectionBoundary
        ) {
            self.init(
                url: url,
                fileManager: fileManager,
                protectedFileStore: protectedFileStore,
                replacePreflight: {
                    try faultInjectionBoundary.check(.currentPointerReplace)
                }
            )
        }
    #endif

    private init(
        url: URL,
        fileManager: FileManager,
        protectedFileStore: ProtectedFileStore?,
        replacePreflight: @escaping @Sendable () throws -> Void
    ) {
        self.url = url
        self.fileManager = fileManager
        self.protectedFileStore = protectedFileStore ?? ProtectedFileStore(fileManager: fileManager)
        self.replacePreflight = replacePreflight
    }

    public func read() throws -> CurrentGenerationPointer? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let decoder = JSONDecoder()
        let pointer = try decoder.decode(CurrentGenerationPointer.self, from: Data(contentsOf: url))
        guard pointer.schemaVersion == CurrentGenerationPointer.currentSchemaVersion else {
            throw StoreGenerationError.pointerMismatch
        }
        return pointer
    }

    public func replace(with pointer: CurrentGenerationPointer) throws {
        try replacePreflight()
        guard pointer.schemaVersion == CurrentGenerationPointer.currentSchemaVersion else {
            throw StoreGenerationError.pointerMismatch
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try protectedFileStore.atomicReplace(
            data: encoder.encode(pointer),
            at: url,
            policy: .business
        )
    }
}
