import Foundation

public enum ShareReportFreshness: String, Codable, Sendable {
    case current
    case stale
}

public enum SystemShareOutcome: Equatable, Sendable {
    case completed
    case cancelled
    case failed
}

public struct ShareReport: Hashable, Codable, Sendable, Identifiable {
    public let id: StableUUID
    public let sessionID: StableUUID
    public let generatedForRevision: UInt64
    public let freshness: ShareReportFreshness
    public let createdAtUTC: Date
    public let handedToSystemAtUTC: Date?

    public init(
        id: StableUUID,
        sessionID: StableUUID,
        generatedForRevision: UInt64,
        freshness: ShareReportFreshness,
        createdAtUTC: Date,
        handedToSystemAtUTC: Date?
    ) {
        self.id = id
        self.sessionID = sessionID
        self.generatedForRevision = generatedForRevision
        self.freshness = freshness
        self.createdAtUTC = createdAtUTC
        self.handedToSystemAtUTC = handedToSystemAtUTC
    }

    public static func make(
        id: StableUUID,
        sessionID: StableUUID,
        generatedForRevision: UInt64,
        now: Date
    ) -> ShareReport {
        ShareReport(
            id: id,
            sessionID: sessionID,
            generatedForRevision: generatedForRevision,
            freshness: .current,
            createdAtUTC: now,
            handedToSystemAtUTC: nil
        )
    }

    public func markingStale() -> ShareReport {
        ShareReport(
            id: id,
            sessionID: sessionID,
            generatedForRevision: generatedForRevision,
            freshness: .stale,
            createdAtUTC: createdAtUTC,
            handedToSystemAtUTC: handedToSystemAtUTC
        )
    }

    public func recordingHandedToSystem(at date: Date) -> ShareReport {
        ShareReport(
            id: id,
            sessionID: sessionID,
            generatedForRevision: generatedForRevision,
            freshness: freshness,
            createdAtUTC: createdAtUTC,
            handedToSystemAtUTC: date
        )
    }
}

public struct ShareReportModuleSelection: Hashable, Codable, Sendable {
    public var includeStudentDisplayName: Bool
    public var studentDisplayNameOverride: String?
    public var includeDate: Bool
    public var includeExercisesAndSets: Bool
    public var includeDuration: Bool
    public var includeTrainingFocus: Bool
    public var includeStudentFacingSummary: Bool
    public var includeTrainingVolume: Bool

    public init(
        includeStudentDisplayName: Bool,
        studentDisplayNameOverride: String?,
        includeDate: Bool,
        includeExercisesAndSets: Bool,
        includeDuration: Bool,
        includeTrainingFocus: Bool,
        includeStudentFacingSummary: Bool,
        includeTrainingVolume: Bool
    ) {
        self.includeStudentDisplayName = includeStudentDisplayName
        self.studentDisplayNameOverride = studentDisplayNameOverride
        self.includeDate = includeDate
        self.includeExercisesAndSets = includeExercisesAndSets
        self.includeDuration = includeDuration
        self.includeTrainingFocus = includeTrainingFocus
        self.includeStudentFacingSummary = includeStudentFacingSummary
        self.includeTrainingVolume = includeTrainingVolume
    }

    public static let privacySafeDefaults = ShareReportModuleSelection(
        includeStudentDisplayName: true,
        studentDisplayNameOverride: nil,
        includeDate: true,
        includeExercisesAndSets: true,
        includeDuration: true,
        includeTrainingFocus: true,
        includeStudentFacingSummary: true,
        includeTrainingVolume: false
    )
}

public enum ShareReportHandoffRecorder {
    public static func applying(
        _ outcome: SystemShareOutcome,
        to report: ShareReport,
        at date: Date
    ) -> ShareReport {
        switch outcome {
        case .completed:
            return report.recordingHandedToSystem(at: date)
        case .cancelled, .failed:
            return report
        }
    }
}
