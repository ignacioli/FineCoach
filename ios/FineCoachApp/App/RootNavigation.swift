import SwiftUI

enum RootDestination: Hashable {
    case archivedList
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
    case applyTemplate
    case bodyData(UUID)
    case bodyMeasurementEntry(studentID: UUID, metricID: UUID)
    case trends(UUID)
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
    @EnvironmentObject private var privacyCoordinator: ScenePrivacyCoordinator
    @State private var path: [RootDestination] = []
    @State private var onboardingCompleted = false
    @State private var didLoadOnboarding = false
    @State private var rootTab: RootTab = .today

    var body: some View {
        ZStack {
            Group {
                if !environment.isStorageAvailable {
                    Text(environment.startupErrorDescription ?? String(localized: "storage.unavailable"))
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(FCSemanticColors.background)
                } else if let catalogUnavailableMessage = environment.catalogUnavailableMessage {
                    Text(catalogUnavailableMessage)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(FCSemanticColors.background)
                } else if !didLoadOnboarding {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(FCSemanticColors.background)
                } else if !onboardingCompleted {
                    OnboardingView(
                        viewModel: OnboardingViewModel(useCases: environment.requireUseCases()),
                        onFinished: {
                            onboardingCompleted = true
                        }
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
                                    path: $path
                                )
                            case .exerciseLibrary:
                                ExerciseLibraryView(useCases: environment.requireExerciseUseCases())
                            case .sessionSummary(let sessionID):
                                SessionSummaryView(
                                    sessionID: StableUUID(sessionID),
                                    useCases: environment.requireHistoryUseCases(),
                                    path: $path
                                )
                            case .history(let studentID):
                                HistoryListView(
                                    studentID: StableUUID(studentID),
                                    useCases: environment.requireHistoryUseCases(),
                                    path: $path
                                )
                            case .sessionDetail(let sessionID):
                                SessionDetailView(
                                    sessionID: StableUUID(sessionID),
                                    useCases: environment.requireHistoryUseCases(),
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
                                    reportsRootURL: environment.requireReportsRootURL(),
                                    renderer: ShareReportRenderer(),
                                    shareAdapter: environment.requireShareAdapter(),
                                    path: $path
                                )
                            case .backupRestore:
                                BackupExportFlowView(
                                    coordinator: environment.requireBackupCoordinator(),
                                    path: $path
                                )
                            case .calendar:
                                CalendarView(
                                    appointmentUseCases: environment.requireAppointmentUseCases(),
                                    studentUseCases: environment.requireUseCases(),
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
                            case .applyTemplate:
                                ApplyTemplateView(
                                    templateUseCases: environment.requireTemplateUseCases(),
                                    sessionUseCases: environment.requireSessionUseCases(),
                                    path: $path
                                )
                            case .bodyData(let studentID):
                                BodyDataListView(
                                    studentID: StableUUID(studentID),
                                    useCases: environment.requireBodyDataUseCases(),
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
                                    calendarProvider: SystemLocalCalendarProvider()
                                )
                            case .placeholder(let kind):
                                PlaceholderDestinationView(kind: kind)
                            }
                        }
                    }
                    .accessibilityIdentifier(FCAccessibilityID.studentList)
                }
            }

            if privacyCoordinator.isCovered {
                PrivacyCover()
            }
        }
        .task {
            await loadInitialState()
        }
    }

    private func loadInitialState() async {
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
    }
}

@MainActor
struct RootTabContainer: View {
    @Binding var rootTab: RootTab
    @Binding var path: [RootDestination]
    let environment: AppEnvironment

    var body: some View {
        VStack(spacing: 0) {
            segmentedControl
            switch rootTab {
            case .today:
                TodayView(
                    appointmentUseCases: environment.requireAppointmentUseCases(),
                    studentUseCases: environment.requireUseCases(),
                    creditLedgerUseCases: environment.creditLedgerUseCases,
                    path: $path
                )
            case .students:
                StudentListView(
                    useCases: environment.requireUseCases(),
                    path: $path
                )
            }
        }
        .background(FCSemanticColors.background)
        .accessibilityIdentifier(FCAccessibilityID.studentList)
    }

    private var segmentedControl: some View {
        HStack(spacing: FCPrimitives.spacingSmall) {
            segmentButton(String(localized: "today.segment.today"), tab: .today)
                .accessibilityIdentifier(FCAccessibilityID.todaySegmentToday)
            segmentButton(String(localized: "today.segment.students"), tab: .students)
                .accessibilityIdentifier(FCAccessibilityID.todaySegmentStudents)
            Spacer()
        }
        .padding(.horizontal, FCPrimitives.spacingMedium)
        .padding(.top, FCPrimitives.spacingSmall)
    }

    private func segmentButton(_ title: String, tab: RootTab) -> some View {
        Button {
            rootTab = tab
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, FCPrimitives.spacingMedium)
                .frame(minHeight: 44)
                .background(
                    Capsule().fill(rootTab == tab ? FCSemanticColors.primaryText : FCSemanticColors.tint)
                )
                .foregroundStyle(rootTab == tab ? FCSemanticColors.background : FCSemanticColors.primaryText)
        }
    }
}

struct PlaceholderDestinationView: View {
    let kind: PlaceholderKind

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(String(localized: "placeholder.boundary"))
                .foregroundStyle(FCSemanticColors.secondaryText)
            Spacer()
        }
        .padding(FCPrimitives.spacingMedium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FCSemanticColors.background)
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
}
