import Foundation

public struct SecurityScopedFileAdapter: Sendable {
    public init() {}

    public func withAccess<T>(to url: URL, _ body: () throws -> T) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try body()
    }

    public func copyBounded(
        from sourceURL: URL,
        to destinationURL: URL,
        maximumBytes: UInt64
    ) throws -> UInt64 {
        try withAccess(to: sourceURL) {
            let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                throw BackupError.invalidHeader
            }
            let declared = UInt64(values.fileSize ?? 0)
            let headerLength = UInt64(FineCoachBackupV1.headerLength)
            guard declared >= headerLength else {
                throw BackupError.invalidHeader
            }

            let input = try FileHandle(forReadingFrom: sourceURL)
            defer { try? input.close() }
            let headerBytes = try input.read(upToCount: Int(FineCoachBackupV1.headerLength)) ?? Data()
            guard headerBytes.count == Int(FineCoachBackupV1.headerLength) else {
                throw BackupError.invalidHeader
            }
            let header = try FineCoachBackupHeader.parse(headerBytes)
            try BackupSecurityCeiling.validateHeader(header)
            let expected = try BackupContainerReader.expectedContainerByteCount(header: header)
            guard declared == expected else {
                throw BackupError.invalidHeader
            }
            guard expected <= maximumBytes else {
                throw BackupError.limitExceeded
            }

            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.ensureFreeBytes(
                BackupSecurityCeiling.requiredFreeBytes(plaintextLength: header.plaintextLength),
                near: destinationURL.deletingLastPathComponent()
            )

            try input.seek(toOffset: 0)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
            let output = try FileHandle(forWritingTo: destinationURL)
            defer { try? output.close() }
            var copied: UInt64 = 0
            while copied < expected {
                let remaining = Int(expected - copied)
                let chunk = try input.read(upToCount: min(64 * 1024, remaining)) ?? Data()
                if chunk.isEmpty {
                    break
                }
                let next = copied.addingReportingOverflow(UInt64(chunk.count))
                if next.overflow || next.partialValue > expected {
                    throw BackupError.limitExceeded
                }
                try output.write(contentsOf: chunk)
                copied = next.partialValue
            }
            guard copied == expected, copied == declared else {
                throw BackupError.invalidHeader
            }

            let staged = try Data(contentsOf: destinationURL)
            let restaged = try BackupContainerReader.inspectHeader(staged)
            try BackupContainerReader.rejectTrailingOrReorderedChunks(header: restaged, container: staged)
            return copied
        }
    }

    public func inspectContainerHeader(at sourceURL: URL) throws -> FineCoachBackupHeader {
        try withAccess(to: sourceURL) {
            let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                throw BackupError.invalidHeader
            }
            let declared = UInt64(values.fileSize ?? 0)
            guard declared >= UInt64(FineCoachBackupV1.headerLength) else {
                throw BackupError.invalidHeader
            }
            let input = try FileHandle(forReadingFrom: sourceURL)
            defer { try? input.close() }
            let headerBytes = try input.read(upToCount: Int(FineCoachBackupV1.headerLength)) ?? Data()
            guard headerBytes.count == Int(FineCoachBackupV1.headerLength) else {
                throw BackupError.invalidHeader
            }
            let header = try FineCoachBackupHeader.parse(headerBytes)
            try BackupSecurityCeiling.validateHeader(header)
            let expected = try BackupContainerReader.expectedContainerByteCount(header: header)
            guard declared == expected else {
                throw BackupError.invalidHeader
            }
            return header
        }
    }

    public static func ensureFreeBytes(_ required: UInt64, near url: URL) throws {
        var probe = url
        for _ in 0..<8 {
            if let capacity = try? probe.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            ).volumeAvailableCapacityForImportantUsage {
                guard UInt64(max(0, capacity)) >= required else {
                    throw BackupError.limitExceeded
                }
                return
            }
            let parent = probe.deletingLastPathComponent()
            if parent.path == probe.path {
                break
            }
            probe = parent
        }
        let attrs = try FileManager.default.attributesOfFileSystem(forPath: url.path)
        guard let free = attrs[.systemFreeSize] as? NSNumber, UInt64(truncating: free) >= required else {
            throw BackupError.limitExceeded
        }
    }
}
