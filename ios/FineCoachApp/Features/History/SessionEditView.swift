import SwiftUI

@MainActor
final class SessionEditViewModel: ObservableObject {
    @Published var focus = ""
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
            focus = completed.trainingFocus?.value ?? ""
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
            VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(FCSemanticColors.destructive)
                }
                Text(String(localized: "summary.focus"))
                    .font(.footnote)
                    .foregroundStyle(FCSemanticColors.secondaryText)
                TextField(String(localized: "summary.focus"), text: $viewModel.focus, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: 44)
                    .accessibilityLabel(Text(String(localized: "summary.focus")))
                    .accessibilityIdentifier(FCAccessibilityID.sessionEditFocus)

                FCButton(title: String(localized: "student.editor.save")) {
                    Task {
                        guard await viewModel.save() else { return }
                        if !path.isEmpty {
                            path.removeLast()
                        }
                    }
                }
                .accessibilityIdentifier(FCAccessibilityID.sessionEditSave)
            }
            .padding(FCPrimitives.spacingMedium)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FCSemanticColors.background)
        .navigationTitle(String(localized: "detail.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .accessibilityIdentifier(FCAccessibilityID.sessionEditRoot)
    }
}
