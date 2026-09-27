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
    }

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
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "today.error.generic")
        }
    }

    @discardableResult
    func startTraining(appointmentID: StableUUID) async -> StableUUID? {
        do {
            let session = try await appointmentUseCases.startTraining(appointmentID: appointmentID)
            await reload()
            return session.studentID
        } catch {
            errorMessage = String(localized: "today.error.generic")
            return nil
        }
    }

    func cancel(appointmentID: StableUUID) async {
        do {
            _ = try await appointmentUseCases.cancel(appointmentID: appointmentID, reason: nil)
            await reload()
        } catch {
            errorMessage = String(localized: "today.error.generic")
        }
    }

    func markAbsent(appointmentID: StableUUID, creditChoice: AbsentCreditChoice) async {
        do {
            let updated = try await appointmentUseCases.markAbsent(
                appointmentID: appointmentID,
                creditChoice: creditChoice
            )
            // M1B-FR-014: absence handling is never blocked by the credit ledger --
            // if there is no active package (or the ledger write itself fails), the
            // absence status change above still stands; this is a best-effort
            // side effect, not a precondition of markAbsent succeeding.
            if creditChoice == .charged, let creditLedgerUseCases {
                if let activePackage = try? await creditLedgerUseCases.activePackage(studentID: updated.studentID) {
                    _ = try? await creditLedgerUseCases.applyAbsence(
                        packageID: activePackage.id,
                        appointmentID: appointmentID,
                        creditChoice: creditChoice
                    )
                }
            }
            await reload()
        } catch {
            errorMessage = String(localized: "today.error.generic")
        }
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
    @State private var isChoosingAbsence = false
    @State private var isConfirmingCancel = false

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
        .fcBottomSheet(isPresented: sheetPresented) {
            if let appointment = sheetAppointment {
                courseSheet(appointment)
            }
        }
        .fcConfirmationDialog(isPresented: $isConfirmingCancel) {
            FCConfirmationDialog(
                title: String(localized: "today.cancelConfirm.title"),
                message: String(localized: "today.cancelConfirm.message"),
                cancelAction: .init(title: String(localized: "today.cancelConfirm.keep")) {
                    isConfirmingCancel = false
                },
                confirmAction: .init(title: String(localized: "today.cancelConfirm.confirm")) {
                    let appointment = sheetAppointment
                    isConfirmingCancel = false
                    closeSheet()
                    if let appointment {
                        Task { await viewModel.cancel(appointmentID: appointment.id) }
                    }
                }
            )
        }
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
                Text(TodayRowPresentation.nameAndFocus(viewModel.displayName(for: appointment.studentID), appointment.trainingFocus))
                    .fcFont(.body)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .lineLimit(1)
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

    // MARK: Course action sheet (D1)

    private var sheetPresented: Binding<Bool> {
        Binding(
            get: { sheetAppointment != nil && !isConfirmingCancel },
            set: { if !$0 { closeSheet() } }
        )
    }

    private func openSheet(_ appointment: Appointment) {
        guard appointment.status == .scheduled else { return }
        isChoosingAbsence = false
        sheetAppointment = appointment
    }

    private func closeSheet() {
        sheetAppointment = nil
        isChoosingAbsence = false
    }

    private func courseSheet(_ appointment: Appointment) -> some View {
        FCBottomSheet(
            title: String(
                format: String(localized: "today.sheet.titleFormat"),
                appointment.startTime.canonicalString,
                appointment.durationMinutes
            ),
            titleStyle: .title,
            subtitle: TodayRowPresentation.nameAndFocus(viewModel.displayName(for: appointment.studentID), appointment.trainingFocus),
            accessory: {
                Text(String(localized: "today.status.pending"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
        ) {
            if isChoosingAbsence {
                absenceChoices(appointment)
            } else {
                courseActions(appointment)
            }
        }
    }

    private func courseActions(_ appointment: Appointment) -> some View {
        VStack(spacing: 0) {
            FCButton(title: String(localized: "today.action.start")) {
                closeSheet()
                Task {
                    if let studentID = await viewModel.startTraining(appointmentID: appointment.id) {
                        path.append(.activeSession(studentID.rawValue))
                    }
                }
            }
            .padding(.bottom, FCPrimitives.space2)
            FCActionRow(
                title: String(localized: "today.action.markAbsent"),
                note: String(localized: "today.sheet.absentNote")
            ) {
                isChoosingAbsence = true
            }
            FCListRowDivider()
            FCActionRow(title: String(localized: "today.action.edit")) {
                closeSheet()
                path.append(.appointmentEditor(.edit(appointment.id.rawValue)))
            }
            FCListRowDivider()
            FCActionRow(
                title: String(localized: "today.action.cancelThis"),
                note: String(localized: "today.sheet.cancelNote"),
                role: .destructive
            ) {
                isConfirmingCancel = true
            }
        }
    }

    /// "标记缺席" second step: 不扣课 listed first as the no-consequence
    /// default; 扣课 is the deliberate second choice.
    private func absenceChoices(_ appointment: Appointment) -> some View {
        VStack(spacing: 0) {
            FCSectionLabel(String(localized: "today.action.markAbsent"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, FCPrimitives.space2)
            FCListRowDivider()
            FCActionRow(title: String(localized: "today.action.markAbsentNotCharged")) {
                closeSheet()
                Task { await viewModel.markAbsent(appointmentID: appointment.id, creditChoice: .notCharged) }
            }
            FCListRowDivider()
            FCActionRow(title: String(localized: "today.action.markAbsentCharged")) {
                closeSheet()
                Task { await viewModel.markAbsent(appointmentID: appointment.id, creditChoice: .charged) }
            }
            FCListRowDivider()
            FCLinkButton(title: String(localized: "today.sheet.back")) {
                isChoosingAbsence = false
            }
            .frame(maxWidth: .infinity)
            .padding(.top, FCPrimitives.space2)
        }
    }
}

enum TodayRowPresentation {
    /// "张伟 · 大腿、臀", or just the name when no focus is set.
    static func nameAndFocus(_ name: String, _ focus: Set<BodyPart>) -> String {
        guard let parts = BodyPart.joinedDisplayNames(for: focus, separator: "、") else {
            return name
        }
        return "\(name) · \(parts)"
    }

    /// "60 分钟 · 大腿、臀"
    static func durationAndFocus(_ appointment: Appointment) -> String {
        let duration = String(format: String(localized: "today.durationFormat"), appointment.durationMinutes)
        guard let parts = BodyPart.joinedDisplayNames(for: appointment.trainingFocus, separator: "、") else {
            return duration
        }
        return "\(duration) · \(parts)"
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
