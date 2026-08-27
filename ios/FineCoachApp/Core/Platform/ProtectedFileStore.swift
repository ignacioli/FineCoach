import Foundation

public enum ProtectedFileStoreError: Error, Equatable, Sendable {
    case auditFailed
    case primaryStoreMissing
}

public enum ProtectedFilePolicy: String, CaseIterable, Sendable {
    case business
    case ephemeralReport
    case backupCandidate

    var fileProtection: FileProtectionType {
        switch self {
        case .business, .backupCandidate:
            return .completeUnlessOpen
        case .ephemeralReport:
            return .complete
        }
    }
}

public struct FileProtectionAudit: Equatable, Sendable {
    public let protectionRawValue: String?
    public let isExcludedFromBackup: Bool

    public init(protectionRawValue: String?, isExcludedFromBackup: Bool) {
        self.protectionRawValue = protectionRawValue
        self.isExcludedFromBackup = isExcludedFromBackup
    }
}

public final class ProtectedFileStore: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    public func readData(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func writeData(
        _ data: Data,
        to url: URL,
        policy: ProtectedFilePolicy
    ) throws -> FileProtectionAudit {
        try prepareDirectory(at: url.deletingLastPathComponent(), policy: .business)
        try data.write(to: url, options: .atomic)
        try apply(policy: policy, to: url)
        return try audit(url: url)
    }

    private func replaceItem(at url: URL, withItemAt replacementURL: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: replacementURL)
        } else {
            try fileManager.moveItem(at: replacementURL, to: url)
        }
        try apply(policy: .business, to: url)
    }

    @discardableResult
    public func prepareDirectory(
        at url: URL,
        policy: ProtectedFilePolicy = .business
    ) throws -> FileProtectionAudit {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try apply(policy: policy, to: url)
        return try audit(url: url)
    }

    @discardableResult
    public func atomicReplace(
        data: Data,
        at url: URL,
        policy: ProtectedFilePolicy = .business
    ) throws -> FileProtectionAudit {
        try prepareDirectory(at: url.deletingLastPathComponent(), policy: .business)
        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).tmp-\(UUID().uuidString)",
            isDirectory: false
        )
        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        try data.write(to: temporaryURL, options: .atomic)
        try apply(policy: policy, to: temporaryURL)
        try replaceItem(at: url, withItemAt: temporaryURL)
        try apply(policy: policy, to: url)
        return try audit(url: url)
    }

    public func apply(policy: ProtectedFilePolicy, to url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: policy.fileProtection.rawValue],
            ofItemAtPath: url.path
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
        let result = try audit(url: url)
        guard result.protectionRawValue == policy.fileProtection.rawValue,
            result.isExcludedFromBackup
        else {
            throw ProtectedFileStoreError.auditFailed
        }
    }

    @discardableResult
    public func secureSQLiteStoreArtifacts(
        at storeURL: URL,
        policy: ProtectedFilePolicy = .business
    ) throws -> [URL: FileProtectionAudit] {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            throw ProtectedFileStoreError.primaryStoreMissing
        }

        let candidates = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm"),
        ]
        var results: [URL: FileProtectionAudit] = [:]
        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            try apply(policy: policy, to: candidate)
            results[candidate] = try audit(url: candidate)
        }
        return results
    }

    public func audit(url: URL) throws -> FileProtectionAudit {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let protection = attributes[.protectionKey] as? String
        let resourceValues = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        return FileProtectionAudit(
            protectionRawValue: protection,
            isExcludedFromBackup: resourceValues.isExcludedFromBackup ?? false
        )
    }
}
