import SwiftUI

struct SetEditor: View {
    @ObservedObject var viewModel: ActiveSessionViewModel
    let exercise: SessionExercise
    /// When set, this editor is editing that specific existing set inline
    /// (pre-filled via `viewModel.beginEditingSet(_:)`) instead of the
    /// bottom "add a new set" form. M1-A fix: editing is addressed by this
    /// explicit id, never by `exercise.sets.last`.
    var targetSetID: StableUUID?

    private var isEditMode: Bool { targetSetID != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            if exercise.recordModeSnapshot == .weightReps {
                FCTextField(String(localized: "session.field.weight"), text: $viewModel.weight)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionWeight)
                FCTextField(String(localized: "session.field.reps"), text: $viewModel.reps)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionReps)
            } else if exercise.recordModeSnapshot == .reps {
                FCTextField(String(localized: "session.field.reps"), text: $viewModel.reps)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionReps)
            } else if exercise.recordModeSnapshot == .cardio {
                FCTextField(String(localized: "session.field.cardioDuration"), text: $viewModel.duration)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionDuration)
                FCTextField(String(localized: "session.field.distance"), text: $viewModel.distance)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionDistance)
                FCTextField(String(localized: "session.field.speed"), text: $viewModel.speed)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionSpeed)
                FCTextField(String(localized: "session.field.resistance"), text: $viewModel.resistance)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionResistance)
            } else {
                FCTextField(String(localized: "session.field.duration"), text: $viewModel.duration)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionDuration)
            }

            HStack(spacing: FCPrimitives.spacingSmall) {
                sideButton(
                    title: String(localized: "session.side.none"),
                    identifier: FCAccessibilityID.activeSessionSideNone,
                    value: .none
                )
                sideButton(
                    title: String(localized: "session.side.bilateral"),
                    identifier: FCAccessibilityID.activeSessionSideBilateral,
                    value: .bilateral
                )
            }

            if viewModel.side == .bilateral {
                FCTextField(String(localized: "session.field.left"), text: $viewModel.left)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionLeft)
                FCTextField(String(localized: "session.field.right"), text: $viewModel.right)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionRight)
            }

            if isEditMode {
                HStack(spacing: FCPrimitives.spacingSmall) {
                    FCButton(title: String(localized: "session.action.saveSetEdit")) {
                        Task { await viewModel.saveEditingSet() }
                    }
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionSaveSetEdit)

                    Button(String(localized: "session.action.cancelSetEdit")) {
                        viewModel.cancelEditingSet()
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionCancelSetEdit)
                }
            } else {
                FCButton(title: String(localized: "session.action.addSet")) {
                    Task { await viewModel.addDraftSet() }
                }
                .accessibilityIdentifier(FCAccessibilityID.activeSessionAddSet)

                FCButton(title: String(localized: "session.action.confirmSet")) {
                    Task { await viewModel.confirmActiveDraftSet() }
                }
                .accessibilityIdentifier(FCAccessibilityID.activeSessionConfirmSet)

                HStack(spacing: FCPrimitives.spacingSmall) {
                    Button(String(localized: "session.action.copyPrevious")) {
                        Task { await viewModel.copyPrevious() }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionCopyPrevious)

                    Button(String(localized: "session.action.copyLastSame")) {
                        Task { await viewModel.copyLastSame() }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionCopyLastSame)

                    Button(String(localized: "session.action.undo")) {
                        Task { await viewModel.undoLastSet() }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionUndoSet)
                }
            }
        }
    }

    private func sideButton(title: String, identifier: String, value: SetSide) -> some View {
        Button(title) {
            viewModel.side = value
        }
        .frame(minHeight: 44)
        .padding(.horizontal, FCPrimitives.spacingSmall)
        .background(
            viewModel.side == value ? FCSemanticColors.primaryText : FCSemanticColors.elevatedSurface
        )
        .foregroundStyle(
            viewModel.side == value ? FCSemanticColors.elevatedSurface : FCSemanticColors.primaryText
        )
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(viewModel.side == value ? [.isSelected] : [])
    }
}
