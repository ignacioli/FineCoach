import Foundation

enum BackupContainerCodec {
    static func encrypt(
        plaintext: Data,
        password: BackupPassword,
        recordCount: UInt64,
        random: any SecureRandomSource
    ) throws -> Data {
        guard !plaintext.isEmpty, plaintext.count <= BackupSecurityCeiling.maxPlaintextBytes else {
            throw BackupError.limitExceeded
        }
        let salt = try random.randomBytes(count: 32)
        let noncePrefix = try random.randomBytes(count: 8)
        let key = try BackupKDF.deriveKey(
            passwordUTF8: password.utf8,
            salt: salt,
            iterations: FineCoachBackupV1.iterations
        )
        let chunkSize = Int(FineCoachBackupV1.chunkSize)
        let chunkCount = UInt32((plaintext.count + chunkSize - 1) / chunkSize)
        let header = FineCoachBackupHeader(
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
            plaintextLength: UInt64(plaintext.count),
            recordCount: recordCount,
            chunkCount: chunkCount,
            minimumReaderVersion: FineCoachBackupV1.minimumReaderVersion
        )
        try BackupSecurityCeiling.validateHeader(header)
        let rawHeader = header.encode()
        var container = rawHeader
        var offset = 0
        for index in 0..<chunkCount {
            let end = min(offset + chunkSize, plaintext.count)
            let chunk = plaintext.subdata(in: offset..<end)
            let nonce = try BackupAEAD.chunkNonce(prefix: noncePrefix, chunkIndex: index)
            let flag = try BackupAEAD.finalFlag(chunkIndex: index, chunkCount: chunkCount)
            let aad = BackupAEAD.additionalAuthenticatedData(
                rawHeader: rawHeader,
                chunkIndex: index,
                plaintextChunkLength: UInt32(chunk.count),
                finalFlag: flag
            )
            let sealed = try BackupAEAD.seal(plaintext: chunk, key: key, nonce: nonce, authenticating: aad)
            container.append(sealed.ciphertext)
            container.append(sealed.tag)
            offset = end
        }
        return container
    }

    static func decrypt(container: Data, password: BackupPassword) throws -> Data {
        let header = try BackupContainerReader.inspectHeader(container)
        try BackupSecurityCeiling.validateHeader(header)
        try BackupContainerReader.rejectTrailingOrReorderedChunks(header: header, container: container)
        let key = try BackupKDF.deriveKey(
            passwordUTF8: password.utf8,
            salt: header.salt,
            iterations: header.iterations
        )
        let rawHeader = header.encode()
        var plaintext = Data()
        plaintext.reserveCapacity(Int(header.plaintextLength))
        var offset = Int(FineCoachBackupV1.headerLength)
        var remaining = header.plaintextLength
        for index in 0..<header.chunkCount {
            let chunkPlainLength =
                index == header.chunkCount - 1
                ? remaining
                : UInt64(header.chunkSize)
            remaining -= chunkPlainLength
            let cipherLength = Int(chunkPlainLength)
            let end = offset + cipherLength + FineCoachBackupV1.tagSize
            guard end <= container.count else {
                throw BackupError.authenticationFailed
            }
            let ciphertext = container.subdata(in: offset..<(offset + cipherLength))
            let tag = container.subdata(
                in: (offset + cipherLength)..<(offset + cipherLength + FineCoachBackupV1.tagSize)
            )
            let nonce = try BackupAEAD.chunkNonce(prefix: header.noncePrefix, chunkIndex: index)
            let flag = try BackupAEAD.finalFlag(chunkIndex: index, chunkCount: header.chunkCount)
            let aad = BackupAEAD.additionalAuthenticatedData(
                rawHeader: rawHeader,
                chunkIndex: index,
                plaintextChunkLength: UInt32(chunkPlainLength),
                finalFlag: flag
            )
            let chunk = try BackupAEAD.open(
                ciphertext: ciphertext,
                tag: tag,
                key: key,
                nonce: nonce,
                authenticating: aad
            )
            plaintext.append(chunk)
            offset = end
        }
        guard UInt64(plaintext.count) == header.plaintextLength else {
            throw BackupError.authenticationFailed
        }
        return plaintext
    }
}
