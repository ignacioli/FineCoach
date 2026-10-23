import Foundation

/// Crash-recovery snapshots, one file per in-progress Session.
///
/// `url` is the historical single-snapshot location
/// (`active-session-recovery-v1.json`). Per-session files are siblings named
/// `active-session-recovery-v1.<session-uuid>.json`, so pre-2026-10-22 data
/// keeps decoding and is migrated at launch. Filenames carry only the Session
/// UUID, never Student identity.
public struct ActiveSessionRecoveryStore: Sendable {
    private let url: URL
    private let protectedFileStore: ProtectedFileStore
    #if DEBUG
        private let faultInjectionBoundary: FaultInjectionBoundary?
    #endif

    public init(url: URL, protectedFileStore: ProtectedFileStore = ProtectedFileStore()) {
        self.url = url
        self.protectedFileStore = protectedFileStore
        #if DEBUG
            self.faultInjectionBoundary = nil
        #endif
    }

    #if DEBUG
        public init(
            url: URL,
            protectedFileStore: ProtectedFileStore = ProtectedFileStore(),
            faultInjectionBoundary: FaultInjectionBoundary
        ) {
            self.url = url
            self.protectedFileStore = protectedFileStore
            self.faultInjectionBoundary = faultInjectionBoundary
        }
    #endif

    /// Single-snapshot compatibility for the one-Session call sites and tests.
    /// Throws `DomainError.invalidState` when more than one snapshot exists so
    /// a caller can never silently pick a different Student's Session.
    public func load() throws -> ActiveSessionRecoverySnapshot? {
        let snapshots = try loadAll()
        guard snapshots.count <= 1 else {
            throw DomainError.invalidState
        }
        return snapshots.first
    }

    public func load(sessionID: StableUUID) throws -> ActiveSessionRecoverySnapshot? {
        let perSession: ActiveSessionRecoverySnapshot?
        if protectedFileStore.fileExists(at: snapshotURL(for: sessionID)) {
            perSession = try decodeSnapshot(at: snapshotURL(for: sessionID))
        } else {
            perSession = nil
        }
        let legacy = try loadLegacySnapshot()
        let matchingLegacy = legacy?.session.id == sessionID ? legacy : nil
        switch (perSession, matchingLegacy) {
        case (let perSession?, let legacy?):
            return perSession.revision >= legacy.revision ? perSession : legacy
        case (let perSession?, nil):
            return perSession
        case (nil, let legacy?):
            return legacy
        case (nil, nil):
            return nil
        }
    }

    public func loadAll() throws -> [ActiveSessionRecoverySnapshot] {
        var snapshots: [StableUUID: ActiveSessionRecoverySnapshot] = [:]
        for sessionID in try sessionIDsOnDisk() {
            let snapshot = try decodeSnapshot(at: snapshotURL(for: sessionID))
            snapshots[sessionID] = snapshot
        }
        if let legacy = try loadLegacySnapshot() {
            if let existing = snapshots[legacy.session.id] {
                if legacy.revision > existing.revision {
                    snapshots[legacy.session.id] = legacy
                }
            } else {
                snapshots[legacy.session.id] = legacy
            }
        }
        return snapshots.values.sorted {
            $0.session.startedAtUTC == $1.session.startedAtUTC
                ? $0.session.id.rawValue.uuidString < $1.session.id.rawValue.uuidString
                : $0.session.startedAtUTC < $1.session.startedAtUTC
        }
    }

    public func replace(_ snapshot: ActiveSessionRecoverySnapshot) throws {
        #if DEBUG
            try faultInjectionBoundary?.check(.recoverySnapshotReplace)
        #endif
        let data = try snapshot.encoded()
        do {
            _ = try protectedFileStore.atomicReplace(
                data: data,
                at: snapshotURL(for: snapshot.session.id),
                policy: .business
            )
            removeLegacyIfShadowed(by: snapshot)
        } catch {
            throw DomainError.persistenceFailed
        }
    }

    /// Moves a pre-2026-10-22 single snapshot to its per-Session file.
    public func migrateLegacySnapshot() throws {
        guard let legacy = try loadLegacySnapshot() else {
            return
        }
        let target = snapshotURL(for: legacy.session.id)
        if protectedFileStore.fileExists(at: target) {
            if let current = try? decodeSnapshot(at: target), current.revision >= legacy.revision {
                try? removeFile(at: url)
                return
            }
        }
        _ = try protectedFileStore.atomicReplace(data: try legacy.encoded(), at: target, policy: .business)
        try? removeFile(at: url)
    }

    public func migrateAndLoadAll() throws -> [ActiveSessionRecoverySnapshot] {
        try migrateLegacySnapshot()
        return try loadAll()
    }

