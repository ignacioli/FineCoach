import Foundation

/// Coach-only billing annotation on a completed Session (owner decision
/// 2026-10-11): stored on `SessionMO.creditSettlementNote` (model V4) and
/// deliberately NOT a field of `Session`/`CompletedSession`, so the Share
/// Report, the archive export and the backup can never read it. Never logged.
public enum SessionCreditSettlementNote: String, Sendable {
    /// Finished with no active course package: no debit, no prompt.
    case noActivePackage
}

/// Ledger entry direction (data-model §2.4).
public enum CreditDirection: String, Codable, Sendable {
    case debit
    case credit
}

/// Why a `CreditAdjustment` exists. The four non-manual kinds are always
/// produced with a deterministic `sourceEventKey` (see `CreditLedger`) so
/// repeating the triggering action never double-applies (data-model §2.4,
/// plan D-M1B-002). `manualCorrection` is the only kind a coach can key in
/// directly and is the only kind that requires `reasonText`.
public enum CreditReasonKind: String, Codable, Sendable {
    case sessionComplete
    case appointmentAbsent
    case adhocSession
    case manualCorrection
    case sessionReopen
}

/// A single append-only, immutable ledger entry against a `CoursePackage`
/// (data-model §2.4). There is no mutation API on this type on purpose --
/// the ledger's only lifecycle is "insert once per `sourceEventKey`"; callers
/// that need to reverse an entry append a new opposite-direction entry
/// instead (e.g. `sessionReopen` credits back a prior `sessionComplete`
/// debit, it never edits or deletes it).
public struct CreditAdjustment: Hashable, Codable, Sendable, Identifiable {
    public let id: StableUUID
    public let packageID: StableUUID
    public let direction: CreditDirection
    public let amount: Int
    public let reasonKind: CreditReasonKind
    public let reasonText: ValidatedText?
    public let linkedSessionID: StableUUID?
    public let linkedAppointmentID: StableUUID?
    public let sourceEventKey: String
    public let createdAtUTC: Date

    public init(
        id: StableUUID,
        packageID: StableUUID,
        direction: CreditDirection,
        amount: Int,
        reasonKind: CreditReasonKind,
        reasonText: ValidatedText? = nil,
        linkedSessionID: StableUUID? = nil,
        linkedAppointmentID: StableUUID? = nil,
        sourceEventKey: String,
        createdAtUTC: Date
    ) throws {
        guard amount > 0 else {
            throw DomainError.invalidNumber
        }
        guard !sourceEventKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainError.invalidIdentifier
        }
        // Manual corrections are the only kind a coach types in freehand, so
        // they are the only kind required to carry a human-readable reason
        // (data-model §2.4, M1B-FR-016). Automatic kinds MAY still carry one.
        if reasonKind == .manualCorrection {
            guard let reasonText, !reasonText.isEmpty else {
                throw DomainError.emptyText
            }
        }
        self.id = id
        self.packageID = packageID
        self.direction = direction
        self.amount = amount
        self.reasonKind = reasonKind
        self.reasonText = reasonText
        self.linkedSessionID = linkedSessionID
        self.linkedAppointmentID = linkedAppointmentID
        self.sourceEventKey = sourceEventKey
        self.createdAtUTC = createdAtUTC
    }
}

/// Pure ledger math and idempotency-key construction. Deliberately stateless
/// -- persistence (T023) owns the actual dedup-by-key upsert and the
/// transactional read-then-write that makes the negative-balance check race
/// free; this type only expresses what the invariants ARE.
public enum CreditLedger {
    /// Authoritative balance derivation (data-model §2.3/§2.4): the stored
    /// `CoursePackage.remainingCredits` is only ever a cache of this.
    public static func balance(totalCredits: Int, adjustments: [CreditAdjustment]) -> Int {
        var balance = totalCredits
        for adjustment in adjustments {
            switch adjustment.direction {
            case .debit:
                balance -= adjustment.amount
            case .credit:
                balance += adjustment.amount
            }
        }
        return balance
    }

    /// Debit precondition (M1B-FR-014/015/016): a debit must never be allowed
    /// to push the balance negative. Callers MUST evaluate this against a
    /// balance read inside the same transaction that will record the debit,
    /// not a stale snapshot.
    public static func canDebit(currentBalance: Int, amount: Int) -> Bool {
        currentBalance - amount >= 0
    }

    // MARK: - Deterministic sourceEventKey construction (data-model §2.4)

    public static func sourceEventKey(sessionComplete sessionID: StableUUID) -> String {
        "session-complete:\(sessionID.rawValue.uuidString)"
    }

    public static func sourceEventKey(sessionReopen sessionID: StableUUID) -> String {
        "session-reopen:\(sessionID.rawValue.uuidString)"
    }

    public static func sourceEventKey(appointmentAbsent appointmentID: StableUUID) -> String {
        "appointment-absent:\(appointmentID.rawValue.uuidString)"
    }

    public static func sourceEventKey(adhocSession sessionID: StableUUID) -> String {
        "adhoc-session:\(sessionID.rawValue.uuidString)"
    }

    /// Manual corrections have no natural automatic-event id to key off of,
    /// so each one is its own unique key derived from the adjustment's own
    /// (freshly generated) id -- unique by construction, never collides with
    /// another manual correction or with an automatic key's `"<kind>:"` prefix.
    public static func sourceEventKey(manualCorrection adjustmentID: StableUUID) -> String {
        "manual-correction:\(adjustmentID.rawValue.uuidString)"
    }
}
