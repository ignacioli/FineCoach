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
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            if exercise.recordModeSnapshot == .weightReps {
                VStack(alignment: .leading, spacing: FCPrimitives.space3) {
                    stepperField(
                        title: String(localized: "session.field.weight"),
                        text: $viewModel.weight,
                        field: .weight,
                        keyboardType: .decimalPad,
                        fieldIdentifier: FCAccessibilityID.activeSessionWeight,
                        decrementIdentifier: FCAccessibilityID.activeSessionWeightDecrement,
                        incrementIdentifier: FCAccessibilityID.activeSessionWeightIncrement
                    )
                    stepperField(
                        title: String(localized: "session.field.reps"),
                        text: $viewModel.reps,
                        field: .reps,
                        keyboardType: .numberPad,
                        fieldIdentifier: FCAccessibilityID.activeSessionReps,
                        decrementIdentifier: FCAccessibilityID.activeSessionRepsDecrement,
                        incrementIdentifier: FCAccessibilityID.activeSessionRepsIncrement
                    )
                }
                Text(String(localized: "session.field.weightStepHint"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, FCStepperField.valueColumnInset)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionWeightStepHint)
            } else if exercise.recordModeSnapshot == .reps {
                stepperField(
                    title: String(localized: "session.field.reps"),
                    text: $viewModel.reps,
                    field: .reps,
                    keyboardType: .numberPad,
                    fieldIdentifier: FCAccessibilityID.activeSessionReps,
                    decrementIdentifier: FCAccessibilityID.activeSessionRepsDecrement,
                    incrementIdentifier: FCAccessibilityID.activeSessionRepsIncrement
                )
            } else if exercise.recordModeSnapshot == .cardio {
                FCTextField(String(localized: "session.field.durationFlexible"), text: $viewModel.duration)
                    .keyboardType(.default)
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
                FCTextField(String(localized: "session.field.durationFlexible"), text: $viewModel.duration)
                    .keyboardType(.default)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionDuration)
            }

            // Left/right entry has no toggle of its own any more (P0-D8);
            // a set already recorded with sides keeps showing them when it
            // is edited, so no data is hidden.
            if viewModel.side != .none {
                FCTextField(String(localized: "session.field.left"), text: $viewModel.left)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionLeft)
                FCTextField(String(localized: "session.field.right"), text: $viewModel.right)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionRight)
            }

            if isEditMode {
                HStack(spacing: FCPrimitives.space2) {
                    FCButton(title: String(localized: "session.action.saveSetEdit")) {
                        Task { await viewModel.saveEditingSet() }
                    }
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionSaveSetEdit)

                    FCLinkButton(title: String(localized: "session.action.cancelSetEdit")) {
                        viewModel.cancelEditingSet()
                    }
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionCancelSetEdit)
                }
            } else {
                // The only primary action (P0-D11): prefill and kept values
                // replace add / copy, and undo lives on the recorded row.
                FCButton(title: String(localized: "session.action.confirmSet")) {
                    Task { await viewModel.confirmActiveDraftSet() }
                }
                .accessibilityIdentifier(FCAccessibilityID.activeSessionConfirmSet)
            }
        }
    }

    private func stepperField(
        title: String,
        text: Binding<String>,
        field: SetValueStepping.Field,
        keyboardType: UIKeyboardType,
        fieldIdentifier: String,
        decrementIdentifier: String,
        incrementIdentifier: String
    ) -> some View {
        FCLabelValueRow(label: title) {
            FCStepperField(
                title,
                text: text,
                canDecrement: SetValueStepping.canStepDown(text.wrappedValue, field: field),
                keyboardType: keyboardType,
                fieldIdentifier: fieldIdentifier,
                decrementIdentifier: decrementIdentifier,
                incrementIdentifier: incrementIdentifier,
                onDecrement: { viewModel.step(field, up: false) },
                onIncrement: { viewModel.step(field, up: true) }
            )
        }
    }
}
