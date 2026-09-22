import Charts
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
    @Published var selectedTab: TrendsTab = .comparison
    @Published var errorMessage: String?
    /// Whether the currently-selected trend/PR exercise is marked as
    /// assisted-load (M1B-FR-028). Looked up from `ExerciseLibraryUseCases`
    /// whenever `selectedExerciseKey` changes, since `CompletedSession`
    /// history carries no preference data of its own.
    @Published private(set) var isAssistedForSelectedExercise = false

    let studentID: StableUUID
    private let historyUseCases: HistoryUseCases
    private let exerciseUseCases: ExerciseLibraryUseCases
    private let calendarProvider: any LocalCalendarProvider

    init(
        studentID: StableUUID,
        historyUseCases: HistoryUseCases,
        exerciseUseCases: ExerciseLibraryUseCases,
        calendarProvider: any LocalCalendarProvider
    ) {
        self.studentID = studentID
        self.historyUseCases = historyUseCases
        self.exerciseUseCases = exerciseUseCases
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

    private var loadDirection: Comparison.LoadDirection {
        isAssistedForSelectedExercise ? .decreaseIsImprovement : .increaseIsImprovement
    }

    func exerciseTrend() -> [Comparison.SetTrendPoint] {
        guard let (id, mode) = selectedTrendOption() else { return [] }
        return Comparison.exerciseTrend(exerciseID: id, recordMode: mode, across: allSessions, loadDirection: loadDirection)
    }

    func personalRecords() -> Comparison.PersonalRecordSet? {
        guard let (id, mode) = selectedTrendOption() else { return nil }
        return Comparison.personalRecords(exerciseID: id, recordMode: mode, across: allSessions, loadDirection: loadDirection)
    }

    /// Sets the trend/PR exercise selection (shared by both the "动作趋势"
    /// and "个人最佳" Tabs, so switching Tabs never loses the pick) and
    /// refreshes whether it's assisted-load, since that flips how "best" is
    /// interpreted for both derived views above.
    func selectExercise(key: String) {
        selectedExerciseKey = key
        Task { await loadAssistedFlag() }
    }

    private func loadAssistedFlag() async {
        guard let (id, _) = selectedTrendOption() else {
            isAssistedForSelectedExercise = false
            return
        }
        do {
            let entries = try await exerciseUseCases.search(query: "", includeHidden: true)
            isAssistedForSelectedExercise = entries.first(where: { $0.id == id })?.preference?.isAssisted ?? false
        } catch {
            isAssistedForSelectedExercise = false
        }
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

enum TrendsTab: String, CaseIterable, Identifiable {
    case comparison
    case exerciseTrend
    case personalRecord

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comparison: return String(localized: "trends.tab.comparison")
        case .exerciseTrend: return String(localized: "trends.tab.exerciseTrend")
        case .personalRecord: return String(localized: "trends.tab.personalRecord")
        }
    }
}

struct TrendsView: View {
    @StateObject private var viewModel: TrendsViewModel
    @State private var selectedTrendMetric: TrendMetric = .weight

