import SwiftUI

struct QuickCreateExerciseFlow: View {
    @ObservedObject var viewModel: ActiveSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            FCTextField(String(localized: "session.field.exerciseName"), text: $viewModel.exerciseName)
                .accessibilityIdentifier(FCAccessibilityID.activeSessionExerciseName)
            HStack(spacing: FCPrimitives.spacingSmall) {
                modeChip(
                    .weightReps,
                    title: String(localized: "session.mode.weightReps"),
                    id: FCAccessibilityID.activeSessionModeWeightReps
                )
            }
            HStack(spacing: FCPrimitives.spacingSmall) {
                modeChip(
                    .reps,
                    title: String(localized: "session.mode.reps"),
                    id: FCAccessibilityID.activeSessionModeReps
                )
                modeChip(
                    .duration,
                    title: String(localized: "session.mode.duration"),
                    id: FCAccessibilityID.activeSessionModeDuration
                )
            }
            if let exerciseNameConflict = viewModel.exerciseNameConflict {
                Text(exerciseNameConflict)
                    .foregroundStyle(FCSemanticColors.destructive)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionExerciseNameConflict)
            }
            FCButton(title: String(localized: "session.action.saveSessionOnly")) {
                Task { await viewModel.saveExercise() }
            }
            .accessibilityIdentifier(FCAccessibilityID.activeSessionSaveExercise)
            FCButton(title: String(localized: "session.action.saveToLibrary")) {
                Task { await viewModel.saveExerciseToLibrary() }
            }
            .accessibilityIdentifier(FCAccessibilityID.activeSessionSaveExerciseToLibrary)
        }
    }

    private func modeChip(_ mode: RecordMode, title: String, id: String) -> some View {
        Button(title) {
            viewModel.recordMode = mode
        }
        .frame(minHeight: 44)
        .padding(.horizontal, FCPrimitives.spacingSmall)
        .background(
            viewModel.recordMode == mode ? FCSemanticColors.primaryText : FCSemanticColors.separator
        )
        .foregroundStyle(
            viewModel.recordMode == mode ? FCSemanticColors.elevatedSurface : FCSemanticColors.primaryText
        )
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
        .accessibilityIdentifier(id)
        .accessibilityLabel(title)
        .accessibilityAddTraits(viewModel.recordMode == mode ? [.isSelected] : [])
    }
}
