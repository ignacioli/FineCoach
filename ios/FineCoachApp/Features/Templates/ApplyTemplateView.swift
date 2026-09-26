import SwiftUI

/// Picks a template and deep-copies it onto the CURRENT in-progress Session
/// (T032, M1B-FR-019). Persists the Session write through
/// `ActiveSessionUseCases.applyTemplate` (crash-recovery safe) and then the
/// new Sections through `TemplateUseCases.persistAppliedSections`.
@MainActor
final class ApplyTemplateViewModel: ObservableObject {
    @Published var templates: [TrainingTemplate] = []
    @Published var errorMessage: String?
    @Published var didApply = false

    private let templateUseCases: TemplateUseCases
    private let sessionUseCases: ActiveSessionUseCases

    init(templateUseCases: TemplateUseCases, sessionUseCases: ActiveSessionUseCases) {
        self.templateUseCases = templateUseCases
        self.sessionUseCases = sessionUseCases
    }

    func reload() async {
        do {
            templates = try await templateUseCases.templates()
            errorMessage = nil
        } catch {
            present(error)
        }
    }

    func apply(_ template: TrainingTemplate) async {
        do {
            guard let current = try await sessionUseCases.loadActive() else {
                throw DomainError.notFound
            }
            let snapshot = try await templateUseCases.loadApplicationSnapshot(templateID: template.id)
            let existingSessionSections = try await templateUseCases.sessionSections(sessionID: current.id)
            let result = try await sessionUseCases.applyTemplate(
                templateExercises: snapshot.exercises,
                templateSections: snapshot.sections,
                templateTrainingFocus: template.trainingFocus,
                existingSessionSections: existingSessionSections
            )
            try await templateUseCases.persistAppliedSections(result.newSections)
            didApply = true
            errorMessage = nil
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "templates.error.generic")
    }
}

struct ApplyTemplateView: View {
    @StateObject private var viewModel: ApplyTemplateViewModel
    @Binding var path: [RootDestination]

    init(templateUseCases: TemplateUseCases, sessionUseCases: ActiveSessionUseCases, path: Binding<[RootDestination]>) {
        _viewModel = StateObject(
            wrappedValue: ApplyTemplateViewModel(templateUseCases: templateUseCases, sessionUseCases: sessionUseCases)
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(FCSemanticColors.destructive)
                }
                if viewModel.templates.isEmpty {
                    Text(String(localized: "applyTemplate.empty"))
                        .foregroundStyle(FCSemanticColors.secondaryText)
                } else {
                    ForEach(viewModel.templates) { template in
                        Button {
                            Task {
                                await viewModel.apply(template)
                                if viewModel.didApply {
                                    path.removeLast()
                                }
                            }
                        } label: {
                            Text(template.name.value)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(FCAccessibilityID.applyTemplateRow(template.id))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "applyTemplate.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(FCAccessibilityID.applyTemplateRoot)
        .task { await viewModel.reload() }
    }
}
