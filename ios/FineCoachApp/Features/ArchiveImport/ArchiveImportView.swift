import SwiftUI
import UniformTypeIdentifiers

/// M2-08 导入档案 (T041): file row, masked password, 「导入」, and the failure result.
struct ArchiveImportView: View {
    @ObservedObject var model: ArchiveImportViewModel
    let onBack: () -> Void

    private static var archiveType: UTType {
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

    @ViewBuilder
    private var fileValue: some View {
        if let url = model.fileURL {
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

/// Placeholder for 「导入较新档案」 reached by opening an archive file in viewer mode (D-010).
/// US-3 (T055) replaces it; until then it only says so and ends the flow, deleting the Inbox
/// copy. It reads nothing from the file.
struct ArchiveReplacePlaceholderView: View {
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(
                    title: String(localized: "archive.replace.title"),
                    subtitle: String(localized: "archive.replace.subtitle"),
                    back: .init(accessibilityIdentifier: FCAccessibilityID.archiveImportBack, handler: onBack)
                )
                FCStatusLabel(
                    text: String(localized: "archive.replace.unavailable"),
                    symbolName: "info",
                    badgeColor: FCSemanticColors.actionPrimary
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveImportReplacePlaceholder)
    }
}
