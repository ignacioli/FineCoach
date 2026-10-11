import Foundation

/// Composition of the archive-mode services for the UI track (M2-08..M2-20). Built once per
/// launch from the app environment's Coach store handle, which only the install-state probe
/// reads; the viewer use cases receive nothing but the snapshot store (plan §5).
///
/// - `installStateResolver`: viewer > coach > unselected, shared by the app root and the import.
/// - `importUseCases`: first import (and, in T055, replacement). Hand to the import pages and,
///   through the viewer root, to settings.
/// - `viewerUseCases`: loading, queries, display settings. Hand to the viewer root.
struct ArchiveServices {
    let store: ArchiveSnapshotStore
    let installStateResolver: InstallStateResolver
    let importUseCases: ArchiveImportUseCases
    let viewerUseCases: ArchiveViewerUseCases
}

@MainActor
extension AppEnvironment {
    /// Throws only when the `Application Support` location cannot be resolved. When the Coach
    /// store is unavailable the probe fails, so the resolver cannot report `unselected` and an
    /// import fails closed with `installStateUnavailable`.
    func makeArchiveServices() throws -> ArchiveServices {
        let store = ArchiveSnapshotStore(rootURL: try ArchiveSnapshotStore.defaultRootURL())
        let probe: any CoachInstallProbe =
            persistenceWriter.map { CoreDataCoachInstallProbe(writer: $0) } ?? UnavailableCoachInstallProbe()
        let resolver = InstallStateResolver(store: store, probe: probe)
        return ArchiveServices(
            store: store,
            installStateResolver: resolver,
            importUseCases: ArchiveImportUseCases(store: store, resolver: resolver),
            viewerUseCases: ArchiveViewerUseCases(store: store)
        )
    }
}

struct UnavailableCoachInstallProbe: CoachInstallProbe {
    func read() async throws -> CoachInstallSnapshot {
        throw PersistenceControllerError.storeLoadFailed
    }
}
