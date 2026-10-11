import SwiftUI

/// The scene's root view. It resolves the install state once per launch and shows exactly one
/// of two mutually exclusive branches (M2-FR-025):
///
/// - `viewer` -> `ArchiveViewerRoot`, which receives nothing from the Coach environment;
/// - `coach` and `unselected` -> the existing `RootNavigation` (first launch still shows
///   `OnboardingView` there until the two-way choice replaces it).
///
/// The task-switcher `PrivacyCover` lives here, above every branch, so no branch can forget it
/// (NFR-003). Modal content still covers itself with `fcPrivacyCovered()`.
@MainActor
struct AppRoot: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var privacyCoordinator: ScenePrivacyCoordinator
    @State private var installState: InstallState?
    /// Archive-mode services for the import and viewer pages (T041+ pass them on; T045 only
    /// builds them so there is one store and one resolver per launch).
    @State private var archiveServices: ArchiveServices?

    var body: some View {
        ZStack {
            switch installState {
            case nil:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(FCSemanticColors.surfacePage)
            case .viewer:
                ArchiveViewerRoot()
            case .coach, .unselected:
                RootNavigation()
            }

            if privacyCoordinator.isCovered {
                PrivacyCover()
            }
        }
        .task {
            guard installState == nil else {
                return
            }
            installState = await resolveInstallState()
        }
    }

    /// Janitor first, then the resolver. A Coach store that cannot be read must not become
    /// `unselected`; `RootNavigation` reports storage problems itself, so it is the fallback.
    private func resolveInstallState() async -> InstallState {
        guard let services = try? environment.makeArchiveServices() else {
            return .coach
        }
        archiveServices = services
        let store = services.store
        // A failed janitor is not fatal: leftovers are retried on the next launch and an
        // unreadable snapshot already resolves as "not viewer".
        await Task.detached { try? store.runStartupJanitor() }.value
        return (try? await services.installStateResolver.resolve()) ?? .coach
    }
}
