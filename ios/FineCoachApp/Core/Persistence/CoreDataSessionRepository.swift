import Foundation

public struct CoreDataSessionRepository: Sendable {
    private let writer: PersistenceWriter

    public init(writer: PersistenceWriter) {
        self.writer = writer
    }

    public func loadActive() async throws -> Session? {
        try await writer.read { context in
            guard let object = try SessionManagedObjectMapping.inProgressSession(in: context) else {
                return nil
            }
            return try SessionManagedObjectMapping.loadAggregate(from: object, in: context)
        }
    }

    public func session(id: StableUUID) async throws -> Session {
        try await writer.read { context in
            let object = try SessionManagedObjectMapping.requireSession(id: id.rawValue, in: context)
            return try SessionManagedObjectMapping.loadAggregate(from: object, in: context)
        }
    }

    public func save(_ session: Session) async throws -> Session {
        try await writer.transaction { context in
            if session.state == .inProgress {
                if let existing = try SessionManagedObjectMapping.inProgressSession(in: context),
                    let existingID = existing.value(forKey: "id") as? UUID,
                    existingID != session.id.rawValue
                {
                    throw DomainError.conflict
                }
            }
            return try SessionManagedObjectMapping.upsertAggregate(session, in: context)
        }
    }

    public func listCompleted(studentID: StableUUID) async throws -> [CompletedSession] {
        try await writer.read { context in
            let ids = try HistoryReportManagedObjectMapping.completedSessionIDs(
                studentID: studentID.rawValue,
                in: context
            )
            return try ids.map { try HistoryReportManagedObjectMapping.loadCompletedSession(id: $0, in: context) }
        }
    }

    public func completedSession(id: StableUUID) async throws -> CompletedSession {
        try await writer.read { context in
            try HistoryReportManagedObjectMapping.loadCompletedSession(id: id.rawValue, in: context)
        }
    }

    public func saveCompletedEdit(_ session: Session) async throws -> CompletedSession {
        guard session.state == .completed else {
            throw DomainError.invalidState
        }
        return try await writer.transaction { context in
            let saved = try SessionManagedObjectMapping.upsertAggregate(session, in: context)
            try HistoryReportManagedObjectMapping.markCurrentReportsStale(
                sessionID: saved.id.rawValue,
                in: context
            )
            return try HistoryReportManagedObjectMapping.loadCompletedSession(id: saved.id.rawValue, in: context)
        }
    }

    public func insertShareReport(
        _ report: ShareReport,
        modules: ShareReportModuleSelection
    ) async throws -> ShareReport {
        try await writer.transaction { context in
            try HistoryReportManagedObjectMapping.upsertReport(report, modules: modules, in: context)
        }
    }

    public func updateShareReport(_ report: ShareReport) async throws -> ShareReport {
        try await writer.transaction { context in
            try HistoryReportManagedObjectMapping.updateReport(report, in: context)
        }
    }
}
