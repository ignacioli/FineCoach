package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.domain.common.AppointmentID
import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.CoursePackageStatus
import com.ignacioli.finecoach.core.domain.common.CreditAdjustmentID
import com.ignacioli.finecoach.core.domain.common.CreditDirection
import com.ignacioli.finecoach.core.domain.common.CreditLedgerSourceEventKeyFactory
import com.ignacioli.finecoach.core.domain.common.CreditReasonKind
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.SourceEventKey
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.ValidatedText
import com.ignacioli.finecoach.core.domain.credit.CoursePackage
import com.ignacioli.finecoach.core.domain.credit.CreditAdjustment
import com.ignacioli.finecoach.core.domain.credit.CreditLedger
import java.time.Instant
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure Domain coverage for S1 T003 (FR-009/FR-012/FR-015).
 *
 * All identifiers and text are fictional. This suite does not use Android,
 * Compose, Room, a database, or a real repository. The duplicate-event case
 * exercises the pure key/algorithm contract only; it is NOT proof of Repository
 * idempotency (T007/T009 prove that against real Room).
 */
class CreditLedgerDomainTests {
    private val packageID = CoursePackageID.parse("11111111-1111-4111-8111-111111111111")
    private val studentID = StudentID.parse("22222222-2222-4222-8222-222222222222")
    private val sessionID = SessionID.parse("aaaaaaaa-1111-4111-8111-111111111111")
    private val adjustmentID = "cccccccc-3333-4333-8333-333333333333"
    private val otherAdjustmentID = "dddddddd-4444-4444-8444-444444444444"
    private val appointmentID = AppointmentID.parse("bbbbbbbb-2222-4222-8222-222222222222")
    private val now = Instant.parse("2026-11-06T08:00:00Z")
    private val later = Instant.parse("2026-11-06T08:01:00Z")

    // MARK: - Balance derivation (FR-012)

    @Test
    fun balanceWithNoAdjustmentsEqualsTotalCredits() {
        assertEquals(10L, CreditLedger.balance(totalCredits = 10, adjustments = emptyList()))
    }

    @Test
    fun balanceSumsCreditsAndDebits() {
        val adjustments = listOf(
            adjustment(
                direction = CreditDirection.debit,
                amount = 3,
                reasonKind = CreditReasonKind.sessionComplete,
                sourceEventKey = "session-complete:TEST",
            ),
            adjustment(
                direction = CreditDirection.credit,
                amount = 1,
                reasonKind = CreditReasonKind.sessionReopen,
                sourceEventKey = "session-reopen:TEST",
            ),
        )

        assertEquals(8L, CreditLedger.balance(totalCredits = 10, adjustments = adjustments))
    }

    @Test
    fun balanceUsesExactArithmeticInsteadOfWrapping() {
        val credit = adjustment(
            direction = CreditDirection.credit,
            amount = 1,
            reasonKind = CreditReasonKind.manualCorrection,
            reasonText = ValidatedText.required("fictional correction"),
            sourceEventKey = "manual-correction:OVERFLOW",
        )
        val debit = adjustment(
            direction = CreditDirection.debit,
            amount = 1,
            reasonKind = CreditReasonKind.sessionComplete,
            sourceEventKey = "session-complete:UNDERFLOW",
        )

        assertThrows(ArithmeticException::class.java) {
            CreditLedger.balance(Long.MAX_VALUE, listOf(credit))
        }
        assertThrows(ArithmeticException::class.java) {
            CreditLedger.balance(Long.MIN_VALUE, listOf(debit))
        }
    }

    @Test
    fun canDebitRejectsAnyNegativeResult() {
        assertFalse(CreditLedger.canDebit(currentBalance = 0, amount = 1))
        assertTrue(CreditLedger.canDebit(currentBalance = 1, amount = 1))
        assertTrue(CreditLedger.canDebit(currentBalance = 5, amount = 5))
        assertFalse(CreditLedger.canDebit(currentBalance = 5, amount = 6))
    }

    // MARK: - Course package lifecycle (FR-009/FR-012/FR-013)

    @Test
    fun totalCreditsMustBePositive() {
        assertThrows(IllegalArgumentException::class.java) {
            coursePackage(totalCredits = 0)
        }
        assertThrows(IllegalArgumentException::class.java) {
            coursePackage(totalCredits = -1)
        }
    }

    @Test
    fun remainingCreditsCacheDefaultsToTotalCredits() {
        val packageValue = CoursePackage(
            coursePackageID = packageID,
            studentID = studentID,
            totalCredits = 10,
            createdAtUTC = now,
            updatedAtUTC = now,
        )

        assertEquals(10L, packageValue.remainingCreditsCache)
    }

