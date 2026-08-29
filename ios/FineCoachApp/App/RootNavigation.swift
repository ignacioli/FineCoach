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
    case placeholder(PlaceholderKind)
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

@MainActor
struct RootNavigation: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var privacyCoordinator: ScenePrivacyCoordinator
    @State private var path: [RootDestination] = []
    @State private var onboardingCompleted = false
    @State private var didLoadOnboarding = false

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
                        StudentListView(
                            useCases: environment.requireUseCases(),
                            path: $path
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
        guard let useCases = environment.studentUseCases else {
            didLoadOnboarding = true
            return
        }
        onboardingCompleted = (try? await useCases.isOnboardingCompleted()) ?? false
        didLoadOnboarding = true
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
