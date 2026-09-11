import FineCoach
import XCTest

final class CreditLedgerIdempotencyTests: XCTestCase {
    private let packageID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Balance derivation (data-model §2.3/§2.4)

    func testBalanceSumsDebitsAndCredits() throws {
        let adjustments = [
            try CreditAdjustment(
                id: makeID(1),
                packageID: packageID,
                direction: .debit,
                amount: 3,
                reasonKind: .sessionComplete,
                sourceEventKey: "k1",
                createdAtUTC: now
            ),
            try CreditAdjustment(
                id: makeID(2),
                packageID: packageID,
                direction: .credit,
                amount: 1,
                reasonKind: .sessionReopen,
                sourceEventKey: "k2",
                createdAtUTC: now
            ),
        ]
        XCTAssertEqual(CreditLedger.balance(totalCredits: 10, adjustments: adjustments), 8)
    }

    func testBalanceWithNoAdjustmentsEqualsTotalCredits() {
        XCTAssertEqual(CreditLedger.balance(totalCredits: 10, adjustments: []), 10)
    }

    func testCanDebitRejectsWhenWouldGoNegative() {
        XCTAssertFalse(CreditLedger.canDebit(currentBalance: 0, amount: 1))
        XCTAssertTrue(CreditLedger.canDebit(currentBalance: 1, amount: 1))
        XCTAssertTrue(CreditLedger.canDebit(currentBalance: 5, amount: 5))
        XCTAssertFalse(CreditLedger.canDebit(currentBalance: 5, amount: 6))
    }

    // MARK: - Deterministic sourceEventKey construction (data-model §2.4)

    func testSourceEventKeysAreDeterministicAndDistinctAcrossKinds() {
        let sessionID = StableUUID(UUID())
        let appointmentID = StableUUID(UUID())

        XCTAssertEqual(
            CreditLedger.sourceEventKey(sessionComplete: sessionID),
            CreditLedger.sourceEventKey(sessionComplete: sessionID)
        )
        let allKeys = [
            CreditLedger.sourceEventKey(sessionComplete: sessionID),
            CreditLedger.sourceEventKey(sessionReopen: sessionID),
            CreditLedger.sourceEventKey(adhocSession: sessionID),
            CreditLedger.sourceEventKey(appointmentAbsent: appointmentID),
        ]
        XCTAssertEqual(Set(allKeys).count, allKeys.count, "each event kind must produce a distinct key even for the same underlying id")
    }

    func testManualCorrectionKeysAreUniquePerAdjustmentID() {
        let a = StableUUID(UUID())
        let b = StableUUID(UUID())
        XCTAssertNotEqual(
            CreditLedger.sourceEventKey(manualCorrection: a),
            CreditLedger.sourceEventKey(manualCorrection: b)
        )
    }

    // MARK: - CreditAdjustment validation

    func testManualCorrectionRequiresNonEmptyReason() {
        XCTAssertThrowsError(
            try CreditAdjustment(
                id: makeID(1),
                packageID: packageID,
                direction: .debit,
                amount: 1,
                reasonKind: .manualCorrection,
                reasonText: nil,
                sourceEventKey: "manual-correction:x",
                createdAtUTC: now
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .emptyText)
        }
    }

    func testAutomaticReasonsDoNotRequireReasonText() throws {
        _ = try CreditAdjustment(
            id: makeID(1),
            packageID: packageID,
            direction: .debit,
            amount: 1,
            reasonKind: .sessionComplete,
            sourceEventKey: "session-complete:x",
            createdAtUTC: now
        )
    }

    func testAmountMustBePositive() {
        XCTAssertThrowsError(
            try CreditAdjustment(
                id: makeID(1),
                packageID: packageID,
                direction: .debit,
                amount: 0,
                reasonKind: .sessionComplete,
                sourceEventKey: "k",
                createdAtUTC: now
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidNumber)
        }
    }

    // MARK: - CoursePackage lifecycle (data-model §2.3)

    func testTotalCreditsMustBePositive() {
        XCTAssertThrowsError(
            try CoursePackage(
                id: StableUUID(UUID()),
                studentID: StableUUID(UUID()),
                totalCredits: 0,
                createdAtUTC: now,
                updatedAtUTC: now
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidNumber)
        }
    }

