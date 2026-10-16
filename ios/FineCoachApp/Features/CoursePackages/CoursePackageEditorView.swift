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
    /// The Student's currently-active package, if any (M1B-FR-012: saving
    /// this editor atomically ends it). Loaded up front purely so the UI can
    /// warn the coach before that happens -- never influences whether Save
    /// is allowed, only whether it needs an extra confirmation step.
    @Published var existingActivePackage: CoursePackage?
    /// Ledger-derived, never the stale `remainingCreditsCache` (same rule as
    /// `CoursePackageListViewModel.balance(for:)`).
    @Published var existingActivePackageBalance: Int = 0
    @Published var isConfirmingEndActive = false

    let studentID: StableUUID
    private let useCases: CreditLedgerUseCases
    /// Retained (not just used to seed `startDate`/`endDate`) so `save()` can
    /// judge whether an existing active package is still "in effect" as of
    /// today (M1B-FR-012) using the same date this editor was opened with,
    /// consistent with how `startDate`/`endDate` are already derived.
    private let today: LocalDate

    init(studentID: StableUUID, useCases: CreditLedgerUseCases, today: LocalDate) {
        self.studentID = studentID
        self.useCases = useCases
        self.today = today
        self.startDate = today
        self.endDate = today
    }

    /// Best-effort: a lookup failure must never block creating a package, it
    /// only means the coach won't see the heads-up warning this time.
    func loadExistingActivePackage() async {
        guard let active = try? await useCases.activePackage(studentID: studentID) else {
            existingActivePackage = nil
            return
        }
        existingActivePackage = active
        existingActivePackageBalance =
            (try? await useCases.balance(packageID: active.id)) ?? active.remainingCreditsCache
    }

    /// When the Student already has an active package that is STILL in
    /// effect (not expired and has remaining credits), Save must not end it
    /// silently -- route through `isConfirmingEndActive` and wait for the
    /// coach's explicit confirmation instead of calling through immediately.
    /// When there is no active package, or the existing one has already
    /// expired (`isExpired(asOf:)`) or has zero remaining credits, ending it
    /// is not a real, reversible-feeling loss -- MUST NOT require an extra
    /// confirmation step (M1B-FR-012).
    func save() async {
        errorMessage = nil
        guard totalCredits > 0 else {
            errorMessage = String(localized: "coursePackageEditor.creditsInvalid")
            return
        }
        if let existingActivePackage,
            !existingActivePackage.isExpired(asOf: today),
            existingActivePackageBalance != 0
        {
            isConfirmingEndActive = true
            return
        }
        await performSave()
    }

    /// Called only after the coach taps the explicit confirm button in the
    /// confirmation dialog.
    func confirmEndActiveAndSave() async {
        isConfirmingEndActive = false
        await performSave()
    }

    private func performSave() async {
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
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? String(localized: "coursePackageEditor.saveFailed")
        }
    }
}

struct CoursePackageEditorView: View {
    @StateObject private var viewModel: CoursePackageEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var expandedDate: ExpandedDate?
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
                FCPageHeader(title: String(localized: "coursePackageEditor.title"), back: .init())
                    .padding(.bottom, FCPrimitives.space4)
                FCListRowDivider()
                editorRow(String(localized: "coursePackageEditor.name")) {
                    TextField("", text: $viewModel.name)
                        .fcFont(.body)
                        .multilineTextAlignment(.leading)
                }
                .accessibilityIdentifier(FCAccessibilityID.coursePackageEditorName)
                FCListRowDivider()

                editorRow(String(localized: "coursePackageEditor.totalCredits")) {
                    FCStepper(
                        String(localized: "coursePackageEditor.totalCredits"),
                        value: $viewModel.totalCredits,
                        in: 1...999
                    )
                }
                .accessibilityIdentifier(FCAccessibilityID.coursePackageEditorTotalCredits)
                FCListRowDivider()

