import Foundation

public enum ArchiveReplacementDecision: Equatable, Sendable {
    case accept
    case differentSource
    case differentStudent
    /// Candidate `snapshotAtUTC` is not later than the current one. Equal times count as a
    /// duplicate (D-004).
    case notNewer
}

/// Decides whether a candidate archive may replace the installed one (data-model §6).
/// Pure function; the order of checks is part of the contract.
public enum ArchiveReplacementPolicy {
    public static func evaluate(
        current: ArchiveManifest,
        candidate: ArchiveManifest
    ) -> ArchiveReplacementDecision {
        if candidate.sourceID != current.sourceID {
            return .differentSource
        }
        if candidate.studentArchiveID != current.studentArchiveID {
            return .differentStudent
        }
        if candidate.snapshotAtUTC <= current.snapshotAtUTC {
            return .notNewer
        }
        return .accept
    }
}
