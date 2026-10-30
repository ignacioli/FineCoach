import SwiftUI

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var rows: [TodayOrderedAppointment] = []
    @Published var studentNames: [StableUUID: String] = [:]
    @Published var errorMessage: String?
    /// False until the first successful reload. A freshly built view model has
    /// empty `rows`/`inProgress`, so without this gate Today would render its
    /// empty state before the first load returns (C15 walkthrough follow-up).
    @Published private(set) var hasCompletedInitialLoad = false
    @Published var isResolvedExpanded = false
    /// Every Student currently training, oldest start first (M1A-FR-018
    /// revision; owner decision 2026-10-22: one hint-bar row per Student).
    @Published var inProgress: [InProgressTrainingSummary] = []
    /// Students whose active 课包 is expired or out of credits (M1B-FR-014):
    /// today only warns briefly (NFR-005), never shows the balance.
    @Published var packageAlertStudentIDs: Set<StableUUID> = []

    private let appointmentUseCases: AppointmentUseCases
    private let studentUseCases: StudentUseCases
    private let creditLedgerUseCases: CreditLedgerUseCases?

    init(
        appointmentUseCases: AppointmentUseCases,
        studentUseCases: StudentUseCases,
        creditLedgerUseCases: CreditLedgerUseCases? = nil
    ) {
        self.appointmentUseCases = appointmentUseCases
        self.studentUseCases = studentUseCases
        self.creditLedgerUseCases = creditLedgerUseCases
        self.todayDate = appointmentUseCases.todayLocalDate()
        self.courseActions = CourseActions(
            appointmentUseCases: appointmentUseCases,
            creditLedgerUseCases: creditLedgerUseCases
        )
    }

    let courseActions: CourseActions

    let todayDate: LocalDate

    /// Everything except the in-progress row, which the hero card shows.
    var visibleRows: [TodayOrderedAppointment] {
        rows.filter { $0.section != .inProgress }
    }

    var overdueRows: [TodayOrderedAppointment] {
        rows.filter { $0.section == .overdue }
    }

    var nextUpRow: TodayOrderedAppointment? {
        rows.first { $0.section == .nextUp }
    }

    var remainingRows: [TodayOrderedAppointment] {
        rows.filter { $0.section == .remainingToday }
    }

    var resolvedRows: [TodayOrderedAppointment] {
        rows.filter { $0.section == .resolved }
    }

    func displayName(for studentID: StableUUID) -> String {
        studentNames[studentID] ?? ""
    }

    /// The empty state is a load result, never a placeholder: before the first
    /// successful load the conditional content stays empty instead.
    var showsEmptyState: Bool {
        TodayEmptyStatePresentation.showsEmptyState(
            hasCompletedInitialLoad: hasCompletedInitialLoad,
            visibleRows: visibleRows,
            inProgress: inProgress
        )
    }

    func reload() async {
        do {
            rows = try await appointmentUseCases.todayOrdering()
            inProgress = try await studentUseCases.inProgressTrainings()
            var names = studentNames
            for row in rows where names[row.appointment.studentID] == nil {
                if let student = try? await studentUseCases.student(id: row.appointment.studentID) {
                    names[row.appointment.studentID] = student.displayName.value
                }
            }
            studentNames = names
            await reloadPackageAlerts()
            hasCompletedInitialLoad = true
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "today.error.generic")
        }
    }

    private func reloadPackageAlerts() async {
        guard let creditLedgerUseCases else {
            packageAlertStudentIDs = []
            return
        }
        var alerts: Set<StableUUID> = []
        for studentID in Set(rows.map(\.appointment.studentID)) {
            guard let package = try? await creditLedgerUseCases.activePackage(studentID: studentID) else {
                continue
            }
            if package.isExpired(asOf: todayDate)
                || package.isBalanceLow(ledgerBalance: package.remainingCreditsCache)
            {
                alerts.insert(studentID)
            }
        }
        packageAlertStudentIDs = alerts
    }

    func present(_ message: String) {
        errorMessage = message
    }
}

