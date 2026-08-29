import FineCoach
import XCTest

final class BackupGoldenVectorTests: XCTestCase {
    private let creatingPassword = "口令测试甲乙丙丁"
    private let shortCreatingPassword = "口令测试甲乙丙"
    private let leadingSpacePassword = " 口令测试甲乙丙丁"
    private let fixedSalt = Data(repeating: 0x11, count: 32)
    private let fixedNoncePrefix = Data(repeating: 0x44, count: 8)

    /// PBKDF2-HMAC-SHA256(utf8("口令测试甲乙丙丁"), salt=32×0x11, c=600000, dkLen=32).
    private let pbkdf2GoldenKey = Data(
        hex: "9168a43546a30a95a2b6f7e66f572f7d2a8f142f3021796e06a9cf8c3059edab"
    )

    func testV1HeaderIs82BytesRoundTripsAndRejectsInvalidFields() throws {
        XCTAssertEqual(FineCoachBackupV1.magic, Data("FCBK".utf8))
        XCTAssertEqual(FineCoachBackupV1.magic.count, 4)
        XCTAssertEqual(FineCoachBackupV1.headerLength, 82)
        XCTAssertEqual(FineCoachBackupV1.containerVersion, 1)
        XCTAssertEqual(FineCoachBackupV1.payloadSchemaVersion, 1)
        XCTAssertEqual(FineCoachBackupV1.minimumReaderVersion, 1)
        XCTAssertEqual(FineCoachBackupV1.kdfID, 1)
        XCTAssertEqual(FineCoachBackupV1.aeadID, 1)
        XCTAssertEqual(FineCoachBackupV1.iterations, 600_000)
        XCTAssertEqual(FineCoachBackupV1.chunkSize, 1_048_576)
        XCTAssertEqual(FineCoachBackupV1.tagSize, 16)

        let header = makeValidHeader()
        let encoded = header.encode()
        XCTAssertEqual(encoded.count, 82)
        XCTAssertEqual(encoded.count, Int(FineCoachBackupV1.headerLength))
        assertEncodedFieldOrder(encoded, matches: header)

        let parsed = try FineCoachBackupHeader.parse(encoded)
        XCTAssertEqual(parsed, header)
        XCTAssertEqual(parsed.encode(), encoded)
        XCTAssertEqual(parsed.magic, FineCoachBackupV1.magic)
        XCTAssertEqual(parsed.iterations, 600_000)
        XCTAssertEqual(parsed.chunkSize, 1_048_576)

        XCTAssertNil(encoded.range(of: Data("林青".utf8)))
        XCTAssertNil(encoded.range(of: Data("合成备注".utf8)))
        XCTAssertNil(encoded.range(of: Data("13800001111".utf8)))

        XCTAssertThrowsError(try FineCoachBackupHeader.parse(Data())) { error in
            XCTAssertEqual(error as? BackupError, .invalidHeader)
        }
        XCTAssertThrowsError(try FineCoachBackupHeader.parse(Data(encoded.dropLast()))) { error in
            XCTAssertEqual(error as? BackupError, .invalidHeader)
        }
        XCTAssertThrowsError(try FineCoachBackupHeader.parse(encoded + Data([0x00]))) { error in
            XCTAssertEqual(error as? BackupError, .invalidHeader)
        }

        XCTAssertThrowsError(
            try FineCoachBackupHeader.parse(headerReplacing(header, magic: Data("FCBX".utf8)).encode())
        ) { error in
            XCTAssertEqual(error as? BackupError, .invalidHeader)
        }
        XCTAssertThrowsError(
            try FineCoachBackupHeader.parse(headerReplacing(header, magic: Data("fcbk".utf8)).encode())
        ) { error in
            XCTAssertEqual(error as? BackupError, .invalidHeader)
        }
        XCTAssertThrowsError(
            try FineCoachBackupHeader.parse(headerReplacing(header, headerLength: 80).encode())
        ) { error in
            XCTAssertEqual(error as? BackupError, .invalidHeader)
        }
        XCTAssertThrowsError(
            try FineCoachBackupHeader.parse(headerReplacing(header, headerLength: 83).encode())
        ) { error in
            XCTAssertEqual(error as? BackupError, .invalidHeader)
        }

        XCTAssertThrowsError(
            try FineCoachBackupHeader.parse(headerReplacing(header, containerVersion: 2).encode())
        ) { error in
            XCTAssertEqual(error as? BackupError, .unsupportedVersion)
        }
        XCTAssertThrowsError(
            try FineCoachBackupHeader.parse(headerReplacing(header, payloadSchemaVersion: 2).encode())
        ) { error in
            XCTAssertEqual(error as? BackupError, .unsupportedVersion)
        }
        XCTAssertThrowsError(
            try FineCoachBackupHeader.parse(headerReplacing(header, minimumReaderVersion: 2).encode())
        ) { error in
            XCTAssertEqual(error as? BackupError, .unsupportedVersion)
        }
        XCTAssertThrowsError(
            try FineCoachBackupHeader.parse(headerReplacing(header, kdfID: 2).encode())
        ) { error in
            XCTAssertEqual(error as? BackupError, .unsupportedVersion)
        }
        XCTAssertThrowsError(
            try FineCoachBackupHeader.parse(headerReplacing(header, aeadID: 2).encode())
        ) { error in
            XCTAssertEqual(error as? BackupError, .unsupportedVersion)
        }
    }

