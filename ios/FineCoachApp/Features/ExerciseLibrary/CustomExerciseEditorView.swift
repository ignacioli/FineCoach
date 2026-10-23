import Combine
import SwiftUI

@MainActor
final class CustomExerciseEditorViewModel: ObservableObject {
    @Published var name: String
    @Published var recordMode: RecordMode
    @Published var lifecycle: ExerciseLifecycle
    @Published var conflictMessage: String?
    @Published var errorMessage: String?
    @Published var isSaving = false

    let existingID: StableExerciseID?
    private let useCases: ExerciseLibraryUseCases

    init(useCases: ExerciseLibraryUseCases, existing: ExerciseCatalogItem?) {
        self.useCases = useCases
        self.existingID = existing?.id
        self.name = existing?.canonicalName.value ?? ""
        self.recordMode = existing?.recordMode ?? .weightReps
        self.lifecycle = existing?.lifecycle ?? .active
    }

    var isCreate: Bool { existingID == nil }

    var canArchive: Bool { existingID != nil && lifecycle == .active }

    var canRestore: Bool { existingID != nil && lifecycle == .archived }

    func save() async -> Bool {
        conflictMessage = nil
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = DomainError.emptyText.errorDescription
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            if let existingID {
                let updated = try await useCases.updateCustom(
                    id: existingID,
                    name: trimmed,
                    recordMode: recordMode
                )
                lifecycle = updated.lifecycle
                name = updated.canonicalName.value
            } else {
                _ = try await useCases.createCustom(name: trimmed, recordMode: recordMode)
            }
            return true
        } catch {
            present(error)
            return false
        }
    }

    func archive() async -> Bool {
        guard let existingID else {
            return false
        }
        conflictMessage = nil
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let archived = try await useCases.archiveCustom(id: existingID)
            lifecycle = archived.lifecycle
            return true
        } catch {
            present(error)
            return false
        }
    }

    func restore() async -> Bool {
        guard let existingID else {
            return false
        }
        conflictMessage = nil
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let restored = try await useCases.restoreCustom(id: existingID)
            lifecycle = restored.lifecycle
            name = restored.canonicalName.value
            recordMode = restored.recordMode
            return true
        } catch {
            present(error)
            return false
        }
    }

    private func present(_ error: Error) {
        if error as? DomainError == .conflict {
            conflictMessage = String(localized: "exercise.conflict")
            errorMessage = nil
            return
        }
        conflictMessage = nil
        errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
    }
}

struct CustomExerciseEditorView: View {
    @StateObject private var viewModel: CustomExerciseEditorViewModel
    var onFinished: () -> Void

    init(
        useCases: ExerciseLibraryUseCases,
        existing: ExerciseCatalogItem?,
        onFinished: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: CustomExerciseEditorViewModel(useCases: useCases, existing: existing)
        )
        self.onFinished = onFinished
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(
                    title: String(localized: "exercise.editor.title"),
                    back: .init(accessibilityIdentifier: FCAccessibilityID.customExerciseBack)
                )

                Text(String(localized: "exercise.editor.name"))
                    .fcFont(.headline)
                FCTextField(String(localized: "exercise.editor.name"), text: $viewModel.name)
                    .accessibilityIdentifier(FCAccessibilityID.customExerciseName)
                    .disabled(viewModel.lifecycle == .archived)

                HStack(spacing: FCPrimitives.space2) {
                    modeChip(
                        .weightReps,
                        title: String(localized: "session.mode.weightReps"),
                        id: FCAccessibilityID.customExerciseModeWeightReps
                    )
                }
                HStack(spacing: FCPrimitives.space2) {
                    modeChip(
                        .reps,
                        title: String(localized: "session.mode.reps"),
                        id: FCAccessibilityID.customExerciseModeReps
                    )
                    modeChip(
                        .duration,
                        title: String(localized: "session.mode.duration"),
                        id: FCAccessibilityID.customExerciseModeDuration
                    )
                }

                if let conflictMessage = viewModel.conflictMessage {
                    Text(conflictMessage)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                        .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryConflict)
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                }

                FCButton(
                    title: String(localized: "exercise.editor.save"),
                    isEnabled: viewModel.lifecycle == .active && !viewModel.isSaving
                ) {
                    Task {
                        if await viewModel.save() {
                            onFinished()
                        }
                    }
                }
                .accessibilityIdentifier(FCAccessibilityID.customExerciseSave)

                if viewModel.canArchive {
                    Button(String(localized: "exercise.editor.archive")) {
                        Task { _ = await viewModel.archive() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(FCSemanticColors.statusDestructive)
                    .accessibilityIdentifier(FCAccessibilityID.customExerciseArchive)
                    .accessibilityLabel(String(localized: "exercise.editor.archive"))
                }

                if viewModel.canRestore {
                    FCButton(
                        title: String(localized: "exercise.editor.restore"),
                        isEnabled: !viewModel.isSaving
                    ) {
                        Task { _ = await viewModel.restore() }
                    }
                    .accessibilityIdentifier(FCAccessibilityID.customExerciseRestore)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space4)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.customExerciseRoot)
    }

    private func modeChip(_ mode: RecordMode, title: String, id: String) -> some View {
        Button(title) {
            viewModel.recordMode = mode
        }
        .frame(minHeight: 44)
        .padding(.horizontal, FCPrimitives.space2)
        .background(
            viewModel.recordMode == mode ? FCSemanticColors.textPrimary : FCSemanticColors.surfaceDivider
        )
        .foregroundStyle(
            viewModel.recordMode == mode ? FCSemanticColors.surfaceElevated : FCSemanticColors.textPrimary
        )
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSm))
        .disabled(viewModel.lifecycle == .archived)
        .accessibilityIdentifier(id)
        .accessibilityLabel(title)
        .accessibilityAddTraits(viewModel.recordMode == mode ? [.isSelected] : [])
    }
}
