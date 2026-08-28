import Foundation

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

    public func load() throws -> ActiveSessionRecoverySnapshot? {
        guard protectedFileStore.fileExists(at: url) else {
            return nil
        }
        let data: Data
        do {
            data = try protectedFileStore.readData(from: url)
        } catch {
            throw DomainError.persistenceFailed
        }
        if data.isEmpty {
            return nil
        }
        do {
            return try ActiveSessionRecoverySnapshot.decode(data)
        } catch {
            try isolateCorrupt(data: data)
            throw DomainError.incompatibleInput
        }
    }

    public func replace(_ snapshot: ActiveSessionRecoverySnapshot) throws {
        #if DEBUG
            try faultInjectionBoundary?.check(.recoverySnapshotReplace)
        #endif
        let data = try snapshot.encoded()
        do {
            _ = try protectedFileStore.atomicReplace(data: data, at: url, policy: .business)
        } catch {
            throw DomainError.persistenceFailed
        }
    }

    public func remove() throws {
        guard protectedFileStore.fileExists(at: url) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw DomainError.invalidFileOperation
        }
    }

    public func isolateCurrent() throws {
        guard protectedFileStore.fileExists(at: url) else {
            return
        }
        let data = try protectedFileStore.readData(from: url)
        try isolateCorrupt(data: data)
    }

    public func isolateCorrupt(data: Data) throws {
        let isolated = url.deletingLastPathComponent().appendingPathComponent(
            "\(url.lastPathComponent).isolated",
            isDirectory: false
        )
        _ = try protectedFileStore.atomicReplace(data: data, at: isolated, policy: .business)
        if protectedFileStore.fileExists(at: url) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
