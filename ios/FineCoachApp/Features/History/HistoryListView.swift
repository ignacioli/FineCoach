import SwiftUI

/// Date-range presets for the 训练历史 filter (FR-026).
enum HistoryDateRangePreset: Int, CaseIterable, Identifiable {
    case last7 = 7
    case last30 = 30
    case last90 = 90

    var id: Int { rawValue }

    var title: String {
        String(format: String(localized: "history.filter.lastDaysFormat"), rawValue)
    }

    func range(endingAt today: LocalDate, calendar: Calendar) -> ClosedRange<LocalDate> {
        today.addingDays(-(rawValue - 1), calendar: calendar)...today
    }
}

@MainActor
final class HistoryListViewModel: ObservableObject {
    struct ExerciseOption: Identifiable, Hashable {
        let id: StableExerciseID
        let name: String
        let mode: RecordMode
    }

    struct PersonalBestRow: Identifiable {
        let id: String
        let name: String
        let kind: String
        let value: String
        /// "9月17日" — the session the best comes from.
        let day: String?
        /// "25 kg × 8 次" — the set behind a weight best.
        let detail: String?
    }

    @Published var allSessions: [CompletedSession] = []
    @Published var results: [CompletedSession] = []
    @Published var studentName = ""
    @Published var dateRange: HistoryDateRangePreset?
    @Published var focusFilter: Set<BodyPart> = []
    @Published var exerciseFilter: ExerciseOption?
    /// The two sessions being compared, oldest pick first; picking a third
    /// drops the oldest pick (owner 2026-09-28: in-list selection).
    @Published private(set) var comparisonSelection: [StableUUID] = []
    @Published var isSelectingForComparison = false
    @Published var assistedExerciseIDs: Set<StableExerciseID> = []
    @Published var errorMessage: String?

    let studentID: StableUUID
    private let useCases: HistoryUseCases
    private let studentUseCases: StudentUseCases?
    private let exerciseUseCases: ExerciseLibraryUseCases?
    private let calendarProvider: any LocalCalendarProvider

    init(
        studentID: StableUUID,
        useCases: HistoryUseCases,
        studentUseCases: StudentUseCases? = nil,
        exerciseUseCases: ExerciseLibraryUseCases? = nil,
        calendarProvider: any LocalCalendarProvider = SystemLocalCalendarProvider()
    ) {
        self.studentID = studentID
        self.useCases = useCases
        self.studentUseCases = studentUseCases
        self.exerciseUseCases = exerciseUseCases
        self.calendarProvider = calendarProvider
    }

    var hasFilters: Bool {
        dateRange != nil || !focusFilter.isEmpty || exerciseFilter != nil
    }

    /// Distinct exercises across the full history (for the 动作 filter).
    var exerciseOptions: [ExerciseOption] {
        var seen: [String: ExerciseOption] = [:]
        for session in allSessions {
            for exercise in session.exercises {
                guard let sourceID = exercise.sourceID else { continue }
                let key = "\(sourceID.rawValue)|\(exercise.recordModeSnapshot.rawValue)"
                seen[key] = ExerciseOption(id: sourceID, name: exercise.displayNameSnapshot.value, mode: exercise.recordModeSnapshot)
            }
        }
        return seen.values.sorted { $0.name < $1.name }
    }

