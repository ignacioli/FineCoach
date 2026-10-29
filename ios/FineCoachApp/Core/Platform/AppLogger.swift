import OSLog

public enum AppLogEvent: String, CaseIterable, Sendable {
    case modelLoaded = "foundation.model_loaded"
    case writerTransaction = "foundation.writer_transaction"
    case filePolicyApplied = "foundation.file_policy_applied"
    case generationValidated = "foundation.generation_validated"
    case privacyCoverChanged = "foundation.privacy_cover_changed"
    /// A viewer archive and Coach work data coexist; viewer mode wins (data-model §4).
    case archiveInstallViewerPrecedence = "archive.viewer_precedence"
    /// A viewer pointer exists but cannot be read or loaded and the Coach store is empty; the
    /// install state is withheld and the data is kept. Fixed ID only.
    case archiveInstallPointerUnreadable = "archive.install_pointer_unreadable"
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
    /// A newer snapshot replaced the installed one. Fixed ID only; no source, count or time.
    case archiveReplaceCompleted = "archive.replace_completed"
    /// Candidate is not newer than the installed snapshot (older or same time).
    case archiveReplaceRejectedNotNewer = "archive.replace_rejected_not_newer"
    /// Candidate comes from another Coach install.
    case archiveReplaceRejectedSource = "archive.replace_rejected_source"
    /// Candidate belongs to another student of the same source.
    case archiveReplaceRejectedStudent = "archive.replace_rejected_student"
    /// Cancelled or failed to commit; the installed snapshot stands.
    case archiveReplaceInterrupted = "archive.replace_interrupted"
    /// The local archive was deleted.
    case archiveDeleteCompleted = "archive.delete_completed"
    /// Deleting the local archive did not finish; the next launch resumes the cleanup.
    case archiveDeleteFailed = "archive.delete_failed"
    /// Rest-end notification tap routing (C19): fixed phase names only, never
    /// a Student, Session or notification identifier.
    case restNotificationDelegateInstalled = "rest_notification.delegate_installed"
    case restNotificationResponseReceived = "rest_notification.response_received"
    case restNotificationIgnoredPayload = "rest_notification.ignored_payload"
    case restNotificationReceived = "rest_notification.received"
    case restNotificationRootLoading = "rest_notification.root_loading"
    case restNotificationRootLoaded = "rest_notification.root_loaded"
    case restNotificationStackReady = "rest_notification.stack_ready"
    case restNotificationStackRemoved = "rest_notification.stack_removed"
    case restNotificationDeferredNotReady = "rest_notification.deferred_not_ready"
    case restNotificationConsumed = "rest_notification.consumed"
    case restNotificationIgnoredNoRoute = "rest_notification.ignored_no_route"
    case restNotificationRouted = "rest_notification.routed"
    case restNotificationPathEmpty = "rest_notification.path_empty"
    case restNotificationPathNonempty = "rest_notification.path_nonempty"
    case restNotificationInstallCoach = "rest_notification.install_coach"
    case restNotificationInstallViewer = "rest_notification.install_viewer"
    case restNotificationInstallUnselected = "rest_notification.install_unselected"
    case restNotificationDiscarded = "rest_notification.discarded"
    case systemEntrySnapshotWritten = "system_entry.snapshot_written"
    case systemEntrySnapshotFailed = "system_entry.snapshot_failed"
    case systemEntryActivityStarted = "system_entry.activity_started"
    case systemEntryActivityEnded = "system_entry.activity_ended"
    case systemEntryActivityUnavailable = "system_entry.activity_unavailable"
    case systemEntryShortcutOpened = "system_entry.shortcut_opened"
}

public enum AppLogOperation: String, CaseIterable, Sendable {
    case startup
    case persistence
    case fileProtection
    case generation
    case scenePrivacy
    case archiveExport = "archive_export"
    case archiveImport = "archive_import"
    case archiveReplace = "archive_replace"
    case archiveDelete = "archive_delete"
    case restNotification = "rest_notification"
    case systemEntry = "system_entry"
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
