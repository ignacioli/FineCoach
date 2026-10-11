import Foundation

/// Orchestrates `CoursePackage` lifecycle and `CreditAdjustment` ledger
/// writes (T022). Every automatic-event method here is safe to call
/// repeatedly with the same underlying event (same session/appointment id)
/// -- idempotency is enforced by `CoreDataCoursePackageRepository`'s
/// dedup-by-`sourceEventKey` transaction, this layer just always computes
/// the correct deterministic key and trusts the repository to no-op a
/// repeat.
public struct CreditLedgerUseCases: Sendable {
    private let repository: CoreDataCoursePackageRepository
    private let clock: any Clock
    private let ids: any IDGenerator

    public init(
        repository: CoreDataCoursePackageRepository,
        clock: any Clock,
        ids: any IDGenerator
    ) {
        self.repository = repository
        self.clock = clock
        self.ids = ids
    }

    // MARK: - Package lifecycle (M1B-FR-012)

    /// Creates a new active package for a Student, ending whatever package
    /// is currently active for them first (M1B-FR-012: "已有active时新建须先结束当前").
    /// History of the ended package is retained, never deleted.
    public func createActivePackage(
        studentID: StableUUID,
        name: String?,
        totalCredits: Int,
        startDate: LocalDate?,
        endDate: LocalDate?
    ) async throws -> CoursePackage {
        let now = clock.nowUTC()
        let trimmedName = try name.flatMap { rawName -> ValidatedText? in
            let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : try ValidatedText(trimmed)
        }
        let draft = try CoursePackage(
            id: StableUUID(ids.makeID()),
            studentID: studentID,
            name: trimmedName,
            totalCredits: totalCredits,
            startDate: startDate,
            endDate: endDate,
            createdAtUTC: now,
            updatedAtUTC: now
        )
        return try await repository.activatePackage(draft, now: now)
    }

    public func endPackage(packageID: StableUUID) async throws -> CoursePackage {
        try await repository.endPackage(id: packageID, now: clock.nowUTC())
    }

    public func activePackage(studentID: StableUUID) async throws -> CoursePackage? {
        try await repository.activePackage(studentID: studentID)
    }

    public func packages(studentID: StableUUID) async throws -> [CoursePackage] {
        try await repository.packages(studentID: studentID)
    }

    public func package(id: StableUUID) async throws -> CoursePackage {
        try await repository.package(id: id)
    }

    public func balance(packageID: StableUUID) async throws -> Int {
        try await repository.balance(packageID: packageID)
    }

    /// Full traceable ledger trail for a package (T024: "每笔余额变化可查看对应课时调整").
    public func adjustments(packageID: StableUUID) async throws -> [CreditAdjustment] {
        try await repository.adjustments(packageID: packageID)
    }

    // MARK: - Automatic events (data-model §2.4)

    /// Normal session completion: debit one credit, at most once per
    /// session no matter how many times "完成"/edit is triggered.
    @discardableResult
    public func debitOnSessionComplete(packageID: StableUUID, sessionID: StableUUID) async throws -> CreditAdjustment {
        try await recordAutomaticDebit(
            packageID: packageID,
            amount: 1,
            reasonKind: .sessionComplete,
            linkedSessionID: sessionID,
            linkedAppointmentID: nil,
            sourceEventKey: CreditLedger.sourceEventKey(sessionComplete: sessionID)
        )
    }

    /// Reopening a previously-completed session credits back that one debit
    /// (at most once per session, regardless of repeat reopens). If the
    /// session was never debited (no `session-complete` entry on file), this
    /// is a deliberate no-op returning `nil` -- there is nothing to reopen.
    @discardableResult
    public func creditOnSessionReopen(packageID: StableUUID, sessionID: StableUUID) async throws -> CreditAdjustment? {
        let completeKey = CreditLedger.sourceEventKey(sessionComplete: sessionID)
        guard try await repository.adjustment(sourceEventKey: completeKey) != nil else {
            return nil
        }
        return try await recordAutomaticCredit(
            packageID: packageID,
            amount: 1,
            reasonKind: .sessionReopen,
            linkedSessionID: sessionID,
            linkedAppointmentID: nil,
            sourceEventKey: CreditLedger.sourceEventKey(sessionReopen: sessionID)
        )
    }

    /// Absence handling per the coach's `absentCreditChoice` (M1B-FR-014):
    /// `.notCharged` never touches the ledger; `.charged` debits once,
    /// idempotently keyed on the appointment.
    @discardableResult
    public func applyAbsence(
        packageID: StableUUID,
        appointmentID: StableUUID,
        creditChoice: AbsentCreditChoice
    ) async throws -> CreditAdjustment? {
        guard creditChoice == .charged else {
            return nil
        }
        return try await recordAutomaticDebit(
            packageID: packageID,
            amount: 1,
            reasonKind: .appointmentAbsent,
            linkedSessionID: nil,
            linkedAppointmentID: appointmentID,
            sourceEventKey: CreditLedger.sourceEventKey(appointmentAbsent: appointmentID)
        )
    }

