import Foundation

public enum RestoreIntentPhase: String, Codable, Sendable {
    case prepared
    case switched
    case committed
}

public struct RestoreIntent: Equatable, Codable, Sendable {
    public let oldGenerationUUID: UUID
    public let newGenerationUUID: UUID
    public let phase: RestoreIntentPhase

    public init(oldGenerationUUID: UUID, newGenerationUUID: UUID, phase: RestoreIntentPhase) {
        self.oldGenerationUUID = oldGenerationUUID
        self.newGenerationUUID = newGenerationUUID
        self.phase = phase
    }
}

public enum RestoreStartupDecision: Equatable, Sendable {
    case openCurrent
    case keepOldDiscardCandidate
    case verifyNewThenCommit
    case failClosed
}

public enum RestoreGenerationSwitcher {
    public static func decision(intent: RestoreIntent?, pointerUUID: UUID) -> RestoreStartupDecision {
        guard let intent else {
            return .openCurrent
        }
        let pair = [intent.oldGenerationUUID, intent.newGenerationUUID]
        guard pair.contains(pointerUUID) else {
            return .failClosed
        }
        switch intent.phase {
        case .prepared:
            if pointerUUID == intent.oldGenerationUUID {
                return .keepOldDiscardCandidate
            }
            return .verifyNewThenCommit
        case .switched:
            if pointerUUID == intent.newGenerationUUID {
                return .verifyNewThenCommit
            }
            return .failClosed
        case .committed:
            if pointerUUID == intent.newGenerationUUID {
                return .openCurrent
            }
            return .failClosed
        }
    }

    public static func readIntent(from directory: StoreGenerationDirectory) throws -> RestoreIntent? {
        let url = directory.restoreIntentURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try JSONDecoder().decode(RestoreIntent.self, from: Data(contentsOf: url))
    }

    public static func writeIntent(_ intent: RestoreIntent, to directory: StoreGenerationDirectory) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try ProtectedFileStore().atomicReplace(
            data: encoder.encode(intent),
            at: directory.restoreIntentURL,
            policy: .business
        )
    }

    public static func clearIntent(in directory: StoreGenerationDirectory) throws {
        let url = directory.restoreIntentURL
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
