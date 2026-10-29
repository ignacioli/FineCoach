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
        if let active = try? await useCases.loadAllActive() {
            await environment.sessionActivityController.cleanupStale(
                activeSessionIDs: Set(active.map { $0.id.rawValue.uuidString.lowercased() }))
        }
        // Settles a linked finish interrupted before its Appointment and
        // credit were written (idempotent; settled ones are skipped).
        await environment.sessionCreditSettlement?.repairInterruptedLinkedSessions()
        await environment.widgetSnapshotPublisher?.refresh()
    }

    public func sceneWillResignActive(environment: AppEnvironment) async {
        guard let useCases = environment.sessionUseCases else {
            return
        }
        _ = try? await useCases.checkpointOnBackground()
    }
}
