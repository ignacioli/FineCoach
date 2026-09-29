import SwiftUI

/// 资料库 (D2, `19-resource-hub`): the coach's own material, not tied to a
/// student — 动作库, 训练模板. Reached from the 学员 title row (T069b); counts
/// added in T069c. 备份与恢复 moved to 设置 (D15, T079).
struct ResourceHubView: View {
    let exerciseUseCases: ExerciseLibraryUseCases
    let templateUseCases: TemplateUseCases
    @Binding var path: [RootDestination]
    @State private var exerciseSummary: String?
    @State private var templateSummary: String?

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
                        subtitle: exerciseSummary,
                        icon: FCEquipmentIconView(.barbell),
                        identifier: FCAccessibilityID.exerciseLibraryEntry
                    ) {
                        path.append(.exerciseLibrary)
                    }
                    FCListRowDivider()
                    hubRow(
                        title: String(localized: "resourceHub.templates"),
                        subtitle: templateSummary,
                        icon: hubSymbol("list.bullet.rectangle"),
                        identifier: FCAccessibilityID.templatesEntry
                    ) {
                        path.append(.templates)
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
        .task { await loadSummaries() }
    }

    private func loadSummaries() async {
        if let entries = try? await exerciseUseCases.search(query: "", includeHidden: true) {
            let custom = entries.filter { $0.item.kind == .custom }.count
            exerciseSummary = String(
                format: String(localized: "resourceHub.exerciseCountFormat"),
                entries.count - custom,
                custom
            )
        }
        if let templates = try? await templateUseCases.templates() {
            templateSummary = String(format: String(localized: "resourceHub.templateCountFormat"), templates.count)
        }
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
        subtitle: String?,
        icon: Icon,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: FCPrimitives.space4) {
                icon
                VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                    Text(title)
                        .fcFont(.headline)
                        .foregroundStyle(FCSemanticColors.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .fcFont(.caption)
                            .foregroundStyle(FCSemanticColors.textSecondary)
                    }
                }
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
