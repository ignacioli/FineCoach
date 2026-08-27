import Foundation

public struct ValidatedText: Hashable, Codable, Sendable {
    public static let maximumUTF8Bytes = 64 * 1024

    public let value: String

    public init(_ rawValue: String, allowEmpty: Bool = false) throws {
        let canonical =
            rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping

        if !allowEmpty && canonical.isEmpty {
            throw DomainError.emptyText
        }
        guard canonical.utf8.count <= Self.maximumUTF8Bytes else {
            throw DomainError.textTooLong(maximumBytes: Self.maximumUTF8Bytes)
        }
        self.value = canonical
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public var isEmpty: Bool { value.isEmpty }
}
