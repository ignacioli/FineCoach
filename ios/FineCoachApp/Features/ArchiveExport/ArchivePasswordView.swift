import SwiftUI

/// M2-05 设置档案密码 (T033): two masked fields built with the shared `ArchivePasswordField`,
/// the rule text, and a failure result without retry when the entry is rejected (M2-FR-016,
/// M2-FR-018). Validation is the flow's (`submitPassword`); this view only shows its verdict.
/// The password is never logged, stored or put into a file name.
struct ArchivePasswordView: View {
    @ObservedObject var model: ArchiveExportViewModel

    var body: some View {
        ArchiveExportPage {
            FCPageHeader(
                title: String(localized: "archive.export.password.title"),
                subtitle: String(localized: "archive.export.password.subtitle")
            )
            VStack(spacing: FCPrimitives.space3) {
                ArchivePasswordField(String(localized: "archive.export.password.new"), text: $model.password)
                    .accessibilityIdentifier(FCAccessibilityID.archiveExportPassword)
                ArchivePasswordField(String(localized: "archive.export.password.confirm"), text: $model.confirmation)
                    .accessibilityIdentifier(FCAccessibilityID.archiveExportPasswordConfirm)
            }
            Text("archive.export.password.rule")
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let issue = model.passwordIssue {
                FCInlineResult(
                    .failure,
                    title: issue == .mismatch
                        ? String(localized: "archive.export.password.error.mismatch")
                        : String(localized: "archive.export.password.error.tooShort"),
                    message: String(localized: "archive.export.password.error.message"),
                    accessibilityIdentifier: FCAccessibilityID.archiveExportPasswordError
                )
            }
        }
        .archiveBottomButton {
            FCButton(title: String(localized: "archive.export.password.generate"), isEnabled: !model.isBusy) {
                Task { await model.submitPassword() }
            }
            .accessibilityIdentifier(FCAccessibilityID.archiveExportGenerate)
        }
    }
}
