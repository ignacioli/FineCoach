import CoreData
import Foundation

public struct CoreDataSessionRepository: Sendable {
    private let writer: PersistenceWriter

    public init(writer: PersistenceWriter) {
        self.writer = writer
    }

    /// Compatibility for single-session call sites: refuses to guess when more
    /// than one Session is in progress (M1A-FR-018 revision). Callers that
    /// already know the Student or Session MUST use the explicit overloads.
    public func loadActive() async throws -> Session? {
        let sessions = try await loadAllActive()
        guard sessions.count <= 1 else {
            throw DomainError.invalidState
        }
        return sessions.first
    }

    public func loadActive(studentID: StableUUID) async throws -> Session? {
        try await writer.read { context in
            guard
                let object = try SessionManagedObjectMapping.inProgressSession(
                    studentID: studentID.rawValue,
                    in: context
                )
            else {
                return nil
            }
            return try SessionManagedObjectMapping.loadAggregate(from: object, in: context)
        }
    }

    public func loadActive(sessionID: StableUUID) async throws -> Session? {
        try await writer.read { context in
            guard
                let object = try SessionManagedObjectMapping.fetchSession(
                    id: sessionID.rawValue,
                    in: context
                ), object.value(forKey: "state") as? String == SessionState.inProgress.rawValue
            else {
                return nil
            }
            return try SessionManagedObjectMapping.loadAggregate(from: object, in: context)
        }
    }

    public func loadAllActive() async throws -> [Session] {
        try await writer.read { context in
            try SessionManagedObjectMapping.inProgressSessions(in: context).map {
                try SessionManagedObjectMapping.loadAggregate(from: $0, in: context)
            }
        }
    }

    /// Rewrites a pre-2026-10-22 `"active"` pointer to its Student's key.
    public func migrateLegacyPointer() async throws {
        try await writer.transaction { context in
            try SessionManagedObjectMapping.migrateLegacyPointer(in: context)
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
                if let existing = try SessionManagedObjectMapping.inProgressSession(
                    studentID: session.studentID.rawValue,
                    in: context
                ),
                    let existingID = existing.value(forKey: "id") as? UUID,
                    existingID != session.id.rawValue
                {
                    throw DomainError.conflict
                }
            }
            return try SessionManagedObjectMapping.upsertAggregate(session, in: context)
        }
    }

    /// Atomically persists a terminal Session and releases only that
    /// Session's temporary exercise-name claims. Other in-progress Sessions
    /// keep theirs (M1A-FR-018 revision: finishing A must not disturb B).
    /// Built-in claim reconciliation follows as a best-effort operation in the
    /// application layer.
    public func saveAndReleaseSessionScopeClaims(_ session: Session) async throws -> Session {
        guard session.state != .inProgress else {
            throw DomainError.invalidState
        }
        return try await writer.transaction { context in
            let keepOwnerIDs = try self.otherSessionOnlyOwnerIDs(excluding: session.id, in: context)
            let saved = try SessionManagedObjectMapping.upsertAggregate(session, in: context)
            for claim in try ExerciseManagedObjectMapping.fetchClaims(scope: .currentSession, in: context) {
                let ownerID = claim.value(forKey: "ownerID") as? String ?? ""
                if !keepOwnerIDs.contains(ownerID) {
                    context.delete(claim)
                }
            }
            return saved
        }
    }

    private func otherSessionOnlyOwnerIDs(
        excluding sessionID: StableUUID,
        in context: NSManagedObjectContext
    ) throws -> Set<String> {
        var ownerIDs: Set<String> = []
        for object in try SessionManagedObjectMapping.inProgressSessions(in: context) {
            guard let id = object.value(forKey: "id") as? UUID, id != sessionID.rawValue else {
                continue
            }
            let other = try SessionManagedObjectMapping.loadAggregate(from: object, in: context)
            ownerIDs.formUnion(
                other.exercises
                    .filter { $0.sourceKind == .sessionOnly }
                    .map { $0.id.rawValue.uuidString }
            )
        }
        return ownerIDs
    }

    // MARK: - Credit settlement note (coach-only; see SessionCreditSettlementNote)

    public func recordCreditSettlementNote(_ note: SessionCreditSettlementNote, sessionID: StableUUID) async throws {
        try await writer.transaction { context in
            let object = try SessionManagedObjectMapping.requireSession(id: sessionID.rawValue, in: context)
            object.setValue(note.rawValue, forKey: SessionManagedObjectMapping.creditSettlementNoteKey)
        }
    }

    public func creditSettlementNotes(studentID: StableUUID) async throws -> [StableUUID: SessionCreditSettlementNote] {
        try await writer.read { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: SessionManagedObjectMapping.sessionEntityName)
            request.predicate = NSPredicate(
                format: "studentID == %@ AND %K != nil",
                studentID.rawValue as CVarArg,
                SessionManagedObjectMapping.creditSettlementNoteKey
            )
            var notes: [StableUUID: SessionCreditSettlementNote] = [:]
            for object in try context.fetch(request) {
                guard let id = object.value(forKey: "id") as? UUID,
                    let raw = object.value(forKey: SessionManagedObjectMapping.creditSettlementNoteKey) as? String,
                    let note = SessionCreditSettlementNote(rawValue: raw)
                else {
                    continue
                }
                notes[StableUUID(id)] = note
            }
            return notes
        }
    }

    public func creditSettlementNote(sessionID: StableUUID) async throws -> SessionCreditSettlementNote? {
        try await writer.read { context in
            let object = try SessionManagedObjectMapping.requireSession(id: sessionID.rawValue, in: context)
            return (object.value(forKey: SessionManagedObjectMapping.creditSettlementNoteKey) as? String)
                .flatMap(SessionCreditSettlementNote.init(rawValue:))
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

    public func listAllCompleted() async throws -> [CompletedSession] {
        try await writer.read { context in
            let ids = try HistoryReportManagedObjectMapping.completedSessionIDs(in: context)
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