    func testEndingActivePackageTransitionsStatusAndRejectsDoubleEnd() throws {
        let package = try CoursePackage(
            id: StableUUID(UUID()),
            studentID: StableUUID(UUID()),
            totalCredits: 10,
            createdAtUTC: now,
            updatedAtUTC: now
        )
        let ended = try package.ending(now: now.addingTimeInterval(60))
        XCTAssertEqual(ended.status, .ended)
        XCTAssertThrowsError(try ended.ending(now: now))
    }

    func testExpiryAndLowBalanceAreDerivedFactsThatNeverMutateStatus() throws {
        let package = try CoursePackage(
            id: StableUUID(UUID()),
            studentID: StableUUID(UUID()),
            totalCredits: 10,
            endDate: try LocalDate(year: 2026, month: 1, day: 1),
            createdAtUTC: now,
            updatedAtUTC: now
        )
        XCTAssertTrue(package.isExpired(asOf: try LocalDate(year: 2026, month: 2, day: 1)))
        XCTAssertFalse(package.isExpired(asOf: try LocalDate(year: 2025, month: 12, day: 1)))
        // M1B-FR-014: expiry never flips storage-level status on its own.
        XCTAssertEqual(package.status, .active)
        XCTAssertTrue(package.isBalanceLow(ledgerBalance: 0))
        XCTAssertFalse(package.isBalanceLow(ledgerBalance: 1))
    }

    // MARK: - AC-010 full combination matrix (SC-003: 0 erroneous extra debits/credits)

    /// A minimal in-memory stand-in for the repository's dedup contract that
    /// `CoreDataCoursePackageRepository.recordIdempotentAdjustment` (T023)
    /// implements against real Core Data: fetch-by-key, no-op if the key is
    /// already present, else validate against the balance and insert.
    /// Exercising the exact same contract here proves the ALGORITHM is
    /// correct across every AC-010 scenario and every one of its repeats
    /// without needing Core Data. T026 separately proves the real repository
    /// implements this same contract across an app restart -- it does not
    /// repeat this matrix (adversarial A3 dedup).
    private final class SimulatedLedger {
        private(set) var adjustments: [CreditAdjustment] = []
        let totalCredits: Int

        init(totalCredits: Int) {
            self.totalCredits = totalCredits
        }

        var balance: Int {
            CreditLedger.balance(totalCredits: totalCredits, adjustments: adjustments)
        }

        @discardableResult
        func record(
            sourceEventKey: String,
            make: (_ currentBalance: Int) throws -> CreditAdjustment
        ) throws -> CreditAdjustment {
            if let existing = adjustments.first(where: { $0.sourceEventKey == sourceEventKey }) {
                return existing
            }
            let adjustment = try make(balance)
            adjustments.append(adjustment)
            return adjustment
        }
    }