    /// Ad-hoc/walk-in session completion where the coach chose to debit the
    /// current active package (idempotently keyed on the ad-hoc session).
    @discardableResult
    public func debitOnAdhocSession(packageID: StableUUID, sessionID: StableUUID) async throws -> CreditAdjustment {
        try await recordAutomaticDebit(
            packageID: packageID,
            amount: 1,
            reasonKind: .adhocSession,
            linkedSessionID: sessionID,
            linkedAppointmentID: nil,
            sourceEventKey: CreditLedger.sourceEventKey(adhocSession: sessionID)
        )
    }

    // MARK: - Manual correction (M1B-FR-016: reasonText required)

    /// Coach-entered correction. `reasonText` is mandatory and non-empty
    /// (enforced by `CreditAdjustment.init`). A debit correction is rejected
    /// if it would push the balance negative, exactly like automatic debits.
    @discardableResult
    public func recordManualCorrection(
        packageID: StableUUID,
        direction: CreditDirection,
        amount: Int,
        reasonText: String
    ) async throws -> CreditAdjustment {
        let now = clock.nowUTC()
        let text = try ValidatedText(reasonText)
        let adjustmentID = StableUUID(ids.makeID())
        let sourceEventKey = CreditLedger.sourceEventKey(manualCorrection: adjustmentID)
        return try await repository.recordIdempotentAdjustment(
            packageID: packageID,
            sourceEventKey: sourceEventKey,
            now: now
        ) { currentBalance in
            if direction == .debit {
                guard CreditLedger.canDebit(currentBalance: currentBalance, amount: amount) else {
                    throw DomainError.invalidState
                }
            }
            return try CreditAdjustment(
                id: adjustmentID,
                packageID: packageID,
                direction: direction,
                amount: amount,
                reasonKind: .manualCorrection,
                reasonText: text,
                sourceEventKey: sourceEventKey,
                createdAtUTC: now
            )
        }
    }

    // MARK: - Shared automatic-event plumbing

    private func recordAutomaticDebit(
        packageID: StableUUID,
        amount: Int,
        reasonKind: CreditReasonKind,
        linkedSessionID: StableUUID?,
        linkedAppointmentID: StableUUID?,
        sourceEventKey: String
    ) async throws -> CreditAdjustment {
        let now = clock.nowUTC()
        let adjustmentID = StableUUID(ids.makeID())
        return try await repository.recordIdempotentAdjustment(
            packageID: packageID,
            sourceEventKey: sourceEventKey,
            now: now
        ) { currentBalance in
            // A debit must never push the balance negative (M1B-FR-014/015/016):
            // this is a hard reject, never a silent clamp.
            guard CreditLedger.canDebit(currentBalance: currentBalance, amount: amount) else {
                throw DomainError.invalidState
            }
            return try CreditAdjustment(
                id: adjustmentID,
                packageID: packageID,
                direction: .debit,
                amount: amount,
                reasonKind: reasonKind,
                linkedSessionID: linkedSessionID,
                linkedAppointmentID: linkedAppointmentID,
                sourceEventKey: sourceEventKey,
                createdAtUTC: now
            )
        }
    }

    private func recordAutomaticCredit(
        packageID: StableUUID,
        amount: Int,
        reasonKind: CreditReasonKind,
        linkedSessionID: StableUUID?,
        linkedAppointmentID: StableUUID?,
        sourceEventKey: String
    ) async throws -> CreditAdjustment {
        let now = clock.nowUTC()
        let adjustmentID = StableUUID(ids.makeID())
        return try await repository.recordIdempotentAdjustment(
            packageID: packageID,
            sourceEventKey: sourceEventKey,
            now: now
        ) { _ in
            try CreditAdjustment(
                id: adjustmentID,
                packageID: packageID,
                direction: .credit,
                amount: amount,
                reasonKind: reasonKind,
                linkedSessionID: linkedSessionID,
                linkedAppointmentID: linkedAppointmentID,
                sourceEventKey: sourceEventKey,
                createdAtUTC: now
            )
        }
    }
}

// MARK: - Session finish → appointment + credit settlement (M1B-FR-013/014)

/// Why a finished Session's package could not be debited (M1B-FR-014).
public enum SessionCreditUnusableReason: Equatable, Sendable {
    case expired
    case insufficientBalance
}

/// What finishing a Session means for the Student's active course package.
public enum SessionCreditOutcome: Equatable, Sendable {
    /// The Student has no active package: nothing to debit, nothing to ask.
    case noActivePackage
    /// Appointment-linked completion: debited automatically (at most once).
    case debited(CoursePackage)
    /// Ad-hoc Session with a usable package: the coach chooses (M1B-FR-013).
    case adhocChoiceRequired(CoursePackage, balance: Int)
    /// Expired or zero balance: nothing debited; the coach is told they can
    /// skip the debit or make an explicit manual adjustment (M1B-FR-014).
    case packageUnusable(CoursePackage, SessionCreditUnusableReason)
}

