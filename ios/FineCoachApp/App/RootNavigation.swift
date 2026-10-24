import SwiftUI

enum RootDestination: Hashable {
    case archivedList
    case resourceHub
    case settings
    case studentDetail(UUID)
    case editor(StudentEditorMode)
    case activeSession(UUID)
    case exerciseLibrary
    case sessionSummary(UUID)
    case history(UUID)
    case sessionDetail(UUID)
    case sessionEdit(UUID)
    case shareReport(UUID)
    case backupRestore
    case calendar
    case appointmentEditor(AppointmentEditorMode)
    case coursePackages(UUID)
    case coursePackageEditor(UUID)
    case creditAdjustmentTrail(UUID)
    case manualCreditAdjustment(UUID)
    case templates
    case templateEditor(UUID)
    case bodyData(UUID)
    case bodyMeasurementEntry(studentID: UUID, metricID: UUID)
    case trends(UUID)
    case insightTrend(studentID: UUID, exerciseID: StableExerciseID)
    case insights
    case archiveExport(UUID)
    #if DEBUG
        /// 动效试验（开发版）only exists in DEBUG builds (README §14.1).
        case motionLab
    #endif
    case placeholder(PlaceholderKind)
}

enum AppointmentEditorMode: Hashable {
    case create(studentID: UUID?, date: LocalDate)
    case edit(UUID)
}

enum StudentEditorMode: Hashable {
    case firstCreate
    case add
    case edit(UUID)
}

enum PlaceholderKind: Hashable {
    case startTraining
    case continueTraining
    case recentTraining
    case history
    case backup
    case exerciseLibrary
    case settings
}

enum RootTab: Hashable {
    case today
    case students
}

