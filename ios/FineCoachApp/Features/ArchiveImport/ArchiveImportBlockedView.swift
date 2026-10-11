import SwiftUI

/// M2-09 导入被阻止 (T042, M2-FR-026/027): a Coach install was opened with an archive file.
/// The file is not read and the page offers no way to clear Coach data.
struct ArchiveImportBlockedView: View {
    let onDismiss: () -> Void

    private let steps = [
        String(localized: "archive.blocked.step1"),
        String(localized: "archive.blocked.step2"),
        String(localized: "archive.blocked.step3"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(
                    title: String(localized: "archive.blocked.title"),
                    back: .init(accessibilityIdentifier: FCAccessibilityID.archiveBlockedBack, handler: onDismiss)
                )
                FCStatusLabel(text: String(localized: "archive.blocked.status"), symbolName: "exclamationmark")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(localized: "archive.blocked.body"))
                    .fcFont(.body)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                FCSectionLabel(String(localized: "archive.blocked.section"))
                    .padding(.top, FCPrimitives.space2)
                VStack(spacing: 0) {
                    FCListRowDivider()
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        FCListRow(title: "\(index + 1)  \(step)", showsDisclosure: false)
                        FCListRowDivider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .archiveBottomButton {
            FCButton(title: String(localized: "archive.blocked.acknowledge"), action: onDismiss)
                .accessibilityIdentifier(FCAccessibilityID.archiveBlockedAcknowledge)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveBlockedRoot)
    }
}
