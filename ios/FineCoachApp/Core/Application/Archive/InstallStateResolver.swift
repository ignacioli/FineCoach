import Foundation

/// Derived, never persisted (data-model §4).
public enum InstallState: Equatable, Sendable {
    case viewer
    case coach
    case unselected
}

/// Where an archive opened from outside the app goes (D-010, adversarial review #2).
public enum ArchiveOpenDestination: Equatable, Sendable {
    /// First import, with the file prefilled in the import flow.
    case importPrefilled
    /// Replacement in viewer mode, with the file prefilled.
    case replacePrefilled
    /// A Coach install never reads the file; the user sees the blocked explanation.
    case blocked
}

public enum ArchiveOpenRouter {
    public static func destination(for state: InstallState) -> ArchiveOpenDestination {
        switch state {
        case .unselected: return .importPrefilled
        case .viewer: return .replacePrefilled
        case .coach: return .blocked
        }
    }
}

/// Resolves the install state in the documented order: viewer, then coach, then unselected.
public struct InstallStateResolver: Sendable {
    private let store: ArchiveSnapshotStore
    private let probe: any CoachInstallProbe
    private let logger: AppLogger

    public init(store: ArchiveSnapshotStore, probe: any CoachInstallProbe, logger: AppLogger = .init()) {
        self.store = store
        self.probe = probe
        self.logger = logger
    }

    /// Throws only when the Coach store cannot be read and the install is not a viewer. The
    /// caller must not treat that as `unselected`, which would offer an archive import on top
    /// of possibly existing Coach data.
    public func resolve() async throws -> InstallState {
        // An unreadable or newer-schema snapshot is "not viewer" (data-model §4).
        let hasViewerArchive = (try? store.load()) != nil
        if hasViewerArchive {
            if let snapshot = try? await probe.read(), snapshot.hasWorkData {
                logger.info(.archiveInstallViewerPrecedence, operation: .startup)
            }
            return .viewer
        }
        let snapshot = try await probe.read()
        return snapshot.onboardingCompleted || snapshot.hasWorkData ? .coach : .unselected
    }
}
