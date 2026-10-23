import SwiftUI

/// The appointment actions behind the D1 course action sheet, shared by
/// 01 今日 and 03 月历 (T069a/T069e).
@MainActor
final class CourseActions {
    private let appointmentUseCases: AppointmentUseCases
    private let creditLedgerUseCases: CreditLedgerUseCases?

    init(appointmentUseCases: AppointmentUseCases, creditLedgerUseCases: CreditLedgerUseCases?) {
        self.appointmentUseCases = appointmentUseCases
        self.creditLedgerUseCases = creditLedgerUseCases
    }

    /// Returns the student whose session started.
    func startTraining(_ appointment: Appointment) async throws -> StableUUID {
        try await appointmentUseCases.startTraining(appointmentID: appointment.id).studentID
    }

    func cancel(_ appointment: Appointment) async throws {
        _ = try await appointmentUseCases.cancel(appointmentID: appointment.id, reason: nil)
    }

    func markAbsent(_ appointment: Appointment, creditChoice: AbsentCreditChoice) async throws {
        let updated = try await appointmentUseCases.markAbsent(
            appointmentID: appointment.id,
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
                    appointmentID: appointment.id,
                    creditChoice: creditChoice
                )
            }
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

/// D1 course action sheet (`18-course-action-sheet`): 开始训练 / 标记缺席 →
/// 不扣课 or 扣课 / 编辑安排 / 取消本次 (destructive, confirmed). Present by
/// setting `appointment` to a scheduled appointment; it clears itself.
private struct CourseActionSheetModifier: ViewModifier {
    @Binding var appointment: Appointment?
    @Binding var path: [RootDestination]
    let actions: CourseActions
    let studentName: (StableUUID) -> String
    let onChanged: () async -> Void
    let onError: (String) -> Void

    @State private var isChoosingAbsence = false
    @State private var isConfirmingCancel = false

    func body(content: Content) -> some View {
        content
            .fcBottomSheet(isPresented: sheetPresented) {
                if let appointment {
                    sheet(appointment)
                }
            }
            .fcConfirmationDialog(isPresented: $isConfirmingCancel) {
                FCConfirmationDialog(
                    title: String(localized: "today.cancelConfirm.title"),
                    message: String(localized: "today.cancelConfirm.message"),
                    cancelAction: .init(title: String(localized: "today.cancelConfirm.keep")) {
                        isConfirmingCancel = false
                    },
                    confirmAction: .init(
                        title: String(localized: "today.cancelConfirm.confirm"),
                        accessibilityIdentifier: FCAccessibilityID.todayCancelConfirm
                    ) {
                        let target = appointment
                        isConfirmingCancel = false
                        close()
                        if let target {
                            perform { try await actions.cancel(target) }
                        }
                    }
                )
            }
    }

    private var sheetPresented: Binding<Bool> {
        Binding(
            get: { appointment != nil && !isConfirmingCancel },
            set: { if !$0 { close() } }
        )
    }

    private func close() {
        appointment = nil
        isChoosingAbsence = false
    }

    private func perform(_ work: @escaping () async throws -> Void) {
        Task {
            var failed = false
            do {
                try await work()
            } catch {
                failed = true
            }
            // Reload first: a reload clears the screen's error message.
            await onChanged()
            if failed {
                onError(String(localized: "today.error.generic"))
            }
        }
    }

    private func sheet(_ appointment: Appointment) -> some View {
        FCBottomSheet(
            title: String(
                format: String(localized: "today.sheet.titleFormat"),
                appointment.startTime.canonicalString,
                appointment.durationMinutes
            ),
            titleStyle: .title,
            subtitle: TodayRowPresentation.nameAndFocus(studentName(appointment.studentID), appointment.trainingFocus),
            accessory: {
                Text(String(localized: "today.status.pending"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            },
            content: {
                if isChoosingAbsence {
                    absenceChoices(appointment)
                } else {
                    mainActions(appointment)
                }
            }
        )
    }

    private func mainActions(_ appointment: Appointment) -> some View {
        VStack(spacing: 0) {
            FCButton(title: String(localized: "today.action.start")) {
                close()
                Task {
                    do {
                        let studentID = try await actions.startTraining(appointment)
                        await onChanged()
                        path.append(.activeSession(studentID.rawValue))
                    } catch {
                        onError(String(localized: "today.error.generic"))
                    }
                }
            }
            .accessibilityIdentifier(FCAccessibilityID.todayStartTraining)
            .padding(.bottom, FCPrimitives.space2)
            FCActionRow(
                title: String(localized: "today.action.markAbsent"),
                note: String(localized: "today.sheet.absentNote")
            ) {
                isChoosingAbsence = true
            }
            FCListRowDivider()
            FCActionRow(title: String(localized: "today.action.edit")) {
                close()
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
            .accessibilityIdentifier(FCAccessibilityID.todayCancelCourse)
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
                close()
                perform { try await actions.markAbsent(appointment, creditChoice: .notCharged) }
            }
            .accessibilityIdentifier(FCAccessibilityID.todayAbsentNotCharged)
            FCListRowDivider()
            FCActionRow(title: String(localized: "today.action.markAbsentCharged")) {
                close()
                perform { try await actions.markAbsent(appointment, creditChoice: .charged) }
            }
            .accessibilityIdentifier(FCAccessibilityID.todayAbsentCharged)
            FCListRowDivider()
            FCLinkButton(title: String(localized: "today.sheet.back")) {
                isChoosingAbsence = false
            }
            .frame(maxWidth: .infinity)
            .padding(.top, FCPrimitives.space2)
        }
    }
}

extension View {
    func courseActionSheet(
        appointment: Binding<Appointment?>,
        path: Binding<[RootDestination]>,
        actions: CourseActions,
        studentName: @escaping (StableUUID) -> String,
        onChanged: @escaping () async -> Void,
        onError: @escaping (String) -> Void
    ) -> some View {
        modifier(
            CourseActionSheetModifier(
                appointment: appointment,
                path: path,
                actions: actions,
                studentName: studentName,
                onChanged: onChanged,
                onError: onError
            ))
    }
}
