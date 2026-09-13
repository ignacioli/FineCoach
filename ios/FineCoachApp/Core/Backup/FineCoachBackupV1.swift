import Foundation

public enum BackupError: Error, Equatable, LocalizedError, Sendable {
    case invalidHeader
    case unsupportedVersion
    case authenticationFailed
    case limitExceeded
    case invalidPassword
    case invalidState

    public var errorDescription: String? {
        switch self {
        case .invalidHeader, .unsupportedVersion:
            return "备份文件无法读取。"
        case .authenticationFailed:
            return "口令不正确，或备份文件已损坏。"
        case .limitExceeded:
            return "本地空间或文件大小超出上限。"
        case .invalidPassword:
            return "请设置至少 8 个字符的口令。"
        case .invalidState:
            return "当前无法完成备份或恢复。"
        }
    }
}

public enum FineCoachBackupV1 {
    public static let magic = Data("FCBK".utf8)
    public static let headerLength: UInt16 = 82
    public static let containerVersion: UInt16 = 1
    /// The payload schema version THIS BUILD WRITES into new backups. M1-B
    /// raises this from 1 to 2 to add the section 6.7 sections (M1B-FR-031/032,
    /// D-M1B-006) -- the 82-byte header shape and the KDF/AEAD contract
    /// below are UNCHANGED and MUST NEVER change here.
    public static let payloadSchemaVersion: UInt16 = 2
    /// The oldest payload schema THIS BUILD CAN STILL READ. An M1-A backup
    /// (schema 1) has none of the M1-B sections; that is "absent", not
    /// malformed, and MUST decode with those sections empty.
    public static let minimumSupportedPayloadSchemaVersion: UInt16 = 1
    /// The reader version THIS BUILD WRITES into new backups' header, i.e.
    /// what a reader needs to safely parse them. Also doubles as the
    /// upper bound this build itself supports when READING an incoming
    /// header: a file declaring a newer `minimumReaderVersion` than this
    /// MUST fail closed (`unsupportedVersion`) rather than silently ignore
    /// sections it does not understand (T043).
    public static let minimumReaderVersion: UInt16 = 2
    public static let kdfID: UInt8 = 1
    public static let aeadID: UInt8 = 1
    public static let iterations: UInt32 = 600_000
    public static let chunkSize: UInt32 = 1_048_576
    public static let tagSize = 16
}

public struct FineCoachBackupHeader: Equatable, Sendable {
    public let magic: Data
    public let containerVersion: UInt16
    public let headerLength: UInt16
    public let payloadSchemaVersion: UInt16
    public let kdfID: UInt8
    public let aeadID: UInt8
    public let iterations: UInt32
    public let salt: Data
    public let noncePrefix: Data
    public let chunkSize: UInt32
    public let plaintextLength: UInt64
    public let recordCount: UInt64
    public let chunkCount: UInt32
    public let minimumReaderVersion: UInt16

    public init(
        magic: Data,
        containerVersion: UInt16,
        headerLength: UInt16,
        payloadSchemaVersion: UInt16,
        kdfID: UInt8,
        aeadID: UInt8,
        iterations: UInt32,
        salt: Data,
        noncePrefix: Data,
        chunkSize: UInt32,
        plaintextLength: UInt64,
        recordCount: UInt64,
        chunkCount: UInt32,
        minimumReaderVersion: UInt16
    ) {
        self.magic = magic
        self.containerVersion = containerVersion
        self.headerLength = headerLength
        self.payloadSchemaVersion = payloadSchemaVersion
        self.kdfID = kdfID
        self.aeadID = aeadID
        self.iterations = iterations
        self.salt = salt
        self.noncePrefix = noncePrefix
        self.chunkSize = chunkSize
        self.plaintextLength = plaintextLength
        self.recordCount = recordCount
        self.chunkCount = chunkCount
        self.minimumReaderVersion = minimumReaderVersion
    }

