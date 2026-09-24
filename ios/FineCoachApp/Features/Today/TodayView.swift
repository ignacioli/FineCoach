import SwiftUI

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var rows: [TodayOrderedAppointment] = []
    @Published var studentNames: [StableUUID: String] = [:]
    @Published var errorMessage: String?
    @Published var isResolvedExpanded = false

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

    var inProgressRow: TodayOrderedAppointment? {
        rows.first { $0.section == .inProgress }
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

struct TodayView: View {
    @StateObject private var viewModel: TodayViewModel
    @Binding var path: [RootDestination]

    init(
        appointmentUseCases: AppointmentUseCases,
        studentUseCases: StudentUseCases,
        creditLedgerUseCases: CreditLedgerUseCases? = nil,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: TodayViewModel(
                appointmentUseCases: appointmentUseCases,
                studentUseCases: studentUseCases,
                creditLedgerUseCases: creditLedgerUseCases
            )
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                header

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(FCSemanticColors.destructive)
                }

                if viewModel.rows.isEmpty {
                    emptyState
                } else {
                    if let inProgress = viewModel.inProgressRow {
                        inProgressCard(inProgress)
                    }

                    if !viewModel.overdueRows.isEmpty {
                        ForEach(viewModel.overdueRows, id: \.appointment.id) { row in
                            appointmentRow(row)
                        }
                    }

                    if let next = viewModel.nextUpRow {
                        sectionLabel(String(localized: "today.section.nextUp"))
                        appointmentRow(next, emphasized: true)
                    }

                    if !viewModel.remainingRows.isEmpty {
                        sectionLabel(String(localized: "today.section.remaining"))
                        ForEach(viewModel.remainingRows, id: \.appointment.id) { row in
                            appointmentRow(row)
                        }
                    }

                    if !viewModel.resolvedRows.isEmpty {
                        resolvedFold
                    }
                }
            }
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.surfacePage)
        .accessibilityIdentifier(FCAccessibilityID.todayRoot)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    path.append(.calendar)
                } label: {
                    Image(systemName: "calendar")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(String(localized: "calendar.title"))
                .accessibilityIdentifier(FCAccessibilityID.todayCalendarEntry)
            }
        }
        .task { await viewModel.reload() }
        .onChange(of: path) { _, _ in
            Task { await viewModel.reload() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            Text(String(localized: "today.title"))
                .font(.largeTitle.weight(.bold))
            Text(TodayDatePresentation.longDay(viewModel.todayDate))
                .foregroundStyle(FCSemanticColors.secondaryText)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            Text(String(localized: "today.empty.title"))
                .font(.headline)
            Text(String(localized: "today.empty.body"))
                .foregroundStyle(FCSemanticColors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, FCPrimitives.spacingMedium)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(FCSemanticColors.secondaryText)
            .padding(.top, FCPrimitives.spacingSmall)
    }

    private func inProgressCard(_ row: TodayOrderedAppointment) -> some View {
        Button {
            path.append(.activeSession(row.appointment.studentID.rawValue))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(localized: "today.inProgress.badge"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, FCPrimitives.spacingSmall)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(FCSemanticColors.elevatedSurface.opacity(0.2)))
                    Spacer()
                    Text(String(localized: "today.inProgress.continue"))
                }
                Text(viewModel.displayName(for: row.appointment.studentID))
                    .font(.headline)
            }
            .frame(minHeight: 44, alignment: .leading)
            .padding(FCPrimitives.spacingMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: FCPrimitives.radiusMedium).fill(FCSemanticColors.primaryText))
            .foregroundStyle(FCSemanticColors.surfacePage)
        }
        .accessibilityIdentifier(FCAccessibilityID.todayInProgress)
    }

    private func appointmentRow(_ row: TodayOrderedAppointment, emphasized: Bool = false) -> some View {
        let appointment = row.appointment
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Text(appointment.startTime.canonicalString)
                    .font(emphasized ? .title2.weight(.bold) : .headline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        "\(viewModel.displayName(for: appointment.studentID)) · "
                            + "\(appointment.durationMinutes) " + String(localized: "today.durationMinutes")
                    )
                    .font(.subheadline)
                    .foregroundStyle(FCSemanticColors.secondaryText)
                    .lineLimit(1)
                }
                Spacer()
                Text(TodayRowStatusPresentation.title(for: row))
                    .font(.footnote)
                    .foregroundStyle(
                        row.section == .overdue ? FCSemanticColors.warning : FCSemanticColors.secondaryText
                    )
                if appointment.status == .scheduled {
                    rowActionsMenu(for: appointment)
                }
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityIdentifier(FCAccessibilityID.todayRow(appointment.id))
        .contextMenu {
            if appointment.status == .scheduled {
                rowActionButtons(for: appointment)
            }
        }
    }

    /// Visible tap target for "开始训练"/"标记缺席"/"取消安排" -- the `contextMenu`
    /// below requires a long-press and is not a discoverable affordance for
    /// a primary, frequently-needed action. A native `Menu` here (not a
    /// hand-rolled dialog) gets the iOS system anchor arrow, automatic
    /// top/bottom boundary flip, and native blur/shadow for free -- exactly
    /// what a custom bubble would otherwise have to reimplement. contextMenu
    /// stays as a harmless power-user long-press shortcut.
    private func rowActionsMenu(for appointment: Appointment) -> some View {
        Menu {
            rowActionButtons(for: appointment)
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityIdentifier(FCAccessibilityID.todayRowActions(appointment.id))
    }

    @ViewBuilder
    private func rowActionButtons(for appointment: Appointment) -> some View {
        Button(String(localized: "today.action.start")) {
            Task {
                if let studentID = await viewModel.startTraining(appointmentID: appointment.id) {
                    path.append(.activeSession(studentID.rawValue))
                }
            }
        }
        // Collapsed from 2 top-level buttons into one submenu (native
        // nested Menu, still anchor/boundary-flip for free) so the
        // top-level list stays at 3 items. "不扣课" is listed first --
        // the safe, no-credit-consequence default -- "扣课" is the more
        // consequential, deliberate second choice.
        Menu(String(localized: "today.action.markAbsent")) {
            Button(String(localized: "today.action.markAbsentNotCharged")) {
                Task { await viewModel.markAbsent(appointmentID: appointment.id, creditChoice: .notCharged) }
            }
            Button(String(localized: "today.action.markAbsentCharged")) {
                Task { await viewModel.markAbsent(appointmentID: appointment.id, creditChoice: .charged) }
            }
        }
        Button(String(localized: "today.action.cancel"), role: .destructive) {
            Task { await viewModel.cancel(appointmentID: appointment.id) }
        }
    }

    private var resolvedFold: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            Button {
                viewModel.isResolvedExpanded.toggle()
            } label: {
                HStack {
                    Text("\(String(localized: "today.section.resolved")) · \(viewModel.resolvedRows.count)")
                        .foregroundStyle(FCSemanticColors.secondaryText)
                    Spacer()
                    Image(systemName: viewModel.isResolvedExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(FCSemanticColors.secondaryText)
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier(FCAccessibilityID.todayResolvedFold)

            if viewModel.isResolvedExpanded {
                ForEach(viewModel.resolvedRows, id: \.appointment.id) { row in
                    appointmentRow(row)
                }
            }
        }
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
        formatter.dateFormat = "M月d日 · EEEE"
        return formatter.string(from: instant)
    }
}
