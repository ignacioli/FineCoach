import Foundation

public struct TempReportLease: Sendable {
    public let flowID: UUID
    public let directoryURL: URL
    public private(set) var fileURLs: [URL]

    private let fileStore: ProtectedFileStore

    public init(
        rootURL: URL,
        flowID: UUID,
        fileStore: ProtectedFileStore = ProtectedFileStore()
    ) throws {
        self.flowID = flowID
        self.fileStore = fileStore
        self.fileURLs = []
        self.directoryURL =
            rootURL
            .appendingPathComponent("share-report-flows", isDirectory: true)
            .appendingPathComponent(flowID.uuidString, isDirectory: true)
        _ = try fileStore.prepareDirectory(at: directoryURL, policy: .ephemeralReport)
    }

    @discardableResult
    public mutating func replacePreview(pages: [Data]) throws -> [URL] {
        let desiredNames = pages.enumerated().map { index, _ in
            String(format: "report-%03d.png", index + 1)
        }
        let existing = try reportFileURLs()
        for url in existing where !desiredNames.contains(url.lastPathComponent) {
            try FileManager.default.removeItem(at: url)
        }
        var written: [URL] = []
        written.reserveCapacity(pages.count)
        for (index, page) in pages.enumerated() {
            let url = directoryURL.appendingPathComponent(desiredNames[index], isDirectory: false)
            _ = try fileStore.writeData(page, to: url, policy: .ephemeralReport)
            written.append(url)
        }
        fileURLs = written
        return written
    }

    public func retainForRetry() {}

    public mutating func close() throws {
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }
        fileURLs = []
    }

    public mutating func completeSystemHandoff() throws {
        try close()
    }

    public static func cleanupOrphans(
        in rootURL: URL,
        keepingFlowIDs: Set<UUID>,
        fileStore: ProtectedFileStore = ProtectedFileStore()
    ) throws {
        let flowsRoot = rootURL.appendingPathComponent("share-report-flows", isDirectory: true)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: flowsRoot.path) else {
            return
        }
        let contents = try fileManager.contentsOfDirectory(
            at: flowsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for url in contents {
            let name = url.lastPathComponent
            guard let flowID = UUID(uuidString: name) else {
                try fileManager.removeItem(at: url)
                continue
            }
            if keepingFlowIDs.contains(flowID) {
                continue
            }
            try fileManager.removeItem(at: url)
        }
        _ = fileStore
    }

    private func reportFileURLs() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix("report-") && $0.pathExtension == "png" }
    }
}