    @Test
    fun cachingRemainingReplacesTheNonAuthoritativeCache() {
        val packageValue = coursePackage(totalCredits = 10, remainingCreditsCache = 10)

        val cached = packageValue.cachingRemaining(ledgerBalance = 7, now = later)

        assertEquals(7L, cached.remainingCreditsCache)
        assertEquals(later, cached.updatedAtUTC)
        assertEquals(packageValue.copy(remainingCreditsCache = 7, updatedAtUTC = later), cached)
    }

    @Test
    fun endingActivePackageKeepsHistoryAndRejectsDoubleEnd() {
        val packageValue = coursePackage(
            name = ValidatedText.required("Fictional 10-pack"),
            totalCredits = 10,
            remainingCreditsCache = 4,
            startDate = LocalDate.of(2026, 1, 1),
            endDate = LocalDate.of(2026, 12, 31),
        )

        val ended = packageValue.ending(now = later)

        assertEquals(CoursePackageStatus.ended, ended.status)
        assertEquals(later, ended.updatedAtUTC)
        assertEquals(packageValue.coursePackageID, ended.coursePackageID)
        assertEquals(packageValue.studentID, ended.studentID)
        assertEquals(packageValue.name, ended.name)
        assertEquals(packageValue.totalCredits, ended.totalCredits)
        assertEquals(packageValue.remainingCreditsCache, ended.remainingCreditsCache)
        assertEquals(packageValue.startDate, ended.startDate)
        assertEquals(packageValue.endDate, ended.endDate)
        assertEquals(packageValue.createdAtUTC, ended.createdAtUTC)
        assertThrows(IllegalStateException::class.java) { ended.ending(now = later) }
    }

    @Test
    fun expiryUsesTheCalendarDayAfterEndDateAndNeverMutatesStatus() {
        val packageValue = coursePackage(endDate = LocalDate.of(2026, 1, 1))

        assertFalse(packageValue.isExpired(LocalDate.of(2025, 12, 31)))
        assertFalse(packageValue.isExpired(LocalDate.of(2026, 1, 1)))
        assertTrue(packageValue.isExpired(LocalDate.of(2026, 1, 2)))
        assertEquals(CoursePackageStatus.active, packageValue.status)
        assertFalse(coursePackage(endDate = null).isExpired(LocalDate.of(2099, 12, 31)))

        val ended = packageValue.ending(now = later)
        assertTrue(ended.isExpired(LocalDate.of(2026, 1, 2)))
    }

    @Test
    fun reverseDateRangeIsAllowedAndDateFactsStillUseEndDate() {
        // S1-D02: the product decision is to match iOS and NOT reject
        // endDate < startDate. This Domain construction is the save precondition;
        // T007 owns the real persistence proof.
        val packageValue = coursePackage(
            startDate = LocalDate.of(2026, 2, 1),
            endDate = LocalDate.of(2026, 1, 1),
        )

        assertEquals(LocalDate.of(2026, 2, 1), packageValue.startDate)
        assertEquals(LocalDate.of(2026, 1, 1), packageValue.endDate)
        assertEquals(CoursePackageStatus.active, packageValue.status)
        assertFalse(packageValue.isExpired(LocalDate.of(2026, 1, 1)))
        assertTrue(packageValue.isExpired(LocalDate.of(2026, 1, 2)))
        assertEquals("课包 · 2026-02-01", packageValue.displayName)
        assertEquals(4L, packageValue.cachingRemaining(ledgerBalance = 4, now = later).remainingCreditsCache)
    }

    @Test
    fun blankCoursePackageNameBecomesNullAndFallsBackToStartDate() {
        val blankName = ValidatedText.optional(" \t\u00A0\u3000\n")

        assertNull(blankName)
        val packageValue = coursePackage(name = blankName, startDate = LocalDate.of(2026, 1, 5))
        assertNull(packageValue.name)
        assertEquals("课包 · 2026-01-05", packageValue.displayName)

        // The shared ValidatedText also trims and NFC-normalizes a real name.
        val named = coursePackage(name = ValidatedText.optional("  Cafe\u0301 plan  "))
        assertEquals("Caf\u00E9 plan", named.displayName)
    }

    @Test
    fun overlongCoursePackageNameIsRejected() {
        // 21_846 * 3 UTF-8 bytes = 65_538 > 64 KiB.
        val overlong = "课".repeat(21_846)

        assertThrows(IllegalArgumentException::class.java) { ValidatedText.optional(overlong) }
        assertThrows(IllegalArgumentException::class.java) {
            coursePackage(name = ValidatedText.optional(overlong))
        }
    }