    func load() async {
        do {
            allSessions = try await useCases.listHistory(studentID: studentID)
            if studentName.isEmpty, let studentUseCases {
                studentName = (try? await studentUseCases.student(id: studentID).displayName.value) ?? ""
            }
            if let exerciseUseCases {
                let entries = (try? await exerciseUseCases.search(query: "", includeHidden: true)) ?? []
                assistedExerciseIDs = Set(entries.filter { $0.preference?.isAssisted == true }.map(\.id))
            }
            await applyFilters()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }

    func applyFilters() async {
        let calendar = calendarProvider.currentCalendar()
        let today = LocalDate(date: Date(), calendar: calendar)
        let criteria = HistoryFilterCriteria(
            dateRange: dateRange?.range(endingAt: today, calendar: calendar),
            trainingFocus: focusFilter,
            exerciseID: exerciseFilter?.id
        )
        do {
            switch try await useCases.filteredHistory(studentID: studentID, criteria: criteria, calendarProvider: calendarProvider) {
            case .matches(let sessions):
                results = sessions.sorted { $0.completedAtUTC > $1.completedAtUTC }
            case .noMatches:
                results = []
            }
            pickDefaultComparison()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }

    func clearFilters() async {
        dateRange = nil
        focusFilter = []
        exerciseFilter = nil
        await applyFilters()
    }

    /// Default comparison: the newest result and the next-newest one with
    /// the same body-part set (FR-027 compatible), if any; the coach can
    /// re-pick in selection mode.
    private func pickDefaultComparison() {
        let ids = Set(results.map(\.id))
        comparisonSelection = comparisonSelection.filter { ids.contains($0) }
        guard comparisonSelection.count < 2, !isSelectingForComparison else { return }
        guard let newest = results.first else {
            comparisonSelection = []
            return
        }
        let partner = results.dropFirst().first { $0.trainingFocus == newest.trainingFocus } ?? results.dropFirst().first
        comparisonSelection = [newest.id] + (partner.map { [$0.id] } ?? [])
    }

    func toggleComparison(_ id: StableUUID) {
        if let index = comparisonSelection.firstIndex(of: id) {
            comparisonSelection.remove(at: index)
            return
        }
        if comparisonSelection.count >= 2 {
            comparisonSelection.removeFirst()
        }
        comparisonSelection.append(id)
    }

    func isSelectedForComparison(_ id: StableUUID) -> Bool {
        comparisonSelection.contains(id)
    }

    func session(_ id: StableUUID?) -> CompletedSession? {
        id.flatMap { id in results.first { $0.id == id } }
    }

    /// The two picks ordered newer-first, for a stable left/right layout.
    var comparedSessions: [CompletedSession] {
        comparisonSelection.compactMap { session($0) }.sorted { $0.completedAtUTC > $1.completedAtUTC }
    }

    var comparison: Comparison.SessionComparisonResult? {
        let pair = comparedSessions
        guard pair.count == 2 else { return nil }
        return Comparison.compareSessions(pair[0], pair[1])
    }

    /// One best per exercise appearing in the current results, computed over
    /// the student's FULL history (a best that ignored out-of-range sessions
    /// would misstate the record). Assisted exercises read "lower is better".
    var personalBests: [PersonalBestRow] {
        var seen = Set<String>()
        var rows: [PersonalBestRow] = []
        for session in results {
            for exercise in session.exercises {
                guard let sourceID = exercise.sourceID else { continue }
                let mode = exercise.recordModeSnapshot
                let key = "\(sourceID.rawValue)|\(mode.rawValue)"
                guard seen.insert(key).inserted else { continue }
                let direction: Comparison.LoadDirection = assistedExerciseIDs.contains(sourceID)
                    ? .decreaseIsImprovement : .increaseIsImprovement
                let records = Comparison.personalRecords(
                    exerciseID: sourceID,
                    recordMode: mode,
                    across: allSessions,
                    loadDirection: direction
                )
                let completedAt = Dictionary(allSessions.map { ($0.id, $0.completedAtUTC) }, uniquingKeysWith: { first, _ in first })
                if let row = HistoryPresentation.bestRow(
                    key: key,
                    name: exercise.displayNameSnapshot.value,
                    records: records,
                    completedAt: completedAt
                ) {
                    rows.append(row)
                }
            }
        }
        return rows
    }
}

enum HistoryPresentation {
    /// "9月25日 周四"
    static func day(_ instant: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter.string(from: instant)
    }

    /// "大腿、臀 · 12 组 · 58 分钟"
    static func summary(_ session: CompletedSession) -> String {
        var parts: [String] = []
        if let focus = BodyPart.joinedDisplayNames(for: session.trainingFocus, separator: "、") {
            parts.append(focus)
        }
        parts.append(String(format: String(localized: "student.detail.setCountFormat"), session.statistics.completedSetCount))
        parts.append(duration(seconds: Double(session.statistics.displayedDurationSeconds.canonicalString) ?? 0))
        return parts.joined(separator: " · ")
    }

    /// A completed-set list as lines, merging consecutive identical sets:
    /// [30×10, 25×12, 25×12] → ["30kg × 10次", "25kg × 12次 · 2 组"]
    /// (owner 2026-09-28: compare the full set lists of shared exercises).
    static func setRuns(_ sets: [TrainingSet]) -> [String] {
        var runs: [(text: String, count: Int)] = []
        for set in sets where set.contributesToStatistics {
            let text = set.displaySummary
            if let last = runs.last, last.text == text {
                runs[runs.count - 1].count += 1
            } else {
                runs.append((text, 1))
            }
        }
        return runs.map { run in
            run.count > 1
                ? String(format: String(localized: "history.compare.runFormat"), run.text, run.count)
                : run.text
        }
    }

    /// Exercises present in both sessions (same name, as `Comparison`'s
    /// 动作差异 matches), in the first session's order, with each side's
    /// merged set lines.
    static func sharedExercises(_ a: CompletedSession, _ b: CompletedSession) -> [(name: String, a: [String], b: [String])] {
        var seen = Set<String>()
        return a.exercises.compactMap { exercise in
            let name = exercise.displayNameSnapshot.value
            guard seen.insert(name).inserted else { return nil }
            let inB = b.exercises.filter { $0.displayNameSnapshot.value == name }
            guard !inB.isEmpty else { return nil }
            let setsA = a.exercises.filter { $0.displayNameSnapshot.value == name }.flatMap(\.sets)
            return (name, setRuns(setsA), setRuns(inB.flatMap(\.sets)))
        }
    }

    /// "58 分钟"; under a minute shows "1 分钟" (never "0 分钟"), the same
    /// rule as the report card and 训练记录 (owner 2026-09-29).
    static func duration(seconds: Double) -> String {
        String(format: String(localized: "today.durationFormat"), max(1, Int((seconds / 60).rounded())))
    }

    /// One best per exercise: the top weight shown big, with the day and
    /// "重量 × 次数" of the set behind it (most reps at that weight, ties to
    /// the most recent session — resolved in `Comparison.personalRecords`).
    static func bestRow(
        key: String,
        name: String,
        records: Comparison.PersonalRecordSet?,
        completedAt: [StableUUID: Date]
    ) -> HistoryListViewModel.PersonalBestRow? {
        guard let records else { return nil }
        func dayOf(_ sessionID: StableUUID) -> String? {
            completedAt[sessionID].map(PackageDetailPresentation.day)
        }
        if let best = records.mostRepsAtWeight {
            return .init(
                id: key,
                name: name,
                kind: String(localized: "history.pb.highestWeight"),
                value: "\(best.weight.canonicalString) kg",
                day: dayOf(best.sessionID),
                detail: String(
                    format: String(localized: "history.pb.setDetailFormat"),
                    best.weight.canonicalString,
                    best.reps.canonicalString
                )
            )
        }
        if let highest = records.highestWeight {
            return .init(
                id: key,
                name: name,
                kind: String(localized: "history.pb.highestWeight"),
                value: "\(highest.weight.canonicalString) kg",
                day: dayOf(highest.sessionID),
                detail: nil
            )
        }
        if let duration = records.longestDuration {
            return .init(
                id: key,
                name: name,
                kind: String(localized: "history.pb.longestDuration"),
                value: DurationTextParser.formatForEditing(secondsText: duration.seconds.canonicalString),
                day: dayOf(duration.sessionID),
                detail: nil
            )
        }
        if let distance = records.longestDistance {
            return .init(
                id: key,
                name: name,
                kind: String(localized: "history.pb.longestDistance"),
                value: "\(distance.distance.canonicalString) km",
                day: dayOf(distance.sessionID),
                detail: nil
            )
        }
        return nil
    }
}

/// 07 训练历史 (T069i; `32-training-history-v2`, D9): display title + student
/// name, filter chips 日期范围 / 训练重点 / 动作 (each opens a sheet;
/// FR-026, 训练重点 matches any selected part), "已筛选：…" and "N 次训练",
/// result rows → 单次训练详情, an understandable no-match state, 课程比较
/// (two visible session pickers; FR-027 incompatible pairs are shown as
/// 不可比较, never merged) and 个人最佳. 训练趋势 keeps only the per-exercise
/// trend charts.
struct HistoryListView: View {
    private enum FilterSheet {
        case date
        case focus
        case exercise
    }

    @StateObject private var viewModel: HistoryListViewModel
    @Binding var path: [RootDestination]
    @State private var filterSheet: FilterSheet?
    /// Shared-exercise blocks the coach expanded or collapsed, keyed per
    /// compared pair; unset means "first expanded, others collapsed".
    @State private var expandedShared: [String: Bool] = [:]

    init(
        studentID: StableUUID,
        useCases: HistoryUseCases,
        studentUseCases: StudentUseCases? = nil,
        exerciseUseCases: ExerciseLibraryUseCases? = nil,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: HistoryListViewModel(
                studentID: studentID,
                useCases: useCases,
                studentUseCases: studentUseCases,
                exerciseUseCases: exerciseUseCases
            )
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                    Text(String(localized: "history.title"))
                        .fcFont(.titleLarge)
                        .foregroundStyle(FCSemanticColors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if !viewModel.studentName.isEmpty {
                        Text(viewModel.studentName)
                            .fcFont(.headline)
                            .foregroundStyle(FCSemanticColors.textSecondary)
                    }
                }

                filterChips

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                }

                resultsSection
                if viewModel.results.count >= 2 {
                    comparisonSection
                }
                personalBestSection
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .fcBottomSheet(isPresented: filterPresented) {
            filterSheetContent
        }
        .task { await viewModel.load() }
        .onChange(of: path) { _, _ in
            Task { await viewModel.load() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.historyRoot)
    }

    // MARK: Filters

    private var filterChips: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            HStack(spacing: FCPrimitives.space2) {
                FCFilterChip(title: String(localized: "history.filter.date"), isSelected: viewModel.dateRange != nil) {
                    filterSheet = .date
                }
                FCFilterChip(title: String(localized: "history.filter.focus"), isSelected: !viewModel.focusFilter.isEmpty) {
                    filterSheet = .focus
                }
                .accessibilityIdentifier(FCAccessibilityID.trendsFilterFocus)
                FCFilterChip(title: String(localized: "history.filter.exercise"), isSelected: viewModel.exerciseFilter != nil) {
                    filterSheet = .exercise
                }
            }
            if viewModel.hasFilters {
                HStack(alignment: .firstTextBaseline) {
                    Text(filterSummary)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                    Spacer(minLength: FCPrimitives.space2)
                    FCLinkButton(title: String(localized: "history.filter.clear")) {
                        Task { await viewModel.clearFilters() }
                    }
                }
            }
        }
    }

