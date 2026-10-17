import SwiftUI

/// Template detail/editor (T032, M1B-FR-017/018/020/021): rename, edit
/// training focus, add/remove planned Exercises, and manage Sections
/// (create/rename/delete-with-disposition, move Exercises between Sections
/// and the unsectioned sequence).
@MainActor
final class TemplateEditorViewModel: ObservableObject {
    @Published var template: TrainingTemplate?
    @Published var exercises: [TemplateExercise] = []
    @Published var sections: [SessionSection] = []
    @Published var errorMessage: String?
    @Published var newExerciseName = ""
    @Published var newSectionName = ""
    @Published var pendingSectionDeletion: SessionSection?

    let templateID: StableUUID
    private let useCases: TemplateUseCases

    init(templateID: StableUUID, useCases: TemplateUseCases) {
        self.templateID = templateID
        self.useCases = useCases
    }

    /// Unsectioned exercises + sections, both sorted by the unified
    /// orderIndex axis (data-model §2.6/§2.7).
    var unsectionedExercises: [TemplateExercise] {
        exercises.filter { $0.sectionID == nil }.sorted { $0.orderIndex < $1.orderIndex }
    }

    func exercises(in section: SessionSection) -> [TemplateExercise] {
        exercises.filter { $0.sectionID == section.id }.sorted { $0.orderIndex < $1.orderIndex }
    }

    var orderedSections: [SessionSection] {
        sections.sorted { $0.orderIndex < $1.orderIndex }
    }

    func reload() async {
        do {
            template = try await useCases.template(id: templateID)
            exercises = try await useCases.exercises(templateID: templateID)
            sections = try await useCases.sections(templateID: templateID)
            errorMessage = nil
        } catch {
            present(error)
        }
    }

    /// T069c moved 删除模板 here from the list (05 artwork has no inline
    /// delete); guarded by an FCConfirmationDialog in the view.
    func deleteTemplate() async -> Bool {
        do {
            try await useCases.deleteTemplate(id: templateID)
            return true
        } catch {
            present(error)
            return false
        }
    }

    func rename(_ name: String) async {
        do {
            template = try await useCases.renameTemplate(id: templateID, name: name)
        } catch {
            present(error)
        }
    }

    func updateTrainingFocus(_ value: Set<BodyPart>) async {
        do {
            template = try await useCases.updateTrainingFocus(
                id: templateID,
                trainingFocus: value
            )
        } catch {
            present(error)
        }
    }

    func addExercise() async {
        let name = newExerciseName
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        do {
            exercises = try await useCases.addExercise(
                templateID: templateID,
                displayName: name,
                recordMode: .weightReps
            )
            newExerciseName = ""
        } catch {
            present(error)
        }
    }

    func removeExercise(_ id: StableUUID) async {
        do {
            exercises = try await useCases.removeExercise(templateID: templateID, exerciseID: id)
        } catch {
            present(error)
        }
    }

    func moveExercise(_ id: StableUUID, toSectionID sectionID: StableUUID?) async {
        do {
            exercises = try await useCases.moveExercise(
                templateID: templateID,
                exerciseID: id,
                toSectionID: sectionID
            )
        } catch {
            present(error)
        }
    }

    func createSection() async {
        let name = newSectionName
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        do {
            _ = try await useCases.createSection(templateID: templateID, name: name)
            newSectionName = ""
            await reload()
        } catch {
            present(error)
        }
    }

    /// Non-empty Sections MUST require an explicit disposition
    /// (M1B-FR-020/021) -- the UI routes through `pendingSectionDeletion` so
    /// there is no direct "delete" button that skips the choice.
    func requestDeleteSection(_ section: SessionSection) {
        if exercises(in: section).isEmpty {
            Task { await deleteSection(section, disposition: .deleteWithExercises) }
            return
        }
        pendingSectionDeletion = section
    }

    func deleteSection(_ section: SessionSection, disposition: SessionSectionDeletionDisposition) async {
        do {
            try await useCases.deleteSection(templateID: templateID, sectionID: section.id, disposition: disposition)
            pendingSectionDeletion = nil
            await reload()
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "templates.error.generic")
    }
}

struct TemplateEditorView: View {
    @StateObject private var viewModel: TemplateEditorViewModel
    @State private var name = ""
    @State private var trainingFocus: Set<BodyPart> = []

    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false

    init(templateID: StableUUID, useCases: TemplateUseCases) {
        _viewModel = StateObject(wrappedValue: TemplateEditorViewModel(templateID: templateID, useCases: useCases))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(FCSemanticColors.statusDestructive)
                }

                FCTextField(String(localized: "templateEditor.name"), text: $name)
                    .accessibilityIdentifier(FCAccessibilityID.templateEditorName)
                    .onChange(of: name) { _, newValue in
                        Task { await viewModel.rename(newValue) }
                    }
                BodyPartMultiSelectView(
                    title: String(localized: "templateEditor.trainingFocus"),
                    selection: $trainingFocus,
                    chipAccessibilityIdentifier: FCAccessibilityID.templateEditorTrainingFocus
                )
                .onChange(of: trainingFocus) { _, newValue in
                    Task { await viewModel.updateTrainingFocus(newValue) }
                }

                FCListRowDivider()

                ForEach(viewModel.unsectionedExercises) { exercise in
                    exerciseRow(exercise)
                }

