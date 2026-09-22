import SwiftUI

/// History filtering (M1B-FR-026) + session comparison (M1B-FR-027) +
/// exercise trend (M1B-FR-028) + personal records (M1B-FR-029), T039. All
/// three derived views are computed live from `Comparison` -- nothing here
/// is cached or persisted. Trend/PR are always computed over this Student's
/// FULL history (not the date-range filter, which applies only to the
/// history list itself) since a PR or a long-run trend that silently
/// excluded out-of-range sessions would misrepresent the Student's record.
@MainActor
final class TrendsViewModel: ObservableObject {
    @Published var filterResult: HistoryFilterResult = .noMatches
    @Published var allSessions: [CompletedSession] = []
    @Published var focusFilterText = ""
    @Published var selectedForComparison: Set<StableUUID> = []
    @Published var selectedExerciseKey: String?
    @Published var errorMessage: String?

    let studentID: StableUUID
    private let historyUseCases: HistoryUseCases
    private let calendarProvider: any LocalCalendarProvider

    init(studentID: StableUUID, historyUseCases: HistoryUseCases, calendarProvider: any LocalCalendarProvider) {
        self.studentID = studentID
        self.historyUseCases = historyUseCases
        self.calendarProvider = calendarProvider
    }

    var filteredSessions: [CompletedSession] {
        switch filterResult {
        case .matches(let sessions): return sessions
        case .noMatches: return []
        }
    }

    var isEmpty: Bool {
        if case .noMatches = filterResult { return true }
        return false
    }

    /// Distinct (exerciseID, name, recordMode) options across ALL history,
    /// for the trend/PR picker below.
    var exerciseOptions: [(key: String, name: String, id: StableExerciseID, mode: RecordMode)] {
        var seen: [String: (String, StableExerciseID, RecordMode)] = [:]
        for session in allSessions {
            for exercise in session.exercises {
                guard let sourceID = exercise.sourceID else { continue }
                let key = "\(sourceID.rawValue)|\(exercise.recordModeSnapshot.rawValue)"
                seen[key] = (exercise.displayNameSnapshot.value, sourceID, exercise.recordModeSnapshot)
            }
        }
        return seen.map { key, value in (key, value.0, value.1, value.2) }.sorted { $0.name < $1.name }
    }

    var selectedComparisonResult: Comparison.SessionComparisonResult? {
        let selected = filteredSessions.filter { selectedForComparison.contains($0.id) }
        guard selected.count == 2 else { return nil }
        return Comparison.compareSessions(selected[0], selected[1])
    }

    func selectedTrendOption() -> (id: StableExerciseID, mode: RecordMode)? {
        guard let key = selectedExerciseKey,
            let option = exerciseOptions.first(where: { $0.key == key })
        else { return nil }
        return (option.id, option.mode)
    }

    func exerciseTrend() -> [Comparison.SetTrendPoint] {
        guard let (id, mode) = selectedTrendOption() else { return [] }
        return Comparison.exerciseTrend(exerciseID: id, recordMode: mode, across: allSessions)
    }

    func personalRecords() -> Comparison.PersonalRecordSet? {
        guard let (id, mode) = selectedTrendOption() else { return nil }
        return Comparison.personalRecords(exerciseID: id, recordMode: mode, across: allSessions)
    }

    func reload() async {
        do {
            allSessions = try await historyUseCases.listHistory(studentID: studentID)
            await applyFilter()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "trends.error.generic")
        }
    }

    func applyFilter() async {
        do {
            let focus = focusFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
            let criteria = HistoryFilterCriteria(trainingFocus: focus.isEmpty ? nil : focus)
            filterResult = try await historyUseCases.filteredHistory(
                studentID: studentID,
                criteria: criteria,
                calendarProvider: calendarProvider
            )
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "trends.error.generic")
        }
    }

    func toggleComparisonSelection(_ id: StableUUID) {
        if selectedForComparison.contains(id) {
            selectedForComparison.remove(id)
        } else {
            if selectedForComparison.count >= 2 {
                selectedForComparison.removeAll()
            }
            selectedForComparison.insert(id)
        }
    }
}

struct TrendsView: View {
    @StateObject private var viewModel: TrendsViewModel

