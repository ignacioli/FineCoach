import Foundation

/// Failure classes of reading an archive file (contract §6). The UI maps these to its
/// reason categories; no message text lives here.
public enum ArchiveFileError: Error, Equatable, Sendable {
    /// Wrong password, tampering, truncation, appended bytes or reordered chunks.
    case wrongPasswordOrCorrupted
    /// Container / KDF / AEAD / iteration mismatch, or a schema / reader version newer than
    /// this build supports.
    case incompatibleVersion
    /// Wrong magic (including a FineCoach backup file).
    case notAnArchive
    /// Authenticated but structurally invalid: limits, counts, references, frame rules.
    case invalidArchive
}

/// Byte-level constants of `.fcarchive` v1 (contract §2-§3).
public enum ArchiveFileV1 {
    public static let magic = Data("FCPA".utf8)
    public static let headerLength: UInt16 = 82
    public static let containerVersion: UInt16 = 1
    public static let payloadSchemaVersion: UInt16 = 1
    public static let minimumReaderVersion: UInt16 = 1
    public static let kdfID: UInt8 = 1
    public static let aeadID: UInt8 = 1
    public static let iterations: UInt32 = 600_000
    public static let chunkSize: UInt32 = 1_048_576
    public static let tagSize = 16
    public static let maxPlaintextBytes: UInt64 = 64 * 1024 * 1024
    /// Largest file a conforming writer can produce: header + 64 MiB plaintext + one tag per
    /// chunk. Plan §7.3 states the file ceiling as "64 MiB"; the container overhead
    /// (at most 1,106 bytes) is added so that a maximal payload is never rejected by the
    /// file gate while the contract's plaintext bound still accepts it.
    public static let maxFileBytes =
        Int(headerLength) + Int(maxPlaintextBytes) + tagSize * Int(maxPlaintextBytes / UInt64(chunkSize))

    /// Payload section IDs (contract §4).
    public enum Section: UInt16, CaseIterable, Sendable {
        case manifest = 1
        case student = 2
        case exercise = 3
        case session = 4
        case summary = 5
        case bodyMetric = 6
        case bodyMeasurement = 7
        case attribution = 8

        /// Maximum frames of this section (contract §4, plan §7.3).
        public var maxFrames: Int {
            switch self {
            case .manifest, .student, .attribution: return 1
            case .exercise: return ArchiveLimits.maxExercises
            case .session: return ArchiveLimits.maxSessions
            case .summary: return ArchiveLimits.maxSummaries
            case .bodyMetric: return ArchiveLimits.maxBodyMetrics
            case .bodyMeasurement: return ArchiveLimits.maxBodyMeasurements
            }
        }
    }

    /// Upper bound of `recordCount` (frames in the payload): manifest + every section at its
    /// maximum.
    public static let maxRecordCount: UInt64 = UInt64(Section.allCases.reduce(0) { $0 + $1.maxFrames })
}

/// The 82-byte big-endian header (contract §2).
public struct ArchiveFileHeader: Equatable, Sendable {
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