                ForEach(viewModel.orderedSections) { section in
                    sectionBlock(section)
                }

                FCListRowDivider()

                FCTextField(String(localized: "templateEditor.exerciseNamePrompt"), text: $viewModel.newExerciseName)
                FCButton(title: String(localized: "templateEditor.addExercise")) {
                    Task { await viewModel.addExercise() }
                }
                .accessibilityIdentifier(FCAccessibilityID.templateEditorAddExercise)

                FCTextField(String(localized: "templateEditor.sectionNamePrompt"), text: $viewModel.newSectionName)
                    .accessibilityIdentifier(FCAccessibilityID.templateEditorSectionName)
                FCButton(title: String(localized: "templateEditor.createSection")) {
                    Task { await viewModel.createSection() }
                }
                .accessibilityIdentifier(FCAccessibilityID.templateEditorCreateSection)

                FCListRowDivider()
                FCActionRow(title: String(localized: "templateEditor.deleteTemplate"), role: .destructive) {
                    isConfirmingDelete = true
                }
                .accessibilityIdentifier(FCAccessibilityID.templateListDelete)
            }
            .padding(FCPrimitives.space4)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "templateEditor.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.templateEditorRoot)
        .fcConfirmationDialog(isPresented: $isConfirmingDelete) {
            FCConfirmationDialog(
                title: String(localized: "templateEditor.deleteTemplate.title"),
                message: String(localized: "templateEditor.deleteTemplate.message"),
                cancelAction: .init(title: String(localized: "templateEditor.deleteTemplate.keep")) {
                    isConfirmingDelete = false
                },
                confirmAction: .init(
                    title: String(localized: "templateEditor.deleteTemplate.confirm"),
                    accessibilityIdentifier: FCAccessibilityID.templateEditorDeleteConfirm
                ) {
                    isConfirmingDelete = false
                    Task {
                        if await viewModel.deleteTemplate() {
                            dismiss()
                        }
                    }
                }
            )
        }
        .task {
            await viewModel.reload()
            name = viewModel.template?.name.value ?? name
            trainingFocus = viewModel.template?.trainingFocus ?? []
        }
        .fcConfirmationDialog(
            isPresented: Binding(
                get: { viewModel.pendingSectionDeletion != nil },
                set: { if !$0 { viewModel.pendingSectionDeletion = nil } }
            )
        ) {
            if let section = viewModel.pendingSectionDeletion {
                FCConfirmationDialog(
                    title: String(format: String(localized: "section.delete.title"), section.name.value),
                    message: String(
                        format: String(localized: "section.delete.message"),
                        viewModel.exercises(in: section).count
                    ),
                    cancelAction: .init(title: String(localized: "section.delete.cancel")) {
                        viewModel.pendingSectionDeletion = nil
                    },
                    confirmAction: .init(
                        title: String(localized: "templateEditor.deleteSection"),
                        accessibilityIdentifier: FCAccessibilityID.templateEditorDeleteSectionMoveOut
                    ) {
                        Task { await viewModel.deleteSection(section, disposition: .moveExercisesTo(sectionID: nil)) }
                    }
                )
            }
        }
    }

    private func exerciseRow(_ exercise: TemplateExercise) -> some View {
        HStack {
            Text(exercise.displayNameSnapshot.value)
                .foregroundStyle(FCSemanticColors.textPrimary)
            Spacer()
            Menu(String(localized: "templateEditor.moveToUnsectioned")) {
                Button(String(localized: "templateEditor.unsectioned")) {
                    Task { await viewModel.moveExercise(exercise.id, toSectionID: nil) }
                }
                .accessibilityIdentifier(FCAccessibilityID.templateEditorMoveToUnsectioned)
                ForEach(viewModel.orderedSections) { section in
                    Button(section.name.value) {
                        Task { await viewModel.moveExercise(exercise.id, toSectionID: section.id) }
                    }
                    .accessibilityIdentifier(FCAccessibilityID.templateEditorMoveToSection(section.id))
                }
            }
            .frame(minHeight: 44)
            Button(String(localized: "templateEditor.removeExercise")) {
                Task { await viewModel.removeExercise(exercise.id) }
            }
            .frame(minHeight: 44)
            .foregroundStyle(FCSemanticColors.statusDestructive)
            .accessibilityIdentifier(FCAccessibilityID.templateEditorRemoveExercise(exercise.id))
        }
        .padding(FCPrimitives.space2)
        .background(FCSemanticColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSm))
        .accessibilityIdentifier(FCAccessibilityID.templateExerciseRow(exercise.id))
    }

    private func sectionBlock(_ section: SessionSection) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            HStack {
                Text(section.name.value)
                    .fcFont(.sectionLabel)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                Spacer()
                Button(String(localized: "templateEditor.deleteSection")) {
                    viewModel.requestDeleteSection(section)
                }
                .frame(minHeight: 44)
                .foregroundStyle(FCSemanticColors.statusDestructive)
                .accessibilityIdentifier(FCAccessibilityID.templateEditorDeleteSection(section.id))
            }
            .accessibilityIdentifier(FCAccessibilityID.templateSectionRow(section.id))
            ForEach(viewModel.exercises(in: section)) { exercise in
                exerciseRow(exercise)
            }
        }
        .padding(FCPrimitives.space2)
        .background(FCSemanticColors.surfaceSelected)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSm))
    }
}
