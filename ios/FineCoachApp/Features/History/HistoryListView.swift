import SwiftUI

@MainActor
final class HistoryListViewModel: ObservableObject {
    @Published var rows: [CompletedSession] = []
    @Published var errorMessage: String?

    let studentID: StableUUID
    private let useCases: HistoryUseCases

    init(studentID: StableUUID, useCases: HistoryUseCases) {
        self.studentID = studentID
        self.useCases = useCases
    }

    func load() async {
        do {
            rows = try await useCases.listHistory(studentID: studentID)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }
}

struct HistoryListView: View {
    @StateObject private var viewModel: HistoryListViewModel
    @Binding var path: [RootDestination]

    init(studentID: StableUUID, useCases: HistoryUseCases, path: Binding<[RootDestination]>) {
        _viewModel = StateObject(
            wrappedValue: HistoryListViewModel(studentID: studentID, useCases: useCases)
        )
        _path = path
    }

    var body: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(FCSemanticColors.destructive)
            }
            ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                Button {
                    path.append(.sessionDetail(row.id.rawValue))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.dayText(row.completedAtUTC))
                            .font(.headline)
                            .foregroundStyle(FCSemanticColors.primaryText)
                        Text(
                            String(
                                format: String(localized: "history.row.sets.format"),
                                Int64(row.statistics.completedSetCount)
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(FCSemanticColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier(FCAccessibilityID.historyRow(index))
            }
        }
        .background(FCSemanticColors.background)
        .navigationTitle(String(localized: "history.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .onChange(of: path) { _, _ in
            Task { await viewModel.load() }
        }
        .accessibilityIdentifier(FCAccessibilityID.historyRoot)
    }

    private static func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
