import OSLog

public enum AppLogEvent: String, CaseIterable, Sendable {
    case modelLoaded = "foundation.model_loaded"
    case writerTransaction = "foundation.writer_transaction"
    case filePolicyApplied = "foundation.file_policy_applied"
    case generationValidated = "foundation.generation_validated"
    case privacyCoverChanged = "foundation.privacy_cover_changed"
    /// A viewer archive and Coach work data coexist; viewer mode wins (data-model §4).
    case archiveInstallViewerPrecedence = "archive.viewer_precedence"
    /// An export produced more than a plan §7.3 limit allows. Fixed ID only; no counts.
    case archiveExportLimitExceeded = "archive.export_limit_exceeded"
    /// The system accepted the archive file (not "received by the student").
    case archiveExportHandedOff = "archive.export_handed_off"
    case archiveExportDeliveryCancelled = "archive.export_delivery_cancelled"
    /// Generation or delivery failed.
    case archiveExportFailed = "archive.export_failed"
    /// A first import was committed. Fixed ID only; no source, count or time.
    case archiveImportCompleted = "archive.import_completed"
    /// Wrong password, tampering, truncation or any failed authentication.
    case archiveImportRejectedCorrupted = "archive.import_rejected_corrupted"
    /// Container, KDF or schema version this build cannot read.
    case archiveImportRejectedIncompatible = "archive.import_rejected_incompatible"
    /// Not a FineCoach archive, over a resource limit, or structurally invalid.
    case archiveImportRejectedInvalid = "archive.import_rejected_invalid"
    /// Coach data exists on this install (M2-FR-026); the file was not read.
    case archiveImportBlockedCoachData = "archive.import_blocked_coach_data"
    /// A first import was attempted while an archive is already installed.
    case archiveImportBlockedNotFirst = "archive.import_blocked_not_first"
    /// The install state could not be determined, so nothing was imported.
    case archiveImportStateUnavailable = "archive.import_state_unavailable"
    /// Cancelled or failed to commit; the pre-import state stands.
    case archiveImportInterrupted = "archive.import_interrupted"
}

public enum AppLogOperation: String, CaseIterable, Sendable {
    case startup
    case persistence
    case fileProtection
    case generation
    case scenePrivacy
    case archiveExport = "archive_export"
    case archiveImport = "archive_import"
}

public enum AppLogErrorCategory: String, CaseIterable, Sendable {
    case validation
    case conflict
    case protectedDataUnavailable = "protected_data_unavailable"
    case persistenceFailed = "persistence_failed"
    case incompatibleInput = "incompatible_input"
    case externalCancelled = "external_cancelled"
}

/// The logging surface use cases depend on, so tests can observe fixed event IDs.
public protocol AppLogging: Sendable {
    func info(_ event: AppLogEvent, operation: AppLogOperation)
    func failure(_ event: AppLogEvent, operation: AppLogOperation, category: AppLogErrorCategory)
}

public struct AppLogger: AppLogging {
    /// Default instance for call sites outside this file.
    public static var standard: AppLogger { AppLogger() }

    private let logger: Logger

    public init(
        subsystem: String = "com.finecoach.app",
        category: String = "app"
    ) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func info(_ event: AppLogEvent, operation: AppLogOperation) {
        logger.info(
            "event=\(event.rawValue, privacy: .public) operation=\(operation.rawValue, privacy: .public)"
        )
    }

    public func failure(
        _ event: AppLogEvent,
        operation: AppLogOperation,
        category: AppLogErrorCategory
    ) {
        logger.error(
            "event=\(event.rawValue, privacy: .public) operation=\(operation.rawValue, privacy: .public) error_category=\(category.rawValue, privacy: .public)"
        )
    }
}
