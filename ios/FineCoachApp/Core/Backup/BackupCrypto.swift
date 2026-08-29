import CommonCrypto
import CryptoKit
import Foundation

public enum BackupAEAD {
    public static func chunkNonce(prefix: Data, chunkIndex: UInt32) throws -> Data {
        guard prefix.count == 8 else {
            throw BackupError.invalidState
        }
        var nonce = prefix
        nonce.append(UInt8(truncatingIfNeeded: chunkIndex >> 24))
        nonce.append(UInt8(truncatingIfNeeded: chunkIndex >> 16))
        nonce.append(UInt8(truncatingIfNeeded: chunkIndex >> 8))
        nonce.append(UInt8(truncatingIfNeeded: chunkIndex))
        return nonce
    }

    public static func additionalAuthenticatedData(
        rawHeader: Data,
        chunkIndex: UInt32,
        plaintextChunkLength: UInt32,
        finalFlag: UInt8
    ) -> Data {
        var aad = rawHeader
        aad.append(UInt8(truncatingIfNeeded: chunkIndex >> 24))
        aad.append(UInt8(truncatingIfNeeded: chunkIndex >> 16))
        aad.append(UInt8(truncatingIfNeeded: chunkIndex >> 8))
        aad.append(UInt8(truncatingIfNeeded: chunkIndex))
        aad.append(UInt8(truncatingIfNeeded: plaintextChunkLength >> 24))
        aad.append(UInt8(truncatingIfNeeded: plaintextChunkLength >> 16))
        aad.append(UInt8(truncatingIfNeeded: plaintextChunkLength >> 8))
        aad.append(UInt8(truncatingIfNeeded: plaintextChunkLength))
        aad.append(finalFlag)
        return aad
    }

    public static func finalFlag(chunkIndex: UInt32, chunkCount: UInt32) throws -> UInt8 {
        guard chunkCount > 0, chunkIndex < chunkCount else {
            throw BackupError.invalidState
        }
        return chunkIndex == chunkCount - 1 ? 1 : 0
    }

    public static func seal(
        plaintext: Data,
        key: Data,
        nonce: Data,
        authenticating aad: Data
    ) throws -> (ciphertext: Data, tag: Data) {
        do {
            let sealed = try AES.GCM.seal(
                plaintext,
                using: SymmetricKey(data: key),
                nonce: AES.GCM.Nonce(data: nonce),
                authenticating: aad
            )
            return (sealed.ciphertext, sealed.tag)
        } catch {
            throw BackupError.authenticationFailed
        }
    }

    public static func open(
        ciphertext: Data,
        tag: Data,
        key: Data,
        nonce: Data,
        authenticating aad: Data
    ) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: aad)
        } catch {
            throw BackupError.authenticationFailed
        }
    }
}

public enum BackupKDF {
    public static func deriveKey(passwordUTF8: Data, salt: Data, iterations: UInt32) throws -> Data {
        guard salt.count == 32, iterations == FineCoachBackupV1.iterations, !passwordUTF8.isEmpty else {
            throw BackupError.invalidState
        }
        var derived = Data(count: 32)
        let keyLength = derived.count
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            passwordUTF8.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordUTF8.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw BackupError.authenticationFailed
        }
        return derived
    }
}
