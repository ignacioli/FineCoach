import SwiftUI

@MainActor
final class AppointmentEditorViewModel: ObservableObject {
    /// How a recurring series ends (M1B-FR-004: exactly one of the two).
    enum EndMode: Hashable {
        case date
        case count
    }

    enum Scope {
        case thisInstanceOnly
        case thisAndFuture
    }

    /// What `save()` resolved to; kept so a conflict override retries the
    /// same operation.
    private enum Operation {
        case createSingle
        case createRecurring
        case reschedule
        case thisAndFuture
        case trainingFocusOnly
    }

    /// The series an edited appointment belongs to (only for a live series
    /// member, i.e. not a detached "仅本次" exception).
    struct SeriesContext {
        let series: RecurrenceSeries
        let thisAndFutureCount: Int
    }

    @Published var students: [Student] = []
    @Published var selectedStudentID: StableUUID?
    @Published var date: LocalDate
    @Published var startTime: LocalTime
    @Published var durationMinutes: Int = 60
    @Published var reminderEnabled = true
    @Published var reminderLeadMinutes: ReminderLeadMinutes = .sixty
    @Published var trainingFocus: Set<BodyPart> = []
    /// `nil` = 不重复 (the default, M1B-FR-004).
    @Published var repeatInterval: RecurrenceInterval?
    @Published var endMode: EndMode = .date
    @Published var endDate: LocalDate
    @Published var repeatCount = 8
    @Published var errorMessage: String?
    @Published var conflictMessage = ""
    @Published var isScopeSheetPresented = false
    @Published private(set) var seriesContext: SeriesContext?
    @Published private(set) var original: Appointment?
    @Published var isSaving = false
    @Published var didSave = false
    @Published private var pendingOverride: Operation?

    let mode: AppointmentEditorMode
    let calendar: Calendar
    private let appointmentUseCases: AppointmentUseCases
    private let studentUseCases: StudentUseCases
    private var existingAppointmentID: StableUUID?

    init(
        mode: AppointmentEditorMode,
        appointmentUseCases: AppointmentUseCases,
        studentUseCases: StudentUseCases,
        calendar: Calendar
    ) {
        self.mode = mode
        self.calendar = calendar
        self.appointmentUseCases = appointmentUseCases
        self.studentUseCases = studentUseCases
        let initialDate: LocalDate
        switch mode {
        case .create(let studentID, let date):
            self.selectedStudentID = studentID.map { StableUUID($0) }
            initialDate = date
        case .edit(let id):
            self.existingAppointmentID = StableUUID(id)
            initialDate = appointmentUseCases.todayLocalDate()
        }
        self.date = initialDate
        self.endDate = initialDate.addingDays(28, calendar: calendar)
        self.startTime = (try? LocalTime(hour: 9, minute: 0)) ?? LocalTime.zero
    }

    var title: String {
        switch mode {
        case .create:
            return String(localized: "appointmentEditor.createTitle")
        case .edit:
            return String(localized: "appointmentEditor.editTitle")
        }
    }

    var isEditing: Bool { existingAppointmentID != nil }

    var hasConflictPrompt: Bool { pendingOverride != nil }

    var isDateChanged: Bool {
        original.map { $0.date != date } ?? false
    }

    var termination: RecurrenceTermination {
        switch endMode {
        case .date: return .endDate(endDate)
        case .count: return .repeatCount(repeatCount)
        }
    }

    /// "将创建 N 节课（首日 – 末日，每 N 天一次）" (D4), or the bound/ordering
    /// error when the chosen end cannot materialize (D-012).
    var recurrencePreview: String? {
        guard !isEditing, let interval = repeatInterval else {
            return nil
        }
        do {
            try RecurrenceSeries.validateMaterializationBound(
                termination: termination,
                firstOccurrenceDate: date,
                calendar: calendar
            )
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? String(localized: "appointmentEditor.saveFailed")
        }
        let dates = RecurrenceSeries.materializedDates(
            intervalDays: interval,
            firstOccurrenceDate: date,
            termination: termination,
            calendar: calendar
        )
        guard let first = dates.first, let last = dates.last else {
            return nil
        }
        return String(
            format: String(localized: "appointmentEditor.previewFormat"),
            dates.count,
            AppointmentEditorFormatting.monthDay(first),
            AppointmentEditorFormatting.monthDay(last),
            interval.rawValue
        )
    }