    func testRFC8785CanonicalUTF8SortsKeysAndPreservesDecimalStrings() throws {
        let nested: [String: Any] = [
            "zeta": "丙",
            "alpha": "甲",
        ]
        let object: [String: Any] = [
            "量": "12.50",
            "项": ["乙", "甲"],
            "元": nested,
            "版": 1,
        ]

        let canonical = try BackupJSONCanonicalization.canonicalUTF8(object)
        let expected = Data(#"{"元":{"alpha":"甲","zeta":"丙"},"版":1,"量":"12.50","项":["乙","甲"]}"#.utf8)
        XCTAssertEqual(canonical, expected)
        XCTAssertFalse(canonical.contains(where: { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }))

        let reorderedNested: [String: Any] = [
            "alpha": "甲",
            "zeta": "丙",
        ]
        let reordered: [String: Any] = [
            "版": 1,
            "元": reorderedNested,
            "量": "12.50",
            "项": ["乙", "甲"],
        ]
        XCTAssertEqual(try BackupJSONCanonicalization.canonicalUTF8(reordered), canonical)
        XCTAssertEqual(
            try BackupJSONCanonicalization.canonicalUTF8(["乙": "2", "甲": "1"] as [String: Any]),
            try BackupJSONCanonicalization.canonicalUTF8(["甲": "1", "乙": "2"] as [String: Any])
        )
        XCTAssertEqual(
            try BackupJSONCanonicalization.canonicalUTF8(["甲": "1", "乙": "2"] as [String: Any]),
            Data(#"{"乙":"2","甲":"1"}"#.utf8)
        )
    }

    func testFinalFlagIsZeroUntilLastChunk() throws {
        XCTAssertEqual(try BackupAEAD.finalFlag(chunkIndex: 0, chunkCount: 3), 0)
        XCTAssertEqual(try BackupAEAD.finalFlag(chunkIndex: 1, chunkCount: 3), 0)
        XCTAssertEqual(try BackupAEAD.finalFlag(chunkIndex: 2, chunkCount: 3), 1)
        XCTAssertEqual(try BackupAEAD.finalFlag(chunkIndex: 0, chunkCount: 1), 1)

        XCTAssertThrowsError(try BackupAEAD.finalFlag(chunkIndex: 0, chunkCount: 0)) { error in
            XCTAssertEqual(error as? BackupError, .invalidState)
        }
        XCTAssertThrowsError(try BackupAEAD.finalFlag(chunkIndex: 3, chunkCount: 3)) { error in
            XCTAssertEqual(error as? BackupError, .invalidState)
        }
        XCTAssertThrowsError(try BackupAEAD.finalFlag(chunkIndex: 1, chunkCount: 1)) { error in
            XCTAssertEqual(error as? BackupError, .invalidState)
        }
    }

    func testAADBytesAreHeaderIndexLengthAndFlagConcatenation() throws {
        let rawHeader = makeValidHeader().encode()
        let chunkIndex: UInt32 = 2
        let plaintextChunkLength: UInt32 = 1_024
        let finalFlag: UInt8 = 1

        let aad = BackupAEAD.additionalAuthenticatedData(
            rawHeader: rawHeader,
            chunkIndex: chunkIndex,
            plaintextChunkLength: plaintextChunkLength,
            finalFlag: finalFlag
        )

        var expected = rawHeader
        expected.append(contentsOf: bytesBE(chunkIndex))
        expected.append(contentsOf: bytesBE(plaintextChunkLength))
        expected.append(finalFlag)
        XCTAssertEqual(aad, expected)
        XCTAssertEqual(aad.count, rawHeader.count + 9)

        let changedHeader = BackupAEAD.additionalAuthenticatedData(
            rawHeader: Data(rawHeader + [0x00]),
            chunkIndex: chunkIndex,
            plaintextChunkLength: plaintextChunkLength,
            finalFlag: finalFlag
        )
        let changedIndex = BackupAEAD.additionalAuthenticatedData(
            rawHeader: rawHeader,
            chunkIndex: chunkIndex + 1,
            plaintextChunkLength: plaintextChunkLength,
            finalFlag: finalFlag
        )
        let changedLength = BackupAEAD.additionalAuthenticatedData(
            rawHeader: rawHeader,
            chunkIndex: chunkIndex,
            plaintextChunkLength: plaintextChunkLength + 1,
            finalFlag: finalFlag
        )
        let changedFlag = BackupAEAD.additionalAuthenticatedData(
            rawHeader: rawHeader,
            chunkIndex: chunkIndex,
            plaintextChunkLength: plaintextChunkLength,
            finalFlag: 0
        )
        XCTAssertNotEqual(changedHeader, aad)
        XCTAssertNotEqual(changedIndex, aad)
        XCTAssertNotEqual(changedLength, aad)
        XCTAssertNotEqual(changedFlag, aad)
    }

    func testChunkNonceIs12BytesPrefixPlusBigEndianIndex() throws {
        let prefix = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x01, 0x02])
        let nonce = try BackupAEAD.chunkNonce(prefix: prefix, chunkIndex: 0x0102_0304)
        XCTAssertEqual(nonce.count, 12)
        XCTAssertEqual(nonce, prefix + Data([0x01, 0x02, 0x03, 0x04]))
        XCTAssertEqual(
            try BackupAEAD.chunkNonce(prefix: prefix, chunkIndex: 0),
            prefix + Data([0x00, 0x00, 0x00, 0x00])
        )
        XCTAssertEqual(
            try BackupAEAD.chunkNonce(prefix: prefix, chunkIndex: 1),
            prefix + Data([0x00, 0x00, 0x00, 0x01])
        )

        XCTAssertThrowsError(try BackupAEAD.chunkNonce(prefix: Data(repeating: 0x11, count: 7), chunkIndex: 0)) {
            error in
            XCTAssertEqual(error as? BackupError, .invalidState)
        }
        XCTAssertThrowsError(try BackupAEAD.chunkNonce(prefix: Data(repeating: 0x11, count: 9), chunkIndex: 0)) {
            error in
            XCTAssertEqual(error as? BackupError, .invalidState)
        }
    }

