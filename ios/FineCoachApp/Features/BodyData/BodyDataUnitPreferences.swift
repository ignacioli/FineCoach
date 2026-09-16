import Foundation

/// The coach's globally-remembered display-unit choice for built-in
/// weight/length metrics (M1B-FR-025): "same saved value, switch the
/// display unit" is a per-coach UI preference, not per-Student data, so it
/// is stored once via `UserDefaults` rather than through the Student-scoped
/// persistence layer. This is DISPLAY ONLY -- it never changes what gets
/// written to a `BodyMeasurement` (see `BuiltInUnitConversion`, which always
/// stores/reads the canonical kg/cm value).
@MainActor
public final class BodyDataUnitPreferences {
    public static let shared = BodyDataUnitPreferences()

    private enum Key {
        static let weight = "bodyData.displayUnit.weight"
        static let length = "bodyData.displayUnit.length"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var weightUnit: BuiltInUnitConversion.WeightDisplayUnit {
        get {
            defaults.string(forKey: Key.weight)
                .flatMap(BuiltInUnitConversion.WeightDisplayUnit.init(rawValue:)) ?? .kilograms
        }
        set { defaults.set(newValue.rawValue, forKey: Key.weight) }
    }

    public var lengthUnit: BuiltInUnitConversion.LengthDisplayUnit {
        get {
            defaults.string(forKey: Key.length)
                .flatMap(BuiltInUnitConversion.LengthDisplayUnit.init(rawValue:)) ?? .centimeters
        }
        set { defaults.set(newValue.rawValue, forKey: Key.length) }
    }
}
