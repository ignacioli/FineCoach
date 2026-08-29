import FineCoach
import XCTest

final class BackupHostileInputTests: XCTestCase {
    private let salt = Data(repeating: 0x11, count: 32)
    private let noncePrefix = Data(repeating: 0x22, count: 8)

    func testTruncatedHeaderIsInvalidHeader() {
        XCTAssertEqual(Int(FineCoachBackupV1.headerLength), 82)

        for length in [0, 1, 81] {
            let truncated = Data(repeating: 0x00, count: length)
            assertBackupError(
                { try FineCoachBackupHeader.parse(truncated) },
                .invalidHeader
            )
            assertBackupError(
                { try BackupContainerReader.inspectHeader(truncated) },
                .invalidHeader
            )
        }
    }

    func testInspectHeaderReadsOnlyFirstEightyTwoBytes() throws {
        let header = validHeader()
        var file = header.encode()
        XCTAssertEqual(file.count, Int(FineCoachBackupV1.headerLength))
        file.append(Data(repeating: 0xFF, count: 64))

        let inspected = try BackupContainerReader.inspectHeader(file)
        XCTAssertEqual(inspected, header)
        XCTAssertEqual(inspected.encode(), header.encode())
    }

    func testCopyBoundedRejectsNonContainerBeforeWritingDestination() throws {
        let adapter = SecurityScopedFileAdapter()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let source = tmp.appendingPathComponent("junk.bin")
        try Data(repeating: 0x41, count: 256 * 1024).write(to: source)
        let dest = tmp.appendingPathComponent("staging.fcbackup")
        XCTAssertThrowsError(
            try adapter.copyBounded(
                from: source,
                to: dest,
                maximumBytes: BackupSecurityCeiling.maxAppManagedTempBytes
            )
        ) { error in
            XCTAssertEqual(error as? BackupError, .invalidHeader)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
    }

    func testTrailingBytesAfterExactContainerLengthFailClosed() throws {
        let header = validHeader()
        try BackupSecurityCeiling.validateHeader(header)
        let exact = dummyContainer(for: header)
        XCTAssertNoThrow(
            try BackupContainerReader.rejectTrailingOrReorderedChunks(header: header, container: exact)
        )

        var trailing = exact
        trailing.append(0x7F)
        assertFailClosed(
            { try BackupContainerReader.rejectTrailingOrReorderedChunks(header: header, container: trailing) },
            permitted: [.authenticationFailed, .invalidHeader]
        )
    }

    func testTruncatedContainerFailsClosed() throws {
        let header = validHeader()
        let exact = dummyContainer(for: header)
        XCTAssertGreaterThan(exact.count, Int(FineCoachBackupV1.headerLength))
        let truncated = exact.dropLast()
        assertFailClosed(
            {
                try BackupContainerReader.rejectTrailingOrReorderedChunks(
                    header: header,
                    container: Data(truncated)
                )
            },
            permitted: [.authenticationFailed, .invalidHeader]
        )
    }

    func testWrongChunkCountVersusContainerSizeFailsClosed() throws {
        let oneChunkHeader = validHeader(plaintextLength: 64, chunkCount: 1)
        let oneChunkContainer = dummyContainer(for: oneChunkHeader)

        let twoChunkHeader = validHeader(
            plaintextLength: UInt64(FineCoachBackupV1.chunkSize) + 64,
            chunkCount: 2
        )
        assertFailClosed(
            {
                try BackupContainerReader.rejectTrailingOrReorderedChunks(
                    header: twoChunkHeader,
                    container: oneChunkContainer
                )
            },
            permitted: [.authenticationFailed, .invalidHeader]
        )

        var duplicated = oneChunkContainer
        duplicated.append(Data(repeating: 0xA5, count: 64 + FineCoachBackupV1.tagSize))
        assertFailClosed(
            {
                try BackupContainerReader.rejectTrailingOrReorderedChunks(
                    header: oneChunkHeader,
                    container: duplicated
                )
            },
            permitted: [.authenticationFailed, .invalidHeader]
        )
    }

    func testUnknownContainerVersionKDFAndAEADFailClosed() throws {
        let encoded = validHeader().encode()

        assertParseOrInspectFailsClosed(patching: encoded, offset: Offset.containerVersion) { data in
            data.writeUInt16BE(99, at: Offset.containerVersion)
        }
        assertParseOrInspectFailsClosed(patching: encoded, offset: Offset.payloadSchemaVersion) { data in
            data.writeUInt16BE(99, at: Offset.payloadSchemaVersion)
        }
        assertParseOrInspectFailsClosed(patching: encoded, offset: Offset.minimumReaderVersion) { data in
            data.writeUInt16BE(99, at: Offset.minimumReaderVersion)
        }
        assertParseOrInspectFailsClosed(patching: encoded, offset: Offset.kdfID) { data in
            data[Offset.kdfID] = 99
        }
        assertParseOrInspectFailsClosed(patching: encoded, offset: Offset.aeadID) { data in
            data[Offset.aeadID] = 99
        }
    }

    func testFlippingOneHeaderByteAfterEncodeFailsParseOrVersion() throws {
        let original = validHeader().encode()
        XCTAssertEqual(original.count, Int(FineCoachBackupV1.headerLength))

        let structuralOffsets = [
            Offset.magic,
            Offset.containerVersion,
            Offset.headerLength,
            Offset.payloadSchemaVersion,
            Offset.kdfID,
            Offset.aeadID,
        ]
        for offset in structuralOffsets {
            var mutated = original
            mutated[offset] ^= 0x01
            assertFailClosed(
                { try FineCoachBackupHeader.parse(mutated) },
                permitted: [.invalidHeader, .unsupportedVersion]
            )
            assertFailClosed(
                { try BackupContainerReader.inspectHeader(mutated) },
                permitted: [.invalidHeader, .unsupportedVersion]
            )
        }
    }

    func testOversizedPlaintextLengthChunkCountAndRecordCountAreRejected() throws {
        var oversizedPlaintext = validHeader(chunkCount: 1).encode()
        oversizedPlaintext.writeUInt64BE(
            BackupSecurityCeiling.maxPlaintextBytes + 1,
            at: Offset.plaintextLength
        )
        assertCeilingRejected(oversizedPlaintext)

        var oversizedChunks = validHeader().encode()
        oversizedChunks.writeUInt32BE(
            BackupSecurityCeiling.maxChunkCount + 1,
            at: Offset.chunkCount
        )
        assertCeilingRejected(oversizedChunks)

        var oversizedRecords = validHeader().encode()
        oversizedRecords.writeUInt64BE(
            BackupSecurityCeiling.maxRecordCount + 1,
            at: Offset.recordCount
        )
        assertCeilingRejected(oversizedRecords)
    }

    func testCheckedArithmeticOnMaxPlaintextLengthDoesNotCrash() {
        var encoded = validHeader(chunkCount: 1).encode()
        encoded.writeUInt32BE(FineCoachBackupV1.chunkSize, at: Offset.chunkSize)
        encoded.writeUInt64BE(.max, at: Offset.plaintextLength)

        let header: FineCoachBackupHeader
        do {
            header = try FineCoachBackupHeader.parse(encoded)
        } catch let error as BackupError {
            XCTAssertTrue(
                error == .limitExceeded || error == .invalidHeader,
                "parse overflow path: \(error)"
            )
            return
        } catch {
            XCTFail("unexpected parse error: \(error)")
            return
        }

        assertFailClosed(
            { try BackupSecurityCeiling.validateHeader(header) },
            permitted: [.limitExceeded, .invalidHeader]
        )

        let tinyContainer = header.encode() + Data(repeating: 0x00, count: FineCoachBackupV1.tagSize)
        assertFailClosed(
            {
                try BackupContainerReader.rejectTrailingOrReorderedChunks(
                    header: header,
                    container: tinyContainer
                )
            },
            permitted: [.limitExceeded, .invalidHeader, .authenticationFailed]
        )
    }

    func testValidateHeaderRejectsZeroChunksWrongSizeAndInconsistentLength() throws {
        var zeroChunks = validHeader().encode()
        zeroChunks.writeUInt32BE(0, at: Offset.chunkCount)
        assertCeilingRejected(zeroChunks, permitted: [.limitExceeded, .invalidHeader])

        var wrongChunkSize = validHeader().encode()
        wrongChunkSize.writeUInt32BE(FineCoachBackupV1.chunkSize - 1, at: Offset.chunkSize)
        assertCeilingRejected(wrongChunkSize, permitted: [.limitExceeded, .invalidHeader])

        var inconsistent = validHeader(chunkCount: 1).encode()
        inconsistent.writeUInt64BE(UInt64(FineCoachBackupV1.chunkSize) + 1, at: Offset.plaintextLength)
        assertCeilingRejected(inconsistent, permitted: [.limitExceeded, .invalidHeader])
    }

    func testUnknownIterationsFailClosedWithoutDerivingKey() throws {
        var encoded = validHeader().encode()
        encoded.writeUInt32BE(.max, at: Offset.iterations)
        assertFailClosed(
            { try FineCoachBackupHeader.parse(encoded) },
            permitted: [.invalidHeader, .unsupportedVersion]
        )
        assertFailClosed(
            { try BackupContainerReader.inspectHeader(encoded) },
            permitted: [.invalidHeader, .unsupportedVersion]
        )
    }

    func testSecurityCeilingConstantsMatchContract() {
        XCTAssertEqual(BackupSecurityCeiling.maxPlaintextBytes, 512 * 1024 * 1024)
        XCTAssertEqual(BackupSecurityCeiling.maxChunkCount, 512)
        XCTAssertEqual(BackupSecurityCeiling.maxRecordBytes, 1 * 1024 * 1024)
        XCTAssertEqual(BackupSecurityCeiling.maxRecordCount, 2_000_000)
        XCTAssertEqual(BackupSecurityCeiling.maxStudents, 50_000)
        XCTAssertEqual(BackupSecurityCeiling.maxExercises, 100_000)
        XCTAssertEqual(BackupSecurityCeiling.maxSessions, 250_000)
        XCTAssertEqual(BackupSecurityCeiling.maxSessionExercises, 500_000)
        XCTAssertEqual(BackupSecurityCeiling.maxSets, 1_000_000)
        XCTAssertEqual(BackupSecurityCeiling.maxRelationshipEdges, 3_000_000)
        XCTAssertEqual(BackupSecurityCeiling.maxSettings, 10_000)
        XCTAssertEqual(BackupSecurityCeiling.maxStringUTF8Bytes, 64 * 1024)
        XCTAssertEqual(BackupSecurityCeiling.maxJSONDepth, 16)
        XCTAssertEqual(BackupSecurityCeiling.maxAppManagedTempBytes, 2 * 1024 * 1024 * 1024)
        XCTAssertEqual(FineCoachBackupV1.chunkSize, 1_048_576)
        XCTAssertEqual(FineCoachBackupV1.tagSize, 16)
        XCTAssertEqual(FineCoachBackupV1.headerLength, 82)
    }

    func testCanonicalJSONRejectsNestingDeeperThanSixteen() {
        var nested: Any = 0
        for _ in 0..<(BackupSecurityCeiling.maxJSONDepth + 1) {
            nested = [nested]
        }
        assertBackupError(
            { try BackupJSONCanonicalization.canonicalUTF8(nested) },
            .limitExceeded
        )
    }

    func testCanonicalJSONRejectsStringLargerThanSixtyFourKiB() {
        let oversized = String(repeating: "A", count: BackupSecurityCeiling.maxStringUTF8Bytes + 1)
        XCTAssertEqual(oversized.utf8.count, BackupSecurityCeiling.maxStringUTF8Bytes + 1)
        assertBackupError(
            { try BackupJSONCanonicalization.canonicalUTF8(oversized) },
            .limitExceeded
        )
        assertBackupError(
            { try BackupJSONCanonicalization.canonicalUTF8(["note": oversized] as [String: Any]) },
            .limitExceeded
        )
    }
}

extension BackupHostileInputTests {
    private enum Offset {
        static let magic = 0
        static let containerVersion = 4
        static let headerLength = 6
        static let payloadSchemaVersion = 8
        static let kdfID = 10
        static let aeadID = 11
        static let iterations = 12
        static let chunkSize = 56
        static let plaintextLength = 60
        static let recordCount = 68
        static let chunkCount = 76
        static let minimumReaderVersion = 80
    }