    @Test
    fun displayNameFallsBackToStartDateThenGenericLabel() {
        assertEquals(
            "Fictional plan",
            coursePackage(
                name = ValidatedText.required("Fictional plan"),
                startDate = LocalDate.of(2026, 1, 5),
            ).displayName,
        )
        assertEquals(
            "课包 · 2026-01-05",
            coursePackage(
                name = ValidatedText.parse("", allowEmpty = true),
                startDate = LocalDate.of(2026, 1, 5),
            ).displayName,
        )
        assertEquals("课包 · 2026-01-05", coursePackage(startDate = LocalDate.of(2026, 1, 5)).displayName)
        assertEquals("课包", coursePackage().displayName)
    }

    @Test
    fun lowBalanceIsDerivedAtZeroOrBelow() {
        val packageValue = coursePackage()

        assertTrue(packageValue.isBalanceLow(ledgerBalance = 0))
        assertTrue(packageValue.isBalanceLow(ledgerBalance = -1))
        assertFalse(packageValue.isBalanceLow(ledgerBalance = 1))
        assertFalse(packageValue.isBalanceLow(ledgerBalance = 8))
    }

    // MARK: - Credit adjustment validation (FR-014/FR-015)

    @Test
    fun creditAdjustmentAmountMustBePositive() {
        assertThrows(IllegalArgumentException::class.java) {
            adjustment(direction = CreditDirection.debit, amount = 0, reasonKind = CreditReasonKind.sessionComplete)
        }
        assertThrows(IllegalArgumentException::class.java) {
            adjustment(direction = CreditDirection.credit, amount = -1, reasonKind = CreditReasonKind.sessionReopen)
        }
    }

    @Test
    fun manualCorrectionRequiresANonBlankReason() {
        listOf<ValidatedText?>(
            null,
            ValidatedText.optional(""),
            ValidatedText.optional("   "),
        ).forEach { reason ->
            assertNull(reason)
            assertThrows(IllegalArgumentException::class.java) {
                adjustment(
                    direction = CreditDirection.debit,
                    amount = 1,
                    reasonKind = CreditReasonKind.manualCorrection,
                    reasonText = reason,
                )
            }
        }
    }

    @Test
    fun blankReasonTextBecomesNullForAutomaticReasons() {
        val blankReason = ValidatedText.optional(" \t\u00A0\u3000\n")

        assertNull(blankReason)
        val value = adjustment(
            direction = CreditDirection.debit,
            amount = 1,
            reasonKind = CreditReasonKind.appointmentAbsent,
            reasonText = blankReason,
        )

        assertNull(value.reasonText)
    }

    @Test
    fun overlongReasonTextIsRejected() {
        val overlong = "a".repeat(ValidatedText.maximumUTF8Bytes + 1)

        assertThrows(IllegalArgumentException::class.java) { ValidatedText.optional(overlong) }
        assertThrows(IllegalArgumentException::class.java) {
            adjustment(
                direction = CreditDirection.debit,
                amount = 1,
                reasonKind = CreditReasonKind.manualCorrection,
                reasonText = ValidatedText.optional(overlong),
            )
        }
    }

    @Test
    fun invalidAppointmentIdIsRejected() {
        listOf(
            "not-a-uuid",
            "bbbbbbbb-2222-4222-8222-22222222222",
            "bbbbbbbb-2222-4222-8222-22222222222z",
            "bbbbbbbb222242228222222222222222",
        ).forEach { raw ->
            assertThrows(IllegalArgumentException::class.java) { AppointmentID.parse(raw) }
        }
    }

    @Test
    fun automaticReasonsDoNotRequireReasonText() {
        listOf(
            CreditReasonKind.sessionComplete,
            CreditReasonKind.appointmentAbsent,
            CreditReasonKind.adhocSession,
            CreditReasonKind.sessionReopen,
        ).forEach { reason ->
            val value = adjustment(
                direction = CreditDirection.debit,
                amount = 1,
                reasonKind = reason,
                reasonText = null,
                sourceEventKey = "automatic-event:${reason.wireValue}",
            )
            assertEquals(reason, value.reasonKind)
            assertNull(value.reasonText)
        }
    }

