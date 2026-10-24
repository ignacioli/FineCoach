import SwiftUI

@MainActor
final class StudentDetailViewModel: ObservableObject {
    @Published var student: Student?
    @Published var inProgress: InProgressTrainingSummary?
    @Published var notesExpanded = false
    @Published var errorMessage: String?
    /// The Student's most recently COMPLETED session, newest-by-`completedAtUTC`
    /// (not array/fetch order). `nil` means there is genuinely no completed
    /// session yet.
    @Published var mostRecentCompletedSession: CompletedSession?
    @Published var nextAppointment: Appointment?
    @Published var activePackage: CoursePackage?
    @Published var activeBalance: Int?

    let studentID: StableUUID
    let useCases: StudentUseCases
    let courseActions: CourseActions?
    private let historyUseCases: HistoryUseCases
    private let appointmentUseCases: AppointmentUseCases?
    private let creditLedgerUseCases: CreditLedgerUseCases?
    private let calendar: Calendar

    init(
        studentID: StableUUID,
        useCases: StudentUseCases,
        historyUseCases: HistoryUseCases,
        appointmentUseCases: AppointmentUseCases? = nil,
        creditLedgerUseCases: CreditLedgerUseCases? = nil,
        calendar: Calendar = .current
    ) {
        self.studentID = studentID
        self.useCases = useCases
        self.historyUseCases = historyUseCases
        self.appointmentUseCases = appointmentUseCases
        self.creditLedgerUseCases = creditLedgerUseCases
        self.calendar = calendar
        self.courseActions = appointmentUseCases.map {
            CourseActions(appointmentUseCases: $0, creditLedgerUseCases: creditLedgerUseCases)
        }
    }

    var isTrainingThisStudent: Bool {
        inProgress?.studentID == studentID
    }

