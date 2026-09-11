import SwiftUI

@MainActor
final class AppointmentEditorViewModel: ObservableObject {
    @Published var students: [Student] = []
    @Published var selectedStudentID: StableUUID?
    @Published var date: LocalDate
    @Published var startTime: LocalTime
    @Published var durationMinutes: Int = 60
    @Published var reminderEnabled = true
    @Published var reminderLeadMinutes: ReminderLeadMinutes = .sixty
    @Published var errorMessage: String?
    @Published var pendingConflicts: [AppointmentConflict]?
    @Published var isSaving = false
    @Published var didSave = false

    let mode: AppointmentEditorMode
    private let appointmentUseCases: AppointmentUseCases
    private let studentUseCases: StudentUseCases
    private var existingAppointmentID: StableUUID?

    init(mode: AppointmentEditorMode, appointmentUseCases: AppointmentUseCases, studentUseCases: StudentUseCases) {
        self.mode = mode
        self.appointmentUseCases = appointmentUseCases
        self.studentUseCases = studentUseCases
        switch mode {
        case .create(let studentID, let date):
            self.selectedStudentID = studentID.map { StableUUID($0) }
            self.date = date
        case .edit(let id):
            self.existingAppointmentID = StableUUID(id)
            self.date = appointmentUseCases.todayLocalDate()
        }
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

    func load() async {
        students = (try? await studentUseCases.searchActive(query: "")) ?? []
        if selectedStudentID == nil {
            selectedStudentID = students.first?.id
        }
        if let existingAppointmentID, let appointment = try? await appointmentUseCases.appointment(id: existingAppointmentID) {
            selectedStudentID = appointment.studentID
            date = appointment.date
            startTime = appointment.startTime
            durationMinutes = appointment.durationMinutes
            reminderEnabled = appointment.reminderEnabled
            reminderLeadMinutes = appointment.reminderLeadMinutes ?? .sixty
        }
    }

    func save() async {
        errorMessage = nil
        guard let studentID = selectedStudentID else {
            errorMessage = String(localized: "appointmentEditor.studentRequired")
            return
        }
        guard durationMinutes > 0 else {
            errorMessage = String(localized: "appointmentEditor.durationInvalid")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await persist(studentID: studentID, overrideConflict: false)
            didSave = true
        } catch DomainError.conflict {
            pendingConflicts = try? await appointmentUseCases.detectConflicts(
                date: date,
                startTime: startTime,
                durationMinutes: durationMinutes,
                excludingAppointmentID: existingAppointmentID
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "appointmentEditor.saveFailed")
        }
    }

    func confirmOverrideAndSave() async {
        guard let studentID = selectedStudentID else {
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await persist(studentID: studentID, overrideConflict: true)
            pendingConflicts = nil
            didSave = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "appointmentEditor.saveFailed")
        }
    }

    private func persist(studentID: StableUUID, overrideConflict: Bool) async throws {
        if let existingAppointmentID {
            _ = try await appointmentUseCases.rescheduleSingle(
                appointmentID: existingAppointmentID,
                date: date,
                startTime: startTime,
                durationMinutes: durationMinutes,
                reminderEnabled: reminderEnabled,
                reminderLeadMinutes: reminderEnabled ? reminderLeadMinutes : nil,
                overrideConflict: overrideConflict
            )
        } else {
            _ = try await appointmentUseCases.createSingle(
                studentID: studentID,
                date: date,
                startTime: startTime,
                durationMinutes: durationMinutes,
                reminderEnabled: reminderEnabled,
                reminderLeadMinutes: reminderEnabled ? reminderLeadMinutes : nil,
                overrideConflict: overrideConflict
            )
        }
    }
}

private extension LocalTime {
    static let zero = (try? LocalTime(hour: 0, minute: 0))!
}

struct AppointmentEditorView: View {
    @StateObject private var viewModel: AppointmentEditorViewModel
    @Environment(\.dismiss) private var dismiss
    private let calendar: Calendar

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
                studentUseCases: studentUseCases
            )
        )
        self.calendar = calendar
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                editorRow(String(localized: "appointmentEditor.student")) {
                    Picker("", selection: $viewModel.selectedStudentID) {
                        ForEach(viewModel.students) { student in
                            Text(student.displayName.value).tag(Optional(student.id))
                        }
                    }
                    .labelsHidden()
                }
                Divider()

                editorRow(String(localized: "appointmentEditor.date")) {
                    DatePicker("", selection: dateBinding, displayedComponents: .date)
                        .labelsHidden()
                }
                Divider()

                editorRow(String(localized: "appointmentEditor.startTime")) {
                    DatePicker("", selection: startTimeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                Divider()

                editorRow(String(localized: "appointmentEditor.duration")) {
                    HStack(spacing: FCPrimitives.spacingSmall) {
                        Text("\(viewModel.durationMinutes) " + String(localized: "today.durationMinutes"))
                        Stepper("", value: $viewModel.durationMinutes, in: 15...240, step: 15)
                            .labelsHidden()
                    }
                }
                Divider()

                editorRow(String(localized: "appointmentEditor.reminder")) {
                    Toggle("", isOn: $viewModel.reminderEnabled)
                        .labelsHidden()
                }
                Divider()

                if viewModel.reminderEnabled {
                    editorRow(String(localized: "appointmentEditor.reminderLead")) {
                        Picker("", selection: $viewModel.reminderLeadMinutes) {
                            ForEach(ReminderLeadMinutes.allCases, id: \.self) { lead in
                                Text("\(lead.rawValue) " + String(localized: "today.durationMinutes")).tag(lead)
                            }
                        }
                        .labelsHidden()
                    }
                    Divider()
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(FCSemanticColors.destructive)
                        .padding(.vertical, FCPrimitives.spacingSmall)
                }

                FCButton(
                    title: String(localized: "appointmentEditor.save"),
                    isEnabled: !viewModel.isSaving
                ) {
                    Task { await viewModel.save() }
                }
                .padding(.top, FCPrimitives.spacingMedium)
                .accessibilityIdentifier(FCAccessibilityID.appointmentEditorSave)
            }
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.background)
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(FCAccessibilityID.appointmentEditorRoot)
        .task { await viewModel.load() }
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
                viewModel.pendingConflicts = nil
            }
        } message: {
            Text(conflictMessage)
        }
    }

    private func editorRow<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(FCSemanticColors.primaryText)
            Spacer()
            control()
                .foregroundStyle(FCSemanticColors.primaryText)
        }
        .frame(minHeight: 44)
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { viewModel.date.startOfDay(calendar: calendar) },
            set: { newValue in
                viewModel.date = LocalDate(date: newValue, calendar: calendar)
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
            get: { viewModel.pendingConflicts != nil },
            set: { newValue in
                if !newValue {
                    viewModel.pendingConflicts = nil
                }
            }
        )
    }

    private var conflictMessage: String {
        guard let conflicts = viewModel.pendingConflicts, !conflicts.isEmpty else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return conflicts.map { conflict in
            "\(conflict.conflictingStudentDisplayName) "
                + "\(formatter.string(from: conflict.conflictingStartInstant))"
        }.joined(separator: "\n")
    }
}
