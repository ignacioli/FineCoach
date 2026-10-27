import XCTest

@testable import FineCoach

final class EstimatedOneRepMaxTests: XCTestCase {
    private let squat = try! StableExerciseID("a2f5b6ef-b780-49c0-8d96-fdaff23e27ce")

    func testEpleyBoundariesAndInapplicableValues() throws {
        let weight = try DecimalValue("90")
        XCTAssertEqual(EstimatedOneRepMax.value(weight: weight, reps: try DecimalValue("1"), exerciseID: squat), weight)
        XCTAssertEqual(
            EstimatedOneRepMax.value(weight: weight, reps: try DecimalValue("10"), exerciseID: squat),
            try DecimalValue("120"))
        XCTAssertEqual(
            EstimatedOneRepMax.value(weight: weight, reps: try DecimalValue("5"), exerciseID: squat),
            try DecimalValue("105"))
        for reps in ["0", "11", "1.5", "-1"] {
            XCTAssertNil(EstimatedOneRepMax.value(weight: weight, reps: try DecimalValue(reps), exerciseID: squat))
        }
        for load in ["0", "-20"] {
            XCTAssertNil(
                EstimatedOneRepMax.value(weight: try DecimalValue(load), reps: try DecimalValue("5"), exerciseID: squat)
            )
        }
        XCTAssertNil(
            EstimatedOneRepMax.value(
                weight: weight, reps: try DecimalValue("5"), exerciseID: try StableExerciseID(UUID().uuidString)))
    }

    func testApprovedIDsExistInBundledBarbellWeightRepsCatalog() throws {
        let iosRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try JSONDecoder().decode(
            PlaceholderExerciseCatalog.self,
            from: Data(
                contentsOf: iosRoot.appendingPathComponent("FineCoachApp/Resources/ExerciseCatalog/provenance.json")))
        XCTAssertEqual(EstimatedOneRepMax.exerciseIDs.count, 11)
        for id in EstimatedOneRepMax.exerciseIDs {
            let row = try XCTUnwrap(catalog.exercises.first { $0.id == id.rawValue })
            XCTAssertEqual(row.recordMode, .weightReps)
            XCTAssertEqual(row.equipmentClass, "杠铃")
        }
    }
}
