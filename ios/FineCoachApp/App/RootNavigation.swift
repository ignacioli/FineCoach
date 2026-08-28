import SwiftUI

enum RootDestination: Hashable {
    case archivedList
    case studentDetail(UUID)
    case editor(StudentEditorMode)
    case activeSession(UUID)
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
