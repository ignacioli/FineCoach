import Foundation

public struct DecimalValue: Hashable, Codable, Sendable, Comparable {
    public let canonicalString: String

    public init(_ rawValue: String) throws {
        let input = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            throw DomainError.invalidDecimal
        }

        var hasDecimalPoint = false
        var hasDigit = false
        for (index, character) in input.enumerated() {
            if character >= "0" && character <= "9" {
                hasDigit = true
                continue
            }
            if character == "." && !hasDecimalPoint {
                hasDecimalPoint = true
                continue
            }
            if character == "-" && index == 0 {
                continue
            }
            throw DomainError.invalidDecimal
        }
        guard hasDigit else {
            throw DomainError.invalidDecimal
        }

        guard let decimal = Decimal(string: input, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DomainError.invalidDecimal
        }
        let number = NSDecimalNumber(decimal: decimal)
        guard number != .notANumber else {
            throw DomainError.invalidDecimal
        }
        var canonical = number.stringValue
        if canonical == "-0" {
            canonical = "0"
        }
        guard canonical.utf8.count <= ValidatedText.maximumUTF8Bytes else {
            throw DomainError.textTooLong(maximumBytes: ValidatedText.maximumUTF8Bytes)
        }
        self.canonicalString = canonical
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(canonicalString)
    }

    public static let zero = try! DecimalValue("0")

    public var decimal: Decimal {
        Decimal(string: canonicalString, locale: Locale(identifier: "en_US_POSIX")) ?? .zero
    }

    public var isZero: Bool { self == .zero }
    public var isPositive: Bool { self > .zero }
    public var isInteger: Bool {
        var value = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return rounded == decimal
    }

    public func adding(_ other: DecimalValue) throws -> DecimalValue {
        let sum = NSDecimalNumber(decimal: decimal).adding(NSDecimalNumber(decimal: other.decimal))
        return try DecimalValue(sum.stringValue)
    }

    public func multiplied(by other: DecimalValue) throws -> DecimalValue {
        let product = NSDecimalNumber(decimal: decimal).multiplying(by: NSDecimalNumber(decimal: other.decimal))
        return try DecimalValue(product.stringValue)
    }

    public static func seconds(_ interval: TimeInterval) throws -> DecimalValue {
        let clamped = max(0, interval.rounded(.down))
        return try DecimalValue(String(Int(clamped)))
    }

    public static func < (lhs: DecimalValue, rhs: DecimalValue) -> Bool {
        NSDecimalNumber(decimal: lhs.decimal).compare(NSDecimalNumber(decimal: rhs.decimal)) == .orderedAscending
    }
}

public enum MeasurementUnit: String, Codable, CaseIterable, Sendable {
    case kilograms
    case pounds
    case repetitions
    case seconds
    case none
}

public enum RecordMode: String, Codable, CaseIterable, Sendable {
    case weightReps
    case reps
    case duration
}

public enum SetSide: String, Codable, CaseIterable, Sendable {
    case none
    case left
    case right
    case bilateral
}
