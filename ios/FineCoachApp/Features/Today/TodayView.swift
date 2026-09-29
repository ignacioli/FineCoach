import SwiftUI

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var rows: [TodayOrderedAppointment] = []
    @Published var studentNames: [StableUUID: String] = [:]
    @Published var errorMessage: String?
    @Published var isResolvedExpanded = false
    /// The training in progress, whether or not it started from an
    /// appointment (T063 01 #1).
    @Published var inProgress: InProgressTrainingSummary?
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

    func reload() async {
        do {
            rows = try await appointmentUseCases.todayOrdering()
            inProgress = try await studentUseCases.inProgressTraining()
            var names = studentNames
            for row in rows where names[row.appointment.studentID] == nil {
                if let student = try? await studentUseCases.student(id: row.appointment.studentID) {
                    names[row.appointment.studentID] = student.displayName.value
                }
            }
            studentNames = names
            await reloadPackageAlerts()
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
/// below, the dark hero card for a training in progress, the large
/// "下一节课" row, compact rows for the rest, "已处理 · N", and the D1
/// course action sheet opened by tapping any scheduled row.
struct TodayView: View {
    @StateObject private var viewModel: TodayViewModel
    @Binding var rootTab: RootTab
    @Binding var path: [RootDestination]
    @State private var sheetAppointment: Appointment?

    init(
        appointmentUseCases: AppointmentUseCases,
        studentUseCases: StudentUseCases,
        creditLedgerUseCases: CreditLedgerUseCases? = nil,
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

                if let inProgress = viewModel.inProgress {
                    inProgressCard(inProgress)
                }

                if viewModel.visibleRows.isEmpty, viewModel.inProgress == nil {
                    emptyState
                } else {
                    appointmentSections
                }
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .background(FCSemanticColors.surfacePage)
        .toolbar(.hidden, for: .navigationBar)
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
        .onChange(of: path) { _, _ in
            Task { await viewModel.reload() }
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
                FCTitleIconButton(systemImage: "calendar", accessibilityLabel: String(localized: "calendar.title")) {
                    path.append(.calendar)
                }
                .accessibilityIdentifier(FCAccessibilityID.todayCalendarEntry)
            }
            Text(TodayDatePresentation.longDay(viewModel.todayDate))
                .fcFont(.callout, weight: .regular)
                .foregroundStyle(FCSemanticColors.textSecondary)
        }
        .padding(.top, FCPrimitives.space4)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            Text(String(localized: "today.empty.title"))
                .fcFont(.headline)
                .foregroundStyle(FCSemanticColors.textPrimary)
            Text(String(localized: "today.empty.body"))
                .fcFont(.callout, weight: .regular)
                .foregroundStyle(FCSemanticColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, FCPrimitives.space4)
    }

    private func inProgressCard(_ summary: InProgressTrainingSummary) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            FCHeroCard(
                badgeText: String(localized: "today.inProgress.badge"),
                title: TodayRowPresentation.nameAndFocus(summary.studentDisplayName, summary.trainingFocus),
                subtitle: summary.elapsedMinutes(now: context.date).map {
                    String(format: String(localized: "today.inProgress.elapsedFormat"), $0)
                } ?? "",
                actionTitle: String(localized: "today.inProgress.continue")
            ) {
                path.append(.activeSession(summary.studentID.rawValue))
            }
        }
        .accessibilityIdentifier(FCAccessibilityID.todayInProgress)
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
                .accessibilityValue(Text(viewModel.isResolvedExpanded ? "today.resolved.expanded" : "today.resolved.collapsed"))
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
                    Text(TodayRowPresentation.nameAndFocus(viewModel.displayName(for: appointment.studentID), appointment.trainingFocus))
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
