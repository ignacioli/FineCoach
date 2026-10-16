import SwiftUI

/// M2-18 查看模式设置 (T049): the three local display settings, each a label row with a segmented
/// switch, and the 「档案」 section. They change only how this device shows the archive, never
/// the archive (M2-FR-032). 「导入较新档案」 opens the replace page (M2-19, T055); 「删除本机档案」 is
/// a destructive row that asks for confirmation (M2-20, T058) and then removes the local archive.
struct ArchiveSettingsView: View {
    @ObservedObject var model: ArchiveViewerModel
    /// Open 「导入较新档案」.
    let onImportNewer: () -> Void
    /// The local archive is gone: the host recomputes the install state (M2-FR-050).
    let onDeleted: () -> Void
    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                FCPageHeader(
                    title: String(localized: "archive.settings.title"),
                    back: .init(accessibilityIdentifier: FCAccessibilityID.archiveSettingsBack)
                )
                FCSectionLabel(String(localized: "archive.settings.display"))
                    .padding(.top, FCPrimitives.space4)
                VStack(spacing: 0) {
                    FCListRowDivider()
                    switchRow(
                        label: String(localized: "archive.settings.weight"),
                        options: [("kg", "kg"), ("lb", "lb")],
                        selection: model.settings.weightUnit.rawValue,
                        identifier: FCAccessibilityID.archiveSettingsWeight
                    ) { raw in
                        model.update {
                            $0.weightUnit = ArchiveDisplaySettings.WeightUnit(rawValue: raw) ?? $0.weightUnit
                        }
                    }
                    FCListRowDivider()
                    switchRow(
                        label: String(localized: "archive.settings.length"),
                        options: [("cm", "cm"), ("in", "in")],
                        selection: model.settings.lengthUnit.rawValue,
                        identifier: FCAccessibilityID.archiveSettingsLength
                    ) { raw in
                        model.update {
                            $0.lengthUnit = ArchiveDisplaySettings.LengthUnit(rawValue: raw) ?? $0.lengthUnit
                        }
                    }
                    FCListRowDivider()
                    switchRow(
                        label: String(localized: "archive.settings.density"),
                        options: [
                            ("standard", String(localized: "archive.settings.density.standard")),
                            ("compact", String(localized: "archive.settings.density.compact")),
                        ],
                        selection: model.settings.density.rawValue,
                        identifier: FCAccessibilityID.archiveSettingsDensity
                    ) { raw in
                        model.update { $0.density = ArchiveDisplaySettings.Density(rawValue: raw) ?? $0.density }
                    }
                    FCListRowDivider()
                }
                Text(String(localized: "archive.settings.note"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if model.settingsSaveFailed {
                    FCInlineResult(
                        .failure,
                        title: String(localized: "archive.settings.saveFailed.title"),
                        message: String(localized: "archive.settings.saveFailed.message")
                    )
                }
                FCSectionLabel(String(localized: "archive.settings.archive"))
                    .padding(.top, FCPrimitives.space6)
                VStack(spacing: 0) {
                    FCListRowDivider()
                    FCActionRow(title: String(localized: "archive.settings.importNewer"), action: onImportNewer)
                        .accessibilityIdentifier(FCAccessibilityID.archiveSettingsImportNewer)
                    FCListRowDivider()
                    FCActionRow(
                        title: String(localized: "archive.settings.delete"), role: .destructive,
                        isEnabled: !model.isDeleting, showsTrashIcon: true
                    ) { isConfirmingDelete = true }
                    .accessibilityIdentifier(FCAccessibilityID.archiveSettingsDelete)
                    FCListRowDivider()
                }
                if model.deleteFailed {
                    FCInlineResult(
                        .failure,
                        title: String(localized: "archive.settings.deleteFailed.title"),
                        message: String(localized: "archive.settings.deleteFailed.message"),
                        retry: .init(
                            title: String(localized: "archive.import.retry"),
                            isEnabled: !model.isDeleting,
                            accessibilityIdentifier: FCAccessibilityID.archiveSettingsDeleteRetry
                        ) { deleteConfirmed() },
                        accessibilityIdentifier: FCAccessibilityID.archiveSettingsDeleteFailure
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveSettingsRoot)
        .fcConfirmationDialog(isPresented: $isConfirmingDelete) {
            FCConfirmationDialog(
                title: String(localized: "archive.settings.deleteConfirm.title"),
                message: String(localized: "archive.settings.deleteConfirm.message"),
                cancelAction: .init(title: String(localized: "archive.settings.deleteConfirm.cancel")) {
                    isConfirmingDelete = false
                },
                confirmAction: .init(
                    title: String(localized: "archive.settings.deleteConfirm.confirm"),
                    accessibilityIdentifier: FCAccessibilityID.archiveSettingsDeleteConfirm
                ) {
                    isConfirmingDelete = false
                    deleteConfirmed()
                }
            )
        }
    }

    private func deleteConfirmed() {
        Task {
            if await model.deleteArchive() {
                onDeleted()
            }
        }
    }

    private func switchRow(
        label: String, options: [(String, String)], selection: String, identifier: String,
        select: @escaping (String) -> Void
    ) -> some View {
        FCLabelValueRow(label: label) {
            FCSegmentedSwitch(
                options: options.map { .init(id: $0.0, title: $0.1) },
                selection: Binding(get: { selection }, set: select)
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
        }
    }
}
