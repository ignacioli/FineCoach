import XCTest

@testable import FineCoach

/// P0-D8 / P0-D12: the unilateral flag is the library default, overridable
/// per exercise by `ExercisePreference.isUnilateral`, and a backup written
/// before the field existed still decodes (payloadSchemaVersion stays 3).
final class ExercisePreferenceUnilateralTests: XCTestCase {
    private let exerciseID = StableExerciseID(rawValue: "fc.placeholder.single-arm-row")!

    func testNoOverrideFollowsTheLibraryDefault() throws {
        XCTAssertNil(ExercisePreference(exerciseID: exerciseID).isUnilateral)
        XCTAssertTrue(try entry(preference: nil, byDefault: true).isUnilateral)
        XCTAssertFalse(try entry(preference: ExercisePreference(exerciseID: exerciseID), byDefault: false).isUnilateral)
    }

    func testOverrideWinsOverTheLibraryDefault() throws {
        let off = ExercisePreference(exerciseID: exerciseID, isUnilateral: false)
        let on = ExercisePreference(exerciseID: exerciseID, isUnilateral: true)
        XCTAssertFalse(try entry(preference: off, byDefault: true).isUnilateral)
        XCTAssertTrue(try entry(preference: on, byDefault: false).isUnilateral)
    }

    func testUpdatingKeepsOtherFieldsAndNilLeavesTheOverride() throws {
        let original = ExercisePreference(exerciseID: exerciseID, isFavorite: true, isAssisted: true)
        let updated = original.updating(isUnilateral: true)
        XCTAssertEqual(updated.isUnilateral, true)
        XCTAssertTrue(updated.isFavorite)
        XCTAssertTrue(updated.isAssisted)
        XCTAssertEqual(updated.updating(isHidden: true).isUnilateral, true)
    }

    func testBackupFrameWithoutTheFieldDecodes() throws {
        let legacy = Data(
            #"{"exerciseID":"fc.placeholder.single-arm-row","isAssisted":false,"isFavorite":true,"isHidden":false}"#
                .utf8
        )
        let decoded = try BackupJSONCodec.decode(ExercisePreference.self, from: legacy)
        XCTAssertNil(decoded.isUnilateral)
        XCTAssertTrue(decoded.isFavorite)
        XCTAssertEqual(try BackupJSONCodec.canonical(decoded), legacy, "an old frame must re-encode byte for byte")

        let withOverride = ExercisePreference(exerciseID: exerciseID, isUnilateral: true)
        let roundTripped = try BackupJSONCodec.decode(
            ExercisePreference.self,
            from: try BackupJSONCodec.canonical(withOverride)
        )
        XCTAssertEqual(roundTripped, withOverride)
    }

    private func entry(preference: ExercisePreference?, byDefault: Bool) throws -> ExerciseLibraryEntry {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let item = try ExerciseCatalogItem(
            id: exerciseID,
            kind: .builtIn,
            canonicalName: try NormalizedName("哑铃单臂划船"),
            recordMode: .weightReps,
            metadataVersion: "test",
            lifecycle: .active,
            provenanceRef: "fc.placeholder.single-arm-row",
            createdAtUTC: now,
            updatedAtUTC: now
        )
        return ExerciseLibraryEntry(item: item, preference: preference, isUnilateralByDefault: byDefault)
    }
}
