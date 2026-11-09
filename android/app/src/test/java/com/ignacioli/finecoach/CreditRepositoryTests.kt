// fictional-data: All student IDs, package names, session IDs, and credit ledger entries in this file are fictional test fixtures.
package com.ignacioli.finecoach

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.ApplicationErrorCode
import com.ignacioli.finecoach.core.application.ApplicationResult
import com.ignacioli.finecoach.core.application.CoursePackageRecord
import com.ignacioli.finecoach.core.application.CreditAdjustmentRecord
import com.ignacioli.finecoach.core.application.CreditUseCases
import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.CreditDirection
import com.ignacioli.finecoach.core.domain.common.CreditReasonKind
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.ValidatedText
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory
import com.ignacioli.finecoach.storage.repository.CoursePackageRepository
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class CreditRepositoryTests {
    private val worker = Executors.newSingleThreadExecutor()
    private val defaultZone: ZoneId = ZoneId.of("Asia/Shanghai")
    private lateinit var context: Context
    private lateinit var database: FineCoachDatabase
    private lateinit var clock: MutableAppClock
    private lateinit var ids: SequentialIDGenerator
    private lateinit var repository: CoursePackageRepository
    private lateinit var useCases: CreditUseCases

    private val studentA = StudentID.parse("20000000-0000-4000-8000-000000000001")
    private val session1 = SessionID.parse("30000000-0000-4000-8000-000000000001")
    private val session2 = SessionID.parse("30000000-0000-4000-8000-000000000002")
    private val appointment1 = "40000000-0000-4000-8000-000000000001"

    private fun <T> offMain(action: suspend () -> T): T =
        worker.submit(Callable { runBlocking { action() } }).get(30, TimeUnit.SECONDS)

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        clock = MutableAppClock(Instant.parse("2026-11-06T10:00:00Z"))
        ids = SequentialIDGenerator()
        openFreshStack()
    }

    @After
    fun tearDown() {
        try {
            if (::database.isInitialized && database.isOpen) {
                offMain { database.close() }
            }
        } finally {
            worker.shutdownNow()
            context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        }
    }

    private fun openFreshStack() {
        database = FineCoachDatabaseFactory.create(context)
        repository = CoursePackageRepository(
            database = database,
            clock = clock,
            ids = ids,
            zoneID = defaultZone,
        )
        useCases = CreditUseCases(
            repository = repository,
            clock = clock,
            ids = ids,
            zoneID = defaultZone,
        )
    }

    private fun closeAndReopenStack() {
        database.close()
        openFreshStack()
    }

    /**
     * Reads the persisted `remainingCreditsCache` column directly from the `course_packages` table
     * via [FineCoachDatabase.s1Dao] without any Repository-layer ledger recomputation.
     */
    private fun rawPersistedRemainingCreditsCache(coursePackageID: CoursePackageID): Long =
        requireNotNull(database.s1Dao().findCoursePackage(UUID.fromString(coursePackageID.value))) {
            "Expected course_packages row to exist"
        }.remainingCreditsCache

    @Test
    fun manualDebitAndCreditUpdateBalanceAndTrailAndSurviveCloseAndReopen(): Unit = offMain {
        val pkg = createActivePackage(totalCredits = 6L)
        assertEquals(6L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))

        val debitRes = useCases.recordManualCorrection(
            coursePackageID = pkg.coursePackageID,
            direction = CreditDirection.debit,
            amount = 2L,
            reasonText = "  虚构手工扣减  ",
        )
        val debit = debitRes.requireSuccess("debitRes")
        assertEquals(CreditDirection.debit, debit.direction)
        assertEquals(2L, debit.amount)
        assertEquals(CreditReasonKind.manualCorrection, debit.reasonKind)
        assertEquals("虚构手工扣减", debit.reasonText)
        assertEquals(4L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))

        clock.advanceSeconds(15)
        val creditRes = useCases.recordManualCorrection(
            coursePackageID = pkg.coursePackageID,
            direction = CreditDirection.credit,
            amount = 1L,
            reasonText = "虚构手工返还",
        )
        val credit = creditRes.requireSuccess("creditRes")
        assertEquals(CreditDirection.credit, credit.direction)

        val balanceBeforeReopen = useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balance")
        assertEquals(5L, balanceBeforeReopen)
        assertEquals(balanceBeforeReopen, rawPersistedRemainingCreditsCache(pkg.coursePackageID))

        closeAndReopenStack()

        val balanceAfterReopen = useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceAfterReopen")
        assertEquals(5L, balanceAfterReopen)
        assertEquals(balanceAfterReopen, rawPersistedRemainingCreditsCache(pkg.coursePackageID))
        val pkgAfterReopen = useCases.activePackage(studentA).requireSuccess("pkgAfterReopen")
        assertEquals(5L, pkgAfterReopen?.remainingCreditsCache)

        val trail = useCases.ledger(studentA).requireSuccess("trail")
        assertEquals(listOf(debit, credit), trail)
    }

    @Test
    fun manualCorrectionValidatesPositiveAmountAndNonBlankReasonWithoutWrites(): Unit = offMain {
        val pkg = createActivePackage(totalCredits = 5L)

        val zeroAmount = useCases.recordManualCorrection(
            coursePackageID = pkg.coursePackageID,
            direction = CreditDirection.debit,
            amount = 0L,
            reasonText = "虚构原因",
        )
        assertEquals(
            ApplicationErrorCode.invalidNumber,
            zeroAmount.requireFailure("zeroAmount").code,
        )

        val blankReason = useCases.recordManualCorrection(
            coursePackageID = pkg.coursePackageID,
            direction = CreditDirection.debit,
            amount = 1L,
            reasonText = " \t\u00A0\u3000\n ",
        )
        assertEquals(
            ApplicationErrorCode.emptyText,
            blankReason.requireFailure("blankReason").code,
        )

        val overlongReason = useCases.recordManualCorrection(
            coursePackageID = pkg.coursePackageID,
            direction = CreditDirection.credit,
            amount = 1L,
            reasonText = "虚".repeat((ValidatedText.maximumUTF8Bytes / 3) + 10),
        )
        assertEquals(
            ApplicationErrorCode.textTooLong,
            overlongReason.requireFailure("overlongReason").code,
        )

        assertEquals(5L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balance"))
        assertEquals(5L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))
        assertTrue(useCases.ledger(studentA).requireSuccess("ledger").isEmpty())
    }

    @Test
    fun insufficientBalanceRejectsManualAndAutomaticDebitsWithoutClampingOrWriting(): Unit = offMain {
        val pkg = createActivePackage(totalCredits = 1L)

        // Over-debit manually -> rejected.
        val overDebit = useCases.recordManualCorrection(
            coursePackageID = pkg.coursePackageID,
            direction = CreditDirection.debit,
            amount = 2L,
            reasonText = "虚构超额扣减",
        )
        assertEquals(
            ApplicationErrorCode.invalidState,
            overDebit.requireFailure("overDebit").code,
        )
        assertEquals(1L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balance"))
        assertEquals(1L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))

        // Exact 1 debit succeeds -> balance becomes 0.
        useCases.debitOnSessionComplete(pkg.coursePackageID, session1).requireSuccess("exactDebit")
        assertEquals(0L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceAfterExact"))
        assertEquals(0L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))

        // Subsequent automatic debit for a new session is rejected at 0 balance.
        val secondSessionDebit = useCases.debitOnAdhocSession(pkg.coursePackageID, session2)
        assertEquals(
            ApplicationErrorCode.invalidState,
            secondSessionDebit.requireFailure("secondSessionDebit").code,
        )

        val trail = useCases.ledger(studentA).requireSuccess("trail")
        assertEquals(1, trail.size)
        assertEquals(0L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("finalBalance"))
        assertEquals(0L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))
    }

    @Test
    fun duplicateAutomaticEventsWithSameSourceEventKeyAreIdempotentAcrossReopen(): Unit = offMain {
        val pkg = createActivePackage(totalCredits = 5L)

        val firstComplete = useCases.debitOnSessionComplete(pkg.coursePackageID, session1).requireSuccess("firstComplete")
        clock.advanceSeconds(10)
        val repeatComplete = useCases.debitOnSessionComplete(pkg.coursePackageID, session1).requireSuccess("repeatComplete")
        assertEquals(firstComplete, repeatComplete)
        assertEquals(4L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceAfterComplete"))
        assertEquals(4L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))

        val firstAdhoc = useCases.debitOnAdhocSession(pkg.coursePackageID, session2).requireSuccess("firstAdhoc")
        val repeatAdhoc = useCases.debitOnAdhocSession(pkg.coursePackageID, session2).requireSuccess("repeatAdhoc")
        assertEquals(firstAdhoc, repeatAdhoc)
        assertEquals(3L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceAfterAdhoc"))
        assertEquals(3L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))

        val firstAbsent = useCases.debitOnAppointmentAbsent(pkg.coursePackageID, appointment1).requireSuccess("firstAbsent")
        val repeatAbsent = useCases.debitOnAppointmentAbsent(pkg.coursePackageID, appointment1).requireSuccess("repeatAbsent")
        assertEquals(firstAbsent, repeatAbsent)
        assertEquals(2L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceAfterAbsent"))
        assertEquals(2L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))

        closeAndReopenStack()

        // Repeating after database close and reopen still returns the existing adjustment without double-debiting.
        val repeatCompleteAfterReopen = useCases.debitOnSessionComplete(pkg.coursePackageID, session1)
            .requireSuccess("repeatCompleteAfterReopen")
        assertEquals(firstComplete, repeatCompleteAfterReopen)
        assertEquals(2L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceAfterReopen"))
        assertEquals(2L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))
        assertEquals(3, useCases.ledger(studentA).requireSuccess("ledgerAfterReopen").size)
    }

    @Test
    fun refundOnSessionReopenRefundsAtMostOnceWhenPriorDebitExistsAndNoOpsWhenNotDebited(): Unit = offMain {
        val pkg = createActivePackage(totalCredits = 4L)

        // Reopening a session that was never debited is a deliberate no-op returning null (FR-015, S1-D04).
        val noOpRefund = useCases.refundOnSessionReopen(session2).requireSuccess("noOpRefund")
        assertNull(noOpRefund)
        assertEquals(4L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceInitial"))
        assertEquals(4L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))

        // Complete and debit session1 -> balance 3.
        useCases.debitOnSessionComplete(pkg.coursePackageID, session1).requireSuccess("debitOnSessionComplete")
        assertEquals(3L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceAfterDebit"))
        assertEquals(3L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))

        // First reopen refunds 1 -> balance 4.
        clock.advanceSeconds(20)
        val firstRefund = useCases.refundOnSessionReopen(session1).requireSuccess("firstRefund")
        assertNotNull(firstRefund)
        assertEquals(CreditDirection.credit, firstRefund?.direction)
        assertEquals(CreditReasonKind.sessionReopen, firstRefund?.reasonKind)
        assertEquals(session1, firstRefund?.linkedSessionID)
        assertEquals(4L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceAfterFirstRefund"))
        assertEquals(4L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))

        // Repeat reopen before and after reopen does not credit a second time.
        clock.advanceSeconds(20)
        val secondRefund = useCases.refundOnSessionReopen(session1).requireSuccess("secondRefund")
        assertEquals(firstRefund, secondRefund)
        assertEquals(4L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceAfterSecondRefund"))

        closeAndReopenStack()

        val thirdRefundAfterReopen = useCases.refundOnSessionReopen(session1).requireSuccess("thirdRefundAfterReopen")
        assertEquals(firstRefund, thirdRefundAfterReopen)
        assertEquals(4L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceAfterThirdRefund"))
        assertEquals(4L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))

        val trail = useCases.ledger(studentA).requireSuccess("trail")
        assertEquals(listOf(CreditReasonKind.sessionComplete, CreditReasonKind.sessionReopen), trail.map { it.reasonKind })
    }

    @Test
    fun failedAdjustmentTransactionViaSqliteTriggerRollsBackLedgerEntryAndBalanceCache(): Unit = offMain {
        val pkg = createActivePackage(totalCredits = 5L)

        // First perform a valid debit so the persisted cache column transitions from 5 -> 4.
        useCases.debitOnSessionComplete(pkg.coursePackageID, session1).requireSuccess("initialDebit")
        assertEquals(4L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceAfterInitialDebit"))
        assertEquals(4L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))

        // 1. Inject a failure BEFORE updating course_packages (after inserting credit_adjustments).
        val sqlite = database.openHelper.writableDatabase
        sqlite.execSQL(
            """
            CREATE TRIGGER abort_package_cache_update
            BEFORE UPDATE ON course_packages
            BEGIN
                SELECT RAISE(ABORT, 'injected course_packages cache update failure');
            END
            """.trimIndent(),
        )

        val failedBeforeUpdate = useCases.debitOnAdhocSession(pkg.coursePackageID, session2)
        assertEquals(
            ApplicationErrorCode.persistenceFailed,
            failedBeforeUpdate.requireFailure("failedBeforeUpdate").code,
        )
        sqlite.execSQL("DROP TRIGGER abort_package_cache_update")

        // Both the ledger insert and the cache column remain at the pre-failure state (4L, 1 adjustment).
        assertEquals(4L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceAfterBeforeTrigger"))
        assertEquals(4L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))
        assertEquals(1, useCases.ledger(studentA).requireSuccess("ledgerAfterBeforeTrigger").size)

        // 2. Inject a failure AFTER updating course_packages so the cache column write itself must roll back.
        sqlite.execSQL(
            """
            CREATE TRIGGER abort_after_package_cache_update
            AFTER UPDATE ON course_packages
            BEGIN
                SELECT RAISE(ABORT, 'injected post-update failure');
            END
            """.trimIndent(),
        )

        val failedAfterUpdate = useCases.debitOnAdhocSession(pkg.coursePackageID, session2)
        assertEquals(
            ApplicationErrorCode.persistenceFailed,
            failedAfterUpdate.requireFailure("failedAfterUpdate").code,
        )
        sqlite.execSQL("DROP TRIGGER abort_after_package_cache_update")

        assertEquals(4L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceAfterPostTrigger"))
        assertEquals(4L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))
        assertEquals(1, useCases.ledger(studentA).requireSuccess("ledgerAfterPostTrigger").size)

        closeAndReopenStack()

        val balanceAfterReopen = useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceAfterReopen")
        assertEquals(4L, balanceAfterReopen)
        assertEquals(balanceAfterReopen, rawPersistedRemainingCreditsCache(pkg.coursePackageID))
        assertEquals(1, useCases.ledger(studentA).requireSuccess("ledgerAfterReopen").size)
    }

    @Test
    fun concurrentDebitsAgainstLastRemainingCreditAllowExactlyOneWinnerAndNeverGoNegative(): Unit = offMain {
        val pkg = createActivePackage(totalCredits = 1L)
        val pool = Executors.newFixedThreadPool(2)
        val ready = CountDownLatch(2)
        val start = CountDownLatch(1)

        try {
            val taskA = Callable<ApplicationResult<CreditAdjustmentRecord>> {
                ready.countDown()
                start.await(5, TimeUnit.SECONDS)
                runBlocking {
                    useCases.debitOnSessionComplete(pkg.coursePackageID, session1)
                }
            }
            val taskB = Callable<ApplicationResult<CreditAdjustmentRecord>> {
                ready.countDown()
                start.await(5, TimeUnit.SECONDS)
                runBlocking {
                    useCases.debitOnAdhocSession(pkg.coursePackageID, session2)
                }
            }

            val futureA = pool.submit(taskA)
            val futureB = pool.submit(taskB)
            assertTrue(ready.await(5, TimeUnit.SECONDS))
            start.countDown()

            val results = listOf(
                futureA.get(10, TimeUnit.SECONDS),
                futureB.get(10, TimeUnit.SECONDS),
            )
            val successes = results.filterIsInstance<ApplicationResult.Success<CreditAdjustmentRecord>>()
            val failures = results.filterIsInstance<ApplicationResult.Failure>()

            assertEquals(1, successes.size)
            assertEquals(1, failures.size)
            assertEquals(ApplicationErrorCode.invalidState, failures.single().error.code)
        } finally {
            pool.shutdownNow()
        }

        assertEquals(0L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceNow"))
        assertEquals(0L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))
        assertEquals(1, useCases.ledger(studentA).requireSuccess("ledgerNow").size)

        closeAndReopenStack()

        assertEquals(0L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balanceAfterReopen"))
        assertEquals(0L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))
        assertEquals(1, useCases.ledger(studentA).requireSuccess("ledgerAfterReopen").size)
    }

    @Test
    fun concurrentDuplicateDebitsWithSameSourceEventKeyRecordExactlyOnce(): Unit = offMain {
        val pkg = createActivePackage(totalCredits = 3L)
        val pool = Executors.newFixedThreadPool(2)
        val ready = CountDownLatch(2)
        val start = CountDownLatch(1)

        try {
            val task = Callable<ApplicationResult<CreditAdjustmentRecord>> {
                ready.countDown()
                start.await(5, TimeUnit.SECONDS)
                runBlocking {
                    useCases.debitOnSessionComplete(pkg.coursePackageID, session1)
                }
            }
            val futureA = pool.submit(task)
            val futureB = pool.submit(task)
            assertTrue(ready.await(5, TimeUnit.SECONDS))
            start.countDown()

            val resA = futureA.get(10, TimeUnit.SECONDS).requireSuccess("futureA")
            val resB = futureB.get(10, TimeUnit.SECONDS).requireSuccess("futureB")
            assertEquals(resA, resB)
        } finally {
            pool.shutdownNow()
        }

        assertEquals(2L, useCases.balance(studentA, pkg.coursePackageID).requireSuccess("balance"))
        assertEquals(2L, rawPersistedRemainingCreditsCache(pkg.coursePackageID))
        assertEquals(1, useCases.ledger(studentA).requireSuccess("ledger").size)
    }

    private suspend fun createActivePackage(totalCredits: Long): CoursePackageRecord {
        val res = useCases.createActivePackage(
            studentID = studentA,
            name = "虚构账本测试课包",
            totalCredits = totalCredits,
        )
        return res.requireSuccess("createActivePackage").requireSaved("createActivePackage")
    }
}
