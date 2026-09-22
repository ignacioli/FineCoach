import FineCoach
import XCTest

/// M1B-FR-028: `ExercisePreference.isAssisted` and its `updating(...)`
/// plumbing, mirroring the existing `isFavorite`/`isHidden` coverage
/// pattern. Defaults to `false` and must round-trip through `updating`
/// without disturbing the other flags.
final class ExercisePreferenceAssistedTests: XCTestCase {
    private let exerciseID = StableExerciseID(rawValue: "fc.placeholder.assisted-pullup")!

    func testDefaultsToFalse() {
        let preference = ExercisePreference(exerciseID: exerciseID)
        XCTAssertFalse(preference.isAssisted)
    }

    func testUpdatingSetsIsAssistedWithoutDisturbingOtherFields() throws {
        let alias = try NormalizedName("辅助引体")
        let original = ExercisePreference(
            exerciseID: exerciseID,
            alias: alias,
            isFavorite: true,
            isHidden: false,
            isAssisted: false
        )

        let updated = original.updating(isAssisted: true)

        XCTAssertTrue(updated.isAssisted)
        XCTAssertTrue(updated.isFavorite)
        XCTAssertFalse(updated.isHidden)
        XCTAssertEqual(updated.alias, alias)
    }

    func testUpdatingWithNilLeavesIsAssistedUnchanged() {
        let original = ExercisePreference(exerciseID: exerciseID, isAssisted: true)
        let updated = original.updating(isFavorite: true)
        XCTAssertTrue(updated.isAssisted)
    }
}