    public func encode() -> Data {
        var data = Data()
        data.reserveCapacity(Int(FineCoachBackupV1.headerLength))
        data.append(magic)
        data.appendBE(containerVersion)
        data.appendBE(headerLength)
        data.appendBE(payloadSchemaVersion)
        data.append(kdfID)
        data.append(aeadID)
        data.appendBE(iterations)
        data.append(salt)
        data.append(noncePrefix)
        data.appendBE(chunkSize)
        data.appendBE(plaintextLength)
        data.appendBE(recordCount)
        data.appendBE(chunkCount)
        data.appendBE(minimumReaderVersion)
        return data
    }

    public static func parse(_ data: Data) throws -> FineCoachBackupHeader {
        guard data.count == Int(FineCoachBackupV1.headerLength) else {
            throw BackupError.invalidHeader
        }
        return try decodeFields(data)
    }

    fileprivate static func decodeFields(_ data: Data) throws -> FineCoachBackupHeader {
        guard data.count >= Int(FineCoachBackupV1.headerLength) else {
            throw BackupError.invalidHeader
        }
        let magic = data.subdata(in: 0..<4)
        guard magic == FineCoachBackupV1.magic else {
            throw BackupError.invalidHeader
        }
        let headerLength = data.u16BE(at: 6)
        guard headerLength == FineCoachBackupV1.headerLength else {
            throw BackupError.invalidHeader
        }
        let salt = data.subdata(in: 16..<48)
        let noncePrefix = data.subdata(in: 48..<56)
        guard salt.count == 32, noncePrefix.count == 8 else {
            throw BackupError.invalidHeader
        }
        let header = FineCoachBackupHeader(
            magic: magic,
            containerVersion: data.u16BE(at: 4),
            headerLength: headerLength,
            payloadSchemaVersion: data.u16BE(at: 8),
            kdfID: data[10],
            aeadID: data[11],
            iterations: data.u32BE(at: 12),
            salt: salt,
            noncePrefix: noncePrefix,
            chunkSize: data.u32BE(at: 56),
            plaintextLength: data.u64BE(at: 60),
            recordCount: data.u64BE(at: 68),
            chunkCount: data.u32BE(at: 76),
            minimumReaderVersion: data.u16BE(at: 80)
        )
        try header.validateVersionFields()
        return header
    }

    /// Forward/backward compatible on purpose (T043): a file whose
    /// `payloadSchemaVersion` is between the oldest we still read (1, the
    /// frozen M1-A schema) and the newest we write (2) is accepted -- an
    /// M1-A-era file simply has none of the M1-B sections, which is treated
    /// as "absent" rather than malformed. A file whose `minimumReaderVersion`
    /// exceeds what THIS reader implements is rejected outright: that is
    /// exactly the fail-closed guard that makes a hypothetical M1-A-only
    /// reader (hardcoded to `minimumReaderVersion == 1`) refuse an M1-B
    /// backup instead of silently restoring a partial dataset.
    fileprivate func validateVersionFields() throws {
        guard containerVersion == FineCoachBackupV1.containerVersion,
            payloadSchemaVersion >= FineCoachBackupV1.minimumSupportedPayloadSchemaVersion,
            payloadSchemaVersion <= FineCoachBackupV1.payloadSchemaVersion,
            minimumReaderVersion <= FineCoachBackupV1.minimumReaderVersion,
            kdfID == FineCoachBackupV1.kdfID,
            aeadID == FineCoachBackupV1.aeadID,
            iterations == FineCoachBackupV1.iterations
        else {
            throw BackupError.unsupportedVersion
        }
    }
}

public enum BackupSecurityCeiling {
    public static let maxPlaintextBytes: UInt64 = 512 * 1024 * 1024
    public static let maxChunkCount: UInt32 = 512
    public static let maxRecordBytes: UInt32 = 1 * 1024 * 1024
    public static let maxRecordCount: UInt64 = 2_000_000
    public static let maxStudents = 50_000
    public static let maxExercises = 100_000
    public static let maxSessions = 250_000
    public static let maxSessionExercises = 500_000
    public static let maxSets = 1_000_000
    public static let maxRelationshipEdges = 3_000_000
    public static let maxSettings = 10_000
    public static let maxAppointments = 200_000
    public static let maxRecurrenceSeries = 50_000
    public static let maxCoursePackages = 100_000
    public static let maxCreditAdjustments = 500_000
    public static let maxTrainingTemplates = 20_000
    public static let maxTemplateExercises = 200_000
    public static let maxSessionSections = 200_000
    public static let maxBodyMetrics = 50_000
    public static let maxBodyMeasurements = 1_000_000
    public static let maxStringUTF8Bytes = 64 * 1024
    public static let maxJSONDepth = 16
    public static let maxAppManagedTempBytes: UInt64 = 2 * 1024 * 1024 * 1024
    public static let restoreFreeBytesOverhead: UInt64 = 256 * 1024 * 1024