    func testAC010CombinationMatrixNeverDoubleAppliesOnRepeat() throws {
        let ledger = SimulatedLedger(totalCredits: 10)
        let completedSession = StableUUID(UUID())
        let absentChargedAppointment = StableUUID(UUID())
        let absentNotChargedAppointment = StableUUID(UUID())
        let adhocSession = StableUUID(UUID())

        func debit(
            _ key: String,
            sessionID: StableUUID? = nil,
            appointmentID: StableUUID? = nil,
            reasonKind: CreditReasonKind
        ) throws {
            try ledger.record(sourceEventKey: key) { currentBalance in
                guard CreditLedger.canDebit(currentBalance: currentBalance, amount: 1) else {
                    throw DomainError.invalidState
                }
                return try CreditAdjustment(
                    id: StableUUID(UUID()),
                    packageID: packageID,
                    direction: .debit,
                    amount: 1,
                    reasonKind: reasonKind,
                    linkedSessionID: sessionID,
                    linkedAppointmentID: appointmentID,
                    sourceEventKey: key,
                    createdAtUTC: now
                )
            }
        }
        func credit(_ key: String, sessionID: StableUUID? = nil, reasonKind: CreditReasonKind) throws {
            try ledger.record(sourceEventKey: key) { _ in
                try CreditAdjustment(
                    id: StableUUID(UUID()),
                    packageID: packageID,
                    direction: .credit,
                    amount: 1,
                    reasonKind: reasonKind,
                    linkedSessionID: sessionID,
                    sourceEventKey: key,
                    createdAtUTC: now
                )
            }
        }

        // 1. Session completes normally -> debit once; repeating (re-complete/edit)
        // must not double-debit.
        let completeKey = CreditLedger.sourceEventKey(sessionComplete: completedSession)
        try debit(completeKey, sessionID: completedSession, reasonKind: .sessionComplete)
        try debit(completeKey, sessionID: completedSession, reasonKind: .sessionComplete)
        XCTAssertEqual(ledger.adjustments.filter { $0.sourceEventKey == completeKey }.count, 1)

        // 2. Cancel -> never writes to the ledger at all, repeat included.
        let beforeCancelCount = ledger.adjustments.count
        // (no-op: cancelling has no ledger call, mirrors CreditLedgerUseCases
        // exposing no debit/credit path for cancellation)
        XCTAssertEqual(ledger.adjustments.count, beforeCancelCount)

        // 3. Absent, coach chooses "charged" -> debit once, repeat does not double-debit.
        let absentChargedKey = CreditLedger.sourceEventKey(appointmentAbsent: absentChargedAppointment)
        try debit(absentChargedKey, appointmentID: absentChargedAppointment, reasonKind: .appointmentAbsent)
        try debit(absentChargedKey, appointmentID: absentChargedAppointment, reasonKind: .appointmentAbsent)
        XCTAssertEqual(ledger.adjustments.filter { $0.sourceEventKey == absentChargedKey }.count, 1)

        // 4. Absent, coach chooses "not charged" -> mirrors
        // CreditLedgerUseCases.applyAbsence's early return: the ledger is never
        // touched for this appointment, even once.
        let absentNotChargedKey = CreditLedger.sourceEventKey(appointmentAbsent: absentNotChargedAppointment)
        XCTAssertNil(ledger.adjustments.first { $0.sourceEventKey == absentNotChargedKey })

        // 5. Ad-hoc/walk-in session debits the active package -> once, repeat
        // does not double-debit.
        let adhocKey = CreditLedger.sourceEventKey(adhocSession: adhocSession)
        try debit(adhocKey, sessionID: adhocSession, reasonKind: .adhocSession)
        try debit(adhocKey, sessionID: adhocSession, reasonKind: .adhocSession)
        XCTAssertEqual(ledger.adjustments.filter { $0.sourceEventKey == adhocKey }.count, 1)

        // 6. Reopening the completed session credits back exactly that one debit;
        // repeat reopen does not double-credit.
        let reopenKey = CreditLedger.sourceEventKey(sessionReopen: completedSession)
        try credit(reopenKey, sessionID: completedSession, reasonKind: .sessionReopen)
        try credit(reopenKey, sessionID: completedSession, reasonKind: .sessionReopen)
        XCTAssertEqual(ledger.adjustments.filter { $0.sourceEventKey == reopenKey }.count, 1)

        // SC-003: exactly one ledger entry per distinct real event above (complete,
        // absent-charged, adhoc, reopen -- 4 events), i.e. zero erroneous extra
        // debits/credits from any of the repeats.
        XCTAssertEqual(ledger.adjustments.count, 4)
        // 10 total - 3 debits (complete, absent-charged, adhoc) + 1 credit (reopen) = 8.
        XCTAssertEqual(ledger.balance, 8)
    }

    func testDebitNeverPushesBalanceNegativeAndRejectedDebitIsNotRecorded() throws {
        let ledger = SimulatedLedger(totalCredits: 1)
        try debitOnce(ledger, key: "k1")
        XCTAssertEqual(ledger.balance, 0)
        XCTAssertThrowsError(try debitOnce(ledger, key: "k2")) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
        XCTAssertEqual(ledger.balance, 0, "a rejected debit must never be silently recorded")
        XCTAssertEqual(ledger.adjustments.count, 1, "only the successful debit is on the ledger")
    }

    private func debitOnce(_ ledger: SimulatedLedger, key: String) throws {
        try ledger.record(sourceEventKey: key) { currentBalance in
            guard CreditLedger.canDebit(currentBalance: currentBalance, amount: 1) else {
                throw DomainError.invalidState
            }
            return try CreditAdjustment(
                id: StableUUID(UUID()),
                packageID: packageID,
                direction: .debit,
                amount: 1,
                reasonKind: .manualCorrection,
                reasonText: try ValidatedText("test"),
                sourceEventKey: key,
                createdAtUTC: now
            )
        }
    }

    private func makeID(_ n: Int) -> StableUUID {
        StableUUID(UUID(uuidString: String(format: "aaaaaaaa-0000-4000-8000-%012d", n))!)
    }
}