    init(
        studentID: StableUUID,
        historyUseCases: HistoryUseCases,
        exerciseUseCases: ExerciseLibraryUseCases,
        calendarProvider: any LocalCalendarProvider
    ) {
        _viewModel = StateObject(
            wrappedValue: TrendsViewModel(
                studentID: studentID,
                historyUseCases: historyUseCases,
                exerciseUseCases: exerciseUseCases,
                calendarProvider: calendarProvider
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $viewModel.selectedTab) {
                ForEach(TrendsTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, FCPrimitives.spacingMedium)
            .padding(.top, FCPrimitives.spacingSmall)
            .accessibilityIdentifier(FCAccessibilityID.trendsTabPicker)

            ScrollView {
                VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage).foregroundStyle(FCSemanticColors.destructive)
                    }

                    switch viewModel.selectedTab {
                    case .comparison:
                        comparisonTab
                    case .exerciseTrend:
                        exerciseTrendTab
                    case .personalRecord:
                        personalRecordTab
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(FCPrimitives.spacingMedium)
            }
        }
        .background(FCSemanticColors.background)
        .navigationTitle(String(localized: "trends.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(FCAccessibilityID.trendsRoot)
        .task { await viewModel.reload() }
    }

    // MARK: - 训练对比 Tab

    private var comparisonTab: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
            tabHint(String(localized: "trends.comparisonTabHint"))
            filterSection
            historySection
            comparisonSection
        }
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
                    comparisonChart(detail)
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

    private struct ComparisonBarDatum: Identifiable {
        let id = UUID()
        let metric: String
        let session: String
        let value: Double
    }

    private func comparisonChart(_ detail: Comparison.SessionComparisonDetail) -> some View {
        var data: [ComparisonBarDatum] = [
            ComparisonBarDatum(
                metric: String(localized: "trends.comparisonMetricSets"),
                session: "A",
                value: Double(detail.totalSetCountA)
            ),
            ComparisonBarDatum(
                metric: String(localized: "trends.comparisonMetricSets"),
                session: "B",
                value: Double(detail.totalSetCountB)
            ),
        ]
        if let volumeA = detail.trainingVolumeA, let volumeB = detail.trainingVolumeB,
            let a = Double(volumeA.canonicalString), let b = Double(volumeB.canonicalString)
        {
            data.append(
                ComparisonBarDatum(metric: String(localized: "trends.comparisonMetricVolume"), session: "A", value: a)
            )
            data.append(
                ComparisonBarDatum(metric: String(localized: "trends.comparisonMetricVolume"), session: "B", value: b)
            )
        }
        return Chart(data) { datum in
            BarMark(
                x: .value("metric", datum.metric),
                y: .value("value", datum.value)
            )
            .position(by: .value("session", datum.session))
            .foregroundStyle(datum.session == "A" ? FCPrimitives.brand : FCPrimitives.brand.opacity(0.5))
        }
        .frame(height: 200)
    }

    // MARK: - 动作趋势 Tab

    private var exerciseTrendTab: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
            tabHint(String(localized: "trends.exerciseTrendTabHint"))
            exercisePicker
            exerciseTrendSection
        }
    }

    private var exerciseTrendSection: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            HStack(spacing: FCPrimitives.spacingSmall) {
                sectionTitle(String(localized: "trends.exerciseTrendTitle"))
                if viewModel.isAssistedForSelectedExercise {
                    assistedBadge
                }
            }
            let points = viewModel.exerciseTrend()
            if points.first?.recordMode == .weightReps {
                Picker(String(localized: "trends.metricPickerLabel"), selection: $selectedTrendMetric) {
                    ForEach(TrendMetric.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(FCAccessibilityID.trendsMetricPicker)
                if selectedTrendMetric == .volume {
                    Text(String(localized: "trends.volumeCaption"))
                        .font(.footnote)
                        .foregroundStyle(FCSemanticColors.secondaryText)
                }
            }
            trendContent(for: Comparison.TrendSampleDensity.classify(points))
        }
        .accessibilityIdentifier(FCAccessibilityID.trendsExerciseTrendSection)
    }

    private enum TrendMetric: String, CaseIterable, Identifiable {
        case weight
        case reps
        case volume

        var id: String { rawValue }

        var label: String {
            switch self {
            case .weight: return String(localized: "trends.metric.weight")
            case .reps: return String(localized: "trends.metric.reps")
            case .volume: return String(localized: "trends.metric.volume")
            }
        }

        var unit: String {
            switch self {
            case .weight, .volume: return "kg"
            case .reps: return "次"
            }
        }

        func value(for point: Comparison.SetTrendPoint) -> DecimalValue? {
            switch self {
            case .weight: return point.maxWeight
            case .reps: return point.bestReps
            case .volume: return point.volume
            }
        }
    }

    @ViewBuilder
    private func trendContent(for density: Comparison.TrendSampleDensity) -> some View {
        switch density {
        case .empty:
            Text(String(localized: "trends.exerciseTrendEmpty"))
                .foregroundStyle(FCSemanticColors.secondaryText)
        case .single(let point):
            singlePointTrendView(point)
        case .sparse(let points):
            trendBody(points, dashed: true)
        case .sufficient(let points):
            trendBody(points, dashed: false)
        }
    }

    /// Renders as a `Charts` line for `.weightReps` (the only mode where
    /// `maxWeight` carries the plotted value); other record modes fall back
    /// to the unit-annotated row list, since a weight-axis chart wouldn't
    /// have anything to plot for a duration/cardio-only exercise.
    @ViewBuilder
    private func trendBody(_ points: [Comparison.SetTrendPoint], dashed: Bool) -> some View {
        if points.first?.recordMode == .weightReps {
            metricTrendChart(points, dashed: dashed)
            if selectedTrendMetric == .weight, viewModel.isAssistedForSelectedExercise,
                let summary = trendDeltaSummary(points)
            {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(FCSemanticColors.secondaryText)
            }
        } else {
            trendRows(points)
        }
    }

    private func metricTrendChart(_ points: [Comparison.SetTrendPoint], dashed: Bool) -> some View {
        let metric = selectedTrendMetric
        return Chart(points, id: \.sessionID) { point in
            if let raw = metric.value(for: point), let value = Double(raw.canonicalString) {
                LineMark(
                    x: .value("date", point.completedAtUTC),
                    y: .value(metric.label, value)
                )
                .foregroundStyle(FCPrimitives.brand)
                .lineStyle(dashed ? StrokeStyle(lineWidth: 2, dash: [4, 4]) : StrokeStyle(lineWidth: 2))
                PointMark(
                    x: .value("date", point.completedAtUTC),
                    y: .value(metric.label, value)
                )
                .foregroundStyle(FCPrimitives.brand)
            }
        }
        .frame(height: 200)
    }

    private func trendRows(_ points: [Comparison.SetTrendPoint]) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                HStack {
                    Text(point.completedAtUTC, style: .date)
                    Spacer()
                    Text(point.recordMode == .weightReps ? metricSingleValueText(point) : trendValueText(point))
                }
            }
        }
    }

    /// The metric-switcher's own value text for `.weightReps` points
    /// (weight/reps/volume, driven by `selectedTrendMetric`) -- kept
    /// separate from `trendValueText` below, which is the pre-existing
    /// fixed-field text for the other RecordModes the switcher doesn't
    /// apply to.
    private func metricSingleValueText(_ point: Comparison.SetTrendPoint) -> String {
        let metric = selectedTrendMetric
        return metric.value(for: point).map { "\($0.canonicalString)\(metric.unit)" } ?? "-"
    }

    private func singlePointTrendView(_ point: Comparison.SetTrendPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(point.recordMode == .weightReps ? metricSingleValueText(point) : trendValueText(point))
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(FCSemanticColors.primaryText)
            Text(point.completedAtUTC, style: .date)
                .font(.footnote)
                .foregroundStyle(FCSemanticColors.secondaryText)
            Text(String(localized: "trends.exerciseTrendSingleHint"))
                .font(.footnote)
                .foregroundStyle(FCSemanticColors.secondaryText)
        }
    }

    /// M1B-FR-028 units fix -- weight always shows "kg", `.duration`/`.cardio`
    /// go through `DurationTextParser` (never raw seconds), cardio distance
    /// shows "km". Single source used by both the row fallback and the
    /// single-point large-number view so they can never drift apart.
    private func trendValueText(_ point: Comparison.SetTrendPoint) -> String {
        switch point.recordMode {
        case .weightReps:
            return point.maxWeight.map { "\($0.canonicalString)kg" } ?? "-"
        case .reps:
            return point.bestReps.map { "\($0.canonicalString)次" } ?? "-"
        case .duration:
            guard let duration = point.bestDurationSeconds else { return "-" }
            return DurationTextParser.formatForEditing(secondsText: duration.canonicalString)
        case .cardio:
            var parts: [String] = []
            if let duration = point.bestDurationSeconds {
                parts.append(DurationTextParser.formatForEditing(secondsText: duration.canonicalString))
            }
            if let distance = point.bestDistance {
                parts.append("\(distance.canonicalString)km")
            }
            return parts.isEmpty ? "-" : parts.joined(separator: " · ")
        }
    }

    private func trendDeltaSummary(_ points: [Comparison.SetTrendPoint]) -> String? {
        guard let last = points.last, let delta = last.weightDelta, !delta.isZero else { return nil }
        let magnitude = NSDecimalNumber(decimal: delta.decimal).doubleValue
        let signedText = magnitude >= 0 ? "+\(delta.canonicalString)" : delta.canonicalString
        let isImprovement = viewModel.isAssistedForSelectedExercise ? magnitude < 0 : magnitude > 0
        let label =
            isImprovement
            ? String(localized: "trends.deltaImprovement")
            : String(localized: "trends.deltaRegression")
        return String(format: String(localized: "trends.deltaSummaryFormat"), signedText, label)
    }

    // MARK: - 个人最佳 Tab

    private var personalRecordTab: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
            tabHint(String(localized: "trends.personalRecordTabHint"))
            exercisePicker
            personalRecordSection
        }
    }

    private var personalRecordSection: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            HStack(spacing: FCPrimitives.spacingSmall) {
                sectionTitle(String(localized: "trends.personalRecordTitle"))
                if viewModel.isAssistedForSelectedExercise {
                    assistedBadge
                }
            }
            if let records = viewModel.personalRecords() {
                VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
                    if let highest = records.highestWeight {
                        personalRecordCard("PR: \(highest.weight.canonicalString)kg")
                    }
                    if let longest = records.longestDuration {
                        personalRecordCard(
                            "PR: \(DurationTextParser.formatForEditing(secondsText: longest.seconds.canonicalString))"
                        )
                    }
                    if let distance = records.longestDistance {
                        personalRecordCard("PR: \(distance.distance.canonicalString)km")
                    }
                    if records.highestWeight == nil && records.longestDuration == nil
                        && records.longestDistance == nil
                    {
                        Text(String(localized: "trends.personalRecordEmpty"))
                            .foregroundStyle(FCSemanticColors.secondaryText)
                    }
                }
            } else {
                Text(String(localized: "trends.personalRecordEmpty"))
                    .foregroundStyle(FCSemanticColors.secondaryText)
            }
        }
        .accessibilityIdentifier(FCAccessibilityID.trendsPersonalRecordSection)
    }

    private func personalRecordCard(_ text: String) -> some View {
        Text(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FCPrimitives.spacingSmall)
            .background(FCSemanticColors.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
    }

    // MARK: - Shared

    private var exercisePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(viewModel.exerciseOptions, id: \.key) { option in
                    Button(option.name) {
                        viewModel.selectExercise(key: option.key)
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

    private var assistedBadge: some View {
        Text(String(localized: "trends.assistedBadge"))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, FCPrimitives.spacingSmall)
            .padding(.vertical, 4)
            .background(FCSemanticColors.warning.opacity(0.15))
            .foregroundStyle(FCSemanticColors.warning)
            .clipShape(Capsule())
            .accessibilityIdentifier(FCAccessibilityID.trendsAssistedBadge)
    }

    private func tabHint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(FCSemanticColors.secondaryText)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FCSemanticColors.secondaryText)
    }
}