    func reload() async {
        do {
            student = try await useCases.student(id: studentID)
            inProgress = try await useCases.inProgressTraining(studentID: studentID)
            let history = try await historyUseCases.listHistory(studentID: studentID)
            mostRecentCompletedSession = CompletedSession.mostRecent(in: history)
            if let appointmentUseCases {
                let now = Date()
                nextAppointment = try await appointmentUseCases.appointments(studentID: studentID)
                    .filter { $0.status == .scheduled && $0.startInstant(calendar: calendar) > now }
                    .min { $0.startInstant(calendar: calendar) < $1.startInstant(calendar: calendar) }
            }
            if let creditLedgerUseCases {
                activePackage = try await creditLedgerUseCases.activePackage(studentID: studentID)
                if let activePackage {
                    activeBalance = try await creditLedgerUseCases.balance(packageID: activePackage.id)
                } else {
                    activeBalance = nil
                }
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }

    func restore() async {
        do {
            student = try await useCases.restore(id: studentID)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }

    func present(_ message: String) {
        errorMessage = message
    }
}

/// 学员详情 (T069g; `26-student-detail`, D6): titleLarge name + 编辑资料,
/// avatar + 训练目标, 概览 (下一节课 → D1 sheet, 课包 → 04, 最近训练),
/// 记录 (训练历史 / 训练趋势 / 身体数据), 资料 (label–value), and the single
/// primary action: pinned 开始训练, or the dark hero card while this
/// student is training. Archive and delete now live on 编辑资料 (27).
/// 注意事项 stays collapsed until tapped (M1-A spec: 伤病/注意事项默认不展开).
struct StudentDetailView: View {
    @StateObject private var viewModel: StudentDetailViewModel
    @StateObject private var insightsModel: InsightsViewModel
    @Binding var path: [RootDestination]
    @State private var sheetAppointment: Appointment?

    init(
        studentID: StableUUID,
        useCases: StudentUseCases,
        historyUseCases: HistoryUseCases,
        appointmentUseCases: AppointmentUseCases? = nil,
        creditLedgerUseCases: CreditLedgerUseCases? = nil,
        insightUseCases: InsightUseCases? = nil,
        exerciseUseCases: ExerciseLibraryUseCases? = nil,
        calendar: Calendar = .current,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: StudentDetailViewModel(
                studentID: studentID,
                useCases: useCases,
                historyUseCases: historyUseCases,
                appointmentUseCases: appointmentUseCases,
                creditLedgerUseCases: creditLedgerUseCases,
                calendar: calendar
            )
        )
        _insightsModel = StateObject(
            wrappedValue: InsightsViewModel(
                useCases: insightUseCases, students: useCases, exercises: exerciseUseCases,
                history: historyUseCases, studentID: studentID))
        _path = path

    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space6) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                }
                if let student = viewModel.student {
                    header(student)
                    if student.lifecycle == .archived {
                        archivedNotice
                    } else if let inProgress = viewModel.inProgress, viewModel.isTrainingThisStudent {
                        continueCard(inProgress)
                    }
                    if !insightsModel.insights.isEmpty {
                        InsightSectionView(
                            model: insightsModel, title: String(localized: "insights.section.title"),
                            rows: insightsModel.insights, context: .studentDetail, path: $path
                        )
                        .accessibilityIdentifier(FCAccessibilityID.detailInsights)
                    }
                    if let error = insightsModel.errorMessage {
                        Text(error).fcFont(.caption).foregroundStyle(FCSemanticColors.statusDestructive)
                    }
                    overviewSection(student)

                    recordsSection(student)
                    profileSection(student)
                } else {
                    // Not loaded (or failed): the page still needs its back.
                    FCPageHeader(title: "", back: .init())
                }
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .safeAreaInset(edge: .bottom) {
            bottomAction
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .courseActionSheetIfAvailable(
            appointment: $sheetAppointment,
            path: $path,
            actions: viewModel.courseActions,
            studentName: { _ in viewModel.student?.displayName.value ?? "" },
            onChanged: { await viewModel.reload() },
            onError: { viewModel.present($0) }
        )
        .task { await viewModel.reload() }
        .task { await insightsModel.reload() }
        .onReceive(NotificationCenter.default.publisher(for: InsightsViewModel.didSnooze)) {
            insightsModel.removeSnoozed($0)
        }
        .onChange(of: path) { _, _ in
            Task { await insightsModel.reload() }
            Task { await viewModel.reload() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.detailRoot)
    }

    // MARK: Header

    private func header(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            FCPageHeader(
                title: student.displayName.value,
                back: .init(),
                trailingAction: .init(
                    title: String(localized: "student.detail.edit"),
                    accessibilityIdentifier: "studentDetail.edit"
                ) {
                    path.append(.editor(.edit(viewModel.studentID.rawValue)))
                }
            )
            HStack(spacing: FCPrimitives.space4) {
                FCAvatar(initial: String(student.displayName.value.prefix(1)))
                Text(StudentDetailPresentation.goal(student))
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
        }
    }

    private var archivedNotice: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            FCHintBar(String(localized: "student.detail.archived"))
                .accessibilityIdentifier(FCAccessibilityID.detailArchivedStatus)
            Text(String(localized: "student.detail.archivedHint"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
        }
    }

    private func continueCard(_ summary: InProgressTrainingSummary) -> some View {
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
        .accessibilityIdentifier(FCAccessibilityID.detailContinueTraining)
    }

    // MARK: 概览

    private func overviewSection(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FCSectionLabel(String(localized: "student.detail.overview"))
                .padding(.bottom, FCPrimitives.space2)
            FCListRowDivider()

            overviewRow(
                kicker: String(localized: "student.detail.nextClass"),
                identifier: FCAccessibilityID.detailNextClass
            ) {
                Text(StudentDetailPresentation.nextClass(viewModel.nextAppointment))
                    .fcFont(.body)
                    .foregroundStyle(FCSemanticColors.textPrimary)
            } action: {
                if let next = viewModel.nextAppointment {
                    sheetAppointment = next
                } else if student.lifecycle == .active {
                    path.append(
                        .appointmentEditor(
                            .create(
                                studentID: student.id.rawValue,
                                date: LocalDate(date: Date(), calendar: .current)
                            )))
                }
            }
            FCListRowDivider()

            overviewRow(
                kicker: String(localized: "student.detail.package"),
                identifier: FCAccessibilityID.detailCoursePackages
            ) {
                packageValue
            } action: {
                path.append(.coursePackages(student.id.rawValue))
            }
            FCListRowDivider()

            overviewRow(
                kicker: String(localized: "student.detail.recentKicker"),
                identifier: FCAccessibilityID.detailRecentTraining
            ) {
                Text(StudentDetailPresentation.recent(viewModel.mostRecentCompletedSession))
                    .fcFont(.body)
                    .foregroundStyle(FCSemanticColors.textPrimary)
            } action: {
                if let session = viewModel.mostRecentCompletedSession {
                    path.append(.sessionDetail(session.id.rawValue))
                } else {
                    path.append(.history(student.id.rawValue))
                }
            }
            FCListRowDivider()
        }
    }

    @ViewBuilder
    private var packageValue: some View {
        if let package = viewModel.activePackage, let balance = viewModel.activeBalance {
            HStack(alignment: .firstTextBaseline, spacing: FCPrimitives.space1) {
                Text("\(balance)")
                    .fcFont(.numeralLarge)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                Text(StudentDetailPresentation.packageDetail(package))
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
        } else {
            Text(String(localized: "coursePackages.noActive"))
                .fcFont(.body)
                .foregroundStyle(FCSemanticColors.textSecondary)
        }
    }

    private func overviewRow<Value: View>(
        kicker: String,
        identifier: String,
        @ViewBuilder value: () -> Value,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: FCPrimitives.space2) {
                VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                    Text(kicker)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                    value()
                }
                Spacer(minLength: FCPrimitives.space2)
                FCSymbol(.forward)
            }
            .padding(.vertical, FCPrimitives.space3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    // MARK: 记录

    private func recordsSection(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FCSectionLabel(String(localized: "student.detail.records"))
                .padding(.bottom, FCPrimitives.space2)
            FCListRowDivider()
            FCActionRow(title: String(localized: "student.detail.history")) {
                path.append(.history(student.id.rawValue))
            }
            .accessibilityIdentifier(FCAccessibilityID.detailHistory)
            FCListRowDivider()
            FCActionRow(title: String(localized: "student.detail.trends")) {
                path.append(.trends(student.id.rawValue))
            }
            .accessibilityIdentifier(FCAccessibilityID.detailTrends)
            FCListRowDivider()
            FCActionRow(title: String(localized: "student.detail.bodyData")) {
                path.append(.bodyData(student.id.rawValue))
            }
            .accessibilityIdentifier(FCAccessibilityID.detailBodyData)
            FCListRowDivider()
            // M2-01: also shown for archived students (D-006).
            FCActionRow(title: String(localized: "student.detail.exportArchive")) {
                path.append(.archiveExport(student.id.rawValue))
            }
            .accessibilityIdentifier(FCAccessibilityID.detailExportArchive)
            FCListRowDivider()
        }
    }

    // MARK: 资料

    private func profileSection(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FCSectionLabel(String(localized: "student.detail.profile"))
                .padding(.bottom, FCPrimitives.space2)
            FCListRowDivider()
            FCLabelValueRow(
                label: String(localized: "student.field.sex"), value: StudentSexPresentation.title(student.sex))
            FCListRowDivider()
            FCLabelValueRow(
                label: String(localized: "student.field.phone"), value: StudentDetailPresentation.filled(student.phone))
            FCListRowDivider()
            FCLabelValueRow(
                label: String(localized: "student.field.wechat"),
                value: StudentDetailPresentation.filled(student.wechatID))
            FCListRowDivider()
            FCLabelValueRow(
                label: String(localized: "student.field.privateNote"),
                value: StudentDetailPresentation.filled(student.privateCoachNote))
            FCListRowDivider()
            notesRow(student)
            FCListRowDivider()
            Text(String(localized: "student.editor.contactHint"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .padding(.top, FCPrimitives.space3)
        }
    }

    /// 注意事项: collapsed by default, revealed only on an explicit tap.
    @ViewBuilder
    private func notesRow(_ student: Student) -> some View {
        let hasNotes = student.injuryNotes.map { !$0.value.isEmpty } ?? false
        FCLabelValueRow(
            label: String(localized: "student.field.injuryNotes"),
            action: hasNotes ? { viewModel.notesExpanded.toggle() } : nil
        ) {
            if !hasNotes {
                FCLabelValueText(String(localized: "student.detail.unfilled"))
            } else if viewModel.notesExpanded {
                Text(student.injuryNotes?.value ?? "")
                    .fcFont(.body)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .accessibilityIdentifier(FCAccessibilityID.detailNotesBody)
            } else {
                Text(String(localized: "student.detail.notesTapToShow"))
                    .fcFont(.body)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
        }
        .accessibilityIdentifier(FCAccessibilityID.detailNotesFold)
        .accessibilityValue(
            Text(viewModel.notesExpanded ? "student.detail.notesExpanded" : "student.detail.notesCollapsed"))
        if hasNotes, viewModel.notesExpanded {
            Text(String(localized: "student.detail.notesDisclaimer"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .padding(.bottom, FCPrimitives.space3)
        }
    }

    // MARK: Bottom action

    @ViewBuilder
    private var bottomAction: some View {
        if let student = viewModel.student {
            Group {
                if student.lifecycle == .archived {
                    FCButton(title: String(localized: "student.detail.restore")) {
                        Task { await viewModel.restore() }
                    }
                    .accessibilityIdentifier(FCAccessibilityID.detailRestore)
                } else if !viewModel.isTrainingThisStudent {
                    FCButton(title: String(localized: "student.detail.startTraining")) {
                        path.append(.activeSession(student.id.rawValue))
                    }
                    .accessibilityIdentifier(FCAccessibilityID.detailStartTraining)
                }
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.vertical, FCPrimitives.space2)
            .background(FCSemanticColors.surfacePage)
        }
    }
}

enum StudentDetailPresentation {
    /// "训练目标 · 增肌" or "未设训练目标"
    static func goal(_ student: Student) -> String {
        guard let goal = student.trainingGoal?.value, !goal.isEmpty else {
            return String(localized: "student.detail.noGoal")
        }
        return String(format: String(localized: "student.detail.goalFormat"), goal)
    }

    static func filled(_ text: ValidatedText?) -> String {
        text.flatMap { $0.value.isEmpty ? nil : $0.value } ?? String(localized: "student.detail.unfilled")
    }

    /// "9月27日 周六 15:00 · 大腿、臀" or "暂无安排"
    static func nextClass(_ appointment: Appointment?) -> String {
        guard let appointment else {
            return String(localized: "student.detail.noNextClass")
        }
        let day = AppointmentEditorFormatting.monthDayWeekday(appointment.date).replacingOccurrences(
            of: " · ", with: " ")
        let base = "\(day) \(appointment.startTime.canonicalString)"
        guard let parts = BodyPart.joinedDisplayNames(for: appointment.trainingFocus, separator: "、") else {
            return base
        }
        return "\(base) · \(parts)"
    }

    /// "/ 共 20 课时 · 有效期至 12月31日"
    static func packageDetail(_ package: CoursePackage) -> String {
        let total = String(format: String(localized: "student.detail.packageTotalFormat"), package.totalCredits)
        guard let end = package.endDate else {
            return total
        }
        return "\(total) · "
            + String(format: String(localized: "student.detail.validUntilFormat"), "\(end.month)月\(end.day)日")
    }

    /// "9月25日 · 大腿、臀 · 12 组"
    static func recent(_ session: CompletedSession?) -> String {
        guard let session else {
            return String(localized: "student.detail.recentPlaceholder")
        }
        var parts = [PackageDetailPresentation.day(session.completedAtUTC)]
        if let focus = BodyPart.joinedDisplayNames(for: session.trainingFocus, separator: "、") {
            parts.append(focus)
        }
        parts.append(
            String(format: String(localized: "student.detail.setCountFormat"), session.statistics.completedSetCount))
        return parts.joined(separator: " · ")
    }
}

extension View {
    /// Attaches the D1 course action sheet only when appointment actions
    /// are available (the detail page is also built without them in tests
    /// and previews).
    @ViewBuilder
    func courseActionSheetIfAvailable(
        appointment: Binding<Appointment?>,
        path: Binding<[RootDestination]>,
        actions: CourseActions?,
        studentName: @escaping (StableUUID) -> String,
        onChanged: @escaping () async -> Void,
        onError: @escaping (String) -> Void
    ) -> some View {
        if let actions {
            courseActionSheet(
                appointment: appointment,
                path: path,
                actions: actions,
                studentName: studentName,
                onChanged: onChanged,
                onError: onError
            )
        } else {
            self
        }
    }
}
