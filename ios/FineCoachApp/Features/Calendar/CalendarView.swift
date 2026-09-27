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

    init(appointmentUseCases: AppointmentUseCases, studentUseCases: StudentUseCases, calendar: Calendar) {
        self.appointmentUseCases = appointmentUseCases
        self.studentUseCases = studentUseCases
        self.calendar = calendar
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
}

struct CalendarView: View {
    @StateObject private var viewModel: CalendarViewModel
    @Binding var path: [RootDestination]

    private static let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    init(
        appointmentUseCases: AppointmentUseCases,
        studentUseCases: StudentUseCases,
        calendar: Calendar,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: CalendarViewModel(
                appointmentUseCases: appointmentUseCases,
                studentUseCases: studentUseCases,
                calendar: calendar
            )
        )
        _path = path
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                    header
                    weekdayHeaderRow
                    monthGrid
                    Divider()
                    selectedDaySection
                }
                .padding(FCPrimitives.spacingMedium)
            }
            addButton
        }
        .background(FCSemanticColors.surfacePage)
        .accessibilityIdentifier(FCAccessibilityID.calendarRoot)
        .task { await viewModel.reload() }
        .onChange(of: viewModel.displayedMonthStart) { _, _ in
            Task { await viewModel.reload() }
        }
        .onChange(of: path) { _, _ in
            Task { await viewModel.reload() }
        }
    }

    private var header: some View {
        HStack {
            Text(String(localized: "calendar.title"))
                .font(.title2.weight(.bold))
            Spacer()
            Button {
                viewModel.goToPreviousMonth()
            } label: {
                FCSymbol(.back)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("calendar.previousMonth"))
            .accessibilityIdentifier(FCAccessibilityID.calendarPreviousMonth)

            Text(CalendarDatePresentation.yearMonth(viewModel.displayedMonthStart))
                .font(.subheadline)

            Button {
                viewModel.goToNextMonth()
            } label: {
                FCSymbol(.forward)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("calendar.nextMonth"))
            .accessibilityIdentifier(FCAccessibilityID.calendarNextMonth)
        }
    }

    private var weekdayHeaderRow: some View {
        HStack {
            ForEach(Self.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.footnote)
                    .foregroundStyle(FCSemanticColors.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let columns = Array(repeating: GridItem(.flexible()), count: 7)
        return LazyVGrid(columns: columns, spacing: FCPrimitives.spacingSmall) {
            ForEach(-viewModel.leadingBlankCount..<0, id: \.self) { _ in
                Color.clear.frame(height: 36)
            }
            ForEach(1...viewModel.daysInDisplayedMonth, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Int) -> some View {
        let date = (try? LocalDate(year: viewModel.displayedMonthStart.year, month: viewModel.displayedMonthStart.month, day: day))
        let isSelected = date == viewModel.selectedDate
        let hasAppointments = date.map { !(viewModel.appointmentsByDate[$0] ?? []).isEmpty } ?? false
        return Button {
            viewModel.selectDay(day)
        } label: {
            VStack(spacing: 2) {
                Text("\(day)")
                    .font(.subheadline.weight(isSelected ? .bold : .regular))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(isSelected ? FCSemanticColors.primaryText : Color.clear))
                    .foregroundStyle(isSelected ? FCSemanticColors.surfacePage : FCSemanticColors.primaryText)
                Circle()
                    .fill(hasAppointments ? FCSemanticColors.actionPrimary : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityIdentifier(FCAccessibilityID.calendarDay(day))
    }

    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            Text(CalendarDatePresentation.selectedDayTitle(viewModel.selectedDate))
                .font(.headline)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(FCSemanticColors.destructive)
            }

            if viewModel.selectedDateAppointments.isEmpty {
                Text(String(localized: "calendar.empty"))
                    .foregroundStyle(FCSemanticColors.secondaryText)
            } else {
                ForEach(viewModel.selectedDateAppointments, id: \.id) { appointment in
                    appointmentRow(appointment)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func appointmentRow(_ appointment: Appointment) -> some View {
        if appointment.status == .scheduled {
            // T077: the edit entry (仅本次 / 本次及以后 for series members).
            // T069e replaces this target with the D1 course action sheet.
            Button {
                path.append(.appointmentEditor(.edit(appointment.id.rawValue)))
            } label: {
                appointmentRowContent(appointment, showsDisclosure: true)
            }
            .buttonStyle(.plain)
        } else {
            appointmentRowContent(appointment, showsDisclosure: false)
        }
    }

    private func appointmentRowContent(_ appointment: Appointment, showsDisclosure: Bool) -> some View {
        HStack(alignment: .top) {
            Text(appointment.startTime.canonicalString)
                .font(.headline)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.displayName(for: appointment.studentID))
                    .font(.subheadline)
            }
            Spacer()
            Text(TodayRowStatusPresentation.title(for: TodayOrderedAppointment(appointment: appointment, section: .remainingToday)))
                .font(.footnote)
                .foregroundStyle(FCSemanticColors.secondaryText)
            if showsDisclosure {
                FCSymbol(.forward)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityIdentifier(FCAccessibilityID.calendarAppointmentRow(appointment.id))
    }

    private var addButton: some View {
        Button {
            path.append(.appointmentEditor(.create(studentID: nil, date: viewModel.selectedDate)))
        } label: {
            Text(String(localized: "calendar.addAppointment"))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(FCPrimitives.spacingMedium)
        .background(FCSemanticColors.primaryText)
        .foregroundStyle(FCSemanticColors.surfacePage)
        .accessibilityIdentifier(FCAccessibilityID.calendarAdd)
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
        formatter.dateFormat = "M月d日 · EEEE"
        return formatter.string(from: instant)
    }
}
