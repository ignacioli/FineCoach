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
                FCPageHeader(title: String(localized: "resourceHub.title"), back: .init())

                VStack(spacing: 0) {
                    FCListRowDivider()
                    FCHubRow(
                        icon: .equipment(.barbell),
                        title: String(localized: "exercise.library.entry"),
                        subtitle: exerciseSummary.map { .text($0) },
                        mode: .action { path.append(.exerciseLibrary) }
                    )
                    .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryEntry)
                    FCListRowDivider()
                    FCHubRow(
                        icon: .symbol("list.bullet.rectangle"),
                        title: String(localized: "resourceHub.templates"),
                        subtitle: templateSummary.map { .text($0) },
                        mode: .action { path.append(.templates) }
                    )
                    .accessibilityIdentifier(FCAccessibilityID.templatesEntry)
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
        .fcSecondaryPage()
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
}
