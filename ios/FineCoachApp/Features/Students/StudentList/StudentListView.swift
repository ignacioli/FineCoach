import SwiftUI

@MainActor
final class StudentListViewModel: ObservableObject {
    /// Per-row derived text (21-student-list-v2): the focus of the student's
    /// next scheduled appointment, and the trailing next-class or package
    /// hint. Derived only; nothing is stored on the student.
    struct RowInfo: Equatable {
        var focus: Set<BodyPart> = []
        var trailing: String?
    }

    @Published var students: [Student] = []
    @Published var query = ""
    @Published var inProgress: InProgressTrainingSummary?
    @Published var errorMessage: String?
    @Published var archivedCount = 0
    @Published var rowInfo: [StableUUID: RowInfo] = [:]

    let showsArchived: Bool
    private let useCases: StudentUseCases
    private let appointmentUseCases: AppointmentUseCases?
    private let creditLedgerUseCases: CreditLedgerUseCases?
    private let calendar: Calendar

    init(
        useCases: StudentUseCases,
        showsArchived: Bool = false,
        appointmentUseCases: AppointmentUseCases? = nil,
        creditLedgerUseCases: CreditLedgerUseCases? = nil,
        calendar: Calendar = .current
    ) {
        self.useCases = useCases
        self.showsArchived = showsArchived
        self.appointmentUseCases = appointmentUseCases
        self.creditLedgerUseCases = creditLedgerUseCases
        self.calendar = calendar
    }

    var title: String {
        showsArchived ? String(localized: "student.list.archivedTitle") : String(localized: "student.list.title")
    }

