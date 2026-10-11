import SwiftUI

@MainActor
final class StudentEditorViewModel: ObservableObject {
    @Published var draft: StudentDraft
    @Published var nameError: String?
    @Published var sexError: String?
    @Published var saveError: String?
    @Published var isSaving = false

    /// Loaded in edit mode; drives whether 归档学员 is offered.
    @Published var lifecycle: StudentLifecycle?

    let mode: StudentEditorMode
    let useCases: StudentUseCases

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
                lifecycle = student.lifecycle
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

    var editingStudentID: StableUUID? {
        if case .edit(let id) = mode {
            return StableUUID(id)
        }
        return nil
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

private enum StudentManagementCover: String, Identifiable {
    case archive
    case delete

    var id: String { rawValue }
}

/// 新建 / 编辑资料 (T069g; `27-edit-profile`): titleLarge, label–value rows
/// with inline fields, sex chips (all four M1A-FR-003 options — the artwork
/// draws only 男/女), pinned 保存. In edit mode a 管理 section carries
/// 归档学员 and 永久删除 (moved here from the detail page, D6); both open the
/// existing confirmation flows.
struct StudentEditorView: View {
    @ObservedObject var viewModel: StudentEditorViewModel
    @Binding var path: [RootDestination]
    var onFinished: (Student?) -> Void
    @State private var cover: StudentManagementCover?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FCPageHeader(title: viewModel.title, back: .init())
                    .padding(.bottom, FCPrimitives.space4)
                FCListRowDivider()

                fieldRow(
                    String(localized: "student.editor.nameLabel"),
                    placeholder: String(localized: "student.required"),
                    text: $viewModel.draft.displayName,
                    identifier: FCAccessibilityID.editorName
                )
                errorText(viewModel.nameError)
                FCListRowDivider()

                FCLabelValueRow(label: String(localized: "student.field.sex")) {
                    FCFlowLayout(horizontalSpacing: FCPrimitives.space2, verticalSpacing: FCPrimitives.space2 - (44 - 30)) {
                        ForEach([StudentSex.male, .female, .other, .undisclosed], id: \.self) { sex in
                            FCFilterChip(title: StudentSexPresentation.title(sex), isSelected: viewModel.draft.sex == sex) {
                                viewModel.draft.sex = sex
                                viewModel.sexError = nil
                            }
                            .accessibilityIdentifier(FCAccessibilityID.sexIdentifier(sex))
                        }
                    }
                }
                errorText(viewModel.sexError)
                FCListRowDivider()

                fieldRow(
                    String(localized: "student.field.trainingGoal"),
                    placeholder: String(localized: "student.optional"),
                    text: $viewModel.draft.trainingGoal,
                    identifier: FCAccessibilityID.editorGoal
                )
                FCListRowDivider()
                fieldRow(
                    String(localized: "student.field.phone"),
                    placeholder: String(localized: "student.optional"),
                    text: $viewModel.draft.phone,
                    identifier: FCAccessibilityID.editorPhone,
                    keyboard: .phonePad
                )
                FCListRowDivider()
                fieldRow(
                    String(localized: "student.field.wechat"),
                    placeholder: String(localized: "student.optional"),
                    text: $viewModel.draft.wechatID,
                    identifier: FCAccessibilityID.editorWechat
                )
                FCListRowDivider()
                fieldRow(
                    String(localized: "student.field.privateNote"),
                    placeholder: String(localized: "student.optional"),
                    text: $viewModel.draft.privateCoachNote,
                    identifier: FCAccessibilityID.editorPrivateNote,
                    multiline: true
                )
                FCListRowDivider()
                fieldRow(
                    String(localized: "student.field.injuryNotes"),
                    placeholder: String(localized: "student.optional"),
                    text: $viewModel.draft.injuryNotes,
                    identifier: FCAccessibilityID.editorInjuryNotes,
                    multiline: true
                )
                FCListRowDivider()

                Text(String(localized: "student.editor.contactHint"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .padding(.top, FCPrimitives.space3)

                errorText(viewModel.saveError)

                if viewModel.editingStudentID != nil {
                    managementSection
                }

                if viewModel.showsSkip {
                    FCLinkButton(title: String(localized: "student.editor.skip")) {
                        Task {
                            if await viewModel.skipFirstCreate() {
                                onFinished(nil)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, FCPrimitives.space4)
                    .accessibilityIdentifier(FCAccessibilityID.editorSkip)
                }
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .safeAreaInset(edge: .bottom) {
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
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.vertical, FCPrimitives.space2)
            .background(FCSemanticColors.surfacePage)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .task { await viewModel.loadIfNeeded() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.editorRoot)
        .fullScreenCover(item: $cover) { item in
            if let studentID = viewModel.editingStudentID {
                NavigationStack {
                    if item == .archive {
                        ArchiveStudentView(
                            studentID: studentID,
                            useCases: viewModel.useCases,
                            onCancel: { cover = nil },
                            onArchived: {
                                cover = nil
                                // Back to the detail page, which now shows the archived state.
                                if !path.isEmpty {
                                    path.removeLast()
                                }
                            }
                        )
                    } else {
                        DeleteStudentFlow(
                            studentID: studentID,
                            useCases: viewModel.useCases,
                            onFinish: { result in
                                cover = nil
                                switch result {
                                case .cancelled:
                                    break
                                case .deleted:
                                    path.removeAll()
                                case .backup:
                                    path.append(.backupRestore)
                                case .continueTraining:
                                    path.append(.activeSession(studentID.rawValue))
                                }
                            }
                        )
                    }
                }
                .fcPrivacyCovered()
            }
        }
    }

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FCSectionLabel(String(localized: "student.editor.management"))
                .padding(.top, FCPrimitives.space6)
                .padding(.bottom, FCPrimitives.space2)
            FCListRowDivider()
            if viewModel.lifecycle == .active {
                FCActionRow(
                    title: String(localized: "student.detail.archive"),
                    note: String(localized: "student.editor.archiveNote")
                ) {
                    cover = .archive
                }
                .accessibilityIdentifier(FCAccessibilityID.detailArchive)
                FCListRowDivider()
            }
            FCActionRow(
                title: String(localized: "student.detail.delete"),
                note: String(localized: "student.editor.deleteNote"),
                role: .destructive
            ) {
                cover = .delete
            }
            .accessibilityIdentifier(FCAccessibilityID.detailDelete)
            FCListRowDivider()
        }
    }

    @ViewBuilder
    private func errorText(_ message: String?) -> some View {
        if let message {
            Text(message)
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.statusDestructive)
                .padding(.bottom, FCPrimitives.space2)
        }
    }

    private func fieldRow(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        identifier: String,
        keyboard: UIKeyboardType = .default,
        multiline: Bool = false
    ) -> some View {
        FCLabelValueRow(label: label) {
            TextField(
                "",
                text: text,
                prompt: Text(placeholder).fcFont(.body),
                axis: multiline ? .vertical : .horizontal
            )
            .fcFont(.body)
            .foregroundStyle(FCSemanticColors.textPrimary)
            .keyboardType(keyboard)
            .textContentType(.none)
            .lineLimit(multiline ? 1...5 : 1...1)
            .accessibilityLabel(Text(label))
            .accessibilityIdentifier(identifier)
        }
    }
}
