import SwiftUI

/// M2-10 档案已导入 (T043, M2-FR-029, D-007). The archive is already installed when this shows,
/// so 「开始查看」 and the back control both enter the viewer.
struct ArchiveImportSummaryView: View {
    let summary: ArchiveImportSummary
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(
                    title: String(localized: "archive.summary.title"),
                    subtitle: String(localized: "archive.summary.subtitle"),
                    back: .init(accessibilityIdentifier: FCAccessibilityID.archiveSummaryBack, handler: onStart)
                )
                VStack(spacing: 0) {
                    FCListRowDivider()
                    FCLabelValueRow(
                        label: String(localized: "archive.fact.source"),
                        value: ArchiveImportPresentation.sourceLine(summary.sourceLabel)
                    )
                    FCListRowDivider()
                    FCLabelValueRow(
                        label: String(localized: "archive.fact.snapshotTime"),
                        value: ArchiveImportPresentation.snapshotTime(summary.snapshotAtUTC)
                    )
                    FCListRowDivider()
                    FCLabelValueRow(
                        label: String(localized: "archive.fact.contents"),
                        value: ArchiveImportPresentation.contentSummary(summary.modules)
                    )
                    FCListRowDivider()
                }
                FCStatusLabel(
                    text: String(localized: "archive.summary.readonly"),
                    symbolName: "info",
                    badgeColor: FCSemanticColors.actionPrimary
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .archiveBottomButton {
            FCButton(title: String(localized: "archive.summary.start"), action: onStart)
                .accessibilityIdentifier(FCAccessibilityID.archiveSummaryStart)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage(swipeBackEnabled: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveSummaryRoot)
    }
}
