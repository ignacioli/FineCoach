import SwiftUI

@MainActor
final class SessionSummaryViewModel: ObservableObject {
    @Published var focus = ""
    @Published var privateNote = ""
    @Published var studentSummary = ""
    @Published var durationText = ""
    @Published var completedSetsText = ""
    @Published var errorMessage: String?

    let sessionID: StableUUID
    private let useCases: HistoryUseCases

    init(sessionID: StableUUID, useCases: HistoryUseCases) {
        self.sessionID = sessionID
        self.useCases = useCases
    }

    func load() async {
        do {
            let completed = try await useCases.detail(sessionID: sessionID)
            focus = completed.trainingFocus?.value ?? ""
            privateNote = completed.notes.privateCoachNote?.value ?? ""
            studentSummary = completed.notes.studentFacingSummary?.value ?? ""
            durationText = String(
                format: String(localized: "summary.duration.format"),
                completed.statistics.displayedDurationSeconds.canonicalString
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

    init(sessionID: StableUUID, useCases: HistoryUseCases, path: Binding<[RootDestination]>) {
        _viewModel = StateObject(
            wrappedValue: SessionSummaryViewModel(sessionID: sessionID, useCases: useCases)
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(FCSemanticColors.destructive)
                }

                Text(viewModel.durationText)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier(FCAccessibilityID.sessionSummaryDuration)

                Text(viewModel.completedSetsText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier(FCAccessibilityID.sessionSummaryCompletedSets)

                labeledField(
                    title: String(localized: "summary.focus"),
                    text: $viewModel.focus,
                    identifier: FCAccessibilityID.sessionSummaryFocus
                )
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
            .padding(FCPrimitives.spacingMedium)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "summary.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .task { await viewModel.load() }
        .accessibilityIdentifier(FCAccessibilityID.sessionSummaryRoot)
    }

    private func labeledField(title: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(FCSemanticColors.secondaryText)
            TextField(title, text: text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
                .accessibilityLabel(Text(title))
                .accessibilityIdentifier(identifier)
        }
    }
}
