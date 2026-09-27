import SwiftUI

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var displayedMonthStart: LocalDate
    @Published var selectedDate: LocalDate
    @Published var appointmentsByDate: [LocalDate: [Appointment]] = [:]
    @Published var studentNames: [StableUUID: String] = [:]
    @Published var errorMessage: String?

    private let appointmentUseCases: AppointmentUseCases
    private let studentUseCases: StudentUseCases
    private let calendar: Calendar

    let courseActions: CourseActions

    init(
        appointmentUseCases: AppointmentUseCases,
        studentUseCases: StudentUseCases,
        creditLedgerUseCases: CreditLedgerUseCases? = nil,
        calendar: Calendar
    ) {
        self.appointmentUseCases = appointmentUseCases
        self.studentUseCases = studentUseCases
        self.calendar = calendar
        self.courseActions = CourseActions(
            appointmentUseCases: appointmentUseCases,
            creditLedgerUseCases: creditLedgerUseCases
        )
        let today = appointmentUseCases.todayLocalDate()
        self.displayedMonthStart = (try? LocalDate(year: today.year, month: today.month, day: 1)) ?? today
        self.selectedDate = today
    }

    var selectedDateAppointments: [Appointment] {
        (appointmentsByDate[selectedDate] ?? []).sorted { $0.startTime < $1.startTime }
    }

    /// Days in the displayed month, MUST NOT exceed the month's real length
    /// (no Feb 30th) -- computed via the injected Calendar (T007a), never a
    /// hardcoded 28/30/31 table.
    var daysInDisplayedMonth: Int {
        let start = displayedMonthStart.startOfDay(calendar: calendar)
        return calendar.range(of: .day, in: .month, for: start)?.count ?? 30
    }

    /// Leading blank cells so day 1 lands under the correct Sunday-first
    /// column (data-model has no first-weekday preference; matches the G5
    /// hi-fi mockup's 日一二三四五六 header).
    var leadingBlankCount: Int {
        Int(displayedMonthStart.weekday(calendar: calendar).rawValue % 7)
    }

    func goToPreviousMonth() {
        shiftMonth(by: -1)
    }

    func goToNextMonth() {
        shiftMonth(by: 1)
    }

    private func shiftMonth(by delta: Int) {
        var year = displayedMonthStart.year
        var month = displayedMonthStart.month + delta
        while month < 1 {
            month += 12
            year -= 1
        }
        while month > 12 {
            month -= 12
            year += 1
        }
        displayedMonthStart = (try? LocalDate(year: year, month: month, day: 1)) ?? displayedMonthStart
    }

    func selectDay(_ day: Int) {
        guard let date = try? LocalDate(year: displayedMonthStart.year, month: displayedMonthStart.month, day: day)
        else {
            return
        }
        selectedDate = date
    }

    func reload() async {
        do {
            let days = (1...daysInDisplayedMonth).compactMap { day in
                try? LocalDate(year: displayedMonthStart.year, month: displayedMonthStart.month, day: day)
            }
            let appointments = try await appointmentUseCases.appointments(onLocalDates: days)
            var byDate: [LocalDate: [Appointment]] = [:]
            for appointment in appointments {
                byDate[appointment.date, default: []].append(appointment)
            }
            appointmentsByDate = byDate

            var names = studentNames
            for appointment in appointments where names[appointment.studentID] == nil {
                if let student = try? await studentUseCases.student(id: appointment.studentID) {
                    names[appointment.studentID] = student.displayName.value
                }
            }
            studentNames = names
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "today.error.generic")
        }
    }

    func displayName(for studentID: StableUUID) -> String {
        studentNames[studentID] ?? ""
    }

    func present(_ message: String) {
        errorMessage = message
    }
}

/// 03 月历 (T069e; `25-calendar-v2`): title and month switcher on one row,
/// Sunday-first grid of `FCCalendarDayCell` with has-appointment dots, the
/// selected day's rows (time · 学员 · 部位, status, ›) opening the same D1
/// course action sheet as 今日, and a pinned "＋ 添加课程安排" button.
struct CalendarView: View {
    @StateObject private var viewModel: CalendarViewModel
    @Binding var path: [RootDestination]
    @State private var sheetAppointment: Appointment?