    func reload() async {
        do {
            if showsArchived {
                students = try await useCases.listArchived()
                inProgress = nil
            } else {
                students = try await useCases.searchActive(query: query)
                inProgress = try await useCases.inProgressTraining()
                archivedCount = try await useCases.listArchived().count
                await loadRowInfo()
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }

    func restore(_ student: Student) async {
        do {
            _ = try await useCases.restore(id: student.id)
            await reload()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }

    private func loadRowInfo() async {
        guard let appointmentUseCases else { return }
        let now = Date()
        let today = appointmentUseCases.todayLocalDate()
        var info: [StableUUID: RowInfo] = [:]
        for student in students {
            var row = RowInfo()
            let upcoming = ((try? await appointmentUseCases.appointments(studentID: student.id)) ?? [])
                .filter { $0.status == .scheduled && $0.startInstant(calendar: calendar) > now }
                .min { $0.startInstant(calendar: calendar) < $1.startInstant(calendar: calendar) }
            if let upcoming {
                row.focus = upcoming.trainingFocus
                row.trailing = StudentListPresentation.nextClass(upcoming, today: today, calendar: calendar)
            } else if let creditLedgerUseCases,
                let package = try? await creditLedgerUseCases.activePackage(studentID: student.id),
                let balance = try? await creditLedgerUseCases.balance(packageID: package.id)
            {
                row.trailing = String(format: String(localized: "student.list.packageRemainingFormat"), balance)
            }
            info[student.id] = row
        }
        rowInfo = info
    }
}

enum StudentListPresentation {
    /// "今天 15:00" / "明天 15:00" / "9月30日 15:00"
    static func nextClass(_ appointment: Appointment, today: LocalDate, calendar: Calendar) -> String {
        let time = appointment.startTime.canonicalString
        if appointment.date == today {
            return String(format: String(localized: "student.list.todayTimeFormat"), time)
        }
        if appointment.date == today.addingDays(1, calendar: calendar) {
            return String(format: String(localized: "student.list.tomorrowTimeFormat"), time)
        }
        return "\(AppointmentEditorFormatting.monthDay(appointment.date)) \(time)"
    }

    /// "训练重点 · 胸、肩" or "未设重点".
    static func focus(_ parts: Set<BodyPart>) -> String {
        guard let names = BodyPart.joinedDisplayNames(for: parts, separator: "、") else {
            return String(localized: "student.list.noFocus")
        }
        return String(format: String(localized: "student.list.focusFormat"), names)
    }

    /// "训练中 · 王小明 · 已训练 32 分钟"
    static func trainingBar(_ summary: InProgressTrainingSummary, now: Date) -> String {
        guard let minutes = summary.elapsedMinutes(now: now) else {
            return String(format: String(localized: "student.list.trainingBarShortFormat"), summary.studentDisplayName)
        }
        return String(format: String(localized: "student.list.trainingBarFormat"), summary.studentDisplayName, minutes)
    }

    static func monthDay(_ instant: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: instant)
    }
}

/// 10 学员列表 (T069b; `21-student-list-v2`, `22-archived-students`,
/// `16-empty-state`). The root screen shows the display title with the
/// resource-hub entry, the 今日/学员 switch, search, the in-training bar,
/// avatar rows (never sex, owner 2026-09-24), "已归档 · N ›", and the
/// pinned "＋ 新学员" button. The archived variant lists archived students
/// with a 恢复 action.
struct StudentListView: View {
    @StateObject private var viewModel: StudentListViewModel
    @Binding var path: [RootDestination]
    /// Set only for the root 学员 screen, which shows the 今日/学员 switch.
    private let rootTab: Binding<RootTab>?

    init(
        useCases: StudentUseCases,
        showsArchived: Bool = false,
        appointmentUseCases: AppointmentUseCases? = nil,
        creditLedgerUseCases: CreditLedgerUseCases? = nil,
        calendar: Calendar = .current,
        rootTab: Binding<RootTab>? = nil,
        path: Binding<[RootDestination]>
    ) {
        self.rootTab = rootTab
        _viewModel = StateObject(
            wrappedValue: StudentListViewModel(
                useCases: useCases,
                showsArchived: showsArchived,
                appointmentUseCases: appointmentUseCases,
                creditLedgerUseCases: creditLedgerUseCases,
                calendar: calendar
            )
        )
        _path = path
    }

    var body: some View {
        Group {
            if viewModel.showsArchived {
                archivedBody
            } else {
                rootBody
            }
        }
        .background(FCSemanticColors.surfacePage)
        .task { await viewModel.reload() }
        .onChange(of: path) { _, _ in
            Task { await viewModel.reload() }
        }
    }

    // MARK: Root 学员 screen

    private var isTrulyEmpty: Bool {
        viewModel.students.isEmpty && viewModel.query.isEmpty && viewModel.archivedCount == 0
    }

    private var rootBody: some View {
        VStack(spacing: FCPrimitives.space4) {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                header
                if let rootTab {
                    RootSegmentSwitch(rootTab: rootTab)
                }
            }
            .padding(.horizontal, FCPrimitives.space4)

            if isTrulyEmpty {
                noStudentsEmptyState
            } else {
                studentsScroll
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var studentsScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space3) {
                FCSearchField(String(localized: "student.list.search"), text: $viewModel.query)
                    .accessibilityIdentifier(FCAccessibilityID.studentListSearch)
                    .onChange(of: viewModel.query) { _, _ in
                        Task { await viewModel.reload() }
                    }

                if let inProgress = viewModel.inProgress, viewModel.query.isEmpty {
                    inTrainingBar(inProgress)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                }

                if viewModel.students.isEmpty {
                    searchEmptyState
                } else {
                    VStack(spacing: FCPrimitives.space1) {
                        ForEach(viewModel.students) { student in
                            activeRow(student)
                            FCListRowDivider()
                        }
                    }
                }

                if viewModel.query.isEmpty, viewModel.archivedCount > 0 {
                    FCGroupEntryRow(
                        title: String(localized: "student.list.archivedEntry"),
                        count: viewModel.archivedCount
                    ) {
                        path.append(.archivedList)
                    }
                    .accessibilityIdentifier(FCAccessibilityID.studentListArchived)
                }
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .safeAreaInset(edge: .bottom) {
            FCButton(title: String(localized: "student.list.newStudent")) {
                path.append(.editor(.add))
            }
            .accessibilityIdentifier(FCAccessibilityID.studentListAdd)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.vertical, FCPrimitives.space2)
            .background(FCSemanticColors.surfacePage)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text(String(localized: "student.list.title"))
                .fcFont(.display)
                .foregroundStyle(FCSemanticColors.actionPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            FCTitleIconButton(
                systemImage: "list.bullet.rectangle",
                accessibilityLabel: String(localized: "resourceHub.title")
            ) {
                path.append(.resourceHub)
            }
            .accessibilityIdentifier(FCAccessibilityID.resourceHubEntry)
            FCTitleIconButton(systemImage: "gearshape", accessibilityLabel: String(localized: "settings.entry")) {
                path.append(.settings)
            }
            .accessibilityIdentifier(FCAccessibilityID.settingsEntry)
        }
        .padding(.top, FCPrimitives.space4)
    }

    private func inTrainingBar(_ summary: InProgressTrainingSummary) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            FCActiveSessionBar(
                text: StudentListPresentation.trainingBar(summary, now: context.date),
                actionTitle: String(localized: "student.list.continue")
            ) {
                path.append(.activeSession(summary.studentID.rawValue))
            }
        }
        .accessibilityIdentifier(FCAccessibilityID.studentListInProgress)
    }

    /// Avatar initial + name + "训练重点 · …" + next class / package hint + ›.
    private func activeRow(_ student: Student) -> some View {
        let info = viewModel.rowInfo[student.id] ?? .init()
        return Button {
            path.append(.studentDetail(student.id.rawValue))
        } label: {
            HStack(spacing: FCPrimitives.space4) {
                FCAvatar(initial: String(student.displayName.value.prefix(1)))
                VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                    Text(student.displayName.value)
                        .fcFont(.headline)
                        .foregroundStyle(FCSemanticColors.textPrimary)
                    Text(StudentListPresentation.focus(info.focus))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
                Spacer(minLength: FCPrimitives.space2)
                if let trailing = info.trailing {
                    Text(trailing)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
                FCSymbol(.forward)
            }
            .padding(.vertical, FCPrimitives.space3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(FCAccessibilityID.studentRow(student.id))
    }

    private var searchEmptyState: some View {
        VStack(spacing: FCPrimitives.space2) {
            Text(String(localized: "student.list.searchEmptyTitle"))
                .fcFont(.headline)
                .foregroundStyle(FCSemanticColors.textPrimary)
            Text(String(localized: "student.list.searchEmptyBody"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FCPrimitives.space6)
        .accessibilityIdentifier(FCAccessibilityID.studentListEmpty)
    }

    /// 16 空态 (T067, §8 "空态"): mascot 220×220 (decorative) → title
    /// `headline` `action.primary` → note `caption` `text.secondary` →
    /// pinned primary button.
    private var noStudentsEmptyState: some View {
        VStack(spacing: FCPrimitives.space3) {
            Spacer(minLength: FCPrimitives.space6)
            Image("mascot-empty-state")
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .accessibilityHidden(true)
            Text(String(localized: "student.list.emptyTitle"))
                .fcFont(.headline)
                .foregroundStyle(FCSemanticColors.actionPrimary)
                .padding(.top, FCPrimitives.space6)
            Text(String(localized: "student.list.emptyBody"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            FCButton(title: String(localized: "student.list.emptyAction")) {
                path.append(.editor(.add))
            }
            .accessibilityIdentifier(FCAccessibilityID.studentListEmptyAdd)
            .padding(.bottom, FCPrimitives.space4)
        }
        .padding(.horizontal, FCPrimitives.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.studentListEmpty)
    }

    // MARK: 已归档学员 (22)

    private var archivedBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(title: String(localized: "student.list.archivedTitle"), back: .init())
                Text(String(localized: "student.archived.note"))
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                }

                if viewModel.students.isEmpty {
                    VStack(spacing: FCPrimitives.space2) {
                        Text(String(localized: "student.list.archivedEmptyTitle"))
                            .fcFont(.headline)
                            .foregroundStyle(FCSemanticColors.textPrimary)
                        Text(String(localized: "student.list.archivedEmptyBody"))
                            .fcFont(.caption)
                            .foregroundStyle(FCSemanticColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FCPrimitives.space6)
                    .accessibilityIdentifier(FCAccessibilityID.studentListEmpty)
                } else {
                    VStack(spacing: FCPrimitives.space1) {
                        FCListRowDivider()
                        ForEach(viewModel.students) { student in
                            archivedRow(student)
                            FCListRowDivider()
                        }
                    }
                }
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .fcSecondaryPage()
    }

    /// Avatar + name + "归档于 M月d日" + 恢复. The date is the student's last
    /// update, which is the archive itself: an archived student cannot be
    /// edited until restored.
    private func archivedRow(_ student: Student) -> some View {
        HStack(spacing: FCPrimitives.space4) {
            Button {
                path.append(.studentDetail(student.id.rawValue))
            } label: {
                HStack(spacing: FCPrimitives.space4) {
                    FCAvatar(initial: String(student.displayName.value.prefix(1)))
                    VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                        Text(student.displayName.value)
                            .fcFont(.headline)
                            .foregroundStyle(FCSemanticColors.textPrimary)
                        Text(
                            String(
                                format: String(localized: "student.archived.archivedOnFormat"),
                                StudentListPresentation.monthDay(student.updatedAtUTC)
                            )
                        )
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                    }
                    Spacer(minLength: FCPrimitives.space2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(FCAccessibilityID.studentRow(student.id))

            FCLinkButton(title: String(localized: "student.archived.restore")) {
                Task { await viewModel.restore(student) }
            }
            .accessibilityLabel(Text("\(String(localized: "student.archived.restore")) \(student.displayName.value)"))
        }
        .padding(.vertical, FCPrimitives.space3)
    }
}
