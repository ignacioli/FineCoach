import Foundation
import Security

public struct SecureRandomGenerator: SecureRandomSource, Sendable {
    public init() {}

    public func randomBytes(count: Int) throws -> Data {
        guard count >= 0 else {
            throw DomainError.invalidNumber
        }
        guard count > 0 else {
            return Data()
        }

        var bytes = Data(repeating: 0, count: count)
        let status: OSStatus = bytes.withUnsafeMutableBytes { buffer in
            guard let address = buffer.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, count, address)
        }
        guard status == errSecSuccess else {
            throw DomainError.randomSourceFailed
        }
        return bytes
    }
}
