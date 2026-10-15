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
            if viewModel.usesSideEntry(exercise) {
                sideEntry
            } else if exercise.recordModeSnapshot == .weightReps {
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
            // a set recorded on one side before keeps showing it when it is
            // edited, so no data is hidden.
            if viewModel.side == .left || viewModel.side == .right {
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
                        UIApplication.shared.fcDismissKeyboard()
                        Task { await viewModel.saveEditingSet() }
                    }
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionSaveSetEdit)

                    FCLinkButton(title: String(localized: "session.action.cancelSetEdit")) {
                        UIApplication.shared.fcDismissKeyboard()
                        viewModel.cancelEditingSet()
                    }
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionCancelSetEdit)
                }
            } else {
                // The only primary action (P0-D11): prefill and kept values
                // replace add / copy, and undo lives on the recorded row.
                FCButton(title: String(localized: "session.action.confirmSet")) {
                    // The number pads have no return key; the set is done, so
                    // the keyboard goes away (owner device walkthrough
                    // 2026-10-15: it stayed up across exercises).
                    UIApplication.shared.fcDismissKeyboard()
                    Task { await viewModel.confirmActiveDraftSet() }
                }
                .accessibilityIdentifier(FCAccessibilityID.activeSessionConfirmSet)
            }
        }
    }

    /// Unilateral weight × reps (P0-D8, P0-a2b): one 「每侧重量」 stepper,
    /// or 左 / 右 steppers after 「左右不同」. Both record `side = .bilateral`.
    private var sideEntry: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space3) {
            if viewModel.splitSides {
                sideStepper(.left, title: String(localized: "session.field.leftWeight"), text: $viewModel.left)
                sideStepper(.right, title: String(localized: "session.field.rightWeight"), text: $viewModel.right)
            } else {
                stepperField(
                    title: String(localized: "session.field.perSideWeight"),
                    text: $viewModel.weight,
                    field: .weight,
                    keyboardType: .decimalPad,
                    fieldIdentifier: FCAccessibilityID.activeSessionWeight,
                    decrementIdentifier: FCAccessibilityID.activeSessionWeightDecrement,
                    incrementIdentifier: FCAccessibilityID.activeSessionWeightIncrement
                )
            }
            stepperField(
                title: String(localized: "session.field.reps"),
                text: $viewModel.reps,
                field: .reps,
                keyboardType: .numberPad,
                fieldIdentifier: FCAccessibilityID.activeSessionReps,
                decrementIdentifier: FCAccessibilityID.activeSessionRepsDecrement,
                incrementIdentifier: FCAccessibilityID.activeSessionRepsIncrement
            )
            FCLinkButton(
                title: String(
                    localized: viewModel.splitSides ? "session.action.sidesEqual" : "session.action.sidesDiffer"
                )
            ) {
                viewModel.toggleSplitSides(for: exercise)
            }
            .padding(.leading, FCStepperField.valueColumnInset)
            .accessibilityIdentifier(FCAccessibilityID.activeSessionSplitSides)
        }
    }

    private func sideStepper(_ which: SetSide, title: String, text: Binding<String>) -> some View {
        let isLeft = which == .left
        return FCLabelValueRow(label: title) {
            FCStepperField(
                title,
                text: text,
                canDecrement: SetValueStepping.canStepDown(text.wrappedValue, field: .weight),
                keyboardType: .decimalPad,
                fieldIdentifier: isLeft ? FCAccessibilityID.activeSessionLeft : FCAccessibilityID.activeSessionRight,
                decrementIdentifier: isLeft
                    ? FCAccessibilityID.activeSessionLeftDecrement : FCAccessibilityID.activeSessionRightDecrement,
                incrementIdentifier: isLeft
                    ? FCAccessibilityID.activeSessionLeftIncrement : FCAccessibilityID.activeSessionRightIncrement,
                onDecrement: { viewModel.stepSide(which, up: false) },
                onIncrement: { viewModel.stepSide(which, up: true) }
            )
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

extension UIApplication {
    /// Ends editing in whichever field has focus.
    func fcDismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