    func testPBKDF2HMACSHA256GoldenVectorAndNFCPasswordEquivalence() throws {
        let password = try BackupPassword(creating: creatingPassword)
        XCTAssertEqual(password.utf8, Data(creatingPassword.utf8))

        let key = try BackupKDF.deriveKey(
            passwordUTF8: password.utf8,
            salt: fixedSalt,
            iterations: FineCoachBackupV1.iterations
        )
        XCTAssertEqual(key.count, 32)
        XCTAssertEqual(key, pbkdf2GoldenKey)
        XCTAssertEqual(
            try BackupKDF.deriveKey(
                passwordUTF8: password.utf8,
                salt: fixedSalt,
                iterations: FineCoachBackupV1.iterations
            ),
            key
        )

        let composed = try BackupPassword(importing: "é")
        let decomposed = try BackupPassword(importing: "e\u{0301}")
        XCTAssertEqual(composed.utf8, decomposed.utf8)
        XCTAssertEqual(composed.utf8, Data([0xC3, 0xA9]))
        XCTAssertEqual(
            try BackupKDF.deriveKey(
                passwordUTF8: composed.utf8,
                salt: fixedSalt,
                iterations: FineCoachBackupV1.iterations
            ),
            try BackupKDF.deriveKey(
                passwordUTF8: decomposed.utf8,
                salt: fixedSalt,
                iterations: FineCoachBackupV1.iterations
            )
        )
    }

