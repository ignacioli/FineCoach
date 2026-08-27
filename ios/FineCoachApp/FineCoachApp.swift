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
            RootView()
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

@MainActor
private struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var privacyCoordinator: ScenePrivacyCoordinator

    var body: some View {
        ZStack {
            Group {
                if environment.isStorageAvailable {
                    Text("精练教练")
                        .font(.title2.weight(.semibold))
                } else {
                    Text(environment.startupErrorDescription ?? "本地存储暂不可用。")
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FCSemanticColors.background)

            if privacyCoordinator.isCovered {
                PrivacyCover()
            }
        }
    }
}