    func load() async {
        students = (try? await studentUseCases.searchActive(query: "")) ?? []
        if selectedStudentID == nil {
            selectedStudentID = students.first?.id
        }
        guard let existingAppointmentID,
            let appointment = try? await appointmentUseCases.appointment(id: existingAppointmentID)
        else {
            return
        }
        original = appointment
        selectedStudentID = appointment.studentID
        date = appointment.date
        startTime = appointment.startTime
        durationMinutes = appointment.durationMinutes
        reminderEnabled = appointment.reminderEnabled
        reminderLeadMinutes = appointment.reminderLeadMinutes ?? .sixty
        trainingFocus = appointment.trainingFocus
        if let seriesID = appointment.seriesID, !appointment.isDetachedException,
            let series = try? await appointmentUseCases.series(id: seriesID),
            let count = try? await appointmentUseCases.thisAndFutureAffectedCount(
                seriesID: seriesID, boundaryDate: appointment.date)
        {
            seriesContext = SeriesContext(series: series, thisAndFutureCount: count)
        }
    }

    func save() async {
        errorMessage = nil
        guard selectedStudentID != nil else {
            errorMessage = String(localized: "appointmentEditor.studentRequired")
            return
        }
        guard durationMinutes > 0 else {
            errorMessage = String(localized: "appointmentEditor.durationInvalid")
            return
        }
        guard let original else {
            await run(repeatInterval == nil ? .createSingle : .createRecurring)
            return
        }
        let scheduleChanged =
            original.date != date
            || original.startTime != startTime
            || original.durationMinutes != durationMinutes
            || original.reminderEnabled != reminderEnabled
            || (reminderEnabled && original.reminderLeadMinutes != reminderLeadMinutes)
        let focusChanged = original.trainingFocus != trainingFocus
        if !scheduleChanged {
            // Training focus is per instance: never needs the scope choice.
            if focusChanged {
                await run(.trainingFocusOnly)
            } else {
                didSave = true
            }
        } else if seriesContext != nil {
            isScopeSheetPresented = true
        } else {
            await run(.reschedule)
        }
    }

    func apply(scope: Scope) async {
        isScopeSheetPresented = false
        switch scope {
        case .thisInstanceOnly:
            await run(.reschedule)
        case .thisAndFuture:
            await run(.thisAndFuture)
        }
    }

    func confirmOverrideAndSave() async {
        guard let operation = pendingOverride else {
            return
        }
        pendingOverride = nil
        await run(operation, overrideConflict: true)
    }

    func dismissConflict() {
        pendingOverride = nil
    }

