@testable import FineCoach
import XCTest

/// T078: the body-part summary behind the share-preview diagram (design
/// system §9.1) — primary = union of exercises' primary parts; secondary =
/// union of their secondary parts minus anything already primary; custom
/// exercises (no catalog facet) never color the diagram.
final class TrainedBodyPartsSummaryTests: XCTestCase {
    func testPrimaryIsUnionOfEachExercisesPrimaryPart() {
        let summary = TrainedBodyPartsSummary(exercises: [
            ExerciseBodyParts(primary: .thighs, secondary: [.glutes, .calves]),
            ExerciseBodyParts(primary: .glutes, secondary: [.thighs, .core]),
        ])

        XCTAssertEqual(summary.primary, [.thighs, .glutes])
    }

    func testSecondaryExcludesPartsThatArePrimaryElsewhere() {
        let summary = TrainedBodyPartsSummary(exercises: [
            ExerciseBodyParts(primary: .thighs, secondary: [.glutes, .calves]),
            ExerciseBodyParts(primary: .glutes, secondary: [.thighs, .core]),
        ])

        XCTAssertEqual(summary.secondary, [.calves, .core])
        XCTAssertTrue(summary.primary.isDisjoint(with: summary.secondary))
    }

    func testCustomExerciseContributesNothingEvenWithSecondaryParts() {
        let summary = TrainedBodyPartsSummary(exercises: [
            ExerciseBodyParts(primary: .chest, secondary: [.arms]),
            ExerciseBodyParts(primary: nil, secondary: [.back, .core]),
        ])

        XCTAssertEqual(summary.primary, [.chest])
        XCTAssertEqual(summary.secondary, [.arms])
    }

    func testOnlyCustomOrNoExercisesIsEmpty() {
        XCTAssertTrue(TrainedBodyPartsSummary(exercises: []).isEmpty)
        XCTAssertTrue(TrainedBodyPartsSummary(exercises: [ExerciseBodyParts(primary: nil)]).isEmpty)
    }

    func testDirectInitAlsoKeepsSetsDisjoint() {
        let summary = TrainedBodyPartsSummary(primary: [.back], secondary: [.back, .arms])

        XCTAssertEqual(summary.secondary, [.arms])
    }

    func testCatalogLabelsMapOntoBodyParts() {
        let parts = ExerciseBodyParts(catalogPrimary: "胸", catalogSecondary: ["肩", "臂", "未知"])

        XCTAssertEqual(parts.primary, .chest)
        XCTAssertEqual(parts.secondary, [.shoulders, .arms])
        XCTAssertNil(ExerciseBodyParts(catalogPrimary: nil).primary)
        XCTAssertEqual(
            ExerciseCatalogBrowse.muscleGroupOrder.compactMap(BodyPart.init(catalogMuscleGroup:)),
            BodyPart.allCases
        )
    }

    /// Every muscle-group label actually shipped in the built-in catalog
    /// must map to a `BodyPart`, or its exercise would silently not color
    /// the diagram.
    func testEveryBundledCatalogMuscleLabelMapsToABodyPart() throws {
        // Tests are hosted in the app, so the app bundle is `Bundle.main`.
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "provenance", withExtension: "json")
                ?? Bundle.main.url(forResource: "provenance", withExtension: "json", subdirectory: "ExerciseCatalog")
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let exercises = try XCTUnwrap(root["exercises"] as? [[String: Any]])
        XCTAssertFalse(exercises.isEmpty)

        var labels = Set<String>()
        for exercise in exercises {
            if let primary = exercise["primaryMuscleGroup"] as? String { labels.insert(primary) }
            labels.formUnion(exercise["secondaryMuscleGroups"] as? [String] ?? [])
        }
        let unmapped = labels.filter { BodyPart(catalogMuscleGroup: $0) == nil }
        XCTAssertEqual(unmapped, [], "catalog labels with no BodyPart: \(unmapped.sorted())")
    }

    /// §9.1: front shows shoulders/arms/chest/core/thighs/calves, back shows
    /// shoulders/arms/back/glutes/thighs/calves; together all 8 parts.
    func testDiagramGeometryCoversEachPartOnTheDocumentedSide() {
        let front = Set(FCBodyDiagramGeometry.front.compactMap(\.part))
        let back = Set(FCBodyDiagramGeometry.back.compactMap(\.part))

        XCTAssertEqual(front, [.shoulders, .arms, .chest, .core, .thighs, .calves])
        XCTAssertEqual(back, [.shoulders, .arms, .back, .glutes, .thighs, .calves])
        XCTAssertEqual(front.union(back), Set(BodyPart.allCases))
    }
}
