import SwiftUI
import UniformTypeIdentifiers

/// M2-08 导入档案 (T041): file row, masked password, 「导入」, and the failure result.
struct ArchiveImportView: View {
    @ObservedObject var model: ArchiveImportViewModel
    let onBack: () -> Void

    /// The archive file type; the replace page (M2-19) picks the same kind of file.
    static var archiveType: UTType {
        UTType("com.finecoach.archive") ?? .data
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(
                    title: String(localized: "archive.import.title"),
                    subtitle: String(localized: "archive.import.subtitle"),
                    back: .init(accessibilityIdentifier: FCAccessibilityID.archiveImportBack, handler: onBack)
                )
                VStack(spacing: 0) {
                    FCListRowDivider()
                    FCLabelValueRow(
                        label: String(localized: "archive.import.file.label"),
                        action: { model.isPickerPresented = true }
                    ) {
                        fileValue
                    }
                    .accessibilityIdentifier(FCAccessibilityID.archiveImportFile)
                    FCListRowDivider()
                }
                ArchivePasswordField(String(localized: "archive.import.password"), text: $model.password)
                    .accessibilityIdentifier(FCAccessibilityID.archiveImportPassword)
                FCButton(title: String(localized: "archive.import.submit"), isEnabled: model.canImport) {
                    Task { await model.submit() }
                }
                .accessibilityIdentifier(FCAccessibilityID.archiveImportSubmit)
                result
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .fileImporter(
            isPresented: $model.isPickerPresented,
            allowedContentTypes: [Self.archiveType],
            allowsMultipleSelection: false
        ) { model.fileChosen($0) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveImportRoot)
    }

    private var fileValue: some View {
        ArchiveImportFileValue(url: model.fileURL)
    }

    @ViewBuilder
    private var result: some View {
        if model.phase == .importing {
            HStack(spacing: FCPrimitives.space3) {
                ProgressView()
                Text(String(localized: "archive.import.importing"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(FCAccessibilityID.archiveImportProgress)
        } else if let failure = model.failure {
            FCInlineResult(
                .failure,
                title: String(localized: "archive.import.failure.title"),
                message: ArchiveImportPresentation.failureMessage(failure),
                retry: .init(
                    title: String(localized: "archive.import.retry"),
                    isEnabled: model.canImport,
                    accessibilityIdentifier: FCAccessibilityID.archiveImportRetry
                ) { Task { await model.submit() } },
                accessibilityIdentifier: FCAccessibilityID.archiveImportFailure
            )
        }
    }
}

/// The value side of the 「档案文件」 row (M2-08, M2-19b): the chosen file's display name, or the
/// 「未选择」 hint.
struct ArchiveImportFileValue: View {
    let url: URL?

    var body: some View {
        if let url {
            Text(ArchiveImportPresentation.fileDisplayName(url))
                .fcFont(.body)
                .foregroundStyle(FCSemanticColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(String(localized: "archive.import.file.none"))
                .fcFont(.body)
                .foregroundStyle(FCSemanticColors.textSecondary)
        }
    }
}
