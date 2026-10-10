import SwiftUI

/// The M2 export flow (M2-02 to M2-06) as ONE pushed destination (T035). The page shown is a
/// pure function of `ArchiveExportFlow.state`, so a page can never be reached out of order
/// (M2-FR-014). The flow is left in exactly one way: this view disappearing, by the system back
/// button, the swipe, 「完成」, or any programmatic pop. That calls `ArchiveExportFlow.leave()`,
/// which deletes the temporary archive (AC-005, M2-FR-023). No sheet or full-screen cover is
/// presented here; the system share panel is presented by `SystemShareAdapter`.
struct ArchiveExportFlowView: View {
    @StateObject private var model: ArchiveExportViewModel
    @Binding var path: [RootDestination]

    init(
        studentID: StableUUID,
        useCases: ArchiveExportUseCases,
        studentUseCases: StudentUseCases,
        path: Binding<[RootDestination]>
    ) {
        _model = StateObject(
            wrappedValue: ArchiveExportViewModel(
                studentID: studentID,
                useCases: useCases,
                studentUseCases: studentUseCases
            )
        )
        _path = path
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.actionFailed {
                FCInlineResult(
                    .failure,
                    title: String(localized: "archive.export.error.title"),
                    message: String(localized: "archive.export.error.message"),
                    accessibilityIdentifier: FCAccessibilityID.archiveExportActionError
                )
                .padding(.horizontal, FCPrimitives.space4)
                .padding(.top, FCPrimitives.space2)
            }
            content
        }
        .background(FCSemanticColors.surfacePage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .navigationBarBackButtonHidden(model.hidesSystemBack)
        .toolbar {
            if model.usesStepBack {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await model.stepBack() }
                    } label: {
                        FCSymbol(.back)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("archive.export.back"))
                    .accessibilityIdentifier(FCAccessibilityID.archiveExportBack)
                }
            }
        }
        .task { await model.start() }
        .onDisappear {
            Task { await model.leave() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveExportRoot)
    }

    @ViewBuilder
    private var content: some View {
        switch model.load {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ArchiveExportPage {
                FCPageHeader(title: String(localized: "archive.export.selection.title"))
                FCInlineResult(
                    .failure,
                    title: String(localized: "archive.export.error.title"),
                    message: String(localized: "archive.export.error.message"),
                    accessibilityIdentifier: FCAccessibilityID.archiveExportLoadError
                )
            }
        case .ready:
            page
        }
    }

    @ViewBuilder
    private var page: some View {
        switch model.state {
        case .selecting:
            ArchiveSelectionView(model: model)
        case .previewing:
            ArchivePreviewView(model: model)
        case .confirmingFacts:
            ArchiveDeliveryWarningView(model: model)
        case .settingPassword, .generating:
            ArchivePasswordView(model: model)
        case .generated, .handedToSystem, .cancelled, .failed:
            ArchiveDeliveryView(model: model, onFinish: finish)
        }
    }

    private func finish() {
        Task {
            await model.leave()
            path.popToStudentDetail()
        }
    }
}

/// The scrolling page body shared by M2-02 to M2-06: page margins `space.4`, content filling the
/// width. A pinned bottom button is added with `archiveBottomButton`.
struct ArchiveExportPage<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

extension View {
    /// Pins a full-width bottom action under the page (the page-bottom primary button).
    func archiveBottomButton<Button: View>(@ViewBuilder _ button: () -> Button) -> some View {
        safeAreaInset(edge: .bottom) {
            button()
                .padding(.horizontal, FCPrimitives.space4)
                .padding(.vertical, FCPrimitives.space2)
                .background(FCSemanticColors.surfacePage)
        }
    }
}
