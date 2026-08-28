import SwiftUI

@MainActor
final class StudentEditorViewModel: ObservableObject {
    @Published var draft: StudentDraft
    @Published var nameError: String?
    @Published var sexError: String?
    @Published var saveError: String?
    @Published var isSaving = false

    let mode: StudentEditorMode
    private let useCases: StudentUseCases

    init(mode: StudentEditorMode, useCases: StudentUseCases, existing: Student? = nil) {
        self.mode = mode
        self.useCases = useCases
        self.draft = existing?.draft ?? StudentDraft()
    }

    var title: String {
        switch mode {
        case .firstCreate:
            return String(localized: "student.editor.firstTitle")
        case .add:
            return String(localized: "student.editor.addTitle")
        case .edit:
            return String(localized: "student.editor.editTitle")
        }
    }

    var showsSkip: Bool {
        if case .firstCreate = mode {
            return true
        }
        return false
    }

    func loadIfNeeded() async {
        if case .edit(let id) = mode {
            do {
                let student = try await useCases.student(id: StableUUID(id))
                draft = student.draft
            } catch {
                saveError = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
            }
        }
    }

    func save() async -> Student? {
        nameError = nil
        sexError = nil
        saveError = nil
        if draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nameError = String(localized: "student.editor.nameRequired")
        }
        if draft.sex == nil {
            sexError = String(localized: "student.editor.sexRequired")
        }
        guard nameError == nil, sexError == nil else {
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            switch mode {
            case .firstCreate, .add:
                let student = try await useCases.create(draft: draft)
                if case .firstCreate = mode {
                    try await useCases.completeOnboarding()
                }
                return student
            case .edit(let id):
                return try await useCases.update(id: StableUUID(id), draft: draft)
            }
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
            return nil
        }
    }

    func skipFirstCreate() async -> Bool {
        do {
            try await useCases.completeOnboarding()
            return true
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
            return false
        }
    }
}

struct StudentEditorView: View {
    @ObservedObject var viewModel: StudentEditorViewModel
    @Binding var path: [RootDestination]
    var onFinished: (Student?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                Text(String(localized: "student.editor.kicker"))
                    .foregroundStyle(FCSemanticColors.secondaryText)
                fieldLabel(String(localized: "student.field.displayName"), required: true)
                FCTextField(String(localized: "student.field.displayName"), text: $viewModel.draft.displayName)
                    .accessibilityIdentifier(FCAccessibilityID.editorName)
                if let nameError = viewModel.nameError {
                    Text(nameError).foregroundStyle(FCSemanticColors.destructive)
                }
                Text(String(localized: "student.editor.duplicateHint"))
                    .font(.footnote)
                    .foregroundStyle(FCSemanticColors.secondaryText)

                Text(String(localized: "student.field.sex"))
                    .font(.headline)
                sexChips
                if let sexError = viewModel.sexError {
                    Text(sexError).foregroundStyle(FCSemanticColors.destructive)
                }

                fieldLabel(String(localized: "student.field.trainingGoal"), required: false)
                FCTextField(String(localized: "student.field.trainingGoal"), text: $viewModel.draft.trainingGoal)
                    .accessibilityIdentifier(FCAccessibilityID.editorGoal)

                fieldLabel(String(localized: "student.field.injuryNotes"), required: false)
                TextField(
                    String(localized: "student.field.injuryNotes"),
                    text: $viewModel.draft.injuryNotes,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .frame(minHeight: 44)
                .accessibilityIdentifier(FCAccessibilityID.editorInjuryNotes)
                .accessibilityLabel(String(localized: "student.field.injuryNotes"))

                fieldLabel(String(localized: "student.field.phone"), required: false)
                FCTextField(String(localized: "student.field.phone"), text: $viewModel.draft.phone)
                    .keyboardType(.phonePad)
                    .textContentType(.none)
                    .accessibilityIdentifier(FCAccessibilityID.editorPhone)
                fieldLabel(String(localized: "student.field.wechat"), required: false)
                FCTextField(String(localized: "student.field.wechat"), text: $viewModel.draft.wechatID)
                    .textContentType(.none)
                    .accessibilityIdentifier(FCAccessibilityID.editorWechat)
                Text(String(localized: "student.editor.contactHint"))
                    .font(.footnote)
                    .foregroundStyle(FCSemanticColors.secondaryText)

                fieldLabel(String(localized: "student.field.privateNote"), required: false)
                FCTextField(String(localized: "student.field.privateNote"), text: $viewModel.draft.privateCoachNote)
                    .accessibilityIdentifier(FCAccessibilityID.editorPrivateNote)

                if let saveError = viewModel.saveError {
                    Text(saveError).foregroundStyle(FCSemanticColors.destructive)
                }

                FCButton(
                    title: String(localized: "student.editor.save"),
                    isEnabled: !viewModel.isSaving
                ) {
                    Task {
                        if let student = await viewModel.save() {
                            onFinished(student)
                            if !path.isEmpty {
                                path.removeLast()
                            }
                        }
                    }
                }
                .accessibilityIdentifier(FCAccessibilityID.editorSave)

                if viewModel.showsSkip {
                    Button(String(localized: "student.editor.skip")) {
                        Task {
                            if await viewModel.skipFirstCreate() {
                                onFinished(nil)
                            }
                        }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(FCAccessibilityID.editorSkip)
                }
            }
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.background)
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadIfNeeded() }
        .accessibilityIdentifier(FCAccessibilityID.editorRoot)
    }

    private var sexChips: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            HStack(spacing: FCPrimitives.spacingSmall) {
                sexChip(.male)
                sexChip(.female)
            }
            HStack(spacing: FCPrimitives.spacingSmall) {
                sexChip(.other)
                sexChip(.undisclosed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sexChip(_ sex: StudentSex) -> some View {
        Button {
            viewModel.draft.sex = sex
            viewModel.sexError = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: StudentSexPresentation.symbolName(sex))
                Text(StudentSexPresentation.title(sex))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .background(
                viewModel.draft.sex == sex
                    ? FCSemanticColors.primaryText.opacity(0.12)
                    : FCSemanticColors.elevatedSurface
            )
            .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
        }
        .accessibilityIdentifier(FCAccessibilityID.sexIdentifier(sex))
        .accessibilityLabel(StudentSexPresentation.title(sex))
        .accessibilityAddTraits(viewModel.draft.sex == sex ? [.isSelected] : [])
    }

    private func fieldLabel(_ title: String, required: Bool) -> some View {
        HStack {
            Text(title).font(.headline)
            Text(required ? String(localized: "student.required") : String(localized: "student.optional"))
                .font(.footnote)
                .foregroundStyle(FCSemanticColors.secondaryText)
        }
    }
}
