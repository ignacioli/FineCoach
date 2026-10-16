import SwiftUI

@MainActor
final class SessionSummaryViewModel: ObservableObject {
    @Published var focus: Set<BodyPart> = []
    @Published var privateNote = ""
    @Published var studentSummary = ""
    @Published var durationText = ""
    @Published var completedSetsText = ""
    @Published var errorMessage: String?
    @Published var templateName = ""
    @Published var savedTemplateName: String?

    let sessionID: StableUUID
    private let useCases: HistoryUseCases
    let templateUseCases: TemplateUseCases?

    init(sessionID: StableUUID, useCases: HistoryUseCases, templateUseCases: TemplateUseCases? = nil) {
        self.sessionID = sessionID
        self.useCases = useCases
        self.templateUseCases = templateUseCases
    }

    /// 另存为模板 (M1B-FR-017/018), moved here from the in-training screen by
    /// D8 variant B: snapshots the completed session's exercises and planned
    /// set shape into a new template (never its notes or student identity).
    func saveAsTemplate() async -> Bool {
        guard let templateUseCases else { return false }
        let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        do {
            let session = try await useCases.fullSession(id: sessionID)
            let sections = try await templateUseCases.sessionSections(sessionID: sessionID)
            _ = try await templateUseCases.saveAsTemplate(from: session, existingSessionSections: sections, name: name)
            savedTemplateName = name
            templateName = ""
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "templates.error.generic")
            return false
        }
    }

    func load() async {
        do {
            let completed = try await useCases.detail(sessionID: sessionID)
            focus = completed.trainingFocus
            privateNote = completed.notes.privateCoachNote?.value ?? ""
            studentSummary = completed.notes.studentFacingSummary?.value ?? ""
            durationText = String(
                format: String(localized: "summary.duration.format"),
                HistoryPresentation.duration(
                    seconds: Double(completed.statistics.displayedDurationSeconds.canonicalString) ?? 0
                )
            )
            completedSetsText = String(
                format: String(localized: "summary.sets.format"),
                Int64(completed.statistics.completedSetCount)
            )
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }

    func persistNotes() async -> Bool {
        do {
            _ = try await useCases.saveSummaryNotes(
                sessionID: sessionID,
                trainingFocus: focus,
                privateCoachNote: privateNote,
                studentFacingSummary: studentSummary
            )
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
            return false
        }
    }
}

struct SessionSummaryView: View {
    @StateObject private var viewModel: SessionSummaryViewModel
    @Binding var path: [RootDestination]
    @State private var isNamingTemplate = false

    init(
        sessionID: StableUUID,
        useCases: HistoryUseCases,
        templateUseCases: TemplateUseCases? = nil,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: SessionSummaryViewModel(
                sessionID: sessionID, useCases: useCases, templateUseCases: templateUseCases)
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(FCSemanticColors.statusDestructive)
                }

                Text(viewModel.durationText)
                    .fcFont(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier(FCAccessibilityID.sessionSummaryDuration)

                Text(viewModel.completedSetsText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier(FCAccessibilityID.sessionSummaryCompletedSets)

                BodyPartMultiSelectView(title: String(localized: "summary.focus"), selection: $viewModel.focus)
                    .accessibilityIdentifier(FCAccessibilityID.sessionSummaryFocus)
                labeledField(
                    title: String(localized: "summary.privateNote"),
                    text: $viewModel.privateNote,
                    identifier: FCAccessibilityID.sessionSummaryPrivateNote
                )
                labeledField(
                    title: String(localized: "summary.studentSummary"),
                    text: $viewModel.studentSummary,
                    identifier: FCAccessibilityID.sessionSummaryStudentSummary
                )

                if viewModel.templateUseCases != nil {
                    VStack(spacing: 0) {
                        FCListRowDivider()
                        FCActionRow(
                            title: String(localized: "activeSession.action.saveAsTemplate"),
                            note: viewModel.savedTemplateName.map {
                                String(format: String(localized: "summary.savedTemplateFormat"), $0)
                            }
                        ) {
                            isNamingTemplate = true
                        }
                        .accessibilityIdentifier(FCAccessibilityID.activeSessionSaveAsTemplate)
                        FCListRowDivider()
                    }
                }

                FCButton(title: String(localized: "summary.generateReport")) {
                    Task {
                        guard await viewModel.persistNotes() else { return }
                        path.append(.shareReport(viewModel.sessionID.rawValue))
                    }
                }
                .accessibilityIdentifier(FCAccessibilityID.sessionSummaryGenerateReport)

                FCButton(title: String(localized: "summary.skipShare")) {
                    Task {
                        guard await viewModel.persistNotes() else { return }
                        path.popToStudentDetail()
                    }
                }
                .accessibilityIdentifier(FCAccessibilityID.sessionSummarySkipShare)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FCPrimitives.space4)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "summary.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .task { await viewModel.load() }
        .fcBottomSheet(isPresented: $isNamingTemplate) {
            FCBottomSheet(
                title: String(localized: "activeSession.action.saveAsTemplate"),
                subtitle: String(localized: "summary.saveAsTemplateNote")
            ) {
                VStack(spacing: FCPrimitives.space3) {
                    FCTextField(
                        String(localized: "activeSession.saveAsTemplateNamePrompt"), text: $viewModel.templateName
                    )
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionSaveAsTemplateName)
                    FCButton(
                        title: String(localized: "activeSession.saveAsTemplateConfirm"),
                        isEnabled: !viewModel.templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        Task {
                            if await viewModel.saveAsTemplate() {
                                isNamingTemplate = false
                            }
                        }
                    }
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionSaveAsTemplateConfirm)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.sessionSummaryRoot)
    }

    private func labeledField(title: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space1) {
            Text(title)
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
            TextField(title, text: text, axis: .vertical)
                .fcFont(.body)
                .foregroundStyle(FCSemanticColors.textPrimary)
                .padding(.horizontal, FCPrimitives.space4)
                .padding(.vertical, FCPrimitives.space3)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(FCSemanticColors.surfaceCanvas)
                .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSm))
                .accessibilityLabel(Text(title))
                .accessibilityIdentifier(identifier)
        }
    }
}
