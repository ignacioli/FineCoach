import Foundation

public struct NormalizedName: Hashable, Codable, Sendable {
    public let value: String

    public init(_ rawValue: String) throws {
        let validated = try ValidatedText(rawValue)
        self.value = validated.value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
