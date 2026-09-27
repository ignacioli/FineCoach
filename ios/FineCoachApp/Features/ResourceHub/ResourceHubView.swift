import SwiftUI

/// 资料库 (D2, `19-resource-hub`): the coach's own material, not tied to a
/// student — 动作库, 训练模板, 备份与恢复. Reached from the 学员 title row
/// (T069b); T069c adds the per-row counts and restyles the pages behind it.
struct ResourceHubView: View {
    @Binding var path: [RootDestination]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                Text(String(localized: "resourceHub.title"))
                    .fcFont(.titleLarge)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 0) {
                    FCListRowDivider()
                    hubRow(
                        title: String(localized: "exercise.library.entry"),
                        icon: FCEquipmentIconView(.barbell),
                        identifier: FCAccessibilityID.exerciseLibraryEntry
                    ) {
                        path.append(.exerciseLibrary)
                    }
                    FCListRowDivider()
                    hubRow(
                        title: String(localized: "resourceHub.templates"),
                        icon: hubSymbol("list.bullet.rectangle"),
                        identifier: FCAccessibilityID.templatesEntry
                    ) {
                        path.append(.templates)
                    }
                    FCListRowDivider()
                    hubRow(
                        title: String(localized: "backup.title"),
                        icon: hubSymbol("externaldrive"),
                        identifier: FCAccessibilityID.resourceHubBackup
                    ) {
                        path.append(.backupRestore)
                    }
                    FCListRowDivider()
                }

                Text(String(localized: "resourceHub.note"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
    }

    private func hubSymbol(_ name: String) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .foregroundStyle(FCSemanticColors.actionPrimary)
            .accessibilityHidden(true)
    }

    private func hubRow<Icon: View>(
        title: String,
        icon: Icon,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: FCPrimitives.space4) {
                icon
                Text(title)
                    .fcFont(.headline)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                Spacer(minLength: FCPrimitives.space2)
                FCSymbol(.forward)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
