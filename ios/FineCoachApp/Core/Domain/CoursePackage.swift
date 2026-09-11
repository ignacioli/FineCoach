import Foundation

/// Persisted lifecycle state (data-model §2.3). There is no "expired" or
/// "depleted" case here: expiry and low/zero balance are DERIVED
/// presentation facts (see `isExpired`/`isBalanceLow` below, computed by the
/// Application layer against the ledger), never a status the domain stores
/// or that blocks training (M1B-FR-014).
public enum CoursePackageStatus: String, Codable, Sendable {
    case active
    case ended
}

/// A course package (课包): a Student's pool of purchased training credits
/// (data-model §2.3). Deliberately has NO price/payment/debt/refund fields --
/// that is explicitly out of scope for M1-B and MUST NOT be added here.
/// `remainingCredits` stored on this type is a non-authoritative cache; the
/// authoritative balance is always `CreditLedger.balance(totalCredits:
/// adjustments:)` derived from that package's `CreditAdjustment` ledger.
public struct CoursePackage: Hashable, Codable, Sendable, Identifiable {
    public let id: StableUUID
    public let studentID: StableUUID
    public let name: ValidatedText?
    public let totalCredits: Int
    /// Non-authoritative cache of the ledger-derived balance -- persistence
    /// may store this for cheap reads, but must always recompute and
    /// overwrite it from the ledger on every write, never derive it any
    /// other way (data-model §2.3: "不得静默改").
    public let remainingCreditsCache: Int
    public let startDate: LocalDate?
    public let endDate: LocalDate?
    public let status: CoursePackageStatus
    public let createdAtUTC: Date
    public let updatedAtUTC: Date

    public init(
        id: StableUUID,
        studentID: StableUUID,
        name: ValidatedText? = nil,
        totalCredits: Int,
        remainingCreditsCache: Int? = nil,
        startDate: LocalDate? = nil,
        endDate: LocalDate? = nil,
        status: CoursePackageStatus = .active,
        createdAtUTC: Date,
        updatedAtUTC: Date
    ) throws {
        guard totalCredits > 0 else {
            throw DomainError.invalidNumber
        }
        self.id = id
        self.studentID = studentID
        self.name = name
        self.totalCredits = totalCredits
        self.remainingCreditsCache = remainingCreditsCache ?? totalCredits
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.createdAtUTC = createdAtUTC
        self.updatedAtUTC = updatedAtUTC
    }

    /// Understandable display name even when the coach left `name` empty
    /// (data-model §2.3: "空时用可理解默认显示名").
    public var displayName: String {
        if let name, !name.isEmpty {
            return name.value
        }
        if let startDate {
            return "课包 · \(startDate.canonicalString)"
        }
        return "课包"
    }

    /// Ends this package (M1B-FR-012: creating a new active package requires
    /// ending the current one first). History is retained -- this returns a
    /// new value with `status = .ended`, it never deletes anything.
    public func ending(now: Date) throws -> CoursePackage {
        guard status == .active else {
            throw DomainError.invalidState
        }
        return try CoursePackage(
            id: id,
            studentID: studentID,
            name: name,
            totalCredits: totalCredits,
            remainingCreditsCache: remainingCreditsCache,
            startDate: startDate,
            endDate: endDate,
            status: .ended,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: now
        )
    }

    /// Refreshes the non-authoritative balance cache. Callers MUST pass a
    /// value computed via `CreditLedger.balance`, never an arbitrary number
    /// (data-model §2.3 invariant).
    public func cachingRemaining(_ ledgerBalance: Int, now: Date) throws -> CoursePackage {
        try CoursePackage(
            id: id,
            studentID: studentID,
            name: name,
            totalCredits: totalCredits,
            remainingCreditsCache: ledgerBalance,
            startDate: startDate,
            endDate: endDate,
            status: status,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: now
        )
    }

    /// Derived presentation fact only (M1B-FR-014): an expired package MUST
    /// NOT block training and MUST NOT be auto-transitioned to `.ended` by
    /// this check -- it stays `.active` in storage until the coach explicitly
    /// ends it. Callers decide what (if anything) to show the coach.
    public func isExpired(asOf today: LocalDate) -> Bool {
        guard let endDate else {
            return false
        }
        return today > endDate
    }

    /// Derived presentation fact only (M1B-FR-014): insufficient balance MUST
    /// NOT block training and MUST NOT auto-generate a negative balance --
    /// this is purely informational for the coach's UI.
    public func isBalanceLow(ledgerBalance: Int) -> Bool {
        ledgerBalance <= 0
    }
}
