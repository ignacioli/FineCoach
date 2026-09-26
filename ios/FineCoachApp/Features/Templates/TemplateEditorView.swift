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

    init(templateID: StableUUID, useCases: TemplateUseCases) {
        _viewModel = StateObject(wrappedValue: TemplateEditorViewModel(templateID: templateID, useCases: useCases))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(FCSemanticColors.destructive)
                }

                FCTextField(String(localized: "templateEditor.name"), text: $name)
                    .accessibilityIdentifier(FCAccessibilityID.templateEditorName)
                    .onChange(of: name) { _, newValue in
                        Task { await viewModel.rename(newValue) }
                    }
                BodyPartMultiSelectView(title: String(localized: "templateEditor.trainingFocus"), selection: $trainingFocus)
                    .onChange(of: trainingFocus) { _, newValue in
                        Task { await viewModel.updateTrainingFocus(newValue) }
                    }

                Divider()

                ForEach(viewModel.unsectionedExercises) { exercise in
                    exerciseRow(exercise)
                }

                ForEach(viewModel.orderedSections) { section in
                    sectionBlock(section)
                }

                Divider()

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
            }
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "templateEditor.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(FCAccessibilityID.templateEditorRoot)
        .task {
            await viewModel.reload()
            name = viewModel.template?.name.value ?? name
            trainingFocus = viewModel.template?.trainingFocus ?? []
        }
        .confirmationDialog(
            String(localized: "templateEditor.deleteSection"),
            isPresented: Binding(
                get: { viewModel.pendingSectionDeletion != nil },
                set: { if !$0 { viewModel.pendingSectionDeletion = nil } }
            ),
            presenting: viewModel.pendingSectionDeletion
        ) { section in
            Button(String(localized: "templateEditor.deleteSection.moveOut")) {
                Task { await viewModel.deleteSection(section, disposition: .moveExercisesTo(sectionID: nil)) }
            }
            Button(String(localized: "templateEditor.deleteSection.deleteExercises"), role: .destructive) {
                Task { await viewModel.deleteSection(section, disposition: .deleteWithExercises) }
            }
        }
    }

    private func exerciseRow(_ exercise: TemplateExercise) -> some View {
        HStack {
            Text(exercise.displayNameSnapshot.value)
                .foregroundStyle(FCSemanticColors.primaryText)
            Spacer()
            Menu(String(localized: "templateEditor.moveToUnsectioned")) {
                Button(String(localized: "templateEditor.unsectioned")) {
                    Task { await viewModel.moveExercise(exercise.id, toSectionID: nil) }
                }
                ForEach(viewModel.orderedSections) { section in
                    Button(section.name.value) {
                        Task { await viewModel.moveExercise(exercise.id, toSectionID: section.id) }
                    }
                }
            }
            .frame(minHeight: 44)
            Button(String(localized: "templateEditor.removeExercise")) {
                Task { await viewModel.removeExercise(exercise.id) }
            }
            .frame(minHeight: 44)
            .foregroundStyle(FCSemanticColors.destructive)
        }
        .padding(FCPrimitives.spacingSmall)
        .background(FCSemanticColors.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
        .accessibilityIdentifier(FCAccessibilityID.templateExerciseRow(exercise.id))
    }

    private func sectionBlock(_ section: SessionSection) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            HStack {
                Text(section.name.value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FCSemanticColors.secondaryText)
                Spacer()
                Button(String(localized: "templateEditor.deleteSection")) {
                    viewModel.requestDeleteSection(section)
                }
                .frame(minHeight: 44)
                .foregroundStyle(FCSemanticColors.destructive)
            }
            .accessibilityIdentifier(FCAccessibilityID.templateSectionRow(section.id))
            ForEach(viewModel.exercises(in: section)) { exercise in
                exerciseRow(exercise)
            }
        }
        .padding(FCPrimitives.spacingSmall)
        .background(FCSemanticColors.tint)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
    }
}
