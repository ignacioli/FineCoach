import SwiftUI

struct CopySetFlow {
    static func previousSet(in exercise: SessionExercise) -> TrainingSet? {
        exercise.sets.last
    }

    static func lastCompletedSet(in exercise: SessionExercise) -> TrainingSet? {
        exercise.sets.last { $0.state == .completed }
    }
}
