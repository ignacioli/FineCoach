import Foundation

/// Holds the one encrypted delivery file of an export flow (data-model §7, D-M2-006).
///
/// Unlike `TempReportLease`, nothing here is kept for a retry: the file is deleted as soon as the
/// system takes it over, the user cancels, delivery fails, or the flow is left (AC-005,
/// M2-FR-023). A retry writes a freshly encoded file. Only the encrypted archive is ever
/// written; plaintext never reaches the file system.
public struct ArchiveExportTempLease: Sendable {
    public static let directoryName = "archive-export-flows"

    public let flowID: UUID
    public let directoryURL: URL
    public private(set) var fileURL: URL?

    private let fileStore: ProtectedFileStore

    public init(rootURL: URL, flowID: UUID, fileStore: ProtectedFileStore = ProtectedFileStore()) {
        self.flowID = flowID
        self.fileStore = fileStore
        self.directoryURL =
            Self.flowsRoot(in: rootURL).appendingPathComponent(flowID.uuidString, isDirectory: true)
    }

    /// Writes the archive into the protected, backup-excluded flow directory, replacing any
    /// file the lease still holds.
    @discardableResult
    public mutating func write(archive: Data, fileName: String) throws -> URL {
        try discard()
        _ = try fileStore.prepareDirectory(at: directoryURL, policy: .ephemeralReport)
        let url = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        _ = try fileStore.writeData(archive, to: url, policy: .ephemeralReport)
        fileURL = url
        return url
    }

    /// Removes the flow directory and everything in it. Safe to call repeatedly.
    public mutating func discard() throws {
        fileURL = nil
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }
        // Leave no empty parent behind; another flow's directory keeps it alive.
        let parent = directoryURL.deletingLastPathComponent()
        if let remaining = try? FileManager.default.contentsOfDirectory(atPath: parent.path), remaining.isEmpty {
            try? FileManager.default.removeItem(at: parent)
        }
    }

    /// Startup janitor: removes every flow directory not in `keepingFlowIDs` (and any stray
    /// entry), then the empty parent. Leftovers can only come from a process that died
    /// mid-flow.
    public static func cleanupOrphans(in rootURL: URL, keepingFlowIDs: Set<UUID> = []) throws {
        let flowsRoot = flowsRoot(in: rootURL)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: flowsRoot.path) else {
            return
        }
        let contents = try fileManager.contentsOfDirectory(at: flowsRoot, includingPropertiesForKeys: nil)
        for url in contents {
            if let flowID = UUID(uuidString: url.lastPathComponent), keepingFlowIDs.contains(flowID) {
                continue
            }
            try fileManager.removeItem(at: url)
        }
        if try fileManager.contentsOfDirectory(atPath: flowsRoot.path).isEmpty {
            try fileManager.removeItem(at: flowsRoot)
        }
    }

    private static func flowsRoot(in rootURL: URL) -> URL {
        rootURL.appendingPathComponent(directoryName, isDirectory: true)
    }
}
