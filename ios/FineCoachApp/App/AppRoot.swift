import SwiftUI

/// The scene's root view. It resolves the install state once per launch and shows exactly one
/// of the mutually exclusive branches (M2-FR-025):
///
/// - `viewer` -> `ArchiveViewerRoot`, which receives only the archive services, nothing from
///   the Coach environment;
/// - `coach` -> the existing `RootNavigation`;
/// - `unselected` -> the first-launch choice (M2-07): Coach use shows `RootNavigation` (whose
///   onboarding can go back), archive import shows the import flow.
///
/// An archive file opened from outside the app (`onOpenURL`, `.fcarchive` only) is routed by
/// `ArchiveOpenRouter` and shown as a layer above the branch, so back returns to wherever the
/// user was. The task-switcher `PrivacyCover` lives here, above every branch and layer, so none
/// can forget it (NFR-003). Modal content still covers itself with `fcPrivacyCovered()`.
@MainActor
struct AppRoot: View {
    private enum FirstLaunchRoute {
        case choice
        case coach
    }

    /// An archive file the system opened, and where it goes.
    private struct SystemOpenRequest: Identifiable {
        let id = UUID()
        let url: URL
        let destination: ArchiveOpenDestination
    }

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var privacyCoordinator: ScenePrivacyCoordinator
    @State private var installState: InstallState?
    @State private var archiveServices: ArchiveServices?
    @State private var firstLaunchRoute: FirstLaunchRoute = .choice
    @State private var showsImportFromChoice = false
    @State private var systemOpen: SystemOpenRequest?
    /// A file opened before the archive services were ready (cold start).
    @State private var pendingOpenURL: URL?

    var body: some View {
        ZStack {
            switch installState {
            case nil:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(FCSemanticColors.surfacePage)
            case .viewer:
                if let archiveServices {
                    ArchiveViewerRoot(services: archiveServices)
                }
            case .coach:
                RootNavigation()
            case .unselected:
                firstLaunch
            }

            if let request = systemOpen, let archiveServices {
                systemOpenLayer(request, services: archiveServices)
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
            if let url = pendingOpenURL {
                pendingOpenURL = nil
                handleOpen(url)
            }
        }
        .onOpenURL { handleOpen($0) }
    }

    // MARK: First launch (M2-07)

    @ViewBuilder
    private var firstLaunch: some View {
        switch firstLaunchRoute {
        case .coach:
            RootNavigation(onBackToChoice: { firstLaunchRoute = .choice })
        case .choice:
            NavigationStack {
                FirstLaunchChoiceView(
                    onChooseCoach: { firstLaunchRoute = .coach },
                    onChooseImport: { showsImportFromChoice = true }
                )
                .navigationDestination(isPresented: $showsImportFromChoice) {
                    if let archiveServices {
                        ArchiveImportFlowView(
                            useCases: archiveServices.importUseCases,
                            prefilledURL: nil,
                            onBack: { showsImportFromChoice = false },
                            onInstalled: { Task { await refreshInstallState() } }
                        )
                    }
                }
            }
        }
    }

    // MARK: System open (T044)

    @ViewBuilder
    private func systemOpenLayer(_ request: SystemOpenRequest, services: ArchiveServices) -> some View {
        Group {
            switch request.destination {
            case .importPrefilled:
                NavigationStack {
                    ArchiveImportFlowView(
                        useCases: services.importUseCases,
                        prefilledURL: request.url,
                        onBack: { systemOpen = nil },
                        onInstalled: {
                            systemOpen = nil
                            Task { await refreshInstallState() }
                        }
                    )
                }
            case .blocked:
                ArchiveImportBlockedView(onDismiss: { closeSystemOpen(request, services: services) })
            case .replacePrefilled:
                // US-3 (T055) changes this mapping only: the routing above stays.
                ArchiveReplacePlaceholderView(onBack: { closeSystemOpen(request, services: services) })
            }
        }
        .id(request.id)
        .background(FCSemanticColors.surfacePage)
        .transition(.opacity)
    }

    /// The flows of `.blocked` and `.replacePrefilled` end here; the import flow deletes its
    /// own copy. Only the app's `Documents/Inbox` copy is deleted, never the source file.
    private func closeSystemOpen(_ request: SystemOpenRequest, services: ArchiveServices) {
        systemOpen = nil
        Task { await services.importUseCases.discardInboxCopy(at: request.url) }
    }

    /// Only `.fcarchive` files are accepted; anything else is ignored and left untouched.
    private func handleOpen(_ url: URL) {
        guard url.isFileURL, url.pathExtension.lowercased() == "fcarchive" else {
            return
        }
        guard let services = archiveServices else {
            pendingOpenURL = url
            return
        }
        Task {
            if let previous = systemOpen {
                await services.importUseCases.discardInboxCopy(at: previous.url)
            }
            let destination: ArchiveOpenDestination
            do {
                destination = try await services.importUseCases.openDestination()
            } catch {
                // The Coach store cannot be read: show the import page, whose import fails
                // closed with the generic failure copy instead of claiming Coach data exists.
                destination = .importPrefilled
            }
            systemOpen = SystemOpenRequest(url: url, destination: destination)
        }
    }

    // MARK: Install state

    /// Janitor first, then the resolver. A Coach store that cannot be read must not become
    /// `unselected`; `RootNavigation` reports storage problems itself, so it is the fallback.
    private func resolveInstallState() async -> InstallState {
        guard let services = try? environment.makeArchiveServices() else {
            return .coach
        }
        archiveServices = services
        let store = services.store
        #if DEBUG
            await environment.prepareForDebugLaunchArguments(archiveStore: store)
        #endif
        // A failed janitor is not fatal: leftovers are retried on the next launch and an
        // unreadable snapshot already resolves as "not viewer".
        await Task.detached { try? store.runStartupJanitor() }.value
        return (try? await services.installStateResolver.resolve()) ?? .coach
    }

    private func refreshInstallState() async {
        guard let services = archiveServices else {
            return
        }
        installState = (try? await services.installStateResolver.resolve()) ?? .coach
        firstLaunchRoute = .choice
        showsImportFromChoice = false
    }
}
