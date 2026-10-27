import Foundation

/// Spec 005 §12.1: estimates are derived only for these approved built-in actions.
public enum EstimatedOneRepMax {
    public static let exerciseIDs: Set<StableExerciseID> = Set(
        [
            "a2f5b6ef-b780-49c0-8d96-fdaff23e27ce",
            "3717d144-7815-4a97-9a56-956fb889c996",
            "ee8e8db4-2d82-49e1-ab7f-891e9a354934",
            "0c2d9b74-3d1e-481f-a7bf-3b3532f7d6b0",
            "8b0a0371-c0a9-42a7-aab7-68d520542fb2",
            "3f7b2244-8408-51fb-8211-3a764028d340",
            "9c31b616-0fe1-5fc1-bc97-9dba29be61ca",
            "2ab0f099-1041-5d03-9f63-f7a2a6ec11c9",
            "275fb49f-975c-4d6e-9d63-2c86ed740f40",
            "a390471f-f7ff-5371-850c-8eab07c68fb4",
            "db39aa20-bf4e-53d2-a3a7-e8cf4f2d24a8",
        ].map { try! StableExerciseID($0) })

    public static func value(weight: DecimalValue, reps: DecimalValue, exerciseID: StableExerciseID) -> DecimalValue? {
        guard exerciseIDs.contains(exerciseID), weight.isPositive, reps.isInteger,
            reps.decimal >= 1, reps.decimal <= 10
        else { return nil }
        if reps.decimal == 1 { return weight }
        let estimate = weight.decimal + weight.decimal * reps.decimal / 30
        return try? DecimalValue(NSDecimalNumber(decimal: estimate).stringValue)
    }
}
