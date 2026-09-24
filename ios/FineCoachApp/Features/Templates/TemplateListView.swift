import SwiftUI

/// Cross-Student template list (T032, M1B-FR-017). Reusable across
/// Students -- there is deliberately no Student-scoping here, matching
/// `TrainingTemplate` having no Student identity field.
@MainActor
final class TemplateListViewModel: ObservableObject {
    @Published var templates: [TrainingTemplate] = []
    @Published var exerciseCounts: [StableUUID: Int] = [:]
    @Published var errorMessage: String?
    @Published var newTemplateName = ""

    private let useCases: TemplateUseCases

    init(useCases: TemplateUseCases) {
        self.useCases = useCases
    }

    func reload() async {
        do {
            let loaded = try await useCases.templates()
            templates = loaded
            var counts: [StableUUID: Int] = [:]
            for template in loaded {
                counts[template.id] = try await useCases.exercises(templateID: template.id).count
            }
            exerciseCounts = counts
            errorMessage = nil
        } catch {
            present(error)
        }
    }

    func createBlankTemplate() async -> StableUUID? {
        let name = newTemplateName
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        do {
            let created = try await useCases.createBlankTemplate(name: name)
            newTemplateName = ""
            await reload()
            return created.id
        } catch {
            present(error)
            return nil
        }
    }

    func deleteTemplate(_ id: StableUUID) async {
        do {
            try await useCases.deleteTemplate(id: id)
            await reload()
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "templates.error.generic")
    }
}

struct TemplateListView: View {
    @StateObject private var viewModel: TemplateListViewModel
    @Binding var path: [RootDestination]

    init(useCases: TemplateUseCases, path: Binding<[RootDestination]>) {
        _viewModel = StateObject(wrappedValue: TemplateListViewModel(useCases: useCases))
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(FCSemanticColors.destructive)
                }

                FCTextField(String(localized: "templates.newTemplateNamePrompt"), text: $viewModel.newTemplateName)
                    .accessibilityIdentifier(FCAccessibilityID.templateListAdd)

                FCButton(title: String(localized: "templates.newTemplate")) {
                    Task {
                        if let id = await viewModel.createBlankTemplate() {
                            path.append(.templateEditor(id.rawValue))
                        }
                    }
                }

                if viewModel.templates.isEmpty {
                    Text(String(localized: "templates.empty"))
                        .foregroundStyle(FCSemanticColors.secondaryText)
                } else {
                    ForEach(viewModel.templates) { template in
                        templateRow(template)
                    }
                }
            }
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "templates.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(FCAccessibilityID.templateListRoot)
        .task { await viewModel.reload() }
        .onChange(of: path) { _, _ in
            Task { await viewModel.reload() }
        }
    }

    private func templateRow(_ template: TrainingTemplate) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            Button {
                path.append(.templateEditor(template.id.rawValue))
            } label: {
                VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
                    Text(template.name.value)
                        .font(.headline)
                        .foregroundStyle(FCSemanticColors.primaryText)
                    if let focus = template.trainingFocus, !focus.isEmpty {
                        Text(focus.value)
                            .foregroundStyle(FCSemanticColors.secondaryText)
                    }
                    Text(
                        String(
                            format: String(localized: "templates.exerciseCount"),
                            viewModel.exerciseCounts[template.id] ?? 0
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(FCSemanticColors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(String(localized: "templates.delete")) {
                Task { await viewModel.deleteTemplate(template.id) }
            }
            .frame(minHeight: 44)
            .foregroundStyle(FCSemanticColors.destructive)
            .accessibilityIdentifier(FCAccessibilityID.templateListDelete)
        }
        .padding(FCPrimitives.spacingMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FCSemanticColors.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusMedium))
        .accessibilityIdentifier(FCAccessibilityID.templateRow(template.id))
    }
}