    private func validHeader(
        plaintextLength: UInt64 = 64,
        recordCount: UInt64 = 1,
        chunkCount: UInt32 = 1
    ) -> FineCoachBackupHeader {
        FineCoachBackupHeader(
            magic: FineCoachBackupV1.magic,
            containerVersion: FineCoachBackupV1.containerVersion,
            headerLength: FineCoachBackupV1.headerLength,
            payloadSchemaVersion: FineCoachBackupV1.payloadSchemaVersion,
            kdfID: FineCoachBackupV1.kdfID,
            aeadID: FineCoachBackupV1.aeadID,
            iterations: FineCoachBackupV1.iterations,
            salt: salt,
            noncePrefix: noncePrefix,
            chunkSize: FineCoachBackupV1.chunkSize,
            plaintextLength: plaintextLength,
            recordCount: recordCount,
            chunkCount: chunkCount,
            minimumReaderVersion: FineCoachBackupV1.minimumReaderVersion
        )
    }

    private func dummyContainer(for header: FineCoachBackupHeader) -> Data {
        var data = header.encode()
        let chunkBytes = Int(header.plaintextLength) + (Int(header.chunkCount) * FineCoachBackupV1.tagSize)
        data.append(Data(repeating: 0xA5, count: chunkBytes))
        return data
    }

