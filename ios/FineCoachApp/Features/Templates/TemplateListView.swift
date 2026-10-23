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

/// 训练模板 (T069c; `05-training-template`): titleLarge + note, rows
/// (name, "训练重点 · 部位 · N 个动作" or "未设重点 · …", ›), pinned
/// "＋ 新建模板" which asks for the name in a bottom sheet. Deleting a
/// template now lives in the template editor.
struct TemplateListView: View {
    @StateObject private var viewModel: TemplateListViewModel
    @Binding var path: [RootDestination]
    @State private var isNamingNewTemplate = false

    init(useCases: TemplateUseCases, path: Binding<[RootDestination]>) {
        _viewModel = StateObject(wrappedValue: TemplateListViewModel(useCases: useCases))
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(title: String(localized: "templates.title"), back: .init())
                Text(String(localized: "templates.note"))
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                }

                if viewModel.templates.isEmpty {
                    Text(String(localized: "templates.empty"))
                        .fcFont(.callout, weight: .regular)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                } else {
                    VStack(spacing: FCPrimitives.space1) {
                        ForEach(viewModel.templates) { template in
                            templateRow(template)
                            FCListRowDivider()
                        }
                    }
                }
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .safeAreaInset(edge: .bottom) {
            FCButton(title: String(localized: "templates.newTemplateButton")) {
                isNamingNewTemplate = true
            }
            .accessibilityIdentifier(FCAccessibilityID.templateListAdd)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.vertical, FCPrimitives.space2)
            .background(FCSemanticColors.surfacePage)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.templateListRoot)
        .fcBottomSheet(isPresented: $isNamingNewTemplate) {
            FCBottomSheet(title: String(localized: "templates.newTemplate")) {
                VStack(spacing: FCPrimitives.space3) {
                    FCTextField(String(localized: "templates.newTemplateNamePrompt"), text: $viewModel.newTemplateName)
                    FCButton(
                        title: String(localized: "templates.create"),
                        isEnabled: !viewModel.newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        Task {
                            if let id = await viewModel.createBlankTemplate() {
                                isNamingNewTemplate = false
                                path.append(.templateEditor(id.rawValue))
                            }
                        }
                    }
                    .accessibilityIdentifier(FCAccessibilityID.templateListCreate)
                }
            }
        }
        .task { await viewModel.reload() }
        .onChange(of: path) { _, _ in
            Task { await viewModel.reload() }
        }
    }

    private func templateRow(_ template: TrainingTemplate) -> some View {
        Button {
            path.append(.templateEditor(template.id.rawValue))
        } label: {
            HStack(spacing: FCPrimitives.space2) {
                VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                    Text(template.name.value)
                        .fcFont(.headline)
                        .foregroundStyle(FCSemanticColors.textPrimary)
                    Text(
                        TemplateListPresentation.subtitle(
                            focus: template.trainingFocus,
                            exerciseCount: viewModel.exerciseCounts[template.id] ?? 0
                        )
                    )
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                }
                Spacer(minLength: FCPrimitives.space2)
                FCSymbol(.forward)
            }
            .padding(.vertical, FCPrimitives.space3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(FCAccessibilityID.templateRow(template.id))
    }
}

enum TemplateListPresentation {
    /// "训练重点 · 胸、肩 · 6 个动作" / "未设重点 · 4 个动作"
    static func subtitle(focus: Set<BodyPart>, exerciseCount: Int) -> String {
        let count = String(format: String(localized: "templates.exerciseCount"), exerciseCount)
        return "\(StudentListPresentation.focus(focus)) · \(count)"
    }
}

// MARK: - Template picker (add-exercise sheet)

/// Deep-copies a template onto the CURRENT in-progress Session (T032,
/// M1B-FR-019). Persists the Session write through
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

/// The 从模板 tab of the 添加动作 sheet (T069h, `31-add-exercise-sheet`, D8
/// variant B): template rows ("部位 · N 个动作") with an 应用 link. Applying
/// deep-copies onto the current session.
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