    public static func requiredFreeBytes(plaintextLength: UInt64) -> UInt64 {
        let triple = plaintextLength.multipliedReportingOverflow(by: 3)
        if triple.overflow {
            return UInt64.max
        }
        let total = triple.partialValue.addingReportingOverflow(restoreFreeBytesOverhead)
        return total.overflow ? UInt64.max : total.partialValue
    }

    public static func validateHeader(_ header: FineCoachBackupHeader) throws {
        try header.validateVersionFields()
        guard header.chunkSize == FineCoachBackupV1.chunkSize else {
            throw BackupError.invalidHeader
        }
        guard header.chunkCount > 0, header.chunkCount <= maxChunkCount else {
            throw BackupError.limitExceeded
        }
        guard header.plaintextLength > 0, header.plaintextLength <= maxPlaintextBytes else {
            throw BackupError.limitExceeded
        }
        guard header.recordCount <= maxRecordCount else {
            throw BackupError.limitExceeded
        }
        let chunkSize = UInt64(header.chunkSize)
        let previousChunks = UInt64(header.chunkCount - 1)
        let minExclusive = previousChunks.multipliedReportingOverflow(by: chunkSize)
        let maxInclusive = UInt64(header.chunkCount).multipliedReportingOverflow(by: chunkSize)
        if minExclusive.overflow || maxInclusive.overflow {
            throw BackupError.limitExceeded
        }
        guard header.plaintextLength > minExclusive.partialValue,
            header.plaintextLength <= maxInclusive.partialValue
        else {
            throw BackupError.invalidHeader
        }
    }
}

public enum BackupJSONCanonicalization {
    public static func canonicalUTF8(_ value: Any) throws -> Data {
        var output = Data()
        try append(value, to: &output, depth: 0)
        return output
    }

