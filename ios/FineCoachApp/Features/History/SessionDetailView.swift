import SwiftUI

@MainActor
final class SessionDetailViewModel: ObservableObject {
    @Published var completed: CompletedSession?
    @Published var errorMessage: String?
    @Published var isSavingAsTemplate = false
    @Published var saveAsTemplateName = ""
    @Published var didSaveAsTemplate = false

    let sessionID: StableUUID
    private let useCases: HistoryUseCases
    private let templateUseCases: TemplateUseCases?

    var canSaveAsTemplate: Bool { templateUseCases != nil }

    init(sessionID: StableUUID, useCases: HistoryUseCases, templateUseCases: TemplateUseCases? = nil) {
        self.sessionID = sessionID
        self.useCases = useCases
        self.templateUseCases = templateUseCases
    }

    func load() async {
        do {
            completed = try await useCases.detail(sessionID: sessionID)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }

    /// Saves THIS already-completed Session as a new template (M1B-FR-017:
    /// save-as-template MUST work both from scratch and from a completed
    /// Session, not only a still-live one). Loads the full `Session`
    /// aggregate + its owned Sections on demand -- `CompletedSession` alone
    /// does not carry the raw shape `TemplateUseCases.saveAsTemplate` needs.
    func saveAsTemplate() async {
        guard let templateUseCases else {
            return
        }
        let name = saveAsTemplateName
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        do {
            let session = try await useCases.fullSession(id: sessionID)
            let sections = try await templateUseCases.sessionSections(sessionID: sessionID)
            _ = try await templateUseCases.saveAsTemplate(
                from: session,
                existingSessionSections: sections,
                name: name
            )
            saveAsTemplateName = ""
            isSavingAsTemplate = false
            didSaveAsTemplate = true
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }
}

struct SessionDetailView: View {
    @StateObject private var viewModel: SessionDetailViewModel
    @Binding var path: [RootDestination]

    init(
        sessionID: StableUUID,
        useCases: HistoryUseCases,
        templateUseCases: TemplateUseCases? = nil,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: SessionDetailViewModel(
                sessionID: sessionID,
                useCases: useCases,
                templateUseCases: templateUseCases
            )
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(FCSemanticColors.destructive)
                }

                Text(String(localized: "detail.readonly"))
                    .font(.footnote)
                    .foregroundStyle(FCSemanticColors.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier(FCAccessibilityID.sessionDetailReadonly)

                if let completed = viewModel.completed {
                    Text(completed.studentDisplayName.value)
                        .font(.headline)
                    if let focus = completed.trainingFocus?.value {
                        labeled(String(localized: "summary.focus"), focus)
                    }
                    if let summary = completed.notes.studentFacingSummary?.value {
                        labeled(String(localized: "summary.studentSummary"), summary)
                    }
                    Text(
                        String(
                            format: String(localized: "summary.duration.format"),
                            completed.statistics.displayedDurationSeconds.canonicalString
                        )
                    )
                    Text(
                        String(
                            format: String(localized: "summary.sets.format"),
                            Int64(completed.statistics.completedSetCount)
                        )
                    )

                    if completed.latestReport?.freshness == .stale {
                        Text(String(localized: "detail.reportStale"))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .accessibilityIdentifier(FCAccessibilityID.sessionDetailReportStale)
                    }
                    if completed.latestReport?.handedToSystemAtUTC != nil {
                        Text(String(localized: "share.handedToSystem"))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .accessibilityIdentifier(FCAccessibilityID.sessionDetailHandedToSystem)
                    }

                    ForEach(completed.exercises, id: \.id) { exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.displayNameSnapshot.value).font(.headline)
                            ForEach(exercise.sets.filter(\.contributesToStatistics), id: \.id) { trainingSet in
                                Text(setLine(trainingSet))
                                    .font(.footnote)
                            }
                        }
                    }
                }

                FCButton(title: String(localized: "detail.edit")) {
                    path.append(.sessionEdit(viewModel.sessionID.rawValue))
                }
                .accessibilityIdentifier(FCAccessibilityID.sessionDetailEdit)

                FCButton(title: String(localized: "summary.generateReport")) {
                    path.append(.shareReport(viewModel.sessionID.rawValue))
                }
                .accessibilityIdentifier(FCAccessibilityID.sessionDetailGenerateReport)

                saveAsTemplateControls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .onChange(of: path) { _, _ in
            Task { await viewModel.load() }
        }
        .accessibilityIdentifier(FCAccessibilityID.sessionDetailRoot)
    }

    /// Mirrors `ActiveSessionView.templateAndSectionControls`'s
    /// toggle-between-button-and-inline-name-field pattern, reusing that
    /// flow's existing localization keys verbatim (M1B-FR-017 requires this
    /// second entry point, not new wording).
    @ViewBuilder
    private var saveAsTemplateControls: some View {
        if viewModel.canSaveAsTemplate {
            if viewModel.isSavingAsTemplate {
                FCTextField(
                    String(localized: "activeSession.saveAsTemplateNamePrompt"),
                    text: $viewModel.saveAsTemplateName
                )
                .accessibilityIdentifier(FCAccessibilityID.sessionDetailSaveAsTemplateName)
                FCButton(title: String(localized: "activeSession.saveAsTemplateConfirm")) {
                    Task { await viewModel.saveAsTemplate() }
                }
                .accessibilityIdentifier(FCAccessibilityID.sessionDetailSaveAsTemplateConfirm)
            } else {
                Button(String(localized: "activeSession.action.saveAsTemplate")) {
                    viewModel.isSavingAsTemplate = true
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier(FCAccessibilityID.sessionDetailSaveAsTemplate)
            }
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(FCSemanticColors.secondaryText)
            Text(value)
        }
    }

    private func setLine(_ trainingSet: TrainingSet) -> String {
        "组\(trainingSet.orderIndex + 1) \(trainingSet.displaySummary)"
    }
}