    private func assertBackupError(
        _ work: () throws -> some Any,
        _ expected: BackupError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try work(), file: file, line: line) { error in
            XCTAssertEqual(error as? BackupError, expected, file: file, line: line)
        }
    }

    private func assertFailClosed(
        _ work: () throws -> Void,
        permitted: [BackupError],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try work(), file: file, line: line) { error in
            guard let backup = error as? BackupError, permitted.contains(backup) else {
                XCTFail("expected \(permitted), got \(error)", file: file, line: line)
                return
            }
        }
    }

    private func assertParseOrInspectFailsClosed(
        patching original: Data,
        offset: Int,
        mutate: (inout Data) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var mutated = original
        mutate(&mutated)
        XCTAssertNotEqual(mutated, original, file: file, line: line)
        assertFailClosed(
            { try FineCoachBackupHeader.parse(mutated) },
            permitted: [.invalidHeader, .unsupportedVersion],
            file: file,
            line: line
        )
        assertFailClosed(
            { try BackupContainerReader.inspectHeader(mutated) },
            permitted: [.invalidHeader, .unsupportedVersion],
            file: file,
            line: line
        )
    }

    private func assertCeilingRejected(
        _ encoded: Data,
        permitted: [BackupError] = [.limitExceeded, .invalidHeader, .unsupportedVersion],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let header = try FineCoachBackupHeader.parse(encoded)
            assertFailClosed(
                { try BackupSecurityCeiling.validateHeader(header) },
                permitted: permitted.contains(.limitExceeded)
                    ? permitted.filter { $0 == .limitExceeded || $0 == .invalidHeader }
                    : permitted,
                file: file,
                line: line
            )
        } catch let error as BackupError {
            XCTAssertTrue(permitted.contains(error), "parse: \(error)", file: file, line: line)
        } catch {
            XCTFail("unexpected parse error: \(error)", file: file, line: line)
        }
    }
}

extension Data {
    fileprivate mutating func writeUInt16BE(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(value >> 8)
        self[offset + 1] = UInt8(value & 0xFF)
    }

    fileprivate mutating func writeUInt32BE(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(truncatingIfNeeded: value >> 24)
        self[offset + 1] = UInt8(truncatingIfNeeded: value >> 16)
        self[offset + 2] = UInt8(truncatingIfNeeded: value >> 8)
        self[offset + 3] = UInt8(truncatingIfNeeded: value)
    }

    fileprivate mutating func writeUInt64BE(_ value: UInt64, at offset: Int) {
        self[offset] = UInt8(truncatingIfNeeded: value >> 56)
        self[offset + 1] = UInt8(truncatingIfNeeded: value >> 48)
        self[offset + 2] = UInt8(truncatingIfNeeded: value >> 40)
        self[offset + 3] = UInt8(truncatingIfNeeded: value >> 32)
        self[offset + 4] = UInt8(truncatingIfNeeded: value >> 24)
        self[offset + 5] = UInt8(truncatingIfNeeded: value >> 16)
        self[offset + 6] = UInt8(truncatingIfNeeded: value >> 8)
        self[offset + 7] = UInt8(truncatingIfNeeded: value)
    }
}