    private func run(_ operation: Operation, overrideConflict: Bool = false) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await perform(operation, overrideConflict: overrideConflict)
            didSave = true
        } catch DomainError.conflict where !overrideConflict {
            conflictMessage = await conflictDescription(for: operation)
            pendingOverride = operation
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription ?? String(localized: "appointmentEditor.saveFailed")
        }
    }

    private var resolvedLead: ReminderLeadMinutes? {
        reminderEnabled ? reminderLeadMinutes : nil
    }

    private func perform(_ operation: Operation, overrideConflict: Bool) async throws {
        switch operation {
        case .createSingle:
            guard let studentID = selectedStudentID else { return }
            _ = try await appointmentUseCases.createSingle(
                studentID: studentID,
                date: date,
                startTime: startTime,
                durationMinutes: durationMinutes,
                reminderEnabled: reminderEnabled,
                reminderLeadMinutes: resolvedLead,
                trainingFocus: trainingFocus,
                overrideConflict: overrideConflict
            )
        case .createRecurring:
            guard let studentID = selectedStudentID, let repeatInterval else { return }
            _ = try await appointmentUseCases.createRecurring(
                studentID: studentID,
                draft: RecurringAppointmentDraft(
                    intervalDays: repeatInterval,
                    termination: termination,
                    firstOccurrenceDate: date,
                    startTime: startTime,
                    durationMinutes: durationMinutes,
                    reminderEnabled: reminderEnabled,
                    reminderLeadMinutes: resolvedLead,
                    trainingFocus: trainingFocus
                ),
                overrideConflict: overrideConflict
            )
        case .reschedule:
            guard let original else { return }
            _ = try await appointmentUseCases.rescheduleSingle(
                appointmentID: original.id,
                date: date,
                startTime: startTime,
                durationMinutes: durationMinutes,
                reminderEnabled: reminderEnabled,
                reminderLeadMinutes: resolvedLead,
                trainingFocus: original.trainingFocus != trainingFocus ? trainingFocus : nil,
                overrideConflict: overrideConflict
            )
        case .thisAndFuture:
            // D-011 (owner 2026-09-26: strict): only start time, duration and
            // reminder carry forward; an edited focus applies to this
            // instance alone, and a date change is only possible via 仅本次.
            guard let original, let seriesID = original.seriesID else { return }
            _ = try await appointmentUseCases.applyThisAndFuture(
                seriesID: seriesID,
                boundaryDate: original.date,
                startTime: startTime,
                durationMinutes: durationMinutes,
                reminderEnabled: reminderEnabled,
                reminderLeadMinutes: resolvedLead,
                boundaryTrainingFocus: original.trainingFocus != trainingFocus ? trainingFocus : nil,
                overrideConflict: overrideConflict
            )
        case .trainingFocusOnly:
            guard let original else { return }
            _ = try await appointmentUseCases.updateTrainingFocus(
                appointmentID: original.id, trainingFocus: trainingFocus)
        }
    }

    private func conflictDescription(for operation: Operation) async -> String {
        switch operation {
        case .createSingle, .reschedule:
            let conflicts =
                (try? await appointmentUseCases.detectConflicts(
                    date: date,
                    startTime: startTime,
                    durationMinutes: durationMinutes,
                    excludingAppointmentID: existingAppointmentID
                )) ?? []
            return conflicts.map { conflict in
                "\(conflict.conflictingStudentDisplayName) "
                    + AppointmentEditorFormatting.hourMinute(conflict.conflictingStartInstant, calendar: calendar)
            }.joined(separator: "\n")
        case .createRecurring:
            guard let repeatInterval else { return "" }
            var conflictingCount = 0
            for occurrence in RecurrenceSeries.materializedDates(
                intervalDays: repeatInterval,
                firstOccurrenceDate: date,
                termination: termination,
                calendar: calendar
            ) {
                let conflicts =
                    (try? await appointmentUseCases.detectConflicts(
                        date: occurrence,
                        startTime: startTime,
                        durationMinutes: durationMinutes,
                        excludingAppointmentID: nil
                    )) ?? []
                if !conflicts.isEmpty {
                    conflictingCount += 1
                }
            }
            return String(format: String(localized: "appointmentEditor.recurringConflictFormat"), conflictingCount)
        case .thisAndFuture, .trainingFocusOnly:
            // The superseded instances themselves would be counted as
            // conflicts here, so no per-instance detail is shown.
            return ""
        }
    }
}

enum AppointmentEditorFormatting {
    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format
        return formatter
    }

    private static var zhCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }

    /// "9月27日"
    static func monthDay(_ date: LocalDate) -> String {
        let calendar = zhCalendar
        return formatter("M月d日", calendar: calendar).string(from: date.startOfDay(calendar: calendar))
    }

    /// "9月27日 · 周六"
    static func monthDayWeekday(_ date: LocalDate) -> String {
        let calendar = zhCalendar
        return formatter("M月d日 · EEE", calendar: calendar).string(from: date.startOfDay(calendar: calendar))
    }

    static func hourMinute(_ instant: Date, calendar: Calendar) -> String {
        formatter("HH:mm", calendar: calendar).string(from: instant)
    }

    static func intervalTitle(_ interval: RecurrenceInterval?) -> String {
        switch interval {
        case nil: return String(localized: "appointmentEditor.repeat.none")
        case .everyOtherDay: return String(localized: "appointmentEditor.repeat.everyOtherDay")
        case .everyTwoDays: return String(localized: "appointmentEditor.repeat.everyTwoDays")
        case .everyWeek: return String(localized: "appointmentEditor.repeat.everyWeek")
        }
    }

    static func minutes(_ value: Int) -> String {
        String(format: String(localized: "appointmentEditor.durationValueFormat"), value)
    }

    static func reminderLead(_ lead: ReminderLeadMinutes) -> String {
        String(format: String(localized: "appointmentEditor.reminderLeadValueFormat"), lead.rawValue)
    }

    static func repeatCount(_ count: Int) -> String {
        String(format: String(localized: "appointmentEditor.repeatCountValueFormat"), count)
    }

    static func termination(_ termination: RecurrenceTermination) -> String {
        switch termination {
        case .endDate(let date):
            return String(format: String(localized: "appointmentEditor.seriesEndDateFormat"), monthDay(date))
        case .repeatCount(let count):
            return String(format: String(localized: "appointmentEditor.seriesCountFormat"), count)
        }
    }
}