    /// "已筛选：训练重点 大腿、臀 · 近 30 天 · 深蹲"
    private var filterSummary: String {
        var parts: [String] = []
        if let focus = BodyPart.joinedDisplayNames(for: viewModel.focusFilter, separator: "、") {
            parts.append(String(format: String(localized: "history.filter.focusSummaryFormat"), focus))
        }
        if let range = viewModel.dateRange {
            parts.append(range.title)
        }
        if let exercise = viewModel.exerciseFilter {
            parts.append(exercise.name)
        }
        return String(format: String(localized: "history.filter.summaryFormat"), parts.joined(separator: " · "))
    }

    private var filterPresented: Binding<Bool> {
        Binding(get: { filterSheet != nil }, set: { if !$0 { filterSheet = nil } })
    }

    @ViewBuilder
    private var filterSheetContent: some View {
        switch filterSheet {
        case .date:
            FCBottomSheet(title: String(localized: "history.filter.date")) {
                FCFlowLayout(horizontalSpacing: FCPrimitives.space2, verticalSpacing: FCPrimitives.space2 - (44 - 30)) {
                    FCFilterChip(title: String(localized: "history.filter.all"), isSelected: viewModel.dateRange == nil) {
                        viewModel.dateRange = nil
                        applyAndClose()
                    }
                    ForEach(HistoryDateRangePreset.allCases) { preset in
                        FCFilterChip(title: preset.title, isSelected: viewModel.dateRange == preset) {
                            viewModel.dateRange = preset
                            applyAndClose()
                        }
                    }
                }
            }
        case .focus:
            FCBottomSheet(title: String(localized: "history.filter.focus"), subtitle: String(localized: "history.filter.focusHint")) {
                VStack(spacing: FCPrimitives.space3) {
                    FCBodyPartPicker(selection: $viewModel.focusFilter)
                    FCButton(title: String(localized: "history.filter.done")) {
                        applyAndClose()
                    }
                }
            }
        case .exercise:
            FCBottomSheet(title: String(localized: "history.filter.exercise")) {
                ScrollView {
                    VStack(spacing: 0) {
                        FCActionRow(title: String(localized: "history.filter.allExercises"), note: viewModel.exerciseFilter == nil ? String(localized: "history.filter.selected") : nil) {
                            viewModel.exerciseFilter = nil
                            applyAndClose()
                        }
                        FCListRowDivider()
                        ForEach(viewModel.exerciseOptions) { option in
                            FCActionRow(title: option.name, note: viewModel.exerciseFilter == option ? String(localized: "history.filter.selected") : nil) {
                                viewModel.exerciseFilter = option
                                applyAndClose()
                            }
                            FCListRowDivider()
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        case nil:
            EmptyView()
        }
    }

    private func applyAndClose() {
        filterSheet = nil
        Task { await viewModel.applyFilters() }
    }

    // MARK: Results

    @ViewBuilder
    private var resultsSection: some View {
        if viewModel.results.isEmpty {
            VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                Text(String(localized: viewModel.hasFilters ? "history.empty.filteredTitle" : "history.empty.title"))
                    .fcFont(.headline)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                Text(String(localized: viewModel.hasFilters ? "history.empty.filteredBody" : "history.empty.body"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
            .padding(.vertical, FCPrimitives.space4)
            .accessibilityIdentifier(FCAccessibilityID.trendsNoMatches)
        } else {
            VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                HStack(alignment: .center) {
                    FCSectionLabel(String(format: String(localized: "history.countFormat"), viewModel.results.count))
                    Spacer(minLength: FCPrimitives.space2)
                    if viewModel.results.count >= 2 {
                        FCLinkButton(title: String(localized: viewModel.isSelectingForComparison ? "history.compare.done" : "history.compare.select")) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                viewModel.isSelectingForComparison.toggle()
                            }
                        }
                        .accessibilityIdentifier(FCAccessibilityID.historyCompareSelect)
                    }
                }
                VStack(spacing: 0) {
                    FCListRowDivider()
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, session in
                        Button {
                            if viewModel.isSelectingForComparison {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    viewModel.toggleComparison(session.id)
                                }
                            } else {
                                path.append(.sessionDetail(session.id.rawValue))
                            }
                        } label: {
                            HStack(spacing: FCPrimitives.space3) {
                                if viewModel.isSelectingForComparison {
                                    FCSetStateCircle(viewModel.isSelectedForComparison(session.id) ? .completed : .pending)
                                        .transition(.move(edge: .leading).combined(with: .opacity))
                                }
                                VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                                    Text(HistoryPresentation.day(session.completedAtUTC))
                                        .fcFont(.headline)
                                        .foregroundStyle(FCSemanticColors.textPrimary)
                                    Text(HistoryPresentation.summary(session))
                                        .fcFont(.caption)
                                        .foregroundStyle(FCSemanticColors.textSecondary)
                                }
                                Spacer(minLength: FCPrimitives.space2)
                                if !viewModel.isSelectingForComparison {
                                    FCSymbol(.forward)
                                }
                            }
                            .padding(.vertical, FCPrimitives.space3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            viewModel.isSelectingForComparison && viewModel.isSelectedForComparison(session.id) ? .isSelected : []
                        )
                        .accessibilityIdentifier(FCAccessibilityID.historyRow(index))
                        FCListRowDivider()
                    }
                }
            }
        }
    }

    // MARK: 课程比较

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space3) {
            FCSectionLabel(
                viewModel.isSelectingForComparison
                    ? String(format: String(localized: "history.compare.selectedFormat"), viewModel.comparisonSelection.count)
                    : String(localized: "trends.comparisonTitle")
            )
            let pair = viewModel.comparedSessions
            if !pair.isEmpty {
                HStack(alignment: .top, spacing: FCPrimitives.space4) {
                    ForEach(pair) { session in
                        Text(comparisonTitle(session))
                            .fcFont(.headline)
                            .foregroundStyle(FCSemanticColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if pair.count == 1 {
                        Spacer().frame(maxWidth: .infinity)
                    }
                }
            }
            switch viewModel.comparison {
            case .compatible(let detail):
                HStack(alignment: .top, spacing: FCPrimitives.space4) {
                    comparisonColumn(
                        sets: detail.totalSetCountA,
                        reps: detail.totalRepCountA,
                        volume: detail.trainingVolumeA,
                        onlyHere: detail.exercisesOnlyInA
                    )
                    comparisonColumn(
                        sets: detail.totalSetCountB,
                        reps: detail.totalRepCountB,
                        volume: detail.trainingVolumeB,
                        onlyHere: detail.exercisesOnlyInB
                    )
                }
                if pair.count == 2 {
                    sharedExercisesBlock(pair[0], pair[1])
                }
            case .incompatibleTrainingFocus, .differentStudent:
                VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                    FCStatusLabel(.notComparable)
                    Text(String(localized: "trends.comparisonIncompatible"))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
            case nil:
                Text(String(localized: "history.compare.pickTwo"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
            FCListRowDivider()
        }
        .accessibilityIdentifier(FCAccessibilityID.trendsComparisonSection)
    }

    /// Same exercises in both sessions with their full set lists side by
    /// side; the first is expanded, the rest collapsed until tapped.
    @ViewBuilder
    private func sharedExercisesBlock(_ a: CompletedSession, _ b: CompletedSession) -> some View {
        let shared = HistoryPresentation.sharedExercises(a, b)
        if !shared.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                FCSectionLabel(String(localized: "history.compare.sharedTitle"))
                    .padding(.top, FCPrimitives.space2)
                    .padding(.bottom, FCPrimitives.space1)
                ForEach(Array(shared.enumerated()), id: \.element.name) { index, item in
                    let key = "\(a.id.rawValue)|\(b.id.rawValue)|\(item.name)"
                    let isExpanded = expandedShared[key] ?? (index == 0)
                    FCListRowDivider()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            expandedShared[key] = !isExpanded
                        }
                    } label: {
                        HStack(spacing: FCPrimitives.space2) {
                            Text(item.name)
                                .fcFont(.headline)
                                .foregroundStyle(FCSemanticColors.textPrimary)
                            Spacer(minLength: FCPrimitives.space2)
                            FCSymbol(.collapse)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(Text(isExpanded ? "today.resolved.expanded" : "today.resolved.collapsed"))
                    if isExpanded {
                        HStack(alignment: .top, spacing: FCPrimitives.space4) {
                            setLines(item.a)
                            setLines(item.b)
                        }
                        .padding(.bottom, FCPrimitives.space3)
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    private func setLines(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "9月1日 · 大腿、臀"
    private func comparisonTitle(_ session: CompletedSession) -> String {
        let day = PackageDetailPresentation.day(session.completedAtUTC)
        guard let focus = BodyPart.joinedDisplayNames(for: session.trainingFocus, separator: "、") else {
            return day
        }
        return "\(day) · \(focus)"
    }

    private func comparisonColumn(
        sets: Int,
        reps: DecimalValue?,
        volume: DecimalValue?,
        onlyHere: [NormalizedName]
    ) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            Text(String(format: String(localized: "history.compare.setsFormat"), sets))
            if let reps {
                Text(String(format: String(localized: "history.compare.repsFormat"), reps.canonicalString))
            }
            if let volume {
                Text(String(format: String(localized: "history.compare.volumeFormat"), volume.canonicalString))
            }
            Text(onlyHere.isEmpty
                ? String(localized: "history.compare.noDifference")
                : String(format: String(localized: "history.compare.onlyHereFormat"), onlyHere.map(\.value).joined(separator: "、")))
        }
        .fcFont(.callout, weight: .regular)
        .foregroundStyle(FCSemanticColors.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 个人最佳

    @ViewBuilder
    private var personalBestSection: some View {
        let rows = viewModel.personalBests
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                FCSectionLabel(String(localized: "history.pb.title"))
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(alignment: .center, spacing: FCPrimitives.space4) {
                            VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                                Text(row.name)
                                    .fcFont(.headline)
                                    .foregroundStyle(FCSemanticColors.textPrimary)
                                Text(row.kind)
                                    .fcFont(.caption)
                                    .foregroundStyle(FCSemanticColors.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.value)
                                .fcFont(.titleEmphasis)
                                .foregroundStyle(FCSemanticColors.textPrimary)
                                .lineLimit(1)
                            VStack(alignment: .trailing, spacing: FCPrimitives.space1) {
                                if let day = row.day {
                                    Text(day)
                                        .fcFont(.caption)
                                        .foregroundStyle(FCSemanticColors.textSecondary)
                                }
                                if let detail = row.detail {
                                    Text(detail)
                                        .fcFont(.caption)
                                        .foregroundStyle(FCSemanticColors.textSecondary)
                                }
                            }
                            .frame(minWidth: 88, alignment: .trailing)
                        }
                        .padding(.vertical, FCPrimitives.space3)
                        .accessibilityElement(children: .combine)
                        FCListRowDivider()
                    }
                }
                Text(String(localized: "history.pb.shareNote"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
            .accessibilityIdentifier(FCAccessibilityID.trendsPersonalRecordSection)
        }
    }
}