    private static let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    init(
        appointmentUseCases: AppointmentUseCases,
        studentUseCases: StudentUseCases,
        creditLedgerUseCases: CreditLedgerUseCases? = nil,
        calendar: Calendar,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: CalendarViewModel(
                appointmentUseCases: appointmentUseCases,
                studentUseCases: studentUseCases,
                creditLedgerUseCases: creditLedgerUseCases,
                calendar: calendar
            )
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                header
                weekdayHeaderRow
                monthGrid
                FCListRowDivider()
                selectedDaySection
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .safeAreaInset(edge: .bottom) {
            FCButton(title: String(localized: "calendar.addAppointment")) {
                path.append(.appointmentEditor(.create(studentID: nil, date: viewModel.selectedDate)))
            }
            .accessibilityIdentifier(FCAccessibilityID.calendarAdd)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.vertical, FCPrimitives.space2)
            .background(FCSemanticColors.surfacePage)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .accessibilityIdentifier(FCAccessibilityID.calendarRoot)
        .courseActionSheet(
            appointment: $sheetAppointment,
            path: $path,
            actions: viewModel.courseActions,
            studentName: { viewModel.displayName(for: $0) },
            onChanged: { await viewModel.reload() },
            onError: { viewModel.present($0) }
        )
        .task { await viewModel.reload() }
        .onChange(of: viewModel.displayedMonthStart) { _, _ in
            Task { await viewModel.reload() }
        }
        .onChange(of: path) { _, _ in
            Task { await viewModel.reload() }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: FCPrimitives.space2) {
            Text(String(localized: "calendar.title"))
                .fcFont(.titleLarge)
                .foregroundStyle(FCSemanticColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: FCPrimitives.space2)
            Text(CalendarDatePresentation.yearMonth(viewModel.displayedMonthStart))
                .fcFont(.headline)
                .foregroundStyle(FCSemanticColors.textPrimary)
            Button {
                viewModel.goToPreviousMonth()
            } label: {
                FCSymbol(.back)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("calendar.previousMonth"))
            .accessibilityIdentifier(FCAccessibilityID.calendarPreviousMonth)
            Button {
                viewModel.goToNextMonth()
            } label: {
                FCSymbol(.forward)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("calendar.nextMonth"))
            .accessibilityIdentifier(FCAccessibilityID.calendarNextMonth)
        }
    }

    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .fcFont(.sectionLabel)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var monthGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: FCPrimitives.space2) {
            ForEach(-viewModel.leadingBlankCount..<0, id: \.self) { _ in
                Color.clear.frame(height: 44)
            }
            ForEach(1...viewModel.daysInDisplayedMonth, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Int) -> some View {
        let date = try? LocalDate(year: viewModel.displayedMonthStart.year, month: viewModel.displayedMonthStart.month, day: day)
        let hasAppointments = date.map { !(viewModel.appointmentsByDate[$0] ?? []).isEmpty } ?? false
        return FCCalendarDayCell(
            day: day,
            isSelected: date == viewModel.selectedDate,
            hasAppointments: hasAppointments
        ) {
            viewModel.selectDay(day)
        }
        .accessibilityIdentifier(FCAccessibilityID.calendarDay(day))
    }

    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            Text(CalendarDatePresentation.selectedDayTitle(viewModel.selectedDate))
                .fcFont(.headline)
                .foregroundStyle(FCSemanticColors.textPrimary)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.statusDestructive)
            }

            if viewModel.selectedDateAppointments.isEmpty {
                Text(String(localized: "calendar.empty"))
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.selectedDateAppointments, id: \.id) { appointment in
                        appointmentRow(appointment)
                        FCListRowDivider()
                    }
                }
            }
        }
    }

    /// Whole row tappable for a scheduled appointment → D1 sheet (D5).
    private func appointmentRow(_ appointment: Appointment) -> some View {
        let isActionable = appointment.status == .scheduled
        return Button {
            if isActionable {
                sheetAppointment = appointment
            }
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
                Text(TodayRowStatusPresentation.title(for: TodayOrderedAppointment(appointment: appointment, section: .remainingToday)))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                if isActionable {
                    FCSymbol(.forward)
                }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isActionable)
        .accessibilityIdentifier(FCAccessibilityID.calendarAppointmentRow(appointment.id))
    }
}

enum CalendarDatePresentation {
    static func yearMonth(_ date: LocalDate) -> String {
        "\(date.year)年\(date.month)月"
    }

    static func selectedDayTitle(_ date: LocalDate) -> String {
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