extension LocalTime {
    fileprivate static let zero = (try? LocalTime(hour: 0, minute: 0))!
}

/// 02 新建/编辑课程安排 (`23-new-appointment-v2`, `24-edit-occurrence-scope`;
/// T077 + T069d): label–value form, body-part focus, repeat interval with
/// end mode, "将创建 N 节课" preview, pinned save button, and the
/// 仅本次 / 本次及以后 scope sheet when editing a series member.
struct AppointmentEditorView: View {
    private enum ExpandedField {
        case date
        case startTime
        case duration
        case endDate
        case repeatCount
    }

    @StateObject private var viewModel: AppointmentEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var expanded: ExpandedField?
    @State private var notificationStatus: NotificationAuthorizationStatus = .notDetermined

    init(
        mode: AppointmentEditorMode,
        appointmentUseCases: AppointmentUseCases,
        studentUseCases: StudentUseCases,
        calendar: Calendar
    ) {
        _viewModel = StateObject(
            wrappedValue: AppointmentEditorViewModel(
                mode: mode,
                appointmentUseCases: appointmentUseCases,
                studentUseCases: studentUseCases,
                calendar: calendar
            )
        )
    }

    private var calendar: Calendar { viewModel.calendar }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FCPageHeader(title: viewModel.title, back: .init())
                    .padding(.bottom, FCPrimitives.space4)
                FCListRowDivider()

                studentRow
                FCListRowDivider()