    private static func append(_ value: Any, to output: inout Data, depth: Int) throws {
        guard depth <= BackupSecurityCeiling.maxJSONDepth else {
            throw BackupError.limitExceeded
        }
        if let string = value as? String {
            try appendString(string, to: &output)
            return
        }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            output.append(contentsOf: (number.boolValue ? "true" : "false").utf8)
            return
        }
        if let number = value as? Int {
            output.append(contentsOf: String(number).utf8)
            return
        }
        if let number = value as? UInt {
            output.append(contentsOf: String(number).utf8)
            return
        }
        if let number = value as? NSNumber {
            output.append(contentsOf: number.stringValue.utf8)
            return
        }
        if value is NSNull {
            output.append(contentsOf: "null".utf8)
            return
        }
        if let array = value as? [Any] {
            output.append(UInt8(ascii: "["))
            for (index, element) in array.enumerated() {
                if index > 0 {
                    output.append(UInt8(ascii: ","))
                }
                try append(element, to: &output, depth: depth + 1)
            }
            output.append(UInt8(ascii: "]"))
            return
        }
        if let array = value as? [String] {
            output.append(UInt8(ascii: "["))
            for (index, element) in array.enumerated() {
                if index > 0 {
                    output.append(UInt8(ascii: ","))
                }
                try append(element, to: &output, depth: depth + 1)
            }
            output.append(UInt8(ascii: "]"))
            return
        }
        if let array = value as? NSArray {
            output.append(UInt8(ascii: "["))
            for (index, element) in array.enumerated() {
                if index > 0 {
                    output.append(UInt8(ascii: ","))
                }
                try append(element, to: &output, depth: depth + 1)
            }
            output.append(UInt8(ascii: "]"))
            return
        }
        if let object = value as? [String: Any] {
            try appendObject(object, to: &output, depth: depth)
            return
        }
        if let object = value as? NSDictionary {
            var bridged: [String: Any] = [:]
            for (key, item) in object {
                guard let stringKey = key as? String else {
                    throw BackupError.invalidState
                }
                bridged[stringKey] = item
            }
            try appendObject(bridged, to: &output, depth: depth)
            return
        }
        throw BackupError.invalidState
    }

    private static func appendObject(_ object: [String: Any], to output: inout Data, depth: Int) throws {
        let keys = object.keys.sorted { lhs, rhs in
            lhs.utf16.lexicographicallyPrecedes(rhs.utf16)
        }
        output.append(UInt8(ascii: "{"))
        for (index, key) in keys.enumerated() {
            if index > 0 {
                output.append(UInt8(ascii: ","))
            }
            try appendString(key, to: &output)
            output.append(UInt8(ascii: ":"))
            try append(object[key] as Any, to: &output, depth: depth + 1)
        }
        output.append(UInt8(ascii: "}"))
    }

    private static func appendString(_ string: String, to output: inout Data) throws {
        let utf8Count = string.utf8.count
        guard utf8Count <= BackupSecurityCeiling.maxStringUTF8Bytes else {
            throw BackupError.limitExceeded
        }
        output.append(UInt8(ascii: "\""))
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x22:
                output.append(contentsOf: "\\\"".utf8)
            case 0x5C:
                output.append(contentsOf: "\\\\".utf8)
            case 0x08:
                output.append(contentsOf: "\\b".utf8)
            case 0x0C:
                output.append(contentsOf: "\\f".utf8)
            case 0x0A:
                output.append(contentsOf: "\\n".utf8)
            case 0x0D:
                output.append(contentsOf: "\\r".utf8)
            case 0x09:
                output.append(contentsOf: "\\t".utf8)
            case 0x00..<0x20, 0x2028, 0x2029:
                let hex = String(format: "\\u%04x", scalar.value)
                output.append(contentsOf: hex.utf8)
            default:
                output.append(contentsOf: String(scalar).utf8)
            }
        }
        output.append(UInt8(ascii: "\""))
    }
}

public enum BackupContainerReader {
    public static func inspectHeader(_ fileData: Data) throws -> FineCoachBackupHeader {
        guard fileData.count >= Int(FineCoachBackupV1.headerLength) else {
            throw BackupError.invalidHeader
        }
        return try FineCoachBackupHeader.decodeFields(
            fileData.prefix(Int(FineCoachBackupV1.headerLength))
        )
    }

    public static func expectedContainerByteCount(header: FineCoachBackupHeader) throws -> UInt64 {
        try BackupSecurityCeiling.validateHeader(header)
        let tagBytes = UInt64(header.chunkCount).multipliedReportingOverflow(
            by: UInt64(FineCoachBackupV1.tagSize)
        )
        let payload = header.plaintextLength.addingReportingOverflow(tagBytes.partialValue)
        let expected = UInt64(FineCoachBackupV1.headerLength).addingReportingOverflow(payload.partialValue)
        if tagBytes.overflow || payload.overflow || expected.overflow {
            throw BackupError.limitExceeded
        }
        return expected.partialValue
    }

    public static func rejectTrailingOrReorderedChunks(
        header: FineCoachBackupHeader,
        container: Data
    ) throws {
        let expected = try expectedContainerByteCount(header: header)
        guard UInt64(container.count) == expected else {
            throw BackupError.authenticationFailed
        }
    }
}

extension Data {
    fileprivate mutating func appendBE(_ value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xFF))
    }

    fileprivate mutating func appendBE(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value >> 24))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    fileprivate mutating func appendBE(_ value: UInt64) {
        append(UInt8(truncatingIfNeeded: value >> 56))
        append(UInt8(truncatingIfNeeded: value >> 48))
        append(UInt8(truncatingIfNeeded: value >> 40))
        append(UInt8(truncatingIfNeeded: value >> 32))
        append(UInt8(truncatingIfNeeded: value >> 24))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    fileprivate func u16BE(at offset: Int) -> UInt16 {
        (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }

    fileprivate func u32BE(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24) | (UInt32(self[offset + 1]) << 16) | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }

    fileprivate func u64BE(at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(self[offset + index])
        }
        return value
    }
}
