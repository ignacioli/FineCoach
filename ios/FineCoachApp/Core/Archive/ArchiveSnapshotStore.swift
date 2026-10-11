import Foundation

public enum ArchiveSnapshotStoreError: Error, Equatable, Sendable {
    /// The pointer exists but its snapshot is missing, unreadable or fails validation.
    case snapshotUnreadable
    /// The pointer or snapshot was written by a newer snapshot schema.
    case incompatibleSnapshotSchema
    /// An operation that needs an installed archive found none.
    case noArchive
}

/// `ArchiveViewer/current.json` (data-model §5).
struct ArchiveSnapshotPointer: Codable, Equatable, Sendable {
    let generation: UUID
    let snapshotSchemaVersion: Int
}

/// Local on-disk encoding of a snapshot, versioned independently of the archive file
/// (plan D-M2-002).
private struct StoredArchiveSnapshot: Codable {
    let snapshotSchemaVersion: Int
    let snapshot: ArchiveSnapshot
}

/// Viewer-mode storage under `Application Support/ArchiveViewer/` (plan D-M2-002):
///
///     ArchiveViewer/
///       current.json                      pointer, replaced atomically
///       generations/<uuid>/snapshot.bin   validated snapshot, fsynced before the pointer moves
///       display-settings.json             local display preferences
///       staging/                          transient import / replace scratch space
///
/// Every file and directory is excluded from backup and protected like the Coach store.
/// Nothing is kept in `UserDefaults`. Archive passwords never reach this type.
public final class ArchiveSnapshotStore: @unchecked Sendable {
    public static let currentSnapshotSchemaVersion = 1
    public static let directoryName = "ArchiveViewer"

    private let rootURL: URL
    private let fileManager: FileManager
    private let protectedFileStore: ProtectedFileStore
    private let afterGenerationWritten: @Sendable () throws -> Void
    private let afterPointerRemoved: @Sendable () throws -> Void
    private let lock = NSLock()

    public convenience init(
        rootURL: URL,
        fileManager: FileManager = .default,
        protectedFileStore: ProtectedFileStore? = nil
    ) {
        self.init(
            rootURL: rootURL,
            fileManager: fileManager,
            protectedFileStore: protectedFileStore,
            afterGenerationWritten: {},
            afterPointerRemoved: {}
        )
    }

    #if DEBUG
        public convenience init(
            rootURL: URL,
            fileManager: FileManager = .default,
            protectedFileStore: ProtectedFileStore? = nil,
            faultInjectionBoundary: FaultInjectionBoundary
        ) {
            self.init(
                rootURL: rootURL,
                fileManager: fileManager,
                protectedFileStore: protectedFileStore,
                afterGenerationWritten: {
                    try faultInjectionBoundary.check(.archiveStoreAfterGenerationWritten)
                },
                afterPointerRemoved: {
                    try faultInjectionBoundary.check(.archiveStoreAfterPointerRemoved)
                }
            )
        }
    #endif

    private init(
        rootURL: URL,
        fileManager: FileManager,
        protectedFileStore: ProtectedFileStore?,
        afterGenerationWritten: @escaping @Sendable () throws -> Void,
        afterPointerRemoved: @escaping @Sendable () throws -> Void
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.protectedFileStore = protectedFileStore ?? ProtectedFileStore(fileManager: fileManager)
        self.afterGenerationWritten = afterGenerationWritten
        self.afterPointerRemoved = afterPointerRemoved
    }

