import CryptoKit
import Foundation
import XCTest

@testable import FineCoach

final class PlatformCryptoParityTests: XCTestCase {
    private struct Vector: Decodable {
        let id: String
        let given: Given
        let `when`: Operation
        let then: Expected

        struct Given: Decodable {
            let state: Input
        }
        struct Input: Decodable {
            let passwordNFC: String
            let passwordNFD: String
            let saltHex: String
            let iterations: UInt32
        }
        struct Operation: Decodable {
            let op: String
        }
        struct Expected: Decodable {
            let state: Output
        }
        struct Output: Decodable {
            let keyHex: String
            let passwordNFCUTF8SHA256: String
        }
    }

    func testNFCMatchesIndependentKey() throws {
        try assertParity(useDecomposedInput: false)
    }

    func testNFDMatchesSameIndependentKey() throws {
        try assertParity(useDecomposedInput: true)
    }

    private func assertParity(useDecomposedInput: Bool) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent(
            "shared/test-vectors/s0/crypto/m1a-fr-044__kdf-nfc-equivalence.json"
        )
        let vector = try JSONDecoder().decode(Vector.self, from: Data(contentsOf: url))
        XCTAssertEqual(vector.id, "kdf-nfc-equivalence")
        XCTAssertEqual(vector.when.op, "backup-kdf.derive-equivalent")
        let input = vector.given.state
        let expected = vector.then.state
        let raw = useDecomposedInput ? input.passwordNFD : input.passwordNFC
        let password = try BackupPassword(importing: raw)
        XCTAssertGreaterThanOrEqual(input.passwordNFC.count, 8)
        XCTAssertNotEqual(Array(input.passwordNFC.utf8), Array(input.passwordNFD.utf8))
        XCTAssertEqual(password.utf8, try BackupPassword(importing: input.passwordNFC).utf8)
        let digest = hex(Data(SHA256.hash(data: password.utf8)))
        XCTAssertEqual(digest, expected.passwordNFCUTF8SHA256)
        let salt = try decodeHex(input.saltHex)
        let key = try BackupKDF.deriveKey(passwordUTF8: password.utf8, salt: salt, iterations: input.iterations)
        XCTAssertEqual(key.count, 32)
        XCTAssertEqual(hex(key), expected.keyHex)
        print(
            "iOS platform=\(ProcessInfo.processInfo.operatingSystemVersionString) provider=CommonCrypto "
                + "input=\(useDecomposedInput ? "passwordNFD" : "passwordNFC") digest=\(digest) key=\(hex(key))"
        )
    }

    private func decodeHex(_ value: String) throws -> Data {
        let bytes = Array(value.utf8)
        XCTAssertEqual(bytes.count, 64)
        guard bytes.count == 64 else { throw BackupError.invalidState }
        return try Data(
            stride(from: 0, to: bytes.count, by: 2).map { index in
                let pair = String(decoding: bytes[index...index + 1], as: UTF8.self)
                return try XCTUnwrap(UInt8(pair, radix: 16))
            })
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
