import SwiftUI

struct DeleteExerciseFlow: View {
    let exercise: SessionExercise
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            Text(String(localized: "session.deleteExercise.title"))
                .fcFont(.title)
            Text(String(localized: "session.deleteExercise.lead"))
            Text(
                "• \(exercise.displayNameSnapshot.value) · \(exercise.sets.filter(\.contributesToStatistics).count)"
            )
            Text(String(localized: "session.deleteExercise.hint"))
                .foregroundStyle(FCSemanticColors.textSecondary)
            FCButton(title: String(localized: "session.deleteExercise.confirm")) {
                onConfirm()
            }
            .accessibilityIdentifier(FCAccessibilityID.activeSessionDeleteExerciseConfirm)
            Button(String(localized: "student.flow.cancel"), action: onCancel)
                .frame(minHeight: 44)
            Spacer()
        }
        .padding(FCPrimitives.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FCSemanticColors.surfacePage)
        .toolbar(.hidden, for: .navigationBar)
    }
}
