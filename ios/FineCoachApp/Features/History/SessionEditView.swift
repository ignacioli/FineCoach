import SwiftUI

@MainActor
final class SessionEditViewModel: ObservableObject {
    @Published var focus: Set<BodyPart> = []
    @Published var errorMessage: String?

    let sessionID: StableUUID
    private let useCases: HistoryUseCases

    init(sessionID: StableUUID, useCases: HistoryUseCases) {
        self.sessionID = sessionID
        self.useCases = useCases
    }

    func load() async {
        do {
            let completed = try await useCases.detail(sessionID: sessionID)
            focus = completed.trainingFocus
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }

    func save() async -> Bool {
        do {
            _ = try await useCases.saveFocusEdit(sessionID: sessionID, trainingFocus: focus)
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
            return false
        }
    }
}

struct SessionEditView: View {
    @StateObject private var viewModel: SessionEditViewModel
    @Binding var path: [RootDestination]

    init(sessionID: StableUUID, useCases: HistoryUseCases, path: Binding<[RootDestination]>) {
        _viewModel = StateObject(
            wrappedValue: SessionEditViewModel(sessionID: sessionID, useCases: useCases)
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(title: String(localized: "detail.edit"), back: .init())

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(FCSemanticColors.statusDestructive)
                }
                BodyPartMultiSelectView(title: String(localized: "summary.focus"), selection: $viewModel.focus)
                    .accessibilityIdentifier(FCAccessibilityID.sessionEditFocus)

                FCButton(title: String(localized: "sessionEdit.save")) {
                    Task {
                        guard await viewModel.save() else { return }
                        if !path.isEmpty {
                            path.removeLast()
                        }
                    }
                }
                .accessibilityIdentifier(FCAccessibilityID.sessionEditSave)
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space4)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .task { await viewModel.load() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.sessionEditRoot)
    }
}
