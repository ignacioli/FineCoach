import SwiftUI

@MainActor
final class SessionDetailViewModel: ObservableObject {
    @Published var completed: CompletedSession?
    @Published var errorMessage: String?

    let sessionID: StableUUID
    private let useCases: HistoryUseCases

    init(sessionID: StableUUID, useCases: HistoryUseCases) {
        self.sessionID = sessionID
        self.useCases = useCases
    }

    func load() async {
        do {
            completed = try await useCases.detail(sessionID: sessionID)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }
}

struct SessionDetailView: View {
    @StateObject private var viewModel: SessionDetailViewModel
    @Binding var path: [RootDestination]

    init(sessionID: StableUUID, useCases: HistoryUseCases, path: Binding<[RootDestination]>) {
        _viewModel = StateObject(
            wrappedValue: SessionDetailViewModel(sessionID: sessionID, useCases: useCases)
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.background)
        .navigationTitle(String(localized: "detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .onChange(of: path) { _, _ in
            Task { await viewModel.load() }
        }
        .accessibilityIdentifier(FCAccessibilityID.sessionDetailRoot)
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
        var parts = ["组\(trainingSet.orderIndex + 1)"]
        if let weight = trainingSet.weightValue {
            parts.append(weight.canonicalString)
        }
        if let reps = trainingSet.repetitionCount {
            parts.append("×\(reps.canonicalString)")
        }
        return parts.joined(separator: " ")
    }
}
