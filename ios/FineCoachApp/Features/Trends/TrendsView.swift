import Charts
import SwiftUI

/// 训练趋势: the per-exercise trend (M1B-FR-028), computed live from
/// `Comparison`. Since T069i the history filter, session comparison and
/// personal records live on 训练历史 (`HistoryListView`, 32 artwork); this
/// page keeps only the exercise trend charts. Nothing here is cached or
/// persisted. Trend/PR are always computed over this Student's
/// FULL history (not the date-range filter, which applies only to the
/// history list itself) since a PR or a long-run trend that silently
/// excluded out-of-range sessions would misrepresent the Student's record.
@MainActor
final class TrendsViewModel: ObservableObject {
    @Published var filterResult: HistoryFilterResult = .noMatches
    @Published var allSessions: [CompletedSession] = []
    @Published var focusFilter: Set<BodyPart> = []
    @Published var selectedForComparison: Set<StableUUID> = []
    @Published var selectedExerciseKey: String?
    @Published var selectedTrendMetric: TrendMetric = .weight
    @Published var selectedTab: TrendsTab = .comparison
    @Published var errorMessage: String?
    /// Whether the currently-selected trend/PR exercise is marked as
    /// assisted-load (M1B-FR-028). Looked up from `ExerciseLibraryUseCases`
    /// whenever `selectedExerciseKey` changes, since `CompletedSession`
    /// history carries no preference data of its own.
    @Published private(set) var isAssistedForSelectedExercise = false

    let studentID: StableUUID
    private let initialExerciseID: StableExerciseID?
    private let historyUseCases: HistoryUseCases
    private let exerciseUseCases: ExerciseLibraryUseCases
    private let calendarProvider: any LocalCalendarProvider

    init(
        studentID: StableUUID,
        historyUseCases: HistoryUseCases,
        exerciseUseCases: ExerciseLibraryUseCases,
        calendarProvider: any LocalCalendarProvider,
        initialExerciseID: StableExerciseID? = nil
    ) {
        self.initialExerciseID = initialExerciseID
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
        return Comparison.exerciseTrend(
            exerciseID: id, recordMode: mode, across: allSessions, loadDirection: loadDirection)
    }

    func personalRecords() -> Comparison.PersonalRecordSet? {
        guard let (id, mode) = selectedTrendOption() else { return nil }
        return Comparison.personalRecords(
            exerciseID: id, recordMode: mode, across: allSessions, loadDirection: loadDirection)
    }

    /// Sets the trend/PR exercise selection (shared by both the "动作趋势"
    /// and "个人最佳" Tabs, so switching Tabs never loses the pick) and
    /// refreshes whether it's assisted-load, since that flips how "best" is
    /// interpreted for both derived views above.
    func selectExercise(key: String) {
        selectedExerciseKey = key
        selectedTrendMetric = selectedTrendMetric.resolved(for: selectedTrendOption()?.id)
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

    nonisolated static func initialOptionKey(exerciseID: StableExerciseID, sessions: [CompletedSession]) -> String? {
        let latest = sessions.filter { session in
            session.exercises.contains { $0.sourceID == exerciseID }
        }.max {
            if $0.completedAtUTC != $1.completedAtUTC { return $0.completedAtUTC < $1.completedAtUTC }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
        guard let exercise = latest?.exercises.last(where: { $0.sourceID == exerciseID }) else { return nil }
        return "\(exerciseID.rawValue)|\(exercise.recordModeSnapshot.rawValue)"
    }

    func reload() async {
        do {
            allSessions = try await historyUseCases.listHistory(studentID: studentID)
            if selectedExerciseKey == nil, let initialExerciseID {
                if let key = Self.initialOptionKey(exerciseID: initialExerciseID, sessions: allSessions) {
                    selectExercise(key: key)
                    selectedTab = .exerciseTrend
                }
            }
            await applyFilter()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "trends.error.generic")
        }
    }

    func applyFilter() async {
        do {
            let criteria = HistoryFilterCriteria(trainingFocus: focusFilter)
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

    init(
        studentID: StableUUID,
        historyUseCases: HistoryUseCases,
        exerciseUseCases: ExerciseLibraryUseCases,
        calendarProvider: any LocalCalendarProvider,
        initialExerciseID: StableExerciseID? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: TrendsViewModel(
                studentID: studentID,
                historyUseCases: historyUseCases,
                exerciseUseCases: exerciseUseCases,
                calendarProvider: calendarProvider,
                initialExerciseID: initialExerciseID
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(title: String(localized: "trends.title"), back: .init())
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                }
                exerciseTrendTab
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.trendsRoot)
        .task { await viewModel.reload() }
    }

    // MARK: - 动作趋势 Tab

    private var exerciseTrendTab: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            tabHint(String(localized: "trends.exerciseTrendTabHint"))
            exercisePicker
            exerciseTrendSection
        }
    }