    public func encode() -> Data {
        var data = Data()
        data.reserveCapacity(Int(ArchiveFileV1.headerLength))
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

    static func v1(
        salt: Data,
        noncePrefix: Data,
        plaintextLength: UInt64,
        recordCount: UInt64,
        chunkCount: UInt32
    ) -> ArchiveFileHeader {
        ArchiveFileHeader(
            magic: ArchiveFileV1.magic,
            containerVersion: ArchiveFileV1.containerVersion,
            headerLength: ArchiveFileV1.headerLength,
            payloadSchemaVersion: ArchiveFileV1.payloadSchemaVersion,
            kdfID: ArchiveFileV1.kdfID,
            aeadID: ArchiveFileV1.aeadID,
            iterations: ArchiveFileV1.iterations,
            salt: salt,
            noncePrefix: noncePrefix,
            chunkSize: ArchiveFileV1.chunkSize,
            plaintextLength: plaintextLength,
            recordCount: recordCount,
            chunkCount: chunkCount,
            minimumReaderVersion: ArchiveFileV1.minimumReaderVersion
        )
    }

    /// Structural header checks without any key derivation. Order: magic -> file size
    /// ceiling -> versions -> layout / limits -> exact file length.
    public static func inspect(_ file: Data) throws -> ArchiveFileHeader {
        let magicLength = ArchiveFileV1.magic.count
        guard file.count >= magicLength else {
            // An empty or foreign short file is not an archive; a proper prefix of the magic
            // is a truncated archive.
            if !file.isEmpty && ArchiveFileV1.magic.starts(with: file) {
                throw ArchiveFileError.wrongPasswordOrCorrupted
            }
            throw ArchiveFileError.notAnArchive
        }
        let base = file.startIndex
        guard file[base..<(base + magicLength)].elementsEqual(ArchiveFileV1.magic) else {
            throw ArchiveFileError.notAnArchive
        }
        guard file.count >= Int(ArchiveFileV1.headerLength) else {
            throw ArchiveFileError.wrongPasswordOrCorrupted
        }
        guard file.count <= ArchiveFileV1.maxFileBytes else {
            throw ArchiveFileError.invalidArchive
        }
        let bytes = Data(file.prefix(Int(ArchiveFileV1.headerLength)))
        let header = ArchiveFileHeader(
            magic: bytes.subdata(in: 0..<4),
            containerVersion: bytes.u16BE(at: 4),
            headerLength: bytes.u16BE(at: 6),
            payloadSchemaVersion: bytes.u16BE(at: 8),
            kdfID: bytes[10],
            aeadID: bytes[11],
            iterations: bytes.u32BE(at: 12),
            salt: bytes.subdata(in: 16..<48),
            noncePrefix: bytes.subdata(in: 48..<56),
            chunkSize: bytes.u32BE(at: 56),
            plaintextLength: bytes.u64BE(at: 60),
            recordCount: bytes.u64BE(at: 68),
            chunkCount: bytes.u32BE(at: 76),
            minimumReaderVersion: bytes.u16BE(at: 80)
        )

        guard header.containerVersion == ArchiveFileV1.containerVersion,
            header.kdfID == ArchiveFileV1.kdfID,
            header.aeadID == ArchiveFileV1.aeadID,
            header.iterations == ArchiveFileV1.iterations,
            header.payloadSchemaVersion == ArchiveFileV1.payloadSchemaVersion,
            header.minimumReaderVersion <= ArchiveFileV1.minimumReaderVersion
        else {
            throw ArchiveFileError.incompatibleVersion
        }
        guard header.minimumReaderVersion == ArchiveFileV1.minimumReaderVersion,
            header.headerLength == ArchiveFileV1.headerLength,
            header.chunkSize == ArchiveFileV1.chunkSize,
            header.plaintextLength >= 1,
            header.plaintextLength <= ArchiveFileV1.maxPlaintextBytes,
            header.recordCount <= ArchiveFileV1.maxRecordCount
        else {
            throw ArchiveFileError.invalidArchive
        }
        let chunkSize = UInt64(header.chunkSize)
        let expectedChunks = (header.plaintextLength + chunkSize - 1) / chunkSize
        guard UInt64(header.chunkCount) == expectedChunks else {
            throw ArchiveFileError.invalidArchive
        }
        let expectedLength =
            UInt64(ArchiveFileV1.headerLength) + header.plaintextLength
            + UInt64(ArchiveFileV1.tagSize) * UInt64(header.chunkCount)
        guard UInt64(file.count) == expectedLength else {
            throw ArchiveFileError.wrongPasswordOrCorrupted
        }
        return header
    }
}

/// Encodes and decodes `.fcarchive` v1 files (contract archive-file-v1). Cryptography is the
/// existing `BackupKDF` / `BackupAEAD`; this type only owns the header, the chunk layout and
/// the payload frames. Plaintext exists only in memory; nothing here touches the file system.
public enum ArchiveFileCodec {
    // MARK: Encode

