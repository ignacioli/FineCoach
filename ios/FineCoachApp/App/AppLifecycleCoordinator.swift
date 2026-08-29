import Combine
import SwiftUI

@MainActor
public final class AppLifecycleCoordinator: ObservableObject {
    public init() {}

    public func sceneDidBecomeActive(environment: AppEnvironment) async {
        guard let useCases = environment.sessionUseCases else {
            return
        }
        _ = try? await PerformanceSignposts.shared.measureRecovery {
            try await useCases.reconcileOnLaunch()
        }
    }

    public func sceneWillResignActive(environment: AppEnvironment) async {
        guard let useCases = environment.sessionUseCases else {
            return
        }
        _ = try? await useCases.checkpointOnBackground()
    }
}
