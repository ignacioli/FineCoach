import SwiftUI

/// Picks a template and deep-copies it onto the CURRENT in-progress Session
/// (T032, M1B-FR-019). Persists the Session write through
/// `ActiveSessionUseCases.applyTemplate` (crash-recovery safe) and then the
/// new Sections through `TemplateUseCases.persistAppliedSections`.
@MainActor
final class ApplyTemplateViewModel: ObservableObject {
    @Published var templates: [TrainingTemplate] = []
    @Published var exerciseCounts: [StableUUID: Int] = [:]
    @Published var errorMessage: String?
    @Published var didApply = false

    private let templateUseCases: TemplateUseCases
    private let sessionUseCases: ActiveSessionUseCases
    private let sessionID: StableUUID?

    init(
        templateUseCases: TemplateUseCases,
        sessionUseCases: ActiveSessionUseCases,
        sessionID: StableUUID? = nil
    ) {
        self.templateUseCases = templateUseCases
        self.sessionUseCases = sessionUseCases
        self.sessionID = sessionID
    }

    func reload() async {
        do {
            templates = try await templateUseCases.templates()
            var counts: [StableUUID: Int] = [:]
            for template in templates {
                counts[template.id] = try await templateUseCases.exercises(templateID: template.id).count
            }
            exerciseCounts = counts
            errorMessage = nil
        } catch {
            present(error)
        }
    }

    func apply(_ template: TrainingTemplate) async {
        do {
            let current: Session?
            if let sessionID {
                current = try await sessionUseCases.loadActive(sessionID: sessionID)
            } else {
                current = try await sessionUseCases.loadActive()
            }
            guard let current else {
                throw DomainError.notFound
            }
            let snapshot = try await templateUseCases.loadApplicationSnapshot(templateID: template.id)
            let existingSessionSections = try await templateUseCases.sessionSections(sessionID: current.id)
            let result = try await sessionUseCases.applyTemplate(
                sessionID: current.id,
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

    init(
        templateUseCases: TemplateUseCases,
        sessionUseCases: ActiveSessionUseCases,
        sessionID: StableUUID? = nil,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: ApplyTemplateViewModel(
                templateUseCases: templateUseCases,
                sessionUseCases: sessionUseCases,
                sessionID: sessionID
            )
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(FCSemanticColors.statusDestructive)
                }
                if viewModel.templates.isEmpty {
                    Text(String(localized: "applyTemplate.empty"))
                        .foregroundStyle(FCSemanticColors.textSecondary)
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
            .padding(FCPrimitives.space4)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "applyTemplate.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.applyTemplateRoot)
        .task { await viewModel.reload() }
    }
}

/// The 从模板 tab of the 添加动作 sheet (T069h, `31-add-exercise-sheet`, D8
/// variant B): template rows ("部位 · N 个动作") with an 应用 link. Applying
/// deep-copies onto the current session exactly like the old 应用模板 page.
struct TemplatePickList: View {
    @StateObject private var viewModel: ApplyTemplateViewModel
    private let onApplied: () -> Void

    init(
        templateUseCases: TemplateUseCases,
        sessionUseCases: ActiveSessionUseCases,
        sessionID: StableUUID? = nil,
        onApplied: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: ApplyTemplateViewModel(
                templateUseCases: templateUseCases,
                sessionUseCases: sessionUseCases,
                sessionID: sessionID
            )
        )
        self.onApplied = onApplied
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.statusDestructive)
                    .padding(.bottom, FCPrimitives.space2)
            }
            FCListRowDivider()
            if viewModel.templates.isEmpty {
                Text(String(localized: "applyTemplate.empty"))
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .padding(.vertical, FCPrimitives.space3)
            }
            ForEach(viewModel.templates) { template in
                HStack(spacing: FCPrimitives.space2) {
                    VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                        Text(template.name.value)
                            .fcFont(.headline)
                            .foregroundStyle(FCSemanticColors.textPrimary)
                        Text(subtitle(template))
                            .fcFont(.caption)
                            .foregroundStyle(FCSemanticColors.textSecondary)
                    }
                    Spacer(minLength: FCPrimitives.space2)
                    FCLinkButton(title: String(localized: "applyTemplate.apply")) {
                        Task {
                            await viewModel.apply(template)
                            if viewModel.didApply {
                                onApplied()
                            }
                        }
                    }
                    .accessibilityLabel(Text("\(String(localized: "applyTemplate.apply")) \(template.name.value)"))
                    .accessibilityIdentifier(FCAccessibilityID.applyTemplateRow(template.id))
                }
                .padding(.vertical, FCPrimitives.space3)
                FCListRowDivider()
            }
            Text(String(localized: "applyTemplate.note"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .padding(.top, FCPrimitives.space3)
        }
        .task { await viewModel.reload() }
    }

    private func subtitle(_ template: TrainingTemplate) -> String {
        let count = String(
            format: String(localized: "templates.exerciseCount"), viewModel.exerciseCounts[template.id] ?? 0)
        guard let parts = BodyPart.joinedDisplayNames(for: template.trainingFocus, separator: "、") else {
            return count
        }
        return "\(parts) · \(count)"
    }
}
