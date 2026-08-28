import SwiftUI

@main
@MainActor
struct FineCoachApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var environment: AppEnvironment
    @StateObject private var privacyCoordinator = ScenePrivacyCoordinator()

    init() {
        _environment = StateObject(wrappedValue: AppEnvironment.bootstrap())
    }

    var body: some Scene {
        WindowGroup {
            RootNavigation()
                .environmentObject(environment)
                .environmentObject(privacyCoordinator)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                privacyCoordinator.sceneDidBecomeActive()
            case .inactive, .background:
                privacyCoordinator.sceneWillResignActive()
            @unknown default:
                privacyCoordinator.sceneWillResignActive()
            }
        }
    }
}