    func testCreatingPasswordRequiresEightGraphemesAndImportAllowsShort() throws {
        XCTAssertEqual(Array(creatingPassword).count, 8)
        XCTAssertEqual(Array(shortCreatingPassword).count, 7)
        XCTAssertEqual(Array(leadingSpacePassword).count, 9)

        XCTAssertThrowsError(try BackupPassword(creating: shortCreatingPassword)) { error in
            XCTAssertEqual(error as? BackupError, .invalidPassword)
        }

        let created = try BackupPassword(creating: creatingPassword)
        XCTAssertEqual(created.utf8, Data(creatingPassword.precomposedStringWithCanonicalMapping.utf8))

        let importedShort = try BackupPassword(importing: "丙")
        XCTAssertEqual(importedShort.utf8, Data("丙".utf8))

        let withLeadingSpace = try BackupPassword(creating: leadingSpacePassword)
        XCTAssertEqual(withLeadingSpace.utf8.first, 0x20)
        XCTAssertNotEqual(withLeadingSpace.utf8, created.utf8)
        XCTAssertEqual(
            withLeadingSpace.utf8,
            Data(leadingSpacePassword.precomposedStringWithCanonicalMapping.utf8)
        )
    }

    private func makeValidHeader() -> FineCoachBackupHeader {
        FineCoachBackupHeader(
            magic: FineCoachBackupV1.magic,
            containerVersion: FineCoachBackupV1.containerVersion,
            headerLength: FineCoachBackupV1.headerLength,
            payloadSchemaVersion: FineCoachBackupV1.payloadSchemaVersion,
            kdfID: FineCoachBackupV1.kdfID,
            aeadID: FineCoachBackupV1.aeadID,
            iterations: FineCoachBackupV1.iterations,
            salt: fixedSalt,
            noncePrefix: fixedNoncePrefix,
            chunkSize: FineCoachBackupV1.chunkSize,
            plaintextLength: 2_048,
            recordCount: 3,
            chunkCount: 1,
            minimumReaderVersion: FineCoachBackupV1.minimumReaderVersion
        )
    }

    private func headerReplacing(
        _ base: FineCoachBackupHeader,
        magic: Data? = nil,
        containerVersion: UInt16? = nil,
        headerLength: UInt16? = nil,
        payloadSchemaVersion: UInt16? = nil,
        kdfID: UInt8? = nil,
        aeadID: UInt8? = nil,
        minimumReaderVersion: UInt16? = nil
    ) -> FineCoachBackupHeader {
        FineCoachBackupHeader(
            magic: magic ?? base.magic,
            containerVersion: containerVersion ?? base.containerVersion,
            headerLength: headerLength ?? base.headerLength,
            payloadSchemaVersion: payloadSchemaVersion ?? base.payloadSchemaVersion,
            kdfID: kdfID ?? base.kdfID,
            aeadID: aeadID ?? base.aeadID,
            iterations: base.iterations,
            salt: base.salt,
            noncePrefix: base.noncePrefix,
            chunkSize: base.chunkSize,
            plaintextLength: base.plaintextLength,
            recordCount: base.recordCount,
            chunkCount: base.chunkCount,
            minimumReaderVersion: minimumReaderVersion ?? base.minimumReaderVersion
        )
    }

    private func assertEncodedFieldOrder(_ encoded: Data, matches header: FineCoachBackupHeader) {
        XCTAssertEqual(encoded.count, 82)
        XCTAssertEqual(encoded.subdata(in: 0..<4), header.magic)
        XCTAssertEqual(u16BE(encoded, offset: 4), header.containerVersion)
        XCTAssertEqual(u16BE(encoded, offset: 6), header.headerLength)
        XCTAssertEqual(u16BE(encoded, offset: 8), header.payloadSchemaVersion)
        XCTAssertEqual(encoded[10], header.kdfID)
        XCTAssertEqual(encoded[11], header.aeadID)
        XCTAssertEqual(u32BE(encoded, offset: 12), header.iterations)
        XCTAssertEqual(encoded.subdata(in: 16..<48), header.salt)
        XCTAssertEqual(encoded.subdata(in: 48..<56), header.noncePrefix)
        XCTAssertEqual(u32BE(encoded, offset: 56), header.chunkSize)
        XCTAssertEqual(u64BE(encoded, offset: 60), header.plaintextLength)
        XCTAssertEqual(u64BE(encoded, offset: 68), header.recordCount)
        XCTAssertEqual(u32BE(encoded, offset: 76), header.chunkCount)
        XCTAssertEqual(u16BE(encoded, offset: 80), header.minimumReaderVersion)
        XCTAssertEqual(u32BE(encoded, offset: 12), 600_000)
        XCTAssertEqual(u32BE(encoded, offset: 56), 1_048_576)
    }

    private func u16BE(_ data: Data, offset: Int) -> UInt16 {
        (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private func u32BE(_ data: Data, offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }

    private func u64BE(_ data: Data, offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(data[offset + index])
        }
        return value
    }

    private func bytesBE(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }
}

extension Data {
    fileprivate init(hex: String) {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}