/// Wires the Session finish path to the linked Appointment and the credit
/// ledger. Every step is idempotent: the Appointment is only completed while
/// still `inProgress`, and debits go through the deterministic
/// `sourceEventKey`s, so a repeated settle never double-debits.
public struct SessionCreditSettlement: Sendable {
    private let appointments: AppointmentUseCases
    private let credits: CreditLedgerUseCases
    private let history: HistoryUseCases

    public init(appointments: AppointmentUseCases, credits: CreditLedgerUseCases, history: HistoryUseCases) {
        self.appointments = appointments
        self.credits = credits
        self.history = history
    }

    /// Call right after `ActiveSessionUseCases.finish()` succeeded. A Session
    /// is appointment-linked iff an Appointment carries its id as
    /// `linkedSessionID` (set by `AppointmentUseCases.startTraining` while the
    /// Session is in progress).
    public func settleFinishedSession(_ session: Session) async throws -> SessionCreditOutcome {
        guard session.state == .completed else {
            throw DomainError.invalidState
        }
        let linked = try await linkedAppointment(for: session)
        if let linked, linked.status == .inProgress {
            do {
                _ = try await appointments.completeSession(appointmentID: linked.id)
            } catch DomainError.invalidState {
                // Already completed by a concurrent launch repair; the debit
                // below is keyed, so settling again stays at most once.
            }
        }
        guard let package = try await credits.activePackage(studentID: session.studentID) else {
            // Owner decision 2026-10-11: no prompt, but the record says why.
            try await history.recordCreditSettlementNote(.noActivePackage, sessionID: session.id)
            return .noActivePackage
        }
        if package.isExpired(asOf: appointments.todayLocalDate()) {
            return .packageUnusable(package, .expired)
        }
        guard linked != nil else {
            let balance = try await credits.balance(packageID: package.id)
            guard balance > 0 else {
                return .packageUnusable(package, .insufficientBalance)
            }
            return .adhocChoiceRequired(package, balance: balance)
        }
        do {
            // The repository checks the balance inside the write transaction,
            // and returns the existing entry for an already-debited Session.
            try await credits.debitOnSessionComplete(packageID: package.id, sessionID: session.id)
        } catch DomainError.invalidState {
            return .packageUnusable(package, .insufficientBalance)
        }
        return .debited(package)
    }

    /// The coach chose "扣课" for an ad-hoc Session (idempotent per Session).
    @discardableResult
    public func debitAdhocSession(packageID: StableUUID, sessionID: StableUUID) async throws -> CreditAdjustment {
        try await credits.debitOnAdhocSession(packageID: packageID, sessionID: sessionID)
    }

    /// Call right after `ActiveSessionUseCases.abandonEmpty()`: the linked
    /// Appointment returns to `scheduled` instead of staying in progress.
    public func settleAbandonedSession(_ session: Session) async throws {
        guard let linked = try await linkedAppointment(for: session), linked.status == .inProgress else {
            return
        }
        _ = try await appointments.abandonEmptySession(appointmentID: linked.id)
    }

    /// Launch repair for the crash window between the Session finish write
    /// and the settlement above: an Appointment still `inProgress` whose
    /// linked Session is already completed gets the same settlement as a
    /// normal finish (complete + at most one keyed debit, no prompt); one whose
    /// Session was abandoned returns to `scheduled`. Settled Appointments are
    /// no longer `inProgress`, so they are never touched again. Ad-hoc
    /// Sessions have no Appointment and are left alone (no debit). Returns the
    /// number of Appointments repaired; a failure on one does not stop the rest.
    @discardableResult
    public func repairInterruptedLinkedSessions() async -> Int {
        guard let pending = try? await appointments.inProgressLinkedAppointments() else {
            return 0
        }
        var repaired = 0
        for appointment in pending {
            guard let sessionID = appointment.linkedSessionID,
                let session = try? await history.fullSession(id: sessionID)
            else {
                continue
            }
            switch session.state {
            case .completed:
                if (try? await settleFinishedSession(session)) != nil {
                    repaired += 1
                }
            case .abandonedEmpty:
                if (try? await settleAbandonedSession(session)) != nil {
                    repaired += 1
                }
            case .inProgress:
                continue
            }
        }
        return repaired
    }

    public func activePackage(studentID: StableUUID) async throws -> CoursePackage? {
        try await credits.activePackage(studentID: studentID)
    }

    private func linkedAppointment(for session: Session) async throws -> Appointment? {
        try await appointments.appointments(studentID: session.studentID)
            .first { $0.linkedSessionID == session.id }
    }
}
