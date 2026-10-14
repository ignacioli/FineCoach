import Foundation

/// − / + stepping for the set editor's text fields (experience P0-D4: weight
/// ±2.5 kg, reps ±1). Works on the field's text so the coach can still type
/// any value; the result is only a suggestion until the set is confirmed.
public enum SetValueStepping {
    public enum Field: Sendable {
        case weight
        case reps

        public var step: Decimal {
            switch self {
            case .weight: return Decimal(string: "2.5", locale: Locale(identifier: "en_US_POSIX"))!
            case .reps: return 1
            }
        }

        public var minimum: Decimal {
            switch self {
            case .weight: return 0
            case .reps: return 1
            }
        }
    }

    /// The text moved one step up or down, clamped at `field.minimum`.
    /// Empty text steps up to one step (at least the minimum) and does not
    /// step down; text that is not a number is returned unchanged.
    public static func stepped(_ text: String, field: Field, up: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return up ? format(max(field.step, field.minimum)) : text
        }
        guard let value = try? DecimalValue(trimmed) else {
            return text
        }
        let moved = up ? value.decimal + field.step : value.decimal - field.step
        return format(max(moved, field.minimum))
    }

    /// Whether "−" can still lower the value (drives its disabled state).
    public static func canStepDown(_ text: String, field: Field) -> Bool {
        guard let value = try? DecimalValue(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return value.decimal > field.minimum
    }

    private static func format(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
