import Foundation

public struct HistoryUseCases: Sendable {
    private let sessionRepository: CoreDataSessionRepository
    private let clock: any Clock
    private let ids: any IDGenerator

    public init(
        sessionRepository: CoreDataSessionRepository,
        clock: any Clock,
        ids: any IDGenerator
    ) {
        self.sessionRepository = sessionRepository
        self.clock = clock
        self.ids = ids
    }

    public func listHistory(studentID: StableUUID) async throws -> [CompletedSession] {
        try await sessionRepository.listCompleted(studentID: studentID)
    }

    public func detail(sessionID: StableUUID) async throws -> CompletedSession {
        try await sessionRepository.completedSession(id: sessionID)
    }

    public func saveSummaryNotes(
        sessionID: StableUUID,
        trainingFocus: String,
        privateCoachNote: String,
        studentFacingSummary: String
    ) async throws -> CompletedSession {
        let session = try await sessionRepository.session(id: sessionID)
        let updated = try session.updatingCompletedSummary(
            trainingFocus: optionalText(trainingFocus),
            privateCoachNote: optionalText(privateCoachNote),
            studentFacingSummary: optionalText(studentFacingSummary),
            now: clock.nowUTC()
        )
        let unchanged =
            updated.trainingFocus == session.trainingFocus
            && updated.privateCoachNote == session.privateCoachNote
            && updated.studentFacingSummary == session.studentFacingSummary
        if unchanged {
            return try await sessionRepository.completedSession(id: sessionID)
        }
        return try await sessionRepository.saveCompletedEdit(updated)
    }

    public func saveFocusEdit(sessionID: StableUUID, trainingFocus: String) async throws -> CompletedSession {
        let session = try await sessionRepository.session(id: sessionID)
        let next = try optionalText(trainingFocus)
        if session.trainingFocus == next {
            return try await sessionRepository.completedSession(id: sessionID)
        }
        let updated = try session.updatingTrainingFocus(next, now: clock.nowUTC())
        return try await sessionRepository.saveCompletedEdit(updated)
    }

    public func generateReport(
        sessionID: StableUUID,
        modules: ShareReportModuleSelection = .privacySafeDefaults
    ) async throws -> (completed: CompletedSession, report: ShareReport, dto: ShareReportDTO) {
        let completed = try await sessionRepository.completedSession(id: sessionID)
        let report: ShareReport
        if let existing = completed.latestReport,
            existing.freshness == .current,
            existing.generatedForRevision == completed.revision
        {
            report = existing
        } else {
            report = try await sessionRepository.insertShareReport(
                ShareReport.make(
                    id: StableUUID(ids.makeID()),
                    sessionID: completed.id,
                    generatedForRevision: completed.revision,
                    now: clock.nowUTC()
                ),
                modules: modules
            )
        }
        let dto = try ShareReportPolicy.makeDTO(from: completed, modules: modules)
        let refreshed = try await sessionRepository.completedSession(id: sessionID)
        return (refreshed, report, dto)
    }

    public func recordHandoff(report: ShareReport, outcome: SystemShareOutcome) async throws -> ShareReport {
        let updated = ShareReportHandoffRecorder.applying(outcome, to: report, at: clock.nowUTC())
        if updated == report {
            return report
        }
        return try await sessionRepository.updateShareReport(updated)
    }

    private func optionalText(_ rawValue: String) throws -> ValidatedText? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        return try ValidatedText(trimmed)
    }
}