    @Test
    fun creditAdjustmentKeepsAllTraceableFields() {
        val value = adjustment(
            direction = CreditDirection.credit,
            amount = 2,
            reasonKind = CreditReasonKind.manualCorrection,
            reasonText = ValidatedText.required("fictional correction"),
            linkedSessionID = sessionID,
            linkedAppointmentID = appointmentID,
            sourceEventKey = "manual-correction:TRACE",
        )

        assertEquals(CreditAdjustmentID.parse(adjustmentID), value.creditAdjustmentID)
        assertEquals(packageID, value.coursePackageID)
        assertEquals(CreditDirection.credit, value.direction)
        assertEquals(2L, value.amount)
        assertEquals(CreditReasonKind.manualCorrection, value.reasonKind)
        assertEquals(ValidatedText.required("fictional correction"), value.reasonText)
        assertEquals(sessionID, value.linkedSessionID)
        assertEquals(appointmentID, value.linkedAppointmentID)
        assertEquals("manual-correction:TRACE", value.sourceEventKey.value)
        assertEquals(now, value.createdAtUTC)
    }

    // MARK: - Deterministic sourceEventKey construction (FR-015)

    @Test
    fun sourceEventKeysAreDeterministicAndMatchIosByteShape() {
        val sessionKey = CreditLedgerSourceEventKeyFactory.sessionComplete(sessionID)

        assertEquals(sessionKey, CreditLedgerSourceEventKeyFactory.sessionComplete(sessionID))
        assertEquals(
            "session-complete:AAAAAAAA-1111-4111-8111-111111111111",
            sessionKey.value,
        )
        assertEquals(
            "session-reopen:AAAAAAAA-1111-4111-8111-111111111111",
            CreditLedgerSourceEventKeyFactory.sessionReopen(sessionID).value,
        )
        assertEquals(
            "adhoc-session:AAAAAAAA-1111-4111-8111-111111111111",
            CreditLedgerSourceEventKeyFactory.adhocSession(sessionID).value,
        )
        assertEquals(
            "appointment-absent:BBBBBBBB-2222-4222-8222-222222222222",
            CreditLedgerSourceEventKeyFactory.appointmentAbsent(appointmentID).value,
        )
        assertEquals(
            "manual-correction:CCCCCCCC-3333-4333-8333-333333333333",
            CreditLedgerSourceEventKeyFactory.manualCorrection(
                CreditAdjustmentID.parse(adjustmentID),
            ).value,
        )
    }

    @Test
    fun sourceEventKeysAreDistinctAcrossKindsForTheSameUnderlyingID() {
        val keys = setOf(
            CreditLedgerSourceEventKeyFactory.sessionComplete(sessionID),
            CreditLedgerSourceEventKeyFactory.sessionReopen(sessionID),
            CreditLedgerSourceEventKeyFactory.adhocSession(sessionID),
        )

        assertEquals(3, keys.size)
    }

    @Test
    fun manualCorrectionKeysAreUniquePerAdjustmentID() {
        val first = CreditLedgerSourceEventKeyFactory.manualCorrection(CreditAdjustmentID.parse(adjustmentID))
        val second = CreditLedgerSourceEventKeyFactory.manualCorrection(
            CreditAdjustmentID.parse(otherAdjustmentID),
        )

        assertTrue(first != second)
    }

    // MARK: - Pure repeated-event contract (NOT Repository idempotency proof)

    @Test
    fun repeatingTheSameSourceEventKeyDoesNotDoubleApply() {
        val ledger = SimulatedLedger(totalCredits = 10)
        val completeKey = CreditLedgerSourceEventKeyFactory.sessionComplete(sessionID)
        val reopenKey = CreditLedgerSourceEventKeyFactory.sessionReopen(sessionID)
        val adhocKey = CreditLedgerSourceEventKeyFactory.adhocSession(sessionID)

        val firstDebit = ledger.debit(completeKey, amount = 2, reasonKind = CreditReasonKind.sessionComplete)
        val repeatedDebit = ledger.debit(
            completeKey,
            amount = 2,
            reasonKind = CreditReasonKind.sessionComplete,
        )
        assertSame(firstDebit, repeatedDebit)
        assertEquals(1, ledger.adjustments.size)
        assertEquals(8L, ledger.balance)

        ledger.credit(reopenKey, amount = 2, reasonKind = CreditReasonKind.sessionReopen)
        ledger.credit(reopenKey, amount = 2, reasonKind = CreditReasonKind.sessionReopen)
        assertEquals(2, ledger.adjustments.size)
        assertEquals(10L, ledger.balance)

        ledger.debit(adhocKey, amount = 1, reasonKind = CreditReasonKind.adhocSession)
        ledger.debit(adhocKey, amount = 1, reasonKind = CreditReasonKind.adhocSession)
        assertEquals(3, ledger.adjustments.size)
        assertEquals(9L, ledger.balance)
    }

