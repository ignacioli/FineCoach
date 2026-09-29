import SwiftUI

struct QuickCreateExerciseFlow: View {
    @ObservedObject var viewModel: ActiveSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            FCTextField(String(localized: "session.field.exerciseName"), text: $viewModel.exerciseName)
                .accessibilityIdentifier(FCAccessibilityID.activeSessionExerciseName)
                .onChange(of: viewModel.exerciseName) { _, _ in
                    viewModel.scheduleCatalogSearch()
                }
            if !viewModel.catalogMatches.isEmpty {
                VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                    ForEach(viewModel.catalogMatches) { entry in
                        Button {
                            Task { await viewModel.addCatalogMatch(entry.id) }
                        } label: {
                            HStack(spacing: FCPrimitives.space2) {
                                if let icon = FCEquipmentIcon.icon(equipmentClass: entry.equipmentClass, primaryMuscleGroup: entry.primaryMuscleGroup) {
                                    FCEquipmentIconView(icon)
                                }
                                Text(entry.displayedName)
                                    .fcFont(.body)
                                    .foregroundStyle(FCSemanticColors.textPrimary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier(FCAccessibilityID.activeSessionCatalogRow(entry.id))
                        .accessibilityLabel(entry.displayedName)
                    }
                }
            }
            FCFlowLayout(horizontalSpacing: FCPrimitives.space2, verticalSpacing: FCPrimitives.space2 - (44 - 30)) {
                modeChip(
                    .weightReps,
                    title: String(localized: "session.mode.weightReps"),
                    id: FCAccessibilityID.activeSessionModeWeightReps
                )
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
                modeChip(
                    .cardio,
                    title: String(localized: "session.mode.cardio"),
                    id: FCAccessibilityID.activeSessionModeCardio
                )
            }
            if let exerciseNameConflict = viewModel.exerciseNameConflict {
                Text(exerciseNameConflict)
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.statusDestructive)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionExerciseNameConflict)
            }
            FCButton(
                title: String(localized: "session.action.saveSessionOnly"),
                isEnabled: !viewModel.isMutationInFlight
            ) {
                Task { await viewModel.saveExercise() }
            }
            .accessibilityIdentifier(FCAccessibilityID.activeSessionSaveExercise)
            FCButton(
                title: String(localized: "session.action.saveToLibrary"),
                isEnabled: !viewModel.isMutationInFlight
            ) {
                Task { await viewModel.saveExerciseToLibrary() }
            }
            .accessibilityIdentifier(FCAccessibilityID.activeSessionSaveExerciseToLibrary)
        }
    }

    private func modeChip(_ mode: RecordMode, title: String, id: String) -> some View {
        FCFilterChip(title: title, isSelected: viewModel.recordMode == mode) {
            viewModel.recordMode = mode
        }
        .accessibilityIdentifier(id)
    }
}
