import SwiftUI

struct QuickCreateExerciseFlow: View {
    @ObservedObject var viewModel: ActiveSessionViewModel
    @Binding var isFilterSheetPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            searchRow
            muscleChips
            if viewModel.showsRecentCatalogMatches {
                VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                    FCSectionLabel(String(localized: "exercise.library.recent"))
                        .accessibilityIdentifier(FCAccessibilityID.addExerciseRecent)
                    VStack(alignment: .leading, spacing: 0) {
                        FCListRowDivider()
                        ForEach(viewModel.recentCatalogMatches) { entry in
                            Button {
                                Task { await viewModel.addCatalogMatch(entry.id) }
                            } label: {
                                FCExerciseLibraryRowLabel(entry: entry)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier(FCAccessibilityID.addExerciseRecentRow(entry.id))
                            FCListRowDivider()
                        }
                    }
                }
                .padding(.bottom, FCPrimitives.space2)
            }
            LazyVStack(alignment: .leading, spacing: FCPrimitives.space4) {
                ForEach(viewModel.catalogSections) { section in
                    VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                        FCSectionLabel("\(catalogSectionTitle(section.id)) · \(section.entries.count)")
                            .accessibilityIdentifier(FCAccessibilityID.activeSessionCatalogSection(section.id))
                        VStack(spacing: 0) {
                            FCListRowDivider()
                            ForEach(section.entries) { entry in
                                Button {
                                    Task { await viewModel.addCatalogMatch(entry.id) }
                                } label: {
                                    FCExerciseLibraryRowLabel(entry: entry)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier(FCAccessibilityID.activeSessionCatalogRow(entry.id))
                                FCListRowDivider()
                            }
                        }
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
            if viewModel.recordMode == .weightReps {
                // P0-D8: chosen when the exercise is added; the set entry
                // then offers per-side weights.
                HStack {
                    Text(String(localized: "session.field.unilateralExercise"))
                        .fcFont(.body)
                        .foregroundStyle(FCSemanticColors.textPrimary)
                    Spacer(minLength: FCPrimitives.space2)
                    Toggle(
                        String(localized: "session.field.unilateralExercise"),
                        isOn: $viewModel.newExerciseIsUnilateral
                    )
                    .toggleStyle(FCToggleStyle())
                    .labelsHidden()
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier(FCAccessibilityID.activeSessionNewExerciseUnilateral)
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

    private var searchRow: some View {
        HStack(spacing: FCPrimitives.space2) {
            FCSearchField(String(localized: "exercise.library.search"), text: $viewModel.exerciseName)
                .accessibilityIdentifier(FCAccessibilityID.activeSessionExerciseName)
                .onChange(of: viewModel.exerciseName) { _, _ in
                    viewModel.scheduleCatalogSearch()
                }
            FCTitleIconButton(
                systemImage: viewModel.catalogEquipmentFilter == nil
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill",
                accessibilityLabel: String(localized: "exercise.library.filter.title")
            ) {
                isFilterSheetPresented = true
            }
            .accessibilityValue(
                Text(
                    viewModel.catalogEquipmentFilter == nil
                        ? ""
                        : String(localized: "exercise.library.filter.active")
                )
            )
            .accessibilityIdentifier(FCAccessibilityID.activeSessionCatalogFilter)
        }
    }

    private var muscleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FCPrimitives.space2) {
                FCFilterChip(
                    title: String(localized: "exercise.library.filter.all"),
                    isSelected: viewModel.catalogMuscleFilter == nil
                ) {
                    viewModel.selectCatalogMuscle(nil)
                }
                .accessibilityIdentifier(FCAccessibilityID.activeSessionCatalogMuscleAll)
                ForEach(ExerciseCatalogBrowse.muscleGroupOrder, id: \.self) { muscle in
                    FCFilterChip(title: muscle, isSelected: viewModel.catalogMuscleFilter == muscle) {
                        viewModel.selectCatalogMuscle(muscle)
                    }
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionCatalogMuscle(muscle))
                }
            }
        }
        .accessibilityLabel(Text("exercise.library.filter.muscle"))
    }

    private func catalogSectionTitle(_ id: String) -> String {
        switch id {
        case ExerciseCatalogBrowse.customSectionID:
            return String(localized: "exercise.kind.custom")
        case ExerciseCatalogBrowse.uncategorizedSectionID:
            return String(localized: "exercise.library.section.uncategorized")
        default:
            return id
        }
    }
}
