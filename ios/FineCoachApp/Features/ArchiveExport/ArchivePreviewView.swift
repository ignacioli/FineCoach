import SwiftUI

/// M2-03 预览档案内容 (T031): renders the snapshot the archive will carry, one section per
/// selected module (M2-FR-008). Free text is shown verbatim, one entry per row, so the Coach can
/// check it item by item before continuing (M2-FR-012). The snapshot's identity and time fields
/// are placeholders and are never shown.
struct ArchivePreviewView: View {
    @ObservedObject var model: ArchiveExportViewModel

    var body: some View {
        ArchiveExportPage {
            FCPageHeader(
                title: String(localized: "archive.export.preview.title"),
                subtitle: String(localized: "archive.export.preview.subtitle")
            )
            if let preview = model.preview {
                sections(preview)
            }
            FCStatusLabel(
                text: String(localized: "archive.export.preview.freeTextNotice"),
                symbolName: "info",
                badgeColor: FCSemanticColors.actionPrimary
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(FCAccessibilityID.archiveExportFreeTextNotice)
        }
        .archiveBottomButton {
            FCButton(title: String(localized: "archive.export.preview.continue"), isEnabled: !model.isBusy) {
                Task { await model.confirmPreview() }
            }
            .accessibilityIdentifier(FCAccessibilityID.archiveExportContinue)
        }
    }

    @ViewBuilder
    private func sections(_ preview: ArchivePreviewModel) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space6) {
            if preview.showsBasicProfile {
                section(title: String(localized: "archive.export.group.basicProfile")) {
                    if let name = preview.displayName {
                        FCLabelValueRow(label: String(localized: "archive.export.item.displayName"), value: name)
                        FCListRowDivider()
                    }
                    if let sex = preview.sexTitle {
                        FCLabelValueRow(label: String(localized: "archive.export.item.sex"), value: sex)
                        FCListRowDivider()
                    }
                }
            }
            if preview.modules.trainingRecords {
                section(title: String(localized: "archive.export.item.trainingRecords")) {
                    if let range = preview.range {
                        FCLabelValueRow(label: String(localized: "archive.export.preview.range"), value: range)
                        FCListRowDivider()
                    }
                    FCLabelValueRow(
                        label: String(localized: "archive.export.preview.count"),
                        value: String(
                            format: String(localized: "archive.export.note.trainingRecords"),
                            preview.sessionCount
                        )
                    )
                    FCListRowDivider()
                    if !preview.modules.exerciseInfo {
                        Text("archive.export.preview.placeholderNames")
                            .fcFont(.caption)
                            .foregroundStyle(FCSemanticColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, FCPrimitives.space2)
                            .accessibilityIdentifier(FCAccessibilityID.archiveExportPlaceholderNote)
                    }
                }
            }
            if preview.modules.exerciseInfo {
                section(
                    title: String(
                        format: String(localized: "archive.export.preview.exerciseSection"),
                        preview.exerciseCount
                    )
                ) {
                    FCLabelValueRow(
                        label: String(localized: "archive.export.preview.builtInExercises"),
                        value: String(
                            format: String(localized: "archive.export.preview.builtInValue"),
                            preview.builtInExerciseCount
                        )
                    )
                    FCListRowDivider()
                    if !preview.customExercises.isEmpty {
                        FCSectionLabel(String(localized: "archive.export.preview.customNames"))
                            .padding(.top, FCPrimitives.space3)
                            .padding(.bottom, FCPrimitives.space2)
                        FCListRowDivider()
                        entries(preview.customExercises)
                    }
                }
            }
            if preview.modules.trends {
                section(title: String(localized: "archive.export.item.trends")) {
                    FCLabelValueRow(
                        label: String(localized: "archive.export.preview.trendsScope"),
                        value: String(localized: "archive.export.preview.trendsScopeValue")
                    )
                    FCListRowDivider()
                }
            }
            if preview.modules.summaries {
                section(
                    title: String(
                        format: String(localized: "archive.export.preview.summariesSection"),
                        preview.summaries.count
                    )
                ) {
                    entries(preview.summaries)
                }
            }
            if preview.modules.bodyData {
                section(title: String(localized: "archive.export.group.bodyData")) {
                    ForEach(preview.metrics) { metric in
                        if metric.isCustom {
                            FCListRow(title: metric.title, subtitle: metric.detail, showsDisclosure: false)
                        } else {
                            FCLabelValueRow(label: metric.title, value: metric.detail)
                        }
                        FCListRowDivider()
                    }
                }
            }
        }
    }

    /// Free-text entries, one row each, verbatim, not tappable.
    @ViewBuilder
    private func entries(_ entries: [ArchivePreviewModel.Entry]) -> some View {
        ForEach(entries) { entry in
            FCListRow(title: entry.text, subtitle: entry.meta, showsDisclosure: false)
            FCListRowDivider()
        }
    }

    private func section<Rows: View>(title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FCSectionLabel(title)
                .padding(.bottom, FCPrimitives.space2)
            FCListRowDivider()
            rows()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
