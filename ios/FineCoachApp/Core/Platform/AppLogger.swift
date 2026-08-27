import OSLog

public enum AppLogEvent: String, CaseIterable, Sendable {
    case modelLoaded = "foundation.model_loaded"
    case writerTransaction = "foundation.writer_transaction"
    case filePolicyApplied = "foundation.file_policy_applied"
    case generationValidated = "foundation.generation_validated"
    case privacyCoverChanged = "foundation.privacy_cover_changed"
}

public enum AppLogOperation: String, CaseIterable, Sendable {
    case startup
    case persistence
    case fileProtection
    case generation
    case scenePrivacy
}

public enum AppLogErrorCategory: String, CaseIterable, Sendable {
    case validation
    case conflict
    case protectedDataUnavailable = "protected_data_unavailable"
    case persistenceFailed = "persistence_failed"
    case incompatibleInput = "incompatible_input"
    case externalCancelled = "external_cancelled"
}

public struct AppLogger: Sendable {
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
