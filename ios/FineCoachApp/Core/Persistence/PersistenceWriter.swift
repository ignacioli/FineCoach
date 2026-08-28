import CoreData
import Foundation

public enum PersistenceWriterError: Error, Equatable, Sendable {
    case postCommitProtectionAuditFailed
}

public actor PersistenceWriter {
    private let context: NSManagedObjectContext
    private let secureStoreArtifacts: @Sendable () throws -> Void
    private let preSaveCheck: @Sendable () throws -> Void

    init(
        context: NSManagedObjectContext,
        secureStoreArtifacts: @escaping @Sendable () throws -> Void,
        preSaveCheck: @escaping @Sendable () throws -> Void
    ) {
        self.context = context
        self.secureStoreArtifacts = secureStoreArtifacts
        self.preSaveCheck = preSaveCheck
    }

    @discardableResult
    public func transaction<T: Sendable>(
        _ work: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try context.performAndWait {
            let result: T
            var didSave = false
            do {
                result = try work(context)
                if context.hasChanges {
                    try preSaveCheck()
                    try secureStoreArtifacts()
                    try context.save()
                    didSave = true
                }
            } catch {
                context.rollback()
                throw error
            }
            guard didSave else {
                return result
            }
            do {
                try secureStoreArtifacts()
            } catch {
                throw PersistenceWriterError.postCommitProtectionAuditFailed
            }
            return result
        }
    }

    public func read<T: Sendable>(
        _ work: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try context.performAndWait {
            try work(context)
        }
    }

    #if DEBUG
        func resetForTesting() {
            context.performAndWait {
                context.reset()
            }
        }
    #endif
}
