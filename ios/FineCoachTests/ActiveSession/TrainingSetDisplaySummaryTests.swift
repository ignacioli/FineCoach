import FineCoach
import XCTest

final class TrainingSetDisplaySummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let exerciseID = StableUUID(UUID(uuidString: "88888888-8888-4888-8888-888888888888")!)
    private let setID = StableUUID(UUID(uuidString: "99999999-9999-4999-8999-999999999999")!)

    private func makeSet(_ input: TrainingSetInput) throws -> TrainingSet {
        try TrainingSet.makeDraft(
            id: setID,
            sessionExerciseID: exerciseID,
            orderIndex: 0,
            input: input,
            now: now
        )
    }

    func testWeightRepsDisplaySummaryIncludesUnits() throws {
        let set = try makeSet(
            TrainingSetInput(recordMode: .weightReps, weightValue: "17.5", repetitionCount: "12", unit: .kilograms)
        )
        XCTAssertEqual(set.displaySummary, "17.5kg × 12次")
    }

    func testRepsDisplaySummary() throws {
        let set = try makeSet(
            TrainingSetInput(recordMode: .reps, repetitionCount: "20", unit: .repetitions)
        )
        XCTAssertEqual(set.displaySummary, "20次")
    }

    func testDurationDisplaySummaryStaysInSeconds() throws {
        let set = try makeSet(
            TrainingSetInput(recordMode: .duration, durationSeconds: "60", unit: .seconds)
        )
        XCTAssertEqual(set.displaySummary, "60秒")
    }

    func testCardioDisplaySummaryConvertsDurationToMinutes() throws {
        let set = try makeSet(
            TrainingSetInput(
                recordMode: .cardio,
                durationSeconds: "300",
                unit: .seconds,
                distanceValue: "5",
                speedValue: "10",
                resistanceValue: "3"
            )
        )
        XCTAssertEqual(set.displaySummary, "5分钟 · 5km · 速度 10 · 阻力 3")
    }

    func testCardioDisplaySummaryOmitsOptionalFieldsWhenAbsent() throws {
        let set = try makeSet(
            TrainingSetInput(recordMode: .cardio, durationSeconds: "90", unit: .seconds, distanceValue: "1")
        )
        XCTAssertEqual(set.displaySummary, "1.5分钟 · 1km")
    }

    func testBilateralWeightRepsDisplaySummaryShowsBothSides() throws {
        let set = try makeSet(
            TrainingSetInput(
                recordMode: .weightReps,
                repetitionCount: "10",
                unit: .kilograms,
                side: .bilateral,
                leftValue: "8",
                rightValue: "9"
            )
        )
        XCTAssertEqual(set.displaySummary, "左 8kg / 右 9kg × 10次")
    }
}