@MainActor
struct RootNavigation: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var restNotificationRouter: RestNotificationRouter
    @State private var path: [RootDestination] = []
    @State private var onboardingCompleted = false
    @State private var didLoadOnboarding = false
    @State private var isNavigationStackMounted = false
    @State private var rootTab: RootTab = .today
    /// Set by `AppRoot` while the install is `unselected`, so first-launch onboarding can go
    /// back to the Coach / import choice (M2-07).
    var onBackToChoice: (() -> Void)?

    var body: some View {
        // The app-wide `PrivacyCover` now lives in `AppRoot`, above this branch.
        Group {
            Group {
                if !environment.isStorageAvailable {
                    Text(environment.startupErrorDescription ?? String(localized: "storage.unavailable"))
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(FCSemanticColors.surfacePage)
                } else if let catalogUnavailableMessage = environment.catalogUnavailableMessage {
                    Text(catalogUnavailableMessage)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(FCSemanticColors.surfacePage)
                } else if !didLoadOnboarding {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(FCSemanticColors.surfacePage)
                } else if !onboardingCompleted {
                    OnboardingView(
                        viewModel: OnboardingViewModel(useCases: environment.requireUseCases()),
                        onFinished: {
                            onboardingCompleted = true
                        },
                        onBack: onBackToChoice
                    )
                } else {
                    NavigationStack(path: $path) {
                        RootTabContainer(
                            rootTab: $rootTab,
                            path: $path,
                            environment: environment
                        )
                        .navigationDestination(for: RootDestination.self) { destination in
                            switch destination {
                            case .insights:
                                InsightsListView(
                                    useCases: environment.insightUseCases, students: environment.requireUseCases(),
                                    exercises: environment.exerciseUseCases, history: environment.historyUseCases,
                                    path: $path)
                            case .insightTrend(let studentID, let exerciseID):
                                TrendsView(
                                    studentID: StableUUID(studentID),
                                    historyUseCases: environment.requireHistoryUseCases(),
                                    exerciseUseCases: environment.requireExerciseUseCases(),
                                    calendarProvider: SystemLocalCalendarProvider(), initialExerciseID: exerciseID)
                            case .resourceHub:
                                ResourceHubView(
                                    exerciseUseCases: environment.requireExerciseUseCases(),
                                    templateUseCases: environment.requireTemplateUseCases(),
                                    path: $path
                                )
                            case .archivedList:
                                StudentListView(
                                    useCases: environment.requireUseCases(),
                                    showsArchived: true,
                                    path: $path
                                )
                            case .studentDetail(let id):
                                StudentDetailView(
                                    studentID: StableUUID(id),
                                    useCases: environment.requireUseCases(),
                                    historyUseCases: environment.requireHistoryUseCases(),
                                    appointmentUseCases: environment.requireAppointmentUseCases(),
                                    creditLedgerUseCases: environment.creditLedgerUseCases,
                                    insightUseCases: environment.insightUseCases,
                                    exerciseUseCases: environment.exerciseUseCases,
                                    calendar: environment.requireCalendar(),
                                    path: $path
                                )
                            case .editor(let mode):
                                StudentEditorView(
                                    viewModel: StudentEditorViewModel(
                                        mode: mode,
                                        useCases: environment.requireUseCases()
                                    ),
                                    path: $path,
                                    onFinished: { _ in
                                        if !onboardingCompleted {
                                            onboardingCompleted = true
                                        }
                                    }
                                )
                            case .activeSession(let studentID):
                                ActiveSessionView(
                                    studentID: StableUUID(studentID),
                                    useCases: environment.requireSessionUseCases(),
                                    templateUseCases: environment.templateUseCases,
                                    studentUseCases: environment.requireUseCases(),
                                    creditSettlement: environment.sessionCreditSettlement,
                                    path: $path
                                )
                                .id(studentID)
                            case .exerciseLibrary:
                                ExerciseLibraryView(
                                    useCases: environment.requireExerciseUseCases(),
                                    historyUseCases: environment.requireHistoryUseCases()
                                )
                            #if DEBUG
                                case .motionLab:
                                    MotionLabView()
                            #endif
                            case .sessionSummary(let sessionID):
                                SessionSummaryView(
                                    sessionID: StableUUID(sessionID),
                                    useCases: environment.requireHistoryUseCases(),
                                    templateUseCases: environment.templateUseCases,
                                    exerciseUseCases: environment.requireExerciseUseCases(),
                                    rootTab: $rootTab,
                                    path: $path
                                )
                            case .history(let studentID):
                                HistoryListView(
                                    studentID: StableUUID(studentID),
                                    useCases: environment.requireHistoryUseCases(),
                                    studentUseCases: environment.requireUseCases(),
                                    exerciseUseCases: environment.requireExerciseUseCases(),
                                    path: $path
                                )
                            case .sessionDetail(let sessionID):
                                SessionDetailView(
                                    sessionID: StableUUID(sessionID),
                                    useCases: environment.requireHistoryUseCases(),
                                    templateUseCases: environment.templateUseCases,
                                    exerciseUseCases: environment.requireExerciseUseCases(),
                                    path: $path
                                )
                            case .sessionEdit(let sessionID):
                                SessionEditView(
                                    sessionID: StableUUID(sessionID),
                                    useCases: environment.requireHistoryUseCases(),
                                    path: $path
                                )
                            case .shareReport(let sessionID):
                                ShareReportFlowView(
                                    sessionID: StableUUID(sessionID),
                                    useCases: environment.requireHistoryUseCases(),
                                    exerciseUseCases: environment.requireExerciseUseCases(),
                                    reportsRootURL: environment.requireReportsRootURL(),
                                    shareAdapter: environment.requireShareAdapter(),
                                    rootTab: $rootTab,
                                    path: $path
                                )
                            case .settings:
                                SettingsView(path: $path)
                            case .backupRestore:
                                BackupExportFlowView(
                                    coordinator: environment.requireBackupCoordinator(),
                                    path: $path
                                )
                            case .calendar:
                                CalendarView(
                                    appointmentUseCases: environment.requireAppointmentUseCases(),
                                    studentUseCases: environment.requireUseCases(),
                                    creditLedgerUseCases: environment.creditLedgerUseCases,
                                    calendar: environment.requireCalendar(),
                                    path: $path
                                )
                            case .appointmentEditor(let editorMode):
                                AppointmentEditorView(
                                    mode: editorMode,
                                    appointmentUseCases: environment.requireAppointmentUseCases(),
                                    studentUseCases: environment.requireUseCases(),
                                    calendar: environment.requireCalendar()
                                )
                            case .coursePackages(let studentID):
                                CoursePackageListView(
                                    studentID: StableUUID(studentID),
                                    useCases: environment.requireCreditLedgerUseCases(),
                                    studentUseCases: environment.requireUseCases(),
                                    path: $path
                                )
                            case .coursePackageEditor(let studentID):
                                CoursePackageEditorView(
                                    studentID: StableUUID(studentID),
                                    useCases: environment.requireCreditLedgerUseCases(),
                                    path: $path
                                )
                            case .creditAdjustmentTrail(let packageID):
                                CreditAdjustmentTrailView(
                                    packageID: StableUUID(packageID),
                                    useCases: environment.requireCreditLedgerUseCases()
                                )
                            case .manualCreditAdjustment(let packageID):
                                ManualCreditAdjustmentView(
                                    packageID: StableUUID(packageID),
                                    useCases: environment.requireCreditLedgerUseCases(),
                                    path: $path
                                )
                            case .templates:
                                TemplateListView(
                                    useCases: environment.requireTemplateUseCases(),
                                    path: $path
                                )
                            case .templateEditor(let templateID):
                                TemplateEditorView(
                                    templateID: StableUUID(templateID),
                                    useCases: environment.requireTemplateUseCases()
                                )
                            case .bodyData(let studentID):
                                BodyDataListView(
                                    studentID: StableUUID(studentID),
                                    useCases: environment.requireBodyDataUseCases(),
                                    studentUseCases: environment.requireUseCases(),
                                    path: $path
                                )
                            case .bodyMeasurementEntry(let studentID, let metricID):
                                BodyMeasurementEntryView(
                                    studentID: StableUUID(studentID),
                                    metricID: StableUUID(metricID),
                                    useCases: environment.requireBodyDataUseCases()
                                )
                            case .trends(let studentID):
                                TrendsView(
                                    studentID: StableUUID(studentID),
                                    historyUseCases: environment.requireHistoryUseCases(),
                                    exerciseUseCases: environment.requireExerciseUseCases(),
                                    calendarProvider: SystemLocalCalendarProvider()
                                )
                            case .archiveExport(let studentID):
                                ArchiveExportFlowView(
                                    studentID: StableUUID(studentID),
                                    useCases: environment.requireArchiveExportUseCases(),
                                    studentUseCases: environment.requireUseCases(),
                                    path: $path
                                )
                            case .placeholder(let kind):
                                PlaceholderDestinationView(kind: kind)
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(FCAccessibilityID.studentList)
                    .onAppear {
                        // State loaded by the outer task only selects this branch;
                        // it does not mean NavigationStack has been inserted yet.
                        isNavigationStackMounted = true
                        RestNotificationDiagnostics.record(.stackReady)
                        Task { await consumePendingRestNotificationIfReady() }
                    }
                    .onDisappear {
                        isNavigationStackMounted = false
                        RestNotificationDiagnostics.record(.stackRemoved)
                    }
                }
            }
        }
        .task {
            await loadInitialState()
        }
        .onChange(of: restNotificationRouter.pendingRequest) { _, request in
            guard request != nil else {
                return
            }
            Task { await consumePendingRestNotificationIfReady() }
        }
        .onChange(of: path) { _, nextPath in
            RestNotificationDiagnostics.record(nextPath.isEmpty ? .pathEmpty : .pathNonempty)
        }
    }

    private func loadInitialState() async {
        RestNotificationDiagnostics.record(.rootLoading)
        #if DEBUG
            await environment.applyUITestSeedingIfNeeded()
        #endif
        await environment.prepareExerciseCatalog()
        await T116PerformanceHarness.runIfRequested(using: environment)
        guard let useCases = environment.studentUseCases else {
            didLoadOnboarding = true
            return
        }
        onboardingCompleted = (try? await useCases.isOnboardingCompleted()) ?? false
        didLoadOnboarding = true
        RestNotificationDiagnostics.record(.rootLoaded)
        // NavigationStack.onAppear consumes an early tap after insertion.
        // Later taps are consumed by the pendingRequest observer.
    }

    /// Mirrors the branches that actually render `NavigationStack` below.
    private var isReadyForRestNotification: Bool {
        environment.isStorageAvailable && environment.catalogUnavailableMessage == nil
            && didLoadOnboarding && onboardingCompleted && isNavigationStackMounted
    }

    /// Consume at most one request. The request is taken (cleared) before the
    /// async reads, so it cannot be replayed; if the reads say "no route" the
    /// tap only opened the app.
    private func consumePendingRestNotificationIfReady() async {
        guard let studentUseCases = environment.studentUseCases,
            let sessionUseCases = environment.sessionUseCases
        else {
            return
        }
        guard let request = restNotificationRouter.takePendingRequest(ifReady: isReadyForRestNotification) else {
            return
        }
        // Read-only lookups only: `startOrOpen` is never called here.
        let studentExists = (try? await studentUseCases.student(id: request.studentID)) != nil
        let activeSession = try? await sessionUseCases.loadActive(sessionID: request.sessionID)
        let conditions = RestNotificationRouteConditions(
            isCoachMode: true,
            isStorageAvailable: environment.isStorageAvailable,
            isOnboardingCompleted: onboardingCompleted,
            isRootNavigationReady: isNavigationStackMounted
        )
        let decision = RestNotificationRouting.decide(
            request: request,
            conditions: conditions,
            studentExists: studentExists,
            activeSession: activeSession ?? nil
        )
        guard case .route(let routed) = decision else {
            RestNotificationDiagnostics.record(.ignoredNoRoute)
            return
        }
        showRestNotificationRoute(routed)
    }

    /// 今日 is the default root surface (M1B-FR-001) and hosts the in-progress
    /// training entry; the destination replaces the stack instead of pushing a
    /// duplicate when that Session is already on screen.
    private func showRestNotificationRoute(_ request: RestNotificationRouteRequest) {
        let nextPath = RestNotificationNavigation.path(current: path, studentID: request.studentID)
        guard nextPath != path else {
            return
        }
        rootTab = .today
        path = nextPath
        RestNotificationDiagnostics.record(.routed)
    }
}

@MainActor
struct RootTabContainer: View {
    @Binding var rootTab: RootTab
    @Binding var path: [RootDestination]
    let environment: AppEnvironment

    // The 今日/学员 switch now sits under each screen's large title
    // (01/21 artwork), so each root screen renders `RootSegmentSwitch`.
    var body: some View {
        Group {
            switch rootTab {
            case .today:
                TodayView(
                    appointmentUseCases: environment.requireAppointmentUseCases(),
                    studentUseCases: environment.requireUseCases(),
                    creditLedgerUseCases: environment.creditLedgerUseCases,
                    insightUseCases: environment.insightUseCases,
                    exerciseUseCases: environment.exerciseUseCases,
                    historyUseCases: environment.historyUseCases,
                    rootTab: $rootTab,
                    path: $path
                )
            case .students:
                StudentListView(
                    useCases: environment.requireUseCases(),
                    appointmentUseCases: environment.requireAppointmentUseCases(),
                    creditLedgerUseCases: environment.creditLedgerUseCases,
                    calendar: environment.requireCalendar(),
                    rootTab: $rootTab,
                    path: $path
                )
            }
        }
        .background(FCSemanticColors.surfacePage)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.studentList)
    }
}

/// The top-level 今日 / 学员 switch (§8 "顶部分段切换", `FCSegmentedSwitch`).
struct RootSegmentSwitch: View {
    @Binding var rootTab: RootTab

    private static let options = [
        FCSegmentedSwitch.Option(id: "today", title: String(localized: "today.segment.today")),
        FCSegmentedSwitch.Option(id: "students", title: String(localized: "today.segment.students")),
    ]

    var body: some View {
        FCSegmentedSwitch(
            options: Self.options,
            selection: Binding(
                get: { rootTab == .today ? "today" : "students" },
                set: { rootTab = $0 == "today" ? .today : .students }
            )
        )
    }
}

struct PlaceholderDestinationView: View {
    let kind: PlaceholderKind

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            Text(title)
                .fcFont(.title)
            Text(String(localized: "placeholder.boundary"))
                .foregroundStyle(FCSemanticColors.textSecondary)
            Spacer()
        }
        .padding(FCPrimitives.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        switch kind {
        case .startTraining, .continueTraining:
            return String(localized: "placeholder.training")
        case .recentTraining:
            return String(localized: "placeholder.recent")
        case .history:
            return String(localized: "placeholder.history")
        case .backup:
            return String(localized: "placeholder.backup")
        case .exerciseLibrary:
            return String(localized: "placeholder.library")
        case .settings:
            return String(localized: "placeholder.settings")
        }
    }
}

extension Array where Element == RootDestination {
    mutating func popToStudentDetail() {
        if let index = lastIndex(where: {
            if case .studentDetail = $0 {
                return true
            }
            return false
        }) {
            removeSubrange((index + 1)..<count)
            return
        }
        removeAll()
    }

    /// C15: 「完成」/「跳过分享」end the report flow at the 今日 root. The stack
    /// and the top-level segment are separate state, so both move here:
    /// clearing only the stack would leave the user on 学员, and switching
    /// only the tab would keep the old flow alive behind it.
    mutating func returnToToday(tab: inout RootTab) {
        removeAll()
        tab = .today
    }
}
