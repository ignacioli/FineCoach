import Foundation

public struct StableUUID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UUID) {
        self.init(rawValue: rawValue)
    }

    public init?(uuidString: String) {
        guard let value = UUID(uuidString: uuidString) else {
            return nil
        }
        self.rawValue = value
    }

    public var id: UUID { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(UUID.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct StableExerciseID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: String

    public init?(rawValue: String) {
        let canonical =
            rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        guard !canonical.isEmpty, canonical.utf8.count <= ValidatedText.maximumUTF8Bytes else {
            return nil
        }
        self.rawValue = canonical
    }

    public init(_ rawValue: String) throws {
        guard let value = StableExerciseID(rawValue: rawValue) else {
            let canonical =
                rawValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping
            if canonical.isEmpty {
                throw DomainError.invalidIdentifier
            }
            throw DomainError.textTooLong(maximumBytes: ValidatedText.maximumUTF8Bytes)
        }
        self = value
    }

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
