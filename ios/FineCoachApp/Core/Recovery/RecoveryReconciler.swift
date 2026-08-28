import Foundation

public struct RecoveryReconciler: Sendable {
    public init() {}

    public func decide(
        snapshot: ActiveSessionRecoverySnapshot?,
        databaseSession: Session?,
        currentGenerationUUID: UUID
    ) -> RecoveryLaunchDecision {
        if let snapshot {
            if snapshot.storeGenerationUUID != currentGenerationUUID {
                return .failClosed(.generationMismatch)
            }
            if snapshot.revision != snapshot.session.revision {
                return .failClosed(.invariantViolation)
            }
            if snapshot.revision < 1 {
                return .failClosed(.negativeRevision)
            }
        }

        switch (snapshot, databaseSession) {
        case (nil, nil):
            return .noActiveSession
        case (nil, let database?):
            return .consistent(database)
        case (let snapshot?, nil):
            return .replay(snapshot)
        case (let snapshot?, let database?):
            if snapshot.revision > database.revision {
                return .replay(snapshot)
            }
            if snapshot.revision == database.revision {
                return .consistent(database)
            }
            return .ignoreOlderSnapshot(database)
        }
    }
}
