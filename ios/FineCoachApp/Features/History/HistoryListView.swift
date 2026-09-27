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
    }

    @Published var allSessions: [CompletedSession] = []
    @Published var results: [CompletedSession] = []
    @Published var studentName = ""
    @Published var dateRange: HistoryDateRangePreset?
    @Published var focusFilter: Set<BodyPart> = []
    @Published var exerciseFilter: ExerciseOption?
    @Published var comparisonA: StableUUID?
    @Published var comparisonB: StableUUID?
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
    /// change either side.
    private func pickDefaultComparison() {
        let ids = Set(results.map(\.id))
        if let a = comparisonA, let b = comparisonB, ids.contains(a), ids.contains(b) {
            return
        }
        guard let newest = results.first else {
            comparisonA = nil
            comparisonB = nil
            return
        }
        comparisonA = newest.id
        comparisonB = results.dropFirst().first { $0.trainingFocus == newest.trainingFocus }?.id
            ?? results.dropFirst().first?.id
    }

    func session(_ id: StableUUID?) -> CompletedSession? {
        id.flatMap { id in results.first { $0.id == id } }
    }

    var comparison: Comparison.SessionComparisonResult? {
        guard let a = session(comparisonA), let b = session(comparisonB), a.id != b.id else { return nil }
        return Comparison.compareSessions(a, b)
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
                if let row = HistoryPresentation.bestRow(key: key, name: exercise.displayNameSnapshot.value, records: records) {
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
        if let seconds = Double(session.statistics.displayedDurationSeconds.canonicalString), seconds > 0 {
            parts.append(String(format: String(localized: "today.durationFormat"), Int((seconds / 60).rounded())))
        }
        return parts.joined(separator: " · ")
    }

    static func bestRow(key: String, name: String, records: Comparison.PersonalRecordSet?) -> HistoryListViewModel.PersonalBestRow? {
        guard let records else { return nil }
        if let highest = records.highestWeight {
            return .init(id: key, name: name, kind: String(localized: "history.pb.highestWeight"), value: "\(highest.weight.canonicalString) kg")
        }
        if let reps = records.mostRepsAtWeight {
            return .init(id: key, name: name, kind: String(localized: "history.pb.mostReps"), value: "\(reps.reps.canonicalString) 次")
        }
        if let duration = records.longestDuration {
            return .init(
                id: key,
                name: name,
                kind: String(localized: "history.pb.longestDuration"),
                value: DurationTextParser.formatForEditing(secondsText: duration.seconds.canonicalString)
            )
        }
        if let distance = records.longestDistance {
            return .init(id: key, name: name, kind: String(localized: "history.pb.longestDistance"), value: "\(distance.distance.canonicalString) km")
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
                FCSectionLabel(String(format: String(localized: "history.countFormat"), viewModel.results.count))
                VStack(spacing: 0) {
                    FCListRowDivider()
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, session in
                        Button {
                            path.append(.sessionDetail(session.id.rawValue))
                        } label: {
                            HStack(spacing: FCPrimitives.space2) {
                                VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                                    Text(HistoryPresentation.day(session.completedAtUTC))
                                        .fcFont(.headline)
                                        .foregroundStyle(FCSemanticColors.textPrimary)
                                    Text(HistoryPresentation.summary(session))
                                        .fcFont(.caption)
                                        .foregroundStyle(FCSemanticColors.textSecondary)
                                }
                                Spacer(minLength: FCPrimitives.space2)
                                FCSymbol(.forward)
                            }
                            .padding(.vertical, FCPrimitives.space3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
            FCSectionLabel(String(localized: "trends.comparisonTitle"))
            HStack(alignment: .top, spacing: FCPrimitives.space4) {
                sessionPicker(selection: $viewModel.comparisonA)
                sessionPicker(selection: $viewModel.comparisonB)
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

    private func sessionPicker(selection: Binding<StableUUID?>) -> some View {
        Menu {
            ForEach(viewModel.results) { session in
                Button("\(HistoryPresentation.day(session.completedAtUTC)) · \(BodyPart.joinedDisplayNames(for: session.trainingFocus, separator: "、") ?? String(localized: "student.list.noFocus"))") {
                    selection.wrappedValue = session.id
                }
            }
        } label: {
            HStack(spacing: FCPrimitives.space1) {
                Text(pickerTitle(viewModel.session(selection.wrappedValue)))
                    .fcFont(.headline)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .multilineTextAlignment(.leading)
                FCSymbol(.collapse)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityLabel(Text(String(localized: "history.compare.choose")))
        .accessibilityValue(Text(pickerTitle(viewModel.session(selection.wrappedValue))))
    }

    private func pickerTitle(_ session: CompletedSession?) -> String {
        guard let session else {
            return String(localized: "history.compare.choose")
        }
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
                FCSectionLabel(String(localized: "trends.personalRecordTitle"))
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
                                .frame(maxWidth: .infinity, alignment: .leading)
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