    @Test
    fun rejectedDebitIsNeverRecorded() {
        val ledger = SimulatedLedger(totalCredits = 1)

        ledger.debit(
            CreditLedgerSourceEventKeyFactory.sessionComplete(sessionID),
            amount = 1,
            reasonKind = CreditReasonKind.sessionComplete,
        )
        assertThrows(IllegalStateException::class.java) {
            ledger.debit(
                CreditLedgerSourceEventKeyFactory.adhocSession(sessionID),
                amount = 1,
                reasonKind = CreditReasonKind.adhocSession,
            )
        }

        assertEquals(1, ledger.adjustments.size)
        assertEquals(0L, ledger.balance)
    }

    private fun coursePackage(
        name: ValidatedText? = null,
        totalCredits: Long = 10,
        remainingCreditsCache: Long = totalCredits,
        startDate: LocalDate? = null,
        endDate: LocalDate? = null,
        status: CoursePackageStatus = CoursePackageStatus.active,
    ): CoursePackage = CoursePackage(
        coursePackageID = packageID,
        studentID = studentID,
        name = name,
        totalCredits = totalCredits,
        remainingCreditsCache = remainingCreditsCache,
        startDate = startDate,
        endDate = endDate,
        status = status,
        createdAtUTC = now,
        updatedAtUTC = now,
    )

    private fun adjustment(
        direction: CreditDirection,
        amount: Long,
        reasonKind: CreditReasonKind,
        reasonText: ValidatedText? = null,
        linkedSessionID: SessionID? = null,
        linkedAppointmentID: AppointmentID? = null,
        sourceEventKey: String = "manual-correction:TEST",
    ): CreditAdjustment = CreditAdjustment(
        creditAdjustmentID = CreditAdjustmentID.parse(adjustmentID),
        coursePackageID = packageID,
        direction = direction,
        amount = amount,
        reasonKind = reasonKind,
        reasonText = reasonText,
        linkedSessionID = linkedSessionID,
        linkedAppointmentID = linkedAppointmentID,
        sourceEventKey = SourceEventKey.parse(sourceEventKey),
        createdAtUTC = now,
    )

    /**
     * Test-local stand-in for the Repository's dedup-by-key contract. The real
     * transaction proof is T007/T009 against Room; this only exercises the pure
     * key and balance rules.
     */
    private class SimulatedLedger(private val totalCredits: Long) {
        private var nextID = 0
        val adjustments = mutableListOf<CreditAdjustment>()

        val balance: Long
            get() = CreditLedger.balance(totalCredits, adjustments)

        fun debit(sourceEventKey: SourceEventKey, amount: Long, reasonKind: CreditReasonKind): CreditAdjustment =
            record(sourceEventKey) {
                check(CreditLedger.canDebit(balance, amount)) { "debit would make balance negative" }
                CreditAdjustment(
                    creditAdjustmentID = newAdjustmentID(),
                    coursePackageID = CoursePackageID.parse("11111111-1111-4111-8111-111111111111"),
                    direction = CreditDirection.debit,
                    amount = amount,
                    reasonKind = reasonKind,
                    sourceEventKey = sourceEventKey,
                    createdAtUTC = Instant.parse("2026-11-06T08:00:00Z"),
                )
            }

        fun credit(sourceEventKey: SourceEventKey, amount: Long, reasonKind: CreditReasonKind): CreditAdjustment =
            record(sourceEventKey) {
                CreditAdjustment(
                    creditAdjustmentID = newAdjustmentID(),
                    coursePackageID = CoursePackageID.parse("11111111-1111-4111-8111-111111111111"),
                    direction = CreditDirection.credit,
                    amount = amount,
                    reasonKind = reasonKind,
                    sourceEventKey = sourceEventKey,
                    createdAtUTC = Instant.parse("2026-11-06T08:00:00Z"),
                )
            }

        private fun newAdjustmentID(): CreditAdjustmentID {
            nextID += 1
            return CreditAdjustmentID.parse("eeeeeeee-5555-4555-8555-${nextID.toString().padStart(12, '0')}")
        }

        private fun record(sourceEventKey: SourceEventKey, make: () -> CreditAdjustment): CreditAdjustment {
            adjustments.firstOrNull { it.sourceEventKey == sourceEventKey }?.let { return it }
            val created = make()
            adjustments.add(created)
            return created
        }
    }
}