    private var exerciseTrendSection: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            HStack(spacing: FCPrimitives.space2) {
                sectionTitle(String(localized: "trends.exerciseTrendTitle"))
                if viewModel.isAssistedForSelectedExercise {
                    AssistedLoadBadge()
                }
            }
            let points =
                viewModel.selectedTrendMetric == .estimatedOneRepMax
                ? EstimatedOneRepMaxTrend.points(
                    exerciseID: viewModel.selectedTrendOption()?.id, sessions: viewModel.allSessions)
                : viewModel.exerciseTrend()
            if viewModel.selectedTrendOption()?.mode == .weightReps {
                FCSegmentedSwitch(
                    options: TrendMetric.options(for: viewModel.selectedTrendOption()?.id).map {
                        .init(id: $0.rawValue, title: $0.label)
                    },
                    selection: Binding(
                        get: { viewModel.selectedTrendMetric.rawValue },
                        set: {
                            viewModel.selectedTrendMetric = TrendMetric(rawValue: $0) ?? viewModel.selectedTrendMetric
                        }
                    )
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel(String(localized: "trends.metricPickerLabel"))
                .accessibilityIdentifier(FCAccessibilityID.trendsMetricPicker)
                if viewModel.selectedTrendMetric == .estimatedOneRepMax {
                    Text(String(localized: "trends.e1rmCaption"))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
                if viewModel.selectedTrendMetric == .volume {
                    Text(String(localized: "trends.volumeCaption"))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
            }
            trendContent(for: Comparison.TrendSampleDensity.classify(points))
        }
        .accessibilityIdentifier(FCAccessibilityID.trendsExerciseTrendSection)
    }

    @ViewBuilder
    private func trendContent(for density: Comparison.TrendSampleDensity) -> some View {
        switch density {
        case .empty:
            Text(String(localized: "trends.exerciseTrendEmpty"))
                .foregroundStyle(FCSemanticColors.textSecondary)
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
            if viewModel.selectedTrendMetric == .weight, viewModel.isAssistedForSelectedExercise,
                let summary = trendDeltaSummary(points)
            {
                Text(summary)
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
        } else {
            trendRows(points)
        }
    }

    private func metricTrendChart(_ points: [Comparison.SetTrendPoint], dashed: Bool) -> some View {
        let metric = viewModel.selectedTrendMetric
        return TrendLineChart(
            points: points,
            metricLabel: metric.label,
            unit: metric.unit,
            dashed: dashed,
            value: { point in metric.value(for: point).flatMap { Double($0.canonicalString) } }
        )
    }

    /// Point-label text for chart annotations (see `TrendLineChart.pointLabel`).
    static func pointLabel(_ value: Double, unit: String) -> String {
        TrendLineChart.pointLabel(value, unit: unit)
    }

    private func trendRows(_ points: [Comparison.SetTrendPoint]) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
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
    /// (weight/reps/volume, driven by `viewModel.selectedTrendMetric`) -- kept
    /// separate from `trendValueText` below, which is the pre-existing
    /// fixed-field text for the other RecordModes the switcher doesn't
    /// apply to.
    private func metricSingleValueText(_ point: Comparison.SetTrendPoint) -> String {
        let metric = viewModel.selectedTrendMetric
        return metric.value(for: point).map {
            TrendLineChart.pointLabel(NSDecimalNumber(decimal: $0.decimal).doubleValue, unit: metric.unit)
        } ?? "-"
    }

    private func singlePointTrendView(_ point: Comparison.SetTrendPoint) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space1) {
            Text(point.recordMode == .weightReps ? metricSingleValueText(point) : trendValueText(point))
                .fcFont(.numeralLarge)
                .foregroundStyle(FCSemanticColors.textPrimary)
            Text(point.completedAtUTC, style: .date)
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
            Text(String(localized: "trends.exerciseTrendSingleHint"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
        }
    }

    /// M1B-FR-028 units fix -- weight always shows "kg", `.duration`/`.cardio`
    /// go through `DurationTextParser` (never raw seconds), cardio distance
    /// shows "km". Single source used by both the row fallback and the
    /// single-point large-number view so they can never drift apart.
    private func trendValueText(_ point: Comparison.SetTrendPoint) -> String {
        switch point.recordMode {
        case .weightReps:
            return point.maxWeight.map { "\($0.canonicalString) kg" } ?? "-"
        case .reps:
            return point.bestReps.map { "\($0.canonicalString) 次" } ?? "-"
        case .duration:
            guard let duration = point.bestDurationSeconds else { return "-" }
            return DurationTextParser.formatForEditing(secondsText: duration.canonicalString)
        case .cardio:
            var parts: [String] = []
            if let duration = point.bestDurationSeconds {
                parts.append(DurationTextParser.formatForEditing(secondsText: duration.canonicalString))
            }
            if let distance = point.bestDistance {
                parts.append("\(distance.canonicalString) km")
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

    // MARK: - Shared

    private var exercisePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FCPrimitives.space2) {
                ForEach(viewModel.exerciseOptions, id: \.key) { option in
                    FCFilterChip(
                        title: option.name,
                        isSelected: viewModel.selectedExerciseKey == option.key
                    ) {
                        viewModel.selectExercise(key: option.key)
                    }
                }
            }
        }
    }

    private func tabHint(_ text: String) -> some View {
        Text(text)
            .fcFont(.caption)
            .foregroundStyle(FCSemanticColors.textSecondary)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .fcFont(.sectionLabel)
            .foregroundStyle(FCSemanticColors.textSecondary)
    }
}

enum TrendMetric: String, CaseIterable, Identifiable {
    case weight
    case reps
    case volume
    case estimatedOneRepMax

    static func options(for exerciseID: StableExerciseID?) -> [Self] {
        guard let exerciseID, EstimatedOneRepMax.exerciseIDs.contains(exerciseID) else {
            return [.weight, .reps, .volume]
        }
        return allCases
    }

    func resolved(for exerciseID: StableExerciseID?) -> Self {
        Self.options(for: exerciseID).contains(self) ? self : .weight
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weight: return String(localized: "trends.metric.weight")
        case .reps: return String(localized: "trends.metric.reps")
        case .volume: return String(localized: "trends.metric.volume")
        case .estimatedOneRepMax: return String(localized: "trends.metric.e1rm")
        }
    }

    var unit: String {
        switch self {
        case .weight, .volume, .estimatedOneRepMax: return "kg"
        case .reps: return "次"
        }
    }

    func value(for point: Comparison.SetTrendPoint) -> DecimalValue? {
        switch self {
        case .weight, .estimatedOneRepMax: return point.maxWeight
        case .reps: return point.bestReps
        case .volume: return point.volume
        }
    }
}

/// Uses the approved domain calculation without changing PR or ordinary trend points.
enum EstimatedOneRepMaxTrend {
    static func points(exerciseID: StableExerciseID?, sessions: [CompletedSession]) -> [Comparison.SetTrendPoint] {
        guard let exerciseID, EstimatedOneRepMax.exerciseIDs.contains(exerciseID) else { return [] }
        return sessions.sorted {
            if $0.completedAtUTC != $1.completedAtUTC { return $0.completedAtUTC < $1.completedAtUTC }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }.compactMap { session in
            let best = session.exercises.filter { $0.sourceID == exerciseID && $0.recordModeSnapshot == .weightReps }
                .flatMap(\.sets).filter(\.contributesToStatistics).compactMap { set -> DecimalValue? in
                    guard let weight = set.weightValue, let reps = set.repetitionCount else { return nil }
                    return EstimatedOneRepMax.value(weight: weight, reps: reps, exerciseID: exerciseID)
                }.max()
            guard let best else { return nil }
            return Comparison.SetTrendPoint(
                sessionID: session.id, completedAtUTC: session.completedAtUTC, recordMode: .weightReps,
                maxWeight: best, bestReps: nil, bestDurationSeconds: nil, bestDistance: nil, volume: nil,
                weightDelta: nil, asymmetry: nil)
        }
    }
}