enum TodayEmptyStatePresentation {
    /// Only a completed load with nothing to show is an empty Today. Split out
    /// so the first-load gate is unit-testable without building the Core
    /// Data-backed view model.
    static func showsEmptyState(
        hasCompletedInitialLoad: Bool,
        visibleRows: [TodayOrderedAppointment],
        inProgress: [InProgressTrainingSummary]
    ) -> Bool {
        hasCompletedInitialLoad && visibleRows.isEmpty && inProgress.isEmpty
    }
}

enum TodayRowStatusPresentation {
    static func title(for row: TodayOrderedAppointment) -> String {
        switch row.appointment.status {
        case .completed:
            return String(localized: "today.status.completed")
        case .cancelled:
            return String(localized: "today.status.cancelled")
        case .absent:
            return String(localized: "today.status.absent")
        case .inProgress:
            return String(localized: "today.inProgress.badge")
        case .scheduled:
            return row.section == .overdue
                ? String(localized: "today.status.overdue")
                : String(localized: "today.status.pending")
        }
    }
}

/// 01 今日 (T069a; `01-today`, `18-course-action-sheet`): display title +
/// date with the calendar entry on the title row, the 今日/学员 switch
/// below, one dark hero card for the Students training in progress (single-row
/// for 1, W08-a multi-row for 2+; owner decision 2026-10-22), the large
/// "下一节课" row, compact rows for the rest, "已处理 · N", and the D1 course
/// action sheet opened by tapping any scheduled row.
struct TodayView: View {
    @StateObject private var viewModel: TodayViewModel
    @StateObject private var insightsModel: InsightsViewModel
    @Binding var rootTab: RootTab
    @Binding var path: [RootDestination]
    @State private var sheetAppointment: Appointment?

