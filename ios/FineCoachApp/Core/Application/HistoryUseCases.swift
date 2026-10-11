import Foundation

/// Multi-criterion filter for `HistoryUseCases.filteredHistory` (M1B-FR-026).
/// All three criteria are optional and independently combinable; `nil` means
/// "don't filter on this criterion".
public struct HistoryFilterCriteria: Equatable, Sendable {
    public var dateRange: ClosedRange<LocalDate>?
    /// M1B-FR-026/D-013: any-overlap (union) match against a Session's own
    /// training-focus set -- empty means "don't filter on this criterion",
    /// matching `dateRange`/`exerciseID`'s `nil`-means-unset convention.
    public var trainingFocus: Set<BodyPart>
    public var exerciseID: StableExerciseID?

    public init(
        dateRange: ClosedRange<LocalDate>? = nil,
        trainingFocus: Set<BodyPart> = [],
        exerciseID: StableExerciseID? = nil
    ) {
        self.dateRange = dateRange
        self.trainingFocus = trainingFocus
        self.exerciseID = exerciseID
    }

    public var isEmpty: Bool {
        dateRange == nil && trainingFocus.isEmpty && exerciseID == nil
    }

    /// The ANY-overlap (union) rule itself (M1B-FR-026/D-013), pulled out as a
    /// pure, directly unit-testable function rather than only exercised
    /// inline inside `HistoryUseCases.filteredHistory`'s `Array.filter`.
    /// `filter.isEmpty` means "don't filter on training focus" -- every
    /// Session matches, regardless of its own focus.
    public static func matchesTrainingFocus(sessionFocus: Set<BodyPart>, filter: Set<BodyPart>) -> Bool {
        filter.isEmpty || !sessionFocus.isDisjoint(with: filter)
    }
}

/// Explicit empty-state contract (M1B-FR-026): a real "no matches" result the
/// UI renders as a real empty state, never an ambiguous nil/empty array the
/// caller has to interpret.
public enum HistoryFilterResult: Sendable {
    case matches([CompletedSession])
    case noMatches
}

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

    /// Loads the full `Session` domain aggregate for `id` (any state, not
    /// just in-progress) -- needed by callers such as save-completed-
    /// session-as-template (M1B-FR-017/018) that require the raw Exercise/
    /// Set shape `TemplateUseCases.saveAsTemplate` operates on, which
    /// `CompletedSession` (a read-only display DTO) does not carry.
    public func fullSession(id: StableUUID) async throws -> Session {
        try await sessionRepository.session(id: id)
    }

    /// Coach-only billing annotations for the history list / detail page.
    public func creditSettlementNotes(studentID: StableUUID) async throws -> [StableUUID: SessionCreditSettlementNote] {
        try await sessionRepository.creditSettlementNotes(studentID: studentID)
    }

    public func creditSettlementNote(sessionID: StableUUID) async throws -> SessionCreditSettlementNote? {
        try await sessionRepository.creditSettlementNote(sessionID: sessionID)
    }

    public func recordCreditSettlementNote(_ note: SessionCreditSettlementNote, sessionID: StableUUID) async throws {
        try await sessionRepository.recordCreditSettlementNote(note, sessionID: sessionID)
    }

    public func saveSummaryNotes(
        sessionID: StableUUID,
        trainingFocus: Set<BodyPart>,
        privateCoachNote: String,
        studentFacingSummary: String
    ) async throws -> CompletedSession {
        let session = try await sessionRepository.session(id: sessionID)
        let updated = try session.updatingCompletedSummary(
            trainingFocus: trainingFocus,
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

    public func saveFocusEdit(sessionID: StableUUID, trainingFocus: Set<BodyPart>) async throws -> CompletedSession {
        let session = try await sessionRepository.session(id: sessionID)
        if session.trainingFocus == trainingFocus {
            return try await sessionRepository.completedSession(id: sessionID)
        }
        let updated = try session.updatingTrainingFocus(trainingFocus, now: clock.nowUTC())
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

    /// Applies `criteria` to this Student's completed-session history,
    /// deriving `localCalendarDay` comparisons through the injected
    /// `LocalCalendarProvider` (T007a) rather than `Calendar.current`.
    public func filteredHistory(
        studentID: StableUUID,
        criteria: HistoryFilterCriteria,
        calendarProvider: any LocalCalendarProvider
    ) async throws -> HistoryFilterResult {
        let all = try await listHistory(studentID: studentID)
        guard !criteria.isEmpty else {
            return all.isEmpty ? .noMatches : .matches(all)
        }
        let calendar = calendarProvider.currentCalendar()
        let filtered = all.filter { session in
            if let dateRange = criteria.dateRange {
                let day = LocalDate(date: session.completedAtUTC, calendar: calendar)
                guard dateRange.contains(day) else { return false }
            }
            guard HistoryFilterCriteria.matchesTrainingFocus(
                sessionFocus: session.trainingFocus, filter: criteria.trainingFocus
            ) else {
                return false
            }
            if let exerciseID = criteria.exerciseID {
                guard session.exercises.contains(where: { $0.sourceID == exerciseID }) else { return false }
            }
            return true
        }
        return filtered.isEmpty ? .noMatches : .matches(filtered)
    }

    private func optionalText(_ rawValue: String) throws -> ValidatedText? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        return try ValidatedText(trimmed)
    }
}
