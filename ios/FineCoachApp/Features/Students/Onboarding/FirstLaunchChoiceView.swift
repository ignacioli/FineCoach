import SwiftUI

/// M2-07 首次启动二选一 (T039, M2-FR-025). Shown only while the install state is `unselected`.
/// Choosing 「Coach 使用」 shows the existing onboarding; nothing is written here, and nothing
/// that makes the install a Coach install is written until the coach adds a first student or
/// skips on the onboarding page, so the coach can come back and still import an archive.
struct FirstLaunchChoiceView: View {
    let onChooseCoach: () -> Void
    let onChooseImport: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FCPrimitives.space3) {
                Image("mascot-empty-state")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .accessibilityHidden(true)
                    .padding(.top, FCPrimitives.space8)
                Text(String(localized: "archive.firstLaunch.title"))
                    .fcFont(.headline)
                    .foregroundStyle(FCSemanticColors.actionPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, FCPrimitives.space6)
                Text(String(localized: "archive.firstLaunch.note"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 0) {
                    FCListRowDivider()
                    FCHubRow(
                        icon: .symbol("person"),
                        title: String(localized: "archive.firstLaunch.coach.title"),
                        subtitle: .text(String(localized: "archive.firstLaunch.coach.subtitle")),
                        mode: .action(onChooseCoach)
                    )
                    .accessibilityIdentifier(FCAccessibilityID.firstLaunchCoach)
                    FCListRowDivider()
                    FCHubRow(
                        icon: .symbol("arrow.down.doc"),
                        title: String(localized: "archive.firstLaunch.import.title"),
                        subtitle: .text(String(localized: "archive.firstLaunch.import.subtitle")),
                        mode: .action(onChooseImport)
                    )
                    .accessibilityIdentifier(FCAccessibilityID.firstLaunchImport)
                    FCListRowDivider()
                }
                .padding(.top, FCPrimitives.space4)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, FCPrimitives.space4)
        }
        .background(FCSemanticColors.surfacePage)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.firstLaunchRoot)
    }
}