    init(
        appointmentUseCases: AppointmentUseCases,
        studentUseCases: StudentUseCases,
        creditLedgerUseCases: CreditLedgerUseCases? = nil,
        insightUseCases: InsightUseCases? = nil,
        exerciseUseCases: ExerciseLibraryUseCases? = nil,
        historyUseCases: HistoryUseCases? = nil,
        rootTab: Binding<RootTab>,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: TodayViewModel(
                appointmentUseCases: appointmentUseCases,
                studentUseCases: studentUseCases,
                creditLedgerUseCases: creditLedgerUseCases
            )
        )
        _insightsModel = StateObject(
            wrappedValue: InsightsViewModel(
                useCases: insightUseCases, students: studentUseCases,
                exercises: exerciseUseCases, history: historyUseCases))
        _rootTab = rootTab

        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                header
                RootSegmentSwitch(rootTab: $rootTab)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                }

                if !viewModel.inProgress.isEmpty {
                    inProgressHero(viewModel.inProgress)
                }

                if viewModel.showsEmptyState {
                    emptyState
                } else {
                    appointmentSections
                }
                insightsSection
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .background(FCSemanticColors.surfacePage)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.todayRoot)
        .courseActionSheet(
            appointment: $sheetAppointment,
            path: $path,
            actions: viewModel.courseActions,
            studentName: { viewModel.displayName(for: $0) },
            onChanged: { await viewModel.reload() },
            onError: { viewModel.present($0) }
        )
        .task { await viewModel.reload() }
        .task { await insightsModel.reload() }
        .onDisappear { insightsModel.endUndoWindows() }
        .onReceive(NotificationCenter.default.publisher(for: InsightsViewModel.didUnsnooze)) { _ in
            Task { await insightsModel.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: InsightsViewModel.didSnooze)) {
            insightsModel.removeSnoozed($0)
        }
        .onChange(of: path) { _, _ in
            Task { await insightsModel.reload() }
            Task { await viewModel.reload() }
        }
    }

    @ViewBuilder
    private var insightsSection: some View {
        let selection = TodayInsightSelection(insightsModel.insights)
        if !selection.rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                InsightSectionView(
                    model: insightsModel, title: String(localized: "insights.section.title"),
                    rows: selection.rows, context: .today, path: $path)
                if selection.showsAll {
                    FCGroupEntryRow(title: String(localized: "insights.section.all"), count: selection.totalCount) {
                        path.append(.insights)
                    }
                    .accessibilityIdentifier(FCAccessibilityID.todayAllInsights)
                }
            }
            .accessibilityIdentifier(FCAccessibilityID.todayInsights)
        }
        if let error = insightsModel.errorMessage {
            Text(error).fcFont(.caption).foregroundStyle(FCSemanticColors.statusDestructive)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space1) {
            HStack(alignment: .center) {
                Text(String(localized: "today.title"))
                    .fcFont(.display)
                    .foregroundStyle(FCSemanticColors.actionPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                FCTitleAddButton(accessibilityLabel: String(localized: "today.addAppointment")) {
                    path.append(.appointmentEditor(.create(studentID: nil, date: viewModel.todayDate)))
                }
                .accessibilityIdentifier(FCAccessibilityID.todayAddAppointment)
                FCTitleIconButton(systemImage: "calendar", accessibilityLabel: String(localized: "calendar.title")) {
                    path.append(.calendar)
                }
                .accessibilityIdentifier(FCAccessibilityID.todayCalendarEntry)
                FCTitleIconButton(systemImage: "gearshape", accessibilityLabel: String(localized: "settings.entry")) {
                    path.append(.settings)
                }
                .accessibilityIdentifier(FCAccessibilityID.settingsEntry)
            }
            Text(TodayDatePresentation.longDay(viewModel.todayDate))
                .fcFont(.callout, weight: .regular)
                .foregroundStyle(FCSemanticColors.textSecondary)
        }
        .padding(.top, FCPrimitives.space4)
    }

    private var emptyState: some View {
        VStack(spacing: FCPrimitives.space2) {
            FCAmbientEmptyScene(side: 220)
            Text(String(localized: "today.empty.title"))
                .fcFont(.headline)
                .foregroundStyle(FCSemanticColors.actionPrimary)
            Text(String(localized: "today.empty.body"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, FCPrimitives.space4)
        .accessibilityIdentifier(FCAccessibilityID.todayEmptyState)
    }

    /// 1 Student: the unchanged 01 single-row hero card. 2+: the W08-a
    /// multi-row variant, one independent row per Student, oldest start first
    /// (`inProgressTrainings()` already sorts by `startedAtUTC`, see
    /// `StudentManagedObjectMapping.inProgressSessions`).
    private func inProgressHero(_ summaries: [InProgressTrainingSummary]) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if summaries.count == 1, let summary = summaries.first {
                FCHeroCard(
                    badgeText: String(localized: "today.inProgress.badge"),
                    title: TodayRowPresentation.nameAndFocus(
                        summary.studentDisplayName,
                        summary.trainingFocus
                    ),
                    subtitle: elapsedText(summary, now: context.date),
                    actionTitle: String(localized: "today.inProgress.continue")
                ) {
                    path.append(.activeSession(summary.studentID.rawValue))
                }
                .accessibilityIdentifier(FCAccessibilityID.todayInProgress)
            } else {
                FCHeroCard(
                    badgeText: String(
                        format: String(localized: "today.inProgress.multiBadgeFormat"),
                        summaries.count
                    ),
                    rows: summaries.map { summary in
                        FCHeroCard.Row(
                            id: summary.studentID.rawValue.uuidString,
                            title: TodayRowPresentation.nameAndFocus(
                                summary.studentDisplayName,
                                summary.trainingFocus
                            ),
                            subtitle: elapsedText(summary, now: context.date),
                            actionTitle: String(localized: "today.inProgress.rowContinue"),
                            accessibilityIdentifier: FCAccessibilityID.todayInProgressRow(
                                summary.studentID
                            )
                        )
                    },
                    onRowAction: { id in
                        guard let studentID = UUID(uuidString: id) else { return }
                        path.append(.activeSession(studentID))
                    }
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(FCAccessibilityID.todayInProgress)
            }
        }
    }

    private func elapsedText(_ summary: InProgressTrainingSummary, now: Date) -> String {
        summary.elapsedMinutes(now: now).map {
            String(format: String(localized: "today.inProgress.elapsedFormat"), $0)
        } ?? ""
    }

    // MARK: Appointment sections

    @ViewBuilder
    private var appointmentSections: some View {
        if !viewModel.overdueRows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                FCListRowDivider()
                ForEach(viewModel.overdueRows, id: \.appointment.id) { row in
                    compactRow(row)
                    FCListRowDivider()
                }
            }
        }

        if let next = viewModel.nextUpRow {
            VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                FCSectionLabel(String(localized: "today.section.nextUp"))
                FCListRowDivider()
                nextUpRow(next)
            }
        }

        if !viewModel.remainingRows.isEmpty {
            VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                FCSectionLabel(String(localized: "today.section.remaining"))
                VStack(alignment: .leading, spacing: 0) {
                    FCListRowDivider()
                    ForEach(viewModel.remainingRows, id: \.appointment.id) { row in
                        compactRow(row)
                        FCListRowDivider()
                    }
                }
            }
        }

        if !viewModel.resolvedRows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                FCGroupEntryRow(
                    title: String(localized: "today.section.resolved"),
                    count: viewModel.resolvedRows.count
                ) {
                    viewModel.isResolvedExpanded.toggle()
                }
                .accessibilityIdentifier(FCAccessibilityID.todayResolvedFold)
                .accessibilityValue(
                    Text(viewModel.isResolvedExpanded ? "today.resolved.expanded" : "today.resolved.collapsed"))
                if viewModel.isResolvedExpanded {
                    FCListRowDivider()
                    ForEach(viewModel.resolvedRows, id: \.appointment.id) { row in
                        compactRow(row)
                        FCListRowDivider()
                    }
                }
            }
        }
    }

    /// "下一节课": large time on its own line, then name, then
    /// "时长 · 部位", trailing `›` (01 #4).
    private func nextUpRow(_ row: TodayOrderedAppointment) -> some View {
        let appointment = row.appointment
        return Button {
            openSheet(appointment)
        } label: {
            HStack(spacing: FCPrimitives.space2) {
                VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                    Text(appointment.startTime.canonicalString)
                        .fcFont(.title)
                        .foregroundStyle(FCSemanticColors.textPrimary)
                    Text(viewModel.displayName(for: appointment.studentID))
                        .fcFont(.body)
                        .foregroundStyle(FCSemanticColors.textPrimary)
                    Text(TodayRowPresentation.durationAndFocus(appointment))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                    if viewModel.packageAlertStudentIDs.contains(appointment.studentID) {
                        FCStatusLabel(.coursePackageInvalid)
                    }
                }
                Spacer(minLength: FCPrimitives.space2)
                FCSymbol(.forward)
            }
            .padding(.vertical, FCPrimitives.space3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(appointment.status != .scheduled)
        .accessibilityIdentifier(FCAccessibilityID.todayRow(appointment.id))
    }

    /// Compact row: time · name · 部位, status text; scheduled rows open the
    /// course action sheet (D1) and show `›`.
    private func compactRow(_ row: TodayOrderedAppointment) -> some View {
        let appointment = row.appointment
        let isActionable = appointment.status == .scheduled
        return Button {
            openSheet(appointment)
        } label: {
            HStack(spacing: FCPrimitives.space3) {
                Text(appointment.startTime.canonicalString)
                    .fcFont(.callout, weight: .semibold)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                    Text(
                        TodayRowPresentation.nameAndFocus(
                            viewModel.displayName(for: appointment.studentID), appointment.trainingFocus)
                    )
                    .fcFont(.body)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .lineLimit(1)
                    if viewModel.packageAlertStudentIDs.contains(appointment.studentID) {
                        FCStatusLabel(.coursePackageInvalid)
                    }
                }
                Spacer(minLength: FCPrimitives.space2)
                if row.section == .overdue {
                    FCStatusLabel(.overdue)
                } else {
                    Text(TodayRowStatusPresentation.title(for: row))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
                if isActionable {
                    FCSymbol(.forward)
                }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isActionable)
        .accessibilityIdentifier(FCAccessibilityID.todayRow(appointment.id))
    }

    private func openSheet(_ appointment: Appointment) {
        guard appointment.status == .scheduled else { return }
        sheetAppointment = appointment
    }
}

enum TodayDatePresentation {
    static func longDay(_ date: LocalDate) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        let instant = date.startOfDay(calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 · EEE"
        return formatter.string(from: instant)
    }
}