                FCLabelValueRow(
                    label: String(localized: "appointmentEditor.date"),
                    value: AppointmentEditorFormatting.monthDayWeekday(viewModel.date),
                    action: { toggle(.date) }
                )
                if expanded == .date {
                    DatePicker("", selection: dateBinding(\.date), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(FCSemanticColors.actionPrimary)
                }
                FCListRowDivider()

                FCLabelValueRow(
                    label: String(localized: "appointmentEditor.startTime"),
                    value: viewModel.startTime.canonicalString,
                    action: { toggle(.startTime) }
                )
                if expanded == .startTime {
                    DatePicker("", selection: startTimeBinding, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
                FCListRowDivider()

                FCLabelValueRow(
                    label: String(localized: "appointmentEditor.duration"),
                    value: AppointmentEditorFormatting.minutes(viewModel.durationMinutes),
                    action: { toggle(.duration) }
                )
                if expanded == .duration {
                    Picker("", selection: $viewModel.durationMinutes) {
                        ForEach(Array(stride(from: 15, through: 240, by: 15)), id: \.self) { minutes in
                            Text(AppointmentEditorFormatting.minutes(minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                }
                FCListRowDivider()

                trainingFocusSection
                FCListRowDivider()

                repeatSection

                reminderRow
                FCListRowDivider()

                if let preview = viewModel.recurrencePreview {
                    Text(preview)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                        .padding(.top, FCPrimitives.space3)
                }

                if viewModel.hasConflictPrompt {
                    FCStatusLabel(.conflict)
                        .padding(.top, FCPrimitives.space3)
                }

                if viewModel.reminderEnabled && notificationStatus == .denied {
                    VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                        FCStatusLabel(.permissionDenied)
                        FCLinkButton(title: String(localized: "appointmentEditor.openSystemSettings")) {
                            SystemSettingsLink.openNotificationSettings()
                        }
                    }
                    .padding(.top, FCPrimitives.space3)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                        .padding(.top, FCPrimitives.space3)
                }
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .safeAreaInset(edge: .bottom) {
            FCButton(
                title: String(localized: "appointmentEditor.save"),
                isEnabled: !viewModel.isSaving
            ) {
                Task { await viewModel.save() }
            }
            .accessibilityIdentifier(FCAccessibilityID.appointmentEditorSave)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.vertical, FCPrimitives.space2)
            .background(FCSemanticColors.surfacePage)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.appointmentEditorRoot)
        .fcBottomSheet(isPresented: $viewModel.isScopeSheetPresented) {
            scopeSheet
        }
        .task { await viewModel.load() }
        .task(id: scenePhase) { notificationStatus = await SystemNotificationAdapter().currentStatus() }
        .onChange(of: viewModel.didSave) { _, saved in
            if saved {
                dismiss()
            }
        }
        .confirmationDialog(
            String(localized: "appointmentEditor.conflictTitle"),
            isPresented: conflictPresented,
            titleVisibility: .visible
        ) {
            Button(String(localized: "appointmentEditor.conflictOverride"), role: .destructive) {
                Task { await viewModel.confirmOverrideAndSave() }
            }
            Button(String(localized: "appointmentEditor.conflictCancel"), role: .cancel) {
                viewModel.dismissConflict()
            }
        } message: {
            Text(viewModel.conflictMessage)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var studentRow: some View {
        let name = viewModel.students.first { $0.id == viewModel.selectedStudentID }?.displayName.value ?? ""
        if viewModel.isEditing {
            FCLabelValueRow(label: String(localized: "appointmentEditor.student"), value: name)
        } else {
            Menu {
                Picker("", selection: $viewModel.selectedStudentID) {
                    ForEach(viewModel.students) { student in
                        Text(student.displayName.value).tag(Optional(student.id))
                    }
                }
            } label: {
                FCLabelValueRow(
                    label: String(localized: "appointmentEditor.student"), value: name, showsDisclosure: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var trainingFocusSection: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            HStack {
                Text(String(localized: "appointmentEditor.trainingFocus"))
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                Spacer()
                Text(String(localized: "appointmentEditor.optionalMultiSelect"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
            FCBodyPartPicker(selection: $viewModel.trainingFocus)
        }
        .padding(.vertical, FCPrimitives.space3)
    }

    @ViewBuilder
    private var repeatSection: some View {
        if let context = viewModel.seriesContext {
            // D-011 strict (owner 2026-09-26): the rule is shown, not edited.
            FCLabelValueRow(
                label: String(localized: "appointmentEditor.repeat"),
                value: AppointmentEditorFormatting.intervalTitle(context.series.intervalDays)
            )
            FCListRowDivider()
            FCLabelValueRow(
                label: String(localized: "appointmentEditor.endMode"),
                value: AppointmentEditorFormatting.termination(context.series.termination)
            )
            FCListRowDivider()
        } else if !viewModel.isEditing {
            VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                Text(String(localized: "appointmentEditor.repeat"))
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                FCFlowLayout(horizontalSpacing: FCPrimitives.space2, verticalSpacing: FCPrimitives.space2 - (44 - 30)) {
                    repeatChip(nil)
                    ForEach(RecurrenceInterval.allCases, id: \.self) { interval in
                        repeatChip(interval)
                    }
                }
            }
            .padding(.vertical, FCPrimitives.space3)
            FCListRowDivider()

            if viewModel.repeatInterval != nil {
                FCLabelValueRow(label: String(localized: "appointmentEditor.endMode")) {
                    HStack(spacing: FCPrimitives.space2) {
                        FCFilterChip(
                            title: String(localized: "appointmentEditor.endMode.date"),
                            isSelected: viewModel.endMode == .date
                        ) { viewModel.endMode = .date }
                        FCFilterChip(
                            title: String(localized: "appointmentEditor.endMode.count"),
                            isSelected: viewModel.endMode == .count
                        ) { viewModel.endMode = .count }
                    }
                }
                FCListRowDivider()

                switch viewModel.endMode {
                case .date:
                    FCLabelValueRow(
                        label: String(localized: "appointmentEditor.endDate"),
                        value: AppointmentEditorFormatting.monthDay(viewModel.endDate),
                        action: { toggle(.endDate) }
                    )
                    if expanded == .endDate {
                        DatePicker(
                            "",
                            selection: dateBinding(\.endDate),
                            in: viewModel.date.startOfDay(calendar: calendar)...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(FCSemanticColors.actionPrimary)
                    }
                case .count:
                    FCLabelValueRow(
                        label: String(localized: "appointmentEditor.repeatCount"),
                        value: AppointmentEditorFormatting.repeatCount(viewModel.repeatCount),
                        action: { toggle(.repeatCount) }
                    )
                    if expanded == .repeatCount {
                        Picker("", selection: $viewModel.repeatCount) {
                            ForEach(2...RecurrenceSeries.maximumMaterializedInstances, id: \.self) { count in
                                Text(AppointmentEditorFormatting.repeatCount(count)).tag(count)
                            }
                        }
                        .pickerStyle(.wheel)
                        .labelsHidden()
                    }
                }
                FCListRowDivider()
            }
        }
    }

    private func repeatChip(_ interval: RecurrenceInterval?) -> some View {
        FCFilterChip(
            title: AppointmentEditorFormatting.intervalTitle(interval),
            isSelected: viewModel.repeatInterval == interval
        ) {
            viewModel.repeatInterval = interval
        }
    }

    private var reminderRow: some View {
        FCLabelValueRow(label: String(localized: "appointmentEditor.reminder")) {
            HStack(spacing: FCPrimitives.space2) {
                Menu {
                    Picker("", selection: $viewModel.reminderLeadMinutes) {
                        ForEach(ReminderLeadMinutes.allCases, id: \.self) { lead in
                            Text(AppointmentEditorFormatting.reminderLead(lead)).tag(lead)
                        }
                    }
                } label: {
                    Text(AppointmentEditorFormatting.reminderLead(viewModel.reminderLeadMinutes))
                        .fcFont(.body)
                        .foregroundStyle(
                            viewModel.reminderEnabled ? FCSemanticColors.textPrimary : FCSemanticColors.textDisabled
                        )
                        .frame(minHeight: 44)
                }
                .disabled(!viewModel.reminderEnabled)
                Spacer(minLength: FCPrimitives.space2)
                Toggle(String(localized: "appointmentEditor.reminder"), isOn: $viewModel.reminderEnabled)
                    .toggleStyle(FCToggleStyle())
                    .labelsHidden()
            }
        }
    }

    private var scopeSheet: some View {
        let original = viewModel.original
        let dayText = original.map { AppointmentEditorFormatting.monthDay($0.date) } ?? ""
        let futureDetail =
            viewModel.isDateChanged
            ? String(localized: "appointmentEditor.scope.dateChangedDetail")
            : String(
                format: String(localized: "appointmentEditor.scope.thisAndFutureDetailFormat"),
                dayText,
                viewModel.seriesContext?.thisAndFutureCount ?? 0
            )
        return FCBottomSheet(
            title: String(localized: "appointmentEditor.scope.title"),
            subtitle: String(localized: "appointmentEditor.scope.subtitle")
        ) {
            VStack(spacing: 0) {
                FCListRowDivider()
                FCActionRow(
                    title: String(localized: "appointmentEditor.scope.thisOnly"),
                    subtitle: String(format: String(localized: "appointmentEditor.scope.thisOnlyDetailFormat"), dayText)
                ) {
                    Task { await viewModel.apply(scope: .thisInstanceOnly) }
                }
                FCListRowDivider()
                FCActionRow(
                    title: String(localized: "appointmentEditor.scope.thisAndFuture"),
                    subtitle: futureDetail,
                    isEnabled: !viewModel.isDateChanged
                ) {
                    Task { await viewModel.apply(scope: .thisAndFuture) }
                }
                FCListRowDivider()
                FCLinkButton(title: String(localized: "appointmentEditor.scope.cancel")) {
                    viewModel.isScopeSheetPresented = false
                }
                .frame(maxWidth: .infinity)
                .padding(.top, FCPrimitives.space2)
            }
        }
    }

    // MARK: Bindings

    private func toggle(_ field: ExpandedField) {
        withAnimation(.easeOut(duration: 0.2)) {
            expanded = expanded == field ? nil : field
        }
    }

    private func dateBinding(_ keyPath: ReferenceWritableKeyPath<AppointmentEditorViewModel, LocalDate>) -> Binding<
        Date
    > {
        Binding(
            get: { viewModel[keyPath: keyPath].startOfDay(calendar: calendar) },
            set: { newValue in
                viewModel[keyPath: keyPath] = LocalDate(date: newValue, calendar: calendar)
            }
        )
    }

    private var startTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = viewModel.startTime.hour
                components.minute = viewModel.startTime.minute
                return calendar.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = calendar.dateComponents([.hour, .minute], from: newValue)
                if let hour = components.hour, let minute = components.minute,
                    let time = try? LocalTime(hour: hour, minute: minute)
                {
                    viewModel.startTime = time
                }
            }
        )
    }

    private var conflictPresented: Binding<Bool> {
        Binding(
            get: { viewModel.hasConflictPrompt },
            set: { newValue in
                if !newValue {
                    viewModel.dismissConflict()
                }
            }
        )
    }
}