    /// Normal export path: salt and nonce prefix come from the secure random source.
    public static func encode(
        snapshot: ArchiveSnapshot,
        password: ArchivePassword,
        random: any SecureRandomSource = SecureRandomGenerator()
    ) throws -> Data {
        try encode(
            snapshot: snapshot,
            password: password,
            salt: random.randomBytes(count: 32),
            noncePrefix: random.randomBytes(count: 8)
        )
    }

    /// Deterministic variant for golden vectors. Production code uses the random overload.
    public static func encode(
        snapshot: ArchiveSnapshot,
        password: ArchivePassword,
        salt: Data,
        noncePrefix: Data
    ) throws -> Data {
        let payload = try encodePayload(snapshot)
        return try seal(
            plaintext: payload.plaintext,
            recordCount: payload.frameCount,
            password: password,
            salt: salt,
            noncePrefix: noncePrefix
        )
    }

    /// Frames in section order: manifest, student, exercises, sessions, summaries, body
    /// metrics, body measurements, attribution. JSON uses sorted keys and no extra whitespace.
    ///
    /// Resource limits are not enforced here (plan §7.3: the exporter asserts and logs
    /// `archive.export.limitExceeded`, the importer fails closed); only what cannot be
    /// represented in the container throws.
    public static func encodePayload(
        _ snapshot: ArchiveSnapshot
    ) throws -> (plaintext: Data, frameCount: UInt64) {
        var plaintext = Data()
        var frameCount: UInt64 = 0
        func append<T: Encodable>(_ section: ArchiveFileV1.Section, _ value: T) throws {
            let json = try makeEncoder().encode(value)
            guard json.count <= Int(UInt32.max),
                plaintext.count + 6 + json.count <= Int(ArchiveFileV1.maxPlaintextBytes)
            else {
                throw ArchiveFileError.invalidArchive
            }
            plaintext.appendBE(section.rawValue)
            plaintext.appendBE(UInt32(json.count))
            plaintext.append(json)
            frameCount += 1
        }
        do {
            try append(.manifest, snapshot.manifest)
            if let student = snapshot.student {
                try append(.student, student)
            }
            for exercise in snapshot.exercises {
                try append(.exercise, exercise)
            }
            for session in snapshot.sessions {
                try append(.session, session)
            }
            for summary in snapshot.summaries {
                try append(.summary, summary)
            }
            for metric in snapshot.bodyMetrics {
                try append(.bodyMetric, metric)
            }
            for measurement in snapshot.bodyMeasurements {
                try append(.bodyMeasurement, measurement)
            }
            if let attribution = snapshot.attribution {
                try append(.attribution, attribution)
            }
        } catch let error as ArchiveFileError {
            throw error
        } catch {
            throw ArchiveFileError.invalidArchive
        }
        return (plaintext, frameCount)
    }

    /// Encrypts an already-framed payload. Public so tests can seal deliberately malformed
    /// payloads; production code goes through `encode(snapshot:...)`.
    public static func seal(
        plaintext: Data,
        recordCount: UInt64,
        password: ArchivePassword,
        salt: Data,
        noncePrefix: Data
    ) throws -> Data {
        guard !plaintext.isEmpty, UInt64(plaintext.count) <= ArchiveFileV1.maxPlaintextBytes else {
            throw ArchiveFileError.invalidArchive
        }
        guard salt.count == 32, noncePrefix.count == 8, !password.utf8.isEmpty else {
            throw ArchiveFileError.invalidArchive
        }
        let key = try deriveKey(password: password, salt: salt)
        let chunkSize = Int(ArchiveFileV1.chunkSize)
        let chunkCount = UInt32((plaintext.count + chunkSize - 1) / chunkSize)
        let header = ArchiveFileHeader.v1(
            salt: salt,
            noncePrefix: noncePrefix,
            plaintextLength: UInt64(plaintext.count),
            recordCount: recordCount,
            chunkCount: chunkCount
        )
        let rawHeader = header.encode()
        var container = rawHeader
        container.reserveCapacity(
            rawHeader.count + plaintext.count + ArchiveFileV1.tagSize * Int(chunkCount)
        )
        var offset = 0
        for index in 0..<chunkCount {
            let end = min(offset + chunkSize, plaintext.count)
            let chunk = plaintext.subdata(in: offset..<end)
            let aad = BackupAEAD.additionalAuthenticatedData(
                rawHeader: rawHeader,
                chunkIndex: index,
                plaintextChunkLength: UInt32(chunk.count),
                finalFlag: try BackupAEAD.finalFlag(chunkIndex: index, chunkCount: chunkCount)
            )
            let sealed = try BackupAEAD.seal(
                plaintext: chunk,
                key: key,
                nonce: BackupAEAD.chunkNonce(prefix: noncePrefix, chunkIndex: index),
                authenticating: aad
            )
            container.append(sealed.ciphertext)
            container.append(sealed.tag)
            offset = end
        }
        return container
    }

