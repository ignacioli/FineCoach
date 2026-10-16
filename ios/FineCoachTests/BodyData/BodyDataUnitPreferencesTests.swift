import FineCoach
import XCTest

/// Covers the M1B-FR-025 fix: the coach's chosen display unit for built-in
/// weight/length metrics persists (per-metric-family, coach-wide -- not
/// per-Student) and defaults to the canonical unit when nothing has been
/// chosen yet.
@MainActor
final class BodyDataUnitPreferencesTests: XCTestCase {
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "BodyDataUnitPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testDefaultsToCanonicalUnitsWhenNothingChosenYet() {
        let preferences = BodyDataUnitPreferences(defaults: makeIsolatedDefaults())
        XCTAssertEqual(preferences.weightUnit, .kilograms)
        XCTAssertEqual(preferences.lengthUnit, .centimeters)
    }

    func testWeightUnitChoicePersistsAcrossInstances() {
        let defaults = makeIsolatedDefaults()
        let first = BodyDataUnitPreferences(defaults: defaults)
        first.weightUnit = .pounds

        let second = BodyDataUnitPreferences(defaults: defaults)
        XCTAssertEqual(
            second.weightUnit, .pounds, "the choice must survive as a real UserDefaults write, not just in-memory state"
        )
    }

    func testLengthUnitChoicePersistsAcrossInstances() {
        let defaults = makeIsolatedDefaults()
        let first = BodyDataUnitPreferences(defaults: defaults)
        first.lengthUnit = .inches

        let second = BodyDataUnitPreferences(defaults: defaults)
        XCTAssertEqual(second.lengthUnit, .inches)
    }

    func testWeightAndLengthPreferencesAreIndependent() {
        let defaults = makeIsolatedDefaults()
        let preferences = BodyDataUnitPreferences(defaults: defaults)
        preferences.weightUnit = .pounds

        XCTAssertEqual(preferences.weightUnit, .pounds)
        XCTAssertEqual(
            preferences.lengthUnit, .centimeters, "changing weight unit must not affect the length preference")
    }
}
