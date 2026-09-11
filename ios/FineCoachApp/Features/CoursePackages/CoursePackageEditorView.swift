import SwiftUI

/// Creates a new active `CoursePackage` for a Student. If the Student
/// already has one, saving atomically ends it first (M1B-FR-012) --
/// history is retained, never deleted.
@MainActor
final class CoursePackageEditorViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var totalCredits: Int = 10
    @Published var hasStartDate = false
    @Published var startDate: LocalDate
    @Published var hasEndDate = false
    @Published var endDate: LocalDate
    @Published var errorMessage: String?
    @Published var isSaving = false
    @Published var didSave = false

    let studentID: StableUUID
    private let useCases: CreditLedgerUseCases

    init(studentID: StableUUID, useCases: CreditLedgerUseCases, today: LocalDate) {
        self.studentID = studentID
        self.useCases = useCases
        self.startDate = today
        self.endDate = today
    }

    func save() async {
        errorMessage = nil
        guard totalCredits > 0 else {
            errorMessage = String(localized: "coursePackageEditor.creditsInvalid")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await useCases.createActivePackage(
                studentID: studentID,
                name: name.isEmpty ? nil : name,
                totalCredits: totalCredits,
                startDate: hasStartDate ? startDate : nil,
                endDate: hasEndDate ? endDate : nil
            )
            didSave = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "coursePackageEditor.saveFailed")
        }
    }
}

struct CoursePackageEditorView: View {
    @StateObject private var viewModel: CoursePackageEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Binding var path: [RootDestination]

    init(studentID: StableUUID, useCases: CreditLedgerUseCases, path: Binding<[RootDestination]>) {
        _viewModel = StateObject(
            wrappedValue: CoursePackageEditorViewModel(
                studentID: studentID,
                useCases: useCases,
                today: LocalDate(date: Date(), calendar: Calendar.current)
            )
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                editorRow(String(localized: "coursePackageEditor.name")) {
                    TextField("", text: $viewModel.name)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityIdentifier(FCAccessibilityID.coursePackageEditorName)
                Divider()

                editorRow(String(localized: "coursePackageEditor.totalCredits")) {
                    HStack(spacing: FCPrimitives.spacingSmall) {
                        Text("\(viewModel.totalCredits)")
                        Stepper("", value: $viewModel.totalCredits, in: 1...999)
                            .labelsHidden()
                    }
                }
                .accessibilityIdentifier(FCAccessibilityID.coursePackageEditorTotalCredits)
                Divider()

                editorRow(String(localized: "coursePackageEditor.hasStartDate")) {
                    Toggle("", isOn: $viewModel.hasStartDate)
                        .labelsHidden()
                }
                Divider()

                if viewModel.hasStartDate {
                    editorRow(String(localized: "coursePackageEditor.startDate")) {
                        DatePicker("", selection: startDateBinding, displayedComponents: .date)
                            .labelsHidden()
                    }
                    Divider()
                }

                editorRow(String(localized: "coursePackageEditor.hasEndDate")) {
                    Toggle("", isOn: $viewModel.hasEndDate)
                        .labelsHidden()
                }
                Divider()

                if viewModel.hasEndDate {
                    editorRow(String(localized: "coursePackageEditor.endDate")) {
                        DatePicker("", selection: endDateBinding, displayedComponents: .date)
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
                    title: String(localized: "coursePackageEditor.save"),
                    isEnabled: !viewModel.isSaving
                ) {
                    Task { await viewModel.save() }
                }
                .padding(.top, FCPrimitives.spacingMedium)
                .accessibilityIdentifier(FCAccessibilityID.coursePackageEditorSave)
            }
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.background)
        .navigationTitle(String(localized: "coursePackageEditor.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(FCAccessibilityID.coursePackageEditorRoot)
        .onChange(of: viewModel.didSave) { _, saved in
            if saved {
                dismiss()
            }
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

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.startDate.startOfDay(calendar: Calendar.current) },
            set: { viewModel.startDate = LocalDate(date: $0, calendar: Calendar.current) }
        )
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.endDate.startOfDay(calendar: Calendar.current) },
            set: { viewModel.endDate = LocalDate(date: $0, calendar: Calendar.current) }
        )
    }
}
