import Foundation

public enum FileFlowJanitor {
    public static func cleanupOrphans(
        rootURL: URL,
        currentGenerationUUID: UUID,
        restoreIntent: RestoreIntent?,
        keepingFlowIDs: Set<UUID>
    ) throws {
        let directory = StoreGenerationDirectory(rootURL: rootURL)
        let fileManager = FileManager.default
        let store = ProtectedFileStore(fileManager: fileManager)

        var keptGenerations: Set<UUID> = [currentGenerationUUID]
        if let restoreIntent {
            keptGenerations.insert(restoreIntent.oldGenerationUUID)
            keptGenerations.insert(restoreIntent.newGenerationUUID)
        }

        if fileManager.fileExists(atPath: directory.generationsURL.path) {
            let generations = try fileManager.contentsOfDirectory(
                at: directory.generationsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for url in generations {
                let name = url.lastPathComponent
                guard let uuid = UUID(uuidString: name) else {
                    try fileManager.removeItem(at: url)
                    continue
                }
                if keptGenerations.contains(uuid) {
                    try store.apply(policy: .business, to: url)
                    continue
                }
                try fileManager.removeItem(at: url)
            }
        }

        if fileManager.fileExists(atPath: directory.flowURL.path) {
            let flows = try fileManager.contentsOfDirectory(
                at: directory.flowURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for url in flows {
                let name = url.lastPathComponent
                if name == FileFlowLeaseStore.fileName {
                    if let lease = try FileFlowLeaseStore.read(from: directory),
                        keepingFlowIDs.contains(lease.flowID)
                    {
                        continue
                    }
                    try fileManager.removeItem(at: url)
                    continue
                }
                guard let flowID = UUID(uuidString: name) else {
                    try fileManager.removeItem(at: url)
                    continue
                }
                if keepingFlowIDs.contains(flowID) {
                    continue
                }
                try fileManager.removeItem(at: url)
            }
        }

        if fileManager.fileExists(atPath: directory.currentPointerURL.path) {
            try store.apply(policy: .business, to: directory.currentPointerURL)
        }
        if fileManager.fileExists(atPath: directory.restoreIntentURL.path) {
            try store.apply(policy: .business, to: directory.restoreIntentURL)
        }
    }
}
