import SwiftUI

@main
@MainActor
struct FineCoachApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var environment: AppEnvironment
    @StateObject private var privacyCoordinator = ScenePrivacyCoordinator()
    @StateObject private var lifecycleCoordinator = AppLifecycleCoordinator()

    init() {
        _environment = StateObject(wrappedValue: AppEnvironment.bootstrap())
    }

    var body: some Scene {
        WindowGroup {
            RootNavigation()
                .environmentObject(environment)
                .environmentObject(privacyCoordinator)
                .task {
                    await lifecycleCoordinator.sceneDidBecomeActive(environment: environment)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                privacyCoordinator.sceneDidBecomeActive()
                Task {
                    await lifecycleCoordinator.sceneDidBecomeActive(environment: environment)
                }
            case .inactive:
                privacyCoordinator.sceneWillResignActive()
            case .background:
                privacyCoordinator.sceneWillResignActive()
                Task {
                    await lifecycleCoordinator.sceneWillResignActive(environment: environment)
                }
            @unknown default:
                privacyCoordinator.sceneWillResignActive()
            }
        }
    }
}