    /// `Application Support/ArchiveViewer`, a sibling of the Coach store folder.
    public static func defaultRootURL(fileManager: FileManager = .default) throws -> URL {
        guard
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw DomainError.invalidFileOperation
        }
        return applicationSupport.appendingPathComponent(directoryName, isDirectory: true)
    }

    // MARK: Layout

    private var pointerURL: URL { rootURL.appendingPathComponent("current.json", isDirectory: false) }
    private var generationsURL: URL { rootURL.appendingPathComponent("generations", isDirectory: true) }
    private var displaySettingsURL: URL {
        rootURL.appendingPathComponent("display-settings.json", isDirectory: false)
    }
    public var stagingURL: URL { rootURL.appendingPathComponent("staging", isDirectory: true) }

    private func snapshotURL(generation: UUID) -> URL {
        generationsURL
            .appendingPathComponent(generation.uuidString, isDirectory: true)
            .appendingPathComponent("snapshot.bin", isDirectory: false)
    }

    // MARK: Read

    /// The installed snapshot, or `nil` when no pointer exists. Throws when a pointer exists
    /// but its snapshot cannot be used; the install-state resolver treats that as "not
    /// viewer" (data-model §4).
    public func load() throws -> ArchiveSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let pointer = try readPointer() else {
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: snapshotURL(generation: pointer.generation))
        } catch {
            throw ArchiveSnapshotStoreError.snapshotUnreadable
        }
        do {
            let stored = try JSONDecoder().decode(StoredArchiveSnapshot.self, from: data)
            guard stored.snapshotSchemaVersion == pointer.snapshotSchemaVersion else {
                throw ArchiveSnapshotStoreError.snapshotUnreadable
            }
            try stored.snapshot.validateIntegrity()
            return stored.snapshot
        } catch let error as ArchiveSnapshotStoreError {
            throw error
        } catch {
            throw ArchiveSnapshotStoreError.snapshotUnreadable
        }
    }

    // MARK: Commit

    /// Writes a new generation, switches the pointer, then removes the previous generation.
    /// Display settings are preserved (M2-FR-032). If the pointer switch fails the new
    /// generation is removed and the previous state stands; a crash between the write and
    /// the switch leaves an orphan generation that the startup janitor removes.
    public func commit(snapshot: ArchiveSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }
        try snapshot.validateIntegrity()
        let previous = try? readPointer()

        try protectedFileStore.prepareDirectory(at: rootURL)
        try protectedFileStore.prepareDirectory(at: generationsURL)

        let generation = UUID()
        let generationDirectory = generationsURL.appendingPathComponent(generation.uuidString, isDirectory: true)
        let encoded = try JSONEncoder().encode(
            StoredArchiveSnapshot(
                snapshotSchemaVersion: Self.currentSnapshotSchemaVersion,
                snapshot: snapshot
            )
        )
        do {
            try protectedFileStore.prepareDirectory(at: generationDirectory)
            try writeSynchronized(encoded, to: snapshotURL(generation: generation))
        } catch {
            try? fileManager.removeItem(at: generationDirectory)
            throw error
        }

        try afterGenerationWritten()

        do {
            try writePointer(
                ArchiveSnapshotPointer(
                    generation: generation,
                    snapshotSchemaVersion: Self.currentSnapshotSchemaVersion
                )
            )
        } catch {
            try? fileManager.removeItem(at: generationDirectory)
            throw error
        }

        if let previous, previous.generation != generation {
            // The switch already happened; a leftover old generation is harmless and the
            // startup janitor removes it.
            try? fileManager.removeItem(
                at: generationsURL.appendingPathComponent(previous.generation.uuidString, isDirectory: true)
            )
        }
    }

    // MARK: Delete

    /// Removes the pointer first (so the archive is gone as far as the app is concerned),
    /// then every generation, the staging directory and the display settings.
    public func deleteAll() throws {
        lock.lock()
        defer { lock.unlock() }
        if fileManager.fileExists(atPath: pointerURL.path) {
            try fileManager.removeItem(at: pointerURL)
        }
        try afterPointerRemoved()
        try removeIfPresent(generationsURL)
        try removeIfPresent(stagingURL)
        try removeIfPresent(displaySettingsURL)
    }

    // MARK: Janitor

    /// Startup cleanup. Always empties `staging/`. With a readable pointer it also removes
    /// every generation other than the current one. With no pointer at all it removes all
    /// generations and the display settings (a delete or an interrupted first import left
    /// them behind). With an unreadable pointer it removes nothing else: the data may belong
    /// to a newer build.
    public func runStartupJanitor() throws {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return
        }
        try removeIfPresent(stagingURL)
        if fileManager.fileExists(atPath: pointerURL.path) {
            guard let pointer = try? readPointer() else {
                return
            }
            if fileManager.fileExists(atPath: generationsURL.path) {
                let entries = try fileManager.contentsOfDirectory(
                    at: generationsURL,
                    includingPropertiesForKeys: nil,
                    options: []
                )
                for entry in entries where UUID(uuidString: entry.lastPathComponent) != pointer.generation {
                    try fileManager.removeItem(at: entry)
                }
            }
            try protectedFileStore.apply(policy: .business, to: pointerURL)
        } else {
            try removeIfPresent(generationsURL)
            try removeIfPresent(displaySettingsURL)
        }
    }

    // MARK: Display settings

    /// Defaults when nothing valid is stored.
    public func readDisplaySettings() -> ArchiveDisplaySettings {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: displaySettingsURL),
            let settings = try? JSONDecoder().decode(ArchiveDisplaySettings.self, from: data)
        else {
            return .defaults
        }
        return settings
    }

    /// Only while an archive is installed; without one the file would be an orphan.
    public func writeDisplaySettings(_ settings: ArchiveDisplaySettings) throws {
        lock.lock()
        defer { lock.unlock() }
        guard try readPointer() != nil else {
            throw ArchiveSnapshotStoreError.noArchive
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try protectedFileStore.atomicReplace(
            data: encoder.encode(settings),
            at: displaySettingsURL,
            policy: .business
        )
    }

    // MARK: Internals

    private func readPointer() throws -> ArchiveSnapshotPointer? {
        guard fileManager.fileExists(atPath: pointerURL.path) else {
            return nil
        }
        let pointer: ArchiveSnapshotPointer
        do {
            pointer = try JSONDecoder().decode(ArchiveSnapshotPointer.self, from: Data(contentsOf: pointerURL))
        } catch {
            throw ArchiveSnapshotStoreError.snapshotUnreadable
        }
        guard pointer.snapshotSchemaVersion <= Self.currentSnapshotSchemaVersion else {
            throw ArchiveSnapshotStoreError.incompatibleSnapshotSchema
        }
        guard pointer.snapshotSchemaVersion == Self.currentSnapshotSchemaVersion else {
            throw ArchiveSnapshotStoreError.snapshotUnreadable
        }
        return pointer
    }

    private func writePointer(_ pointer: ArchiveSnapshotPointer) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try protectedFileStore.atomicReplace(data: encoder.encode(pointer), at: pointerURL, policy: .business)
    }

    /// Creates the empty file already protected and excluded from backup, writes, `fsync`s,
    /// then re-applies both and audits the readback. The plaintext is never on disk
    /// without protection or outside the backup exclusion.
    private func writeSynchronized(_ data: Data, to url: URL) throws {
        guard
            fileManager.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.protectionKey: ProtectedFilePolicy.business.fileProtection]
            )
        else {
            throw DomainError.invalidFileOperation
        }
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(excluded)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try protectedFileStore.apply(policy: .business, to: url)
    }

    private func removeIfPresent(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}