    // MARK: Decode

    /// Contract §5 up to and including identity metadata: header -> key derivation ->
    /// per-chunk authenticated decryption -> frame decoding and counts -> reference
    /// integrity -> identity metadata. Replacement and commit belong to later steps. Any
    /// failure discards the in-memory plaintext and leaves no file behind.
    public static func decode(file: Data, password: ArchivePassword) throws -> ArchiveSnapshot {
        let header = try ArchiveFileHeader.inspect(file)
        guard !password.utf8.isEmpty else {
            throw ArchiveFileError.wrongPasswordOrCorrupted
        }
        let key = try deriveKey(password: password, salt: header.salt)
        let rawHeader = header.encode()
        let chunkSize = Int(header.chunkSize)
        var plaintext = Data()
        plaintext.reserveCapacity(Int(header.plaintextLength))
        var offset = Int(ArchiveFileV1.headerLength)
        var remaining = header.plaintextLength
        for index in 0..<header.chunkCount {
            try Task.checkCancellation()
            let chunkLength = Int(min(remaining, UInt64(chunkSize)))
            remaining -= UInt64(chunkLength)
            let cipherStart = file.startIndex + offset
            let ciphertext = file.subdata(in: cipherStart..<(cipherStart + chunkLength))
            let tag = file.subdata(
                in: (cipherStart + chunkLength)..<(cipherStart + chunkLength + ArchiveFileV1.tagSize)
            )
            let aad = BackupAEAD.additionalAuthenticatedData(
                rawHeader: rawHeader,
                chunkIndex: index,
                plaintextChunkLength: UInt32(chunkLength),
                finalFlag: try BackupAEAD.finalFlag(chunkIndex: index, chunkCount: header.chunkCount)
            )
            do {
                plaintext.append(
                    try BackupAEAD.open(
                        ciphertext: ciphertext,
                        tag: tag,
                        key: key,
                        nonce: BackupAEAD.chunkNonce(prefix: header.noncePrefix, chunkIndex: index),
                        authenticating: aad
                    )
                )
            } catch {
                throw ArchiveFileError.wrongPasswordOrCorrupted
            }
            offset += chunkLength + ArchiveFileV1.tagSize
        }
        return try decodePayload(plaintext: plaintext, recordCount: header.recordCount)
    }

