import Darwin
import Foundation

public enum FileFlowKind: String, Codable, Sendable {
    case backupExport
    case restoreImport
}

public struct FileFlowLease: Equatable, Codable, Sendable {
    public let flowID: UUID
    public let kind: FileFlowKind
    public let phase: String
    public let managedRelativePaths: [String]
    public let byteBudget: UInt64

    public init(
        flowID: UUID,
        kind: FileFlowKind,
        phase: String,
        managedRelativePaths: [String],
        byteBudget: UInt64
    ) {
        self.flowID = flowID
        self.kind = kind
        self.phase = phase
        self.managedRelativePaths = managedRelativePaths
        self.byteBudget = byteBudget
    }
}

public enum FileFlowLeaseStore {
    public static let fileName = "exclusive-lease.json"

    public static func url(in directory: StoreGenerationDirectory) -> URL {
        directory.flowURL.appendingPathComponent(fileName, isDirectory: false)
    }

    public static func read(from directory: StoreGenerationDirectory) throws -> FileFlowLease? {
        let url = url(in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try JSONDecoder().decode(FileFlowLease.self, from: Data(contentsOf: url))
    }

    public static func acquire(_ lease: FileFlowLease, in directory: StoreGenerationDirectory) throws {
        try FileManager.default.createDirectory(at: directory.flowURL, withIntermediateDirectories: true)
        if try read(from: directory) != nil {
            throw BackupError.invalidState
        }
        let url = url(in: directory)
        let fd = open(url.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            throw BackupError.invalidState
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(lease)
        let written = data.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.baseAddress else {
                return -1
            }
            return Darwin.write(fd, base, data.count)
        }
        close(fd)
        guard written == data.count else {
            try? FileManager.default.removeItem(at: url)
            throw BackupError.invalidState
        }
    }

    public static func release(in directory: StoreGenerationDirectory) throws {
        let url = url(in: directory)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public static func occupiedByteBudget(in directory: StoreGenerationDirectory) throws -> UInt64 {
        try read(from: directory)?.byteBudget ?? 0
    }
}
