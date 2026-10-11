import SwiftUI

/// The pages of viewer mode. Every destination only reads; there is no editing, adding,
/// sharing, exporting, backup, appointment or package destination (SC-005).
enum ArchiveViewerDestination: Hashable {
    case records
    case sessionDetail(String)
    case bodyData
    case metricHistory(String)
    case trends
    case settings
}

/// Viewer-mode root (M2-11 and its pages). It receives only the archive services, never the
/// Coach environment or any Coach use case (plan §5); it reads through `ArchiveViewerUseCases`.
struct ArchiveViewerRoot: View {
    @StateObject private var model: ArchiveViewerModel
    @State private var path: [ArchiveViewerDestination] = []

    init(services: ArchiveServices) {
        _model = StateObject(wrappedValue: ArchiveViewerModel(useCases: services.viewerUseCases))
    }

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: ArchiveViewerDestination.self) { destination in
                    page(destination)
                }
        }
        .background(FCSemanticColors.surfacePage)
        .task { await model.load() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveViewerRoot)
    }

    @ViewBuilder
    private var root: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(FCSemanticColors.surfacePage)
        case .unreadable:
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCInlineResult(
                    .failure,
                    title: String(localized: "archive.viewer.loadError.title"),
                    message: String(localized: "archive.viewer.loadError.message"),
                    retry: .init(title: String(localized: "archive.import.retry")) {
                        Task { await model.load() }
                    },
                    accessibilityIdentifier: FCAccessibilityID.archiveViewerLoadError
                )
                Spacer()
            }
            .padding(FCPrimitives.space4)
            .background(FCSemanticColors.surfacePage)
        case .loaded(let content):
            ArchiveHomeView(content: content) { path.append($0) }
        }
    }

    @ViewBuilder
    private func page(_ destination: ArchiveViewerDestination) -> some View {
        if case .loaded(let content) = model.phase {
            switch destination {
            case .records:
                ArchiveRecordsView(content: content, model: model) { path.append(.sessionDetail($0)) }
            case .sessionDetail(let key):
                ArchiveSessionDetailView(content: content, sessionKey: key, model: model)
            case .bodyData:
                ArchiveBodyDataView(content: content, model: model) { path.append(.metricHistory($0)) }
            case .metricHistory(let key):
                ArchiveMetricHistoryView(content: content, metricKey: key, model: model)
            case .trends:
                ArchiveTrendsView(content: content, model: model)
            case .settings:
                ArchiveSettingsView(model: model)
            }
        }
    }
}