    /// Decodes and validates an authenticated payload (contract §4). Public so the frame
    /// rules can be tested without paying for key derivation.
    public static func decodePayload(plaintext: Data, recordCount: UInt64) throws -> ArchiveSnapshot {
        let frames = try scanFrames(plaintext)
        guard UInt64(frames.count) == recordCount else {
            throw ArchiveFileError.invalidArchive
        }
        let decoder = JSONDecoder()
        do {
            let manifest = try decoder.decode(ArchiveManifest.self, from: frames[0].json)
            var student: ArchiveStudent?
            var exercises: [ArchiveExercise] = []
            var sessions: [ArchiveSession] = []
            var summaries: [ArchiveSummary] = []
            var bodyMetrics: [ArchiveBodyMetric] = []
            var bodyMeasurements: [ArchiveBodyMeasurement] = []
            var attribution: ArchiveAttribution?
            for frame in frames.dropFirst() {
                switch frame.section {
                case .manifest:
                    throw ArchiveFileError.invalidArchive
                case .student:
                    student = try decoder.decode(ArchiveStudent.self, from: frame.json)
                case .exercise:
                    exercises.append(try decoder.decode(ArchiveExercise.self, from: frame.json))
                case .session:
                    sessions.append(try decoder.decode(ArchiveSession.self, from: frame.json))
                case .summary:
                    summaries.append(try decoder.decode(ArchiveSummary.self, from: frame.json))
                case .bodyMetric:
                    bodyMetrics.append(try decoder.decode(ArchiveBodyMetric.self, from: frame.json))
                case .bodyMeasurement:
                    bodyMeasurements.append(try decoder.decode(ArchiveBodyMeasurement.self, from: frame.json))
                case .attribution:
                    attribution = try decoder.decode(ArchiveAttribution.self, from: frame.json)
                }
            }
            let snapshot = ArchiveSnapshot(
                manifest: manifest,
                student: student,
                exercises: exercises,
                sessions: sessions,
                summaries: summaries,
                bodyMetrics: bodyMetrics,
                bodyMeasurements: bodyMeasurements,
                attribution: attribution
            )
            try snapshot.validateIntegrity()
            return snapshot
        } catch {
            // Every decoding, identity-metadata, count, reference or module-content failure
            // of an authenticated payload is one class (contract §6).
            throw ArchiveFileError.invalidArchive
        }
    }

    // MARK: Internals

    private struct Frame {
        let section: ArchiveFileV1.Section
        let json: Data
    }

    /// Frame layout rules: known section IDs only, ascending order, `manifest` first and
    /// unique, per-section frame ceilings, no truncated frame.
    private static func scanFrames(_ plaintext: Data) throws -> [Frame] {
        var frames: [Frame] = []
        var sectionCounts: [ArchiveFileV1.Section: Int] = [:]
        var lastSectionID: UInt16 = 0
        var offset = 0
        while offset < plaintext.count {
            guard plaintext.count - offset >= 6 else {
                throw ArchiveFileError.invalidArchive
            }
            let sectionID = plaintext.u16BE(at: offset)
            let jsonLength = UInt64(plaintext.u32BE(at: offset + 2))
            offset += 6
            guard let section = ArchiveFileV1.Section(rawValue: sectionID),
                sectionID >= lastSectionID,
                frames.isEmpty == (section == .manifest),
                jsonLength <= UInt64(plaintext.count - offset)
            else {
                throw ArchiveFileError.invalidArchive
            }
            let count = (sectionCounts[section] ?? 0) + 1
            guard count <= section.maxFrames else {
                throw ArchiveFileError.invalidArchive
            }
            sectionCounts[section] = count
            lastSectionID = sectionID
            let start = plaintext.startIndex + offset
            frames.append(Frame(section: section, json: plaintext.subdata(in: start..<(start + Int(jsonLength)))))
            offset += Int(jsonLength)
        }
        guard !frames.isEmpty else {
            throw ArchiveFileError.invalidArchive
        }
        return frames
    }

    private static func deriveKey(password: ArchivePassword, salt: Data) throws -> Data {
        do {
            return try BackupKDF.deriveKey(
                passwordUTF8: password.utf8,
                salt: salt,
                iterations: ArchiveFileV1.iterations
            )
        } catch {
            throw ArchiveFileError.wrongPasswordOrCorrupted
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension Data {
    fileprivate mutating func appendBE(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    fileprivate mutating func appendBE(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value >> 24))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    fileprivate mutating func appendBE(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    fileprivate func u16BE(at offset: Int) -> UInt16 {
        let base = startIndex + offset
        return (UInt16(self[base]) << 8) | UInt16(self[base + 1])
    }

    fileprivate func u32BE(at offset: Int) -> UInt32 {
        let base = startIndex + offset
        return (UInt32(self[base]) << 24) | (UInt32(self[base + 1]) << 16) | (UInt32(self[base + 2]) << 8)
            | UInt32(self[base + 3])
    }

    fileprivate func u64BE(at offset: Int) -> UInt64 {
        let base = startIndex + offset
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(self[base + index])
        }
        return value
    }
}
