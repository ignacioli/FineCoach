import SwiftUI

struct InsightsListView: View {
    @StateObject private var model: InsightsViewModel
    @Binding var path: [RootDestination]

    init(
        useCases: InsightUseCases?, students: StudentUseCases,
        exercises: ExerciseLibraryUseCases?, history: HistoryUseCases?, path: Binding<[RootDestination]>
    ) {
        _model = StateObject(
            wrappedValue: InsightsViewModel(
                useCases: useCases, students: students, exercises: exercises, history: history))
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(title: String(localized: "insights.section.title"), back: .init())
                if let error = model.errorMessage {
                    Text(error).fcFont(.caption).foregroundStyle(FCSemanticColors.statusDestructive)
                }
                if model.insights.isEmpty {
                    Text(String(localized: "insights.list.empty"))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
                group(
                    title: String(localized: "insights.group.package"),
                    kinds: [.packageExhausted, .packageExpired, .packageLow])
                group(title: String(localized: "insights.group.inactive"), kinds: [.inactive])
                group(title: String(localized: "insights.group.stagnant"), kinds: [.stagnant])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityIdentifier(FCAccessibilityID.insightsRoot)
        .task { await model.reload() }
        .onChange(of: path) { _, _ in Task { await model.reload() } }
        .onReceive(NotificationCenter.default.publisher(for: InsightsViewModel.didSnooze)) { model.removeSnoozed($0) }
    }

    @ViewBuilder
    private func group(title: String, kinds: Set<Insight.Kind>) -> some View {
        let rows = model.insights.filter { kinds.contains($0.kind) }
        if !rows.isEmpty {
            InsightSectionView(model: model, title: title, rows: rows, context: .list, path: $path)
        }
    }
}
