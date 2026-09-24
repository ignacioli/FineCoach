import SwiftUI

struct DeleteExerciseFlow: View {
    let exercise: SessionExercise
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
            Text(String(localized: "session.deleteExercise.title"))
                .font(.title3.weight(.semibold))
            Text(String(localized: "session.deleteExercise.lead"))
            Text(
                "• \(exercise.displayNameSnapshot.value) · \(exercise.sets.filter(\.contributesToStatistics).count)"
            )
            Text(String(localized: "session.deleteExercise.hint"))
                .foregroundStyle(FCSemanticColors.secondaryText)
            FCButton(title: String(localized: "session.deleteExercise.confirm")) {
                onConfirm()
            }
            .accessibilityIdentifier(FCAccessibilityID.activeSessionDeleteExerciseConfirm)
            Button(String(localized: "student.flow.cancel"), action: onCancel)
                .frame(minHeight: 44)
            Spacer()
        }
        .padding(FCPrimitives.spacingMedium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "session.deleteExercise.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