                editorRow(String(localized: "coursePackageEditor.hasStartDate")) {
                    Toggle(String(localized: "coursePackageEditor.hasStartDate"), isOn: $viewModel.hasStartDate)
                        .toggleStyle(FCToggleStyle())
                        .labelsHidden()
                }
                FCListRowDivider()

                if viewModel.hasStartDate {
                    FCLabelValueRow(
                        label: String(localized: "coursePackageEditor.startDate"),
                        value: Self.dateText(viewModel.startDate),
                        action: { toggle(.start) }
                    )
                    if expandedDate == .start {
                        DatePicker("", selection: startDateBinding, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .tint(FCSemanticColors.actionPrimary)
                    }
                    FCListRowDivider()
                }

                editorRow(String(localized: "coursePackageEditor.hasEndDate")) {
                    Toggle(String(localized: "coursePackageEditor.hasEndDate"), isOn: $viewModel.hasEndDate)
                        .toggleStyle(FCToggleStyle())
                        .labelsHidden()
                }
                FCListRowDivider()

                if viewModel.hasEndDate {
                    FCLabelValueRow(
                        label: String(localized: "coursePackageEditor.endDate"),
                        value: Self.dateText(viewModel.endDate),
                        action: { toggle(.end) }
                    )
                    if expandedDate == .end {
                        DatePicker("", selection: endDateBinding, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .tint(FCSemanticColors.actionPrimary)
                    }
                    FCListRowDivider()
                }

                if let existingActivePackage = viewModel.existingActivePackage {
                    Text(
                        String(
                            format: String(localized: "coursePackageEditor.activeWarningFormat"),
                            existingActivePackage.displayName,
                            viewModel.existingActivePackageBalance
                        )
                    )
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.statusWarning)
                    .padding(.vertical, FCPrimitives.space2)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .fcFont(.callout, weight: .regular)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                        .padding(.vertical, FCPrimitives.space2)
                }

                FCButton(
                    title: String(localized: "coursePackageEditor.save"),
                    isEnabled: !viewModel.isSaving
                ) {
                    Task { await viewModel.save() }
                }
                .padding(.top, FCPrimitives.space4)
                .accessibilityIdentifier(FCAccessibilityID.coursePackageEditorSave)
            }
            .padding(FCPrimitives.space4)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.coursePackageEditorRoot)
        .task { await viewModel.loadExistingActivePackage() }
        .onChange(of: viewModel.didSave) { _, saved in
            if saved {
                dismiss()
            }
        }
        .confirmationDialog(
            String(localized: "coursePackageEditor.confirmEndActive.title"),
            isPresented: $viewModel.isConfirmingEndActive,
            titleVisibility: .visible
        ) {
            Button(String(localized: "coursePackageEditor.confirmEndActive.confirm"), role: .destructive) {
                Task { await viewModel.confirmEndActiveAndSave() }
            }
            Button(String(localized: "coursePackageEditor.confirmEndActive.cancel"), role: .cancel) {}
        } message: {
            if let existingActivePackage = viewModel.existingActivePackage {
                Text(
                    String(
                        format: String(localized: "coursePackageEditor.confirmEndActive.messageFormat"),
                        existingActivePackage.displayName,
                        viewModel.existingActivePackageBalance
                    )
                )
            }
        }
    }

    /// Which date row has its calendar expanded under it -- the same
    /// tap-to-expand row as 02 新建课程安排 (T069l, owner 2026-09-29).
    private enum ExpandedDate {
        case start
        case end
    }

    private func toggle(_ date: ExpandedDate) {
        withAnimation(.easeOut(duration: 0.2)) {
            expandedDate = expandedDate == date ? nil : date
        }
    }

    /// Full date with year: a package's validity can run into next year.
    private static func dateText(_ date: LocalDate) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date.startOfDay(calendar: calendar))
    }

    private func editorRow<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        FCLabelValueRow(label: label) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                control()
                    .foregroundStyle(FCSemanticColors.textPrimary)
            }
        }
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
