import SwiftUI

/// The first-import flow: M2-08 -> M2-10, or M2-09 when a Coach install shows up meanwhile.
/// Hosted by `AppRoot` (from M2-07 or from a system open). Leaving through any exit deletes
/// the prefilled Inbox copy, if there is one (T044, D-010).
struct ArchiveImportFlowView: View {
    @StateObject private var model: ArchiveImportViewModel
    /// Leave without an archive (back to where the flow came from).
    let onBack: () -> Void
    /// The install state changed (an archive was imported or already existed): the host
    /// re-resolves it and shows the viewer.
    let onInstalled: () -> Void

    init(
        useCases: ArchiveImportUseCases,
        prefilledURL: URL?,
        onBack: @escaping () -> Void,
        onInstalled: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: ArchiveImportViewModel(useCases: useCases, prefilledURL: prefilledURL))
        self.onBack = onBack
        self.onInstalled = onInstalled
    }

    var body: some View {
        Group {
            switch model.outcome {
            case .imported(let summary):
                ArchiveImportSummaryView(summary: summary, onStart: onInstalled)
            case .blocked:
                ArchiveImportBlockedView(onDismiss: onBack)
            case .alreadyInstalled:
                Color.clear.onAppear(perform: onInstalled)
            case nil:
                ArchiveImportView(model: model) {
                    Task {
                        await model.finish()
                        onBack()
                    }
                }
            }
        }
        .onDisappear {
            Task { await model.finish() }
        }
    }
}