    public func remove(sessionID: StableUUID) throws {
        if protectedFileStore.fileExists(at: snapshotURL(for: sessionID)) {
            try removeFile(at: snapshotURL(for: sessionID))
        }
        if let legacy = try? loadLegacySnapshot(), legacy.session.id == sessionID {
            try? removeFile(at: url)
        }
    }

    /// Compatibility: clears every snapshot.
    public func remove() throws {
        for sessionID in try sessionIDsOnDisk() {
            try? removeFile(at: snapshotURL(for: sessionID))
        }
        if protectedFileStore.fileExists(at: url) {
            try removeFile(at: url)
        }
    }

    public func isolate(sessionID: StableUUID) throws {
        let target = snapshotURL(for: sessionID)
        if protectedFileStore.fileExists(at: target) {
            let data = try protectedFileStore.readData(from: target)
            try isolateCorrupt(data: data, sourceURL: target)
        }
        if let legacy = try? loadLegacySnapshot(), legacy.session.id == sessionID {
            let data = try protectedFileStore.readData(from: url)
            try isolateCorrupt(data: data, sourceURL: url)
        }
    }

    /// Compatibility: isolates every snapshot (a generation mismatch applies
    /// to all of them, because they share one store generation).
    public func isolateCurrent() throws {
        for sessionID in try sessionIDsOnDisk() {
            let target = snapshotURL(for: sessionID)
            let data = try protectedFileStore.readData(from: target)
            try isolateCorrupt(data: data, sourceURL: target)
        }
        if protectedFileStore.fileExists(at: url) {
            let data = try protectedFileStore.readData(from: url)
            try isolateCorrupt(data: data, sourceURL: url)
        }
    }

    public func isolateCorrupt(data: Data) throws {
        try isolateCorrupt(data: data, sourceURL: url)
    }

    private func isolateCorrupt(data: Data, sourceURL: URL) throws {
        let isolated = sourceURL.deletingLastPathComponent().appendingPathComponent(
            "\(sourceURL.lastPathComponent).isolated",
            isDirectory: false
        )
        _ = try protectedFileStore.atomicReplace(data: data, at: isolated, policy: .business)
        if protectedFileStore.fileExists(at: sourceURL) {
            try? removeFile(at: sourceURL)
        }
    }

    private func loadLegacySnapshot() throws -> ActiveSessionRecoverySnapshot? {
        guard protectedFileStore.fileExists(at: url) else {
            return nil
        }
        return try decodeSnapshot(at: url)
    }

    private func decodeSnapshot(at fileURL: URL) throws -> ActiveSessionRecoverySnapshot {
        let data: Data
        do {
            data = try protectedFileStore.readData(from: fileURL)
        } catch {
            throw DomainError.persistenceFailed
        }
        if data.isEmpty {
            throw DomainError.incompatibleInput
        }
        do {
            return try ActiveSessionRecoverySnapshot.decode(data)
        } catch {
            try? isolateCorrupt(data: data, sourceURL: fileURL)
            throw DomainError.incompatibleInput
        }
    }

    private func removeLegacyIfShadowed(by snapshot: ActiveSessionRecoverySnapshot) {
        guard let legacy = try? loadLegacySnapshot(), legacy.session.id == snapshot.session.id,
            legacy.revision <= snapshot.revision
        else {
            return
        }
        try? removeFile(at: url)
    }

    private func removeFile(at fileURL: URL) throws {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw DomainError.invalidFileOperation
        }
    }

    private func snapshotURL(for sessionID: StableUUID) -> URL {
        let directory = url.deletingLastPathComponent()
        let extensionPart = url.pathExtension
        let stem = extensionPart.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        let name = "\(stem).\(sessionID.rawValue.uuidString.lowercased())"
        let filename = extensionPart.isEmpty ? name : "\(name).\(extensionPart)"
        return directory.appendingPathComponent(filename, isDirectory: false)
    }

    private func sessionIDsOnDisk() throws -> [StableUUID] {
        let directory = url.deletingLastPathComponent()
        let extensionPart = url.pathExtension
        let stem = extensionPart.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        let prefix = "\(stem)."
        return
            contents
            .filter { name in
                guard name.hasPrefix(prefix) else { return false }
                if !extensionPart.isEmpty {
                    guard name.hasSuffix(".\(extensionPart)") else { return false }
                }
                let raw = name.dropFirst(prefix.count).prefix { $0 != "." }
                return UUID(uuidString: String(raw)) != nil
            }
            .compactMap { name -> StableUUID? in
                let raw = name.dropFirst(prefix.count).prefix { $0 != "." }
                guard let uuid = UUID(uuidString: String(raw)) else {
                    return nil
                }
                return StableUUID(uuid)
            }
    }
}
