import SwiftUI

/// 「导入较新档案」 (M2-19a/b, T055): the form (file row, masked password, 「导入」), then the
/// facts of the installed and the new archive with 「替换为新档案」, or the failure result. Reached
/// from the viewer settings (M2-18) and from opening an archive file in viewer mode (D-010).
/// Leaving through any exit deletes the prefilled Inbox copy, if there is one.
struct ArchiveReplaceFlowView: View {
    @StateObject private var model: ArchiveReplaceViewModel
    /// Leave without replacing (back to where the page came from).
    let onBack: () -> Void
    /// The installed archive was replaced: the host reloads the viewer.
    let onReplaced: () -> Void

    init(
        useCases: ArchiveImportUseCases,
        prefilledURL: URL?,
        onBack: @escaping () -> Void,
        onReplaced: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: ArchiveReplaceViewModel(useCases: useCases, prefilledURL: prefilledURL))
        self.onBack = onBack
        self.onReplaced = onReplaced
    }

    var body: some View {
        Group {
            switch model.phase {
            case .confirm(let preview), .committing(let preview):
                ArchiveReplaceConfirmView(
                    preview: preview,
                    isCommitting: model.isBusy,
                    onBack: { Task { await model.backToForm() } },
                    onConfirm: { Task { await model.confirm() } }
                )
            case .form, .working, .rejected:
                ArchiveReplaceFormView(model: model, onBack: onBack)
            }
        }
        .onChange(of: model.replaced) { _, replaced in
            if replaced { onReplaced() }
        }
        .onDisappear {
            Task { await model.finish() }
        }
    }
}

/// M2-19b: the same file row, password and 「导入」 as M2-08, plus the failure result.
struct ArchiveReplaceFormView: View {
    @ObservedObject var model: ArchiveReplaceViewModel
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(
                    title: String(localized: "archive.replace.title"),
                    subtitle: String(localized: "archive.replace.subtitle"),
                    back: .init(accessibilityIdentifier: FCAccessibilityID.archiveReplaceBack, handler: onBack)
                )
                VStack(spacing: 0) {
                    FCListRowDivider()
                    FCLabelValueRow(
                        label: String(localized: "archive.import.file.label"),
                        action: { model.isPickerPresented = true }
                    ) {
                        ArchiveImportFileValue(url: model.fileURL)
                    }
                    .accessibilityIdentifier(FCAccessibilityID.archiveReplaceFile)
                    FCListRowDivider()
                }
                ArchivePasswordField(String(localized: "archive.import.password"), text: $model.password)
                    .accessibilityIdentifier(FCAccessibilityID.archiveReplacePassword)
                FCButton(title: String(localized: "archive.import.submit"), isEnabled: model.canImport) {
                    Task { await model.submit() }
                }
                .accessibilityIdentifier(FCAccessibilityID.archiveReplaceSubmit)
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
            allowedContentTypes: [ArchiveImportView.archiveType],
            allowsMultipleSelection: false
        ) { model.fileChosen($0) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveReplaceRoot)
    }

    @ViewBuilder
    private var result: some View {
        if model.phase == .working {
            HStack(spacing: FCPrimitives.space3) {
                ProgressView()
                Text(String(localized: "archive.import.importing"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(FCAccessibilityID.archiveReplaceProgress)
        } else if let failure = model.failure {
            FCInlineResult(
                .failure,
                title: String(localized: "archive.replace.failure.title"),
                message: ArchiveImportPresentation.replaceFailureMessage(failure),
                retry: .init(
                    title: String(localized: "archive.import.retry"),
                    isEnabled: model.canImport,
                    accessibilityIdentifier: FCAccessibilityID.archiveReplaceRetry
                ) { Task { await model.submit() } },
                accessibilityIdentifier: FCAccessibilityID.archiveReplaceFailure
            )
        }
    }
}

/// M2-19a: the installed archive and the new archive side by side, and the explicit
/// 「替换为新档案」 (M2-FR-038). Back returns to the form without changing anything.
struct ArchiveReplaceConfirmView: View {
    let preview: ArchiveReplacementPreview
    let isCommitting: Bool
    let onBack: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(
                    title: String(localized: "archive.replace.title"),
                    subtitle: String(localized: "archive.replace.subtitle"),
                    back: .init(accessibilityIdentifier: FCAccessibilityID.archiveReplaceConfirmBack, handler: onBack)
                )
                facts(section: String(localized: "archive.replace.section.current"), preview.current)
                facts(section: String(localized: "archive.replace.section.new"), preview.candidate)
                    .padding(.top, FCPrimitives.space2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .archiveBottomButton {
            FCButton(
                title: String(localized: "archive.replace.confirm"), isEnabled: !isCommitting, action: onConfirm
            )
            .accessibilityIdentifier(FCAccessibilityID.archiveReplaceConfirm)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage(swipeBackEnabled: !isCommitting)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveReplaceConfirmRoot)
    }

    private func facts(section: String, _ summary: ArchiveImportSummary) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            FCSectionLabel(section)
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
        }
    }
}
