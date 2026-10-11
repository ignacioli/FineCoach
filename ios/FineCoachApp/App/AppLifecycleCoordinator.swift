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
        // Settles a linked finish interrupted before its Appointment and
        // credit were written (idempotent; settled ones are skipped).
        await environment.sessionCreditSettlement?.repairInterruptedLinkedSessions()
    }

    public func sceneWillResignActive(environment: AppEnvironment) async {
        guard let useCases = environment.sessionUseCases else {
            return
        }
        _ = try? await useCases.checkpointOnBackground()
    }
}