    init(studentID: StableUUID, historyUseCases: HistoryUseCases, calendarProvider: any LocalCalendarProvider) {
        _viewModel = StateObject(
            wrappedValue: TrendsViewModel(
                studentID: studentID,
                historyUseCases: historyUseCases,
                calendarProvider: calendarProvider
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(FCSemanticColors.destructive)
                }

                filterSection
                Divider()
                historySection
                Divider()
                comparisonSection
                Divider()
                exerciseTrendSection
                Divider()
                personalRecordSection
            }
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.background)
        .navigationTitle(String(localized: "trends.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(FCAccessibilityID.trendsRoot)
        .task { await viewModel.reload() }
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            sectionTitle(String(localized: "trends.filterSection"))
            FCTextField(String(localized: "trends.focusLabel"), text: $viewModel.focusFilterText)
                .accessibilityIdentifier(FCAccessibilityID.trendsFilterFocus)
            FCButton(title: String(localized: "trends.applyFilters")) {
                Task { await viewModel.applyFilter() }
            }
        }
    }

    private var historySection: some View {
        Group {
            if viewModel.isEmpty {
                Text(String(localized: "trends.noMatches"))
                    .foregroundStyle(FCSemanticColors.secondaryText)
                    .accessibilityIdentifier(FCAccessibilityID.trendsNoMatches)
            } else {
                ForEach(viewModel.filteredSessions) { session in
                    Button {
                        viewModel.toggleComparisonSelection(session.id)
                    } label: {
                        HStack {
                            Text(session.completedAtUTC, style: .date)
                            Spacer()
                            if viewModel.selectedForComparison.contains(session.id) {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .padding(FCPrimitives.spacingSmall)
                        .frame(maxWidth: .infinity)
                        .background(FCSemanticColors.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            sectionTitle(String(localized: "trends.comparisonTitle"))
            if let result = viewModel.selectedComparisonResult {
                switch result {
                case .compatible(let detail):
                    Text("\(detail.totalSetCountA) vs \(detail.totalSetCountB) 组")
                    if let volumeA = detail.trainingVolumeA, let volumeB = detail.trainingVolumeB {
                        Text(
                            String(
                                format: String(localized: "trends.comparisonVolumeFormat"),
                                volumeA.canonicalString,
                                volumeB.canonicalString
                            )
                        )
                    }
                case .incompatibleTrainingFocus, .differentStudent:
                    Text(String(localized: "trends.comparisonIncompatible"))
                        .foregroundStyle(FCSemanticColors.secondaryText)
                }
            }
        }
        .accessibilityIdentifier(FCAccessibilityID.trendsComparisonSection)
    }

    private var exerciseTrendSection: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            sectionTitle(String(localized: "trends.exerciseTrendTitle"))
            exercisePicker
            let points = viewModel.exerciseTrend()
            if points.isEmpty {
                Text(String(localized: "trends.exerciseTrendEmpty"))
                    .foregroundStyle(FCSemanticColors.secondaryText)
            } else {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    HStack {
                        Text(point.completedAtUTC, style: .date)
                        Spacer()
                        if let maxWeight = point.maxWeight {
                            Text(maxWeight.canonicalString)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier(FCAccessibilityID.trendsExerciseTrendSection)
    }

    private var personalRecordSection: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            sectionTitle(String(localized: "trends.personalRecordTitle"))
            if let records = viewModel.personalRecords() {
                if let highest = records.highestWeight {
                    Text("PR: \(highest.weight.canonicalString)")
                }
                if let longest = records.longestDuration {
                    Text("PR: \(longest.seconds.canonicalString)s")
                }
                if records.highestWeight == nil && records.longestDuration == nil && records.longestDistance == nil {
                    Text(String(localized: "trends.personalRecordEmpty"))
                        .foregroundStyle(FCSemanticColors.secondaryText)
                }
            } else {
                Text(String(localized: "trends.personalRecordEmpty"))
                    .foregroundStyle(FCSemanticColors.secondaryText)
            }
        }
        .accessibilityIdentifier(FCAccessibilityID.trendsPersonalRecordSection)
    }

    private var exercisePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(viewModel.exerciseOptions, id: \.key) { option in
                    Button(option.name) {
                        viewModel.selectedExerciseKey = option.key
                    }
                    .padding(.horizontal, FCPrimitives.spacingSmall)
                    .frame(minHeight: 44)
                    .background(
                        viewModel.selectedExerciseKey == option.key
                            ? FCSemanticColors.brand.opacity(0.2) : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FCSemanticColors.secondaryText)
    }
}
