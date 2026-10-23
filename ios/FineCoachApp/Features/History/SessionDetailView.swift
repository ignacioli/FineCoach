import SwiftUI

@MainActor
final class SessionDetailViewModel: ObservableObject {
    @Published var completed: CompletedSession?
    /// The record rendered with the report card's sections (T069j review,
    /// owner 2026-09-28: the page must read like 29, not a data table).
    /// This view model only feeds the on-screen page; nothing is exported.
    @Published var record: ShareReportDTO?
    /// Coach-only billing annotation, shown outside the report card.
    @Published var creditNote: SessionCreditSettlementNote?
    @Published var errorMessage: String?
    @Published var isSavingAsTemplate = false
    @Published var saveAsTemplateName = ""
    @Published var didSaveAsTemplate = false

    @Published var gains: SessionGains = .empty
    private let exerciseUseCases: ExerciseLibraryUseCases?

    let sessionID: StableUUID
    private let useCases: HistoryUseCases
    private let templateUseCases: TemplateUseCases?

    var canSaveAsTemplate: Bool { templateUseCases != nil }

    init(
        sessionID: StableUUID, useCases: HistoryUseCases, templateUseCases: TemplateUseCases? = nil,
        exerciseUseCases: ExerciseLibraryUseCases? = nil
    ) {
        self.exerciseUseCases = exerciseUseCases
        self.sessionID = sessionID
        self.useCases = useCases
        self.templateUseCases = templateUseCases
    }

    func load() async {
        do {
            let loaded = try await useCases.detail(sessionID: sessionID)
            let history = try await useCases.listHistory(studentID: loaded.studentID)
            let assisted = (try? await exerciseUseCases?.assistedExerciseIDs()) ?? []
            gains = SessionGains(current: loaded, history: history, assistedExerciseIDs: assisted)
            completed = loaded
            record = try ShareReportPolicy.makeDTO(from: loaded, modules: .privacySafeDefaults)
            creditNote = (try? await useCases.creditSettlementNote(sessionID: sessionID)) ?? nil
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
        exerciseUseCases: ExerciseLibraryUseCases? = nil,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: SessionDetailViewModel(
                sessionID: sessionID,
                useCases: useCases,
                templateUseCases: templateUseCases,
                exerciseUseCases: exerciseUseCases
            )
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space6) {
                FCPageHeader(title: String(localized: "detail.title"), back: .init())

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .fcFont(.callout, weight: .regular)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                }

                if let record = viewModel.record {
                    ShareReportCardView(
                        dto: record, style: .page,
                        blocks: ShareReportCardView.blocks(for: record, style: .page).filter { $0 != .summary })
                    SessionGainsSectionView(gains: viewModel.gains)
                        .accessibilityIdentifier(FCAccessibilityID.sessionDetailGains)
                    if let summary = record.studentFacingSummary, !summary.isEmpty {
                        ShareReportCardView(dto: record, style: .page, blocks: [.summary])
                    }
                }

                if viewModel.creditNote == .noActivePackage {
                    Text(String(localized: "history.creditNote.noActivePackage"))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(FCAccessibilityID.sessionDetailCreditNote)
                }

                if let report = viewModel.completed?.latestReport,
                    report.freshness == .stale || report.handedToSystemAtUTC != nil
                {
                    VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                        if report.freshness == .stale {
                            FCStatusLabel(text: String(localized: "detail.reportStale"), symbolName: "exclamationmark")
                                .accessibilityIdentifier(FCAccessibilityID.sessionDetailReportStale)
                        }
                        if report.handedToSystemAtUTC != nil {
                            FCStatusLabel(
                                text: String(localized: "share.handedToSystem"),
                                symbolName: "info",
                                badgeColor: FCSemanticColors.actionPrimary
                            )
                            .accessibilityIdentifier(FCAccessibilityID.sessionDetailHandedToSystem)
                        }
                    }
                }

                actions
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space4)
        }
        .safeAreaInset(edge: .bottom) {
            FCButton(title: String(localized: "summary.generateReport")) {
                path.append(.shareReport(viewModel.sessionID.rawValue))
            }
            .accessibilityIdentifier(FCAccessibilityID.sessionDetailGenerateReport)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.vertical, FCPrimitives.space2)
            .background(FCSemanticColors.surfacePage)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .task { await viewModel.load() }
        .onChange(of: path) { _, _ in
            Task { await viewModel.load() }
        }
        .fcBottomSheet(isPresented: $viewModel.isSavingAsTemplate) {
            FCBottomSheet(
                title: String(localized: "activeSession.action.saveAsTemplate"),
                subtitle: String(localized: "summary.saveAsTemplateNote")
            ) {
                VStack(spacing: FCPrimitives.space3) {
                    FCTextField(
                        String(localized: "activeSession.saveAsTemplateNamePrompt"),
                        text: $viewModel.saveAsTemplateName
                    )
                    .accessibilityIdentifier(FCAccessibilityID.sessionDetailSaveAsTemplateName)
                    FCButton(
                        title: String(localized: "activeSession.saveAsTemplateConfirm"),
                        isEnabled: !viewModel.saveAsTemplateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        Task { await viewModel.saveAsTemplate() }
                    }
                    .accessibilityIdentifier(FCAccessibilityID.sessionDetailSaveAsTemplateConfirm)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.sessionDetailRoot)
    }

    /// The record itself is read-only; the rows below are the only edits.
    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            FCListRowDivider()
            FCActionRow(title: String(localized: "detail.edit")) {
                path.append(.sessionEdit(viewModel.sessionID.rawValue))
            }
            .accessibilityIdentifier(FCAccessibilityID.sessionDetailEdit)
            if viewModel.canSaveAsTemplate {
                FCListRowDivider()
                FCActionRow(
                    title: String(localized: "activeSession.action.saveAsTemplate"),
                    note: viewModel.didSaveAsTemplate ? String(localized: "detail.savedAsTemplate") : nil
                ) {
                    viewModel.isSavingAsTemplate = true
                }
                .accessibilityIdentifier(FCAccessibilityID.sessionDetailSaveAsTemplate)
            }
            FCListRowDivider()
            Text(String(localized: "detail.readonly"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .padding(.top, FCPrimitives.space2)
                .accessibilityIdentifier(FCAccessibilityID.sessionDetailReadonly)
        }
    }
}
