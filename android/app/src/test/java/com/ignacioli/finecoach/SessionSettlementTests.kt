// fictional-data: invented students, exercises, notes and temporary file databases only.
package com.ignacioli.finecoach

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.storage.*
import com.ignacioli.finecoach.storage.entity.*
import com.ignacioli.finecoach.storage.repository.*
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class SessionSettlementTests {
    private lateinit var f: T009Fixture
    @Before fun prepare() { f = T009Fixture() }
    @After fun close() { f.close() }

    @Test fun finishRequiresExplicitAdhocChoiceAndRetryNeverAutoDebits() = f.test {
        val pkg = f.coursePackage()
        val content = f.content()
        val finished = f.finish(content)
        assertEquals(SessionState.completed, finished.session.state)
        assertTrue(f.ok(finished.settlement) is SessionCreditOutcome.AdhocChoiceRequired)
        assertEquals(0L, f.count("credit_adjustments"))
        assertEquals(0L, f.count("active_session_pointers"))
        assertEquals(pkg.coursePackageID, (f.ok(finished.settlement) as SessionCreditOutcome.AdhocChoiceRequired).coursePackage.coursePackageID)
        f.reopen()
        assertTrue(f.ok(f.finisher.settlement(content.session.sessionID)) is SessionCreditOutcome.AdhocChoiceRequired)
        assertEquals(0L, f.count("credit_adjustments"))
    }

    @Test fun explicitAdhocDebitIsDurableAndRepeatConfirmationReturnsSameEntry() = f.test {
        val pkg = f.coursePackage()
        val content = f.content()
        f.finish(content)
        val first = f.ok(f.finisher.debitAdhoc(content.session.sessionID, pkg.coursePackageID)) as SessionCreditOutcome.Debited
        f.reopen()
        val second = f.ok(f.finisher.debitAdhoc(content.session.sessionID, pkg.coursePackageID)) as SessionCreditOutcome.Debited
        assertEquals(first, second)
        assertEquals(CreditReasonKind.adhocSession, first.adjustment.reasonKind)
        assertEquals(CreditLedgerSourceEventKeyFactory.adhocSession(content.session.sessionID), first.adjustment.sourceEventKey)
        assertEquals(1L, f.count("credit_adjustments"))
        assertEquals(1L, f.ok(f.credits.balance(f.studentID, pkg.coursePackageID)))
    }

    @Test fun concurrentConfirmationDebitsAtMostOnce() = f.test {
        val pkg = f.coursePackage()
        val content = f.content()
        f.finish(content)
        val finishers = List(2) { f.finisher }
        val ready = CountDownLatch(2)
        val start = CountDownLatch(1)
        val threads = Executors.newFixedThreadPool(2)
        try {
            val jobs = finishers.map { useCases -> threads.submit(Callable {
                ready.countDown(); check(start.await(10, TimeUnit.SECONDS))
                runBlocking { f.ok(useCases.debitAdhoc(content.session.sessionID, pkg.coursePackageID)) }
            }) }
            assertTrue(ready.await(10, TimeUnit.SECONDS)); start.countDown()
            val outcomes = jobs.map { it.get(30, TimeUnit.SECONDS) as SessionCreditOutcome.Debited }
            assertEquals(outcomes.first(), outcomes.last())
            assertEquals(1L, f.count("credit_adjustments"))
        } finally { threads.shutdownNow() }
    }

    @Test fun skipAndCancelChoiceWriteNoLedger() = f.test {
        f.coursePackage()
        val content = f.content()
        f.finish(content)
        assertEquals(SessionCreditOutcome.Skipped, f.ok(f.finisher.skipDebit(content.session.sessionID)))
        f.reopen()
        assertEquals(0L, f.count("credit_adjustments"))
        assertEquals(SessionState.completed, f.ok(f.sessions.find(content.session.sessionID))!!.state)
    }

    @Test fun noPackageStoresPrivateAnnotationAcrossReopen() = f.test {
        val content = f.content()
        assertEquals(SessionCreditOutcome.NoActivePackage, f.ok(f.finish(content).settlement))
        f.reopen()
        assertEquals(SessionCreditSettlementNote.noActivePackage, f.ok(f.history.find(content.session.sessionID))!!.note)
        assertEquals(0L, f.count("credit_adjustments"))
    }

    @Test fun annotationWriteFailureReportsCompletedAndSettlementFailureSeparately() = f.test {
        val content = f.content()
        f.db.openHelper.writableDatabase.execSQL("CREATE TRIGGER t009_failure BEFORE UPDATE OF creditSettlementNote ON sessions WHEN NEW.creditSettlementNote IS NOT OLD.creditSettlementNote BEGIN SELECT RAISE(ABORT, 'injected'); END")
        val result = f.finish(content)
        assertEquals(SessionState.completed, result.session.state)
        f.error(ApplicationErrorCode.persistenceFailed, result.settlement)
        assertNull(f.ok(f.history.find(content.session.sessionID)))
        f.clearFailure(); f.reopen()
        assertEquals(SessionCreditOutcome.NoActivePackage, f.ok(f.finisher.settlement(content.session.sessionID)))
    }

    @Test fun debitFailureDoesNotUndoCompletionAndRetryIsExplicitAndDurable() = f.test {
        val pkg = f.coursePackage()
        val content = f.content()
        f.finish(content)
        f.failWrites("credit_adjustments", "INSERT")
        f.error(ApplicationErrorCode.persistenceFailed, f.finisher.debitAdhoc(content.session.sessionID, pkg.coursePackageID))
        assertEquals(SessionState.completed, f.ok(f.sessions.find(content.session.sessionID))!!.state)
        assertEquals(0L, f.count("credit_adjustments"))
        assertEquals(2L, f.ok(f.credits.balance(f.studentID, pkg.coursePackageID)))
        f.clearFailure(); f.reopen()
        assertTrue(f.ok(f.finisher.debitAdhoc(content.session.sessionID, pkg.coursePackageID)) is SessionCreditOutcome.Debited)
        assertEquals(1L, f.count("credit_adjustments"))
    }

    @Test fun balanceCacheFailureRollsBackDebitAndAllowsRetry() = f.test {
        val pkg = f.coursePackage()
        val content = f.content()
        f.finish(content)
        f.failWrites("course_packages", "UPDATE")
        f.error(ApplicationErrorCode.persistenceFailed, f.finisher.debitAdhoc(content.session.sessionID, pkg.coursePackageID))
        assertEquals(0L, f.count("credit_adjustments"))
        assertEquals(2L, f.ok(f.credits.balance(f.studentID, pkg.coursePackageID)))
        f.clearFailure()
        f.ok(f.finisher.debitAdhoc(content.session.sessionID, pkg.coursePackageID))
        assertEquals(1L, f.count("credit_adjustments"))
    }

    @Test fun expiredPackageCompletesWithoutDebitAndReturnsExplicitReason() = f.test {
        val pkg = f.coursePackage(endDate = f.today.minusDays(1))
        val content = f.content()
        val result = f.ok(f.finish(content).settlement) as SessionCreditOutcome.PackageUnusable
        assertEquals(SessionCreditUnusableReason.expired, result.reason)
        f.error(ApplicationErrorCode.invalidState, f.finisher.debitAdhoc(content.session.sessionID, pkg.coursePackageID))
        assertEquals(0L, f.count("credit_adjustments"))
        assertEquals(SessionCreditOutcome.Skipped, f.ok(f.finisher.skipDebit(content.session.sessionID)))
    }

    @Test fun zeroBalanceCompletesWithoutDebitAndReturnsExplicitReason() = f.test {
        val pkg = f.coursePackage(total = 1)
        f.ok(f.credits.recordManualCorrection(pkg.coursePackageID, CreditDirection.debit, 1, "虚构调整"))
        val content = f.content()
        val result = f.ok(f.finish(content).settlement) as SessionCreditOutcome.PackageUnusable
        assertEquals(SessionCreditUnusableReason.insufficientBalance, result.reason)
        f.error(ApplicationErrorCode.invalidState, f.finisher.debitAdhoc(content.session.sessionID, pkg.coursePackageID))
        assertEquals(1L, f.count("credit_adjustments"))
    }

    @Test fun endDateTodayRemainsUsableInExplicitTimezone() = f.test {
        val pkg = f.coursePackage(endDate = f.today)
        val content = f.content()
        assertTrue(f.ok(f.finish(content).settlement) is SessionCreditOutcome.AdhocChoiceRequired)
        f.ok(f.finisher.debitAdhoc(content.session.sessionID, pkg.coursePackageID))
        assertEquals(1L, f.count("credit_adjustments"))
    }

    @Test fun balanceConsumedAfterChoiceReturnsFailureWithoutSecondDebit() = f.test {
        val pkg = f.coursePackage(total = 1)
        val content = f.content()
        f.finish(content)
        f.ok(f.credits.recordManualCorrection(pkg.coursePackageID, CreditDirection.debit, 1, "虚构调整"))
        f.error(ApplicationErrorCode.invalidState, f.finisher.debitAdhoc(content.session.sessionID, pkg.coursePackageID))
        assertEquals(SessionState.completed, f.ok(f.sessions.find(content.session.sessionID))!!.state)
        assertEquals(1L, f.count("credit_adjustments"))
    }

    @Test fun activePackageReplacementRequiresFreshChoice() = f.test {
        val old = f.coursePackage()
        val content = f.content()
        f.finish(content)
        val result = f.ok(f.credits.createActivePackage(f.studentID, "虚构新包", 3,
            observedActivePackageID = old.coursePackageID, confirmReplaceActivePackage = true))
        assertTrue(result is SaveCoursePackageResult.Saved)
        f.error(ApplicationErrorCode.conflict, f.finisher.debitAdhoc(content.session.sessionID, old.coursePackageID))
        assertEquals(0L, f.count("credit_adjustments"))
    }

    @Test fun emptyClassRequiresConfirmedAbandonAndNeverEntersHistory() = f.test {
        val content = f.content(completed = false)
        assertEquals(SessionFinishGate.abandonEmpty, f.ok(f.finisher.gate(content.session.sessionID)))
        f.error(ApplicationErrorCode.invalidState, f.finisher.finish(content.session.sessionID, content.session.revision))
        f.error(ApplicationErrorCode.invalidState, f.finisher.abandonEmpty(content.session.sessionID, content.session.revision, false))
        assertEquals(SessionState.inProgress, f.ok(f.sessions.find(content.session.sessionID))!!.state)
        val abandoned = f.ok(f.finisher.abandonEmpty(content.session.sessionID, content.session.revision, true))
        assertEquals(SessionState.abandonedEmpty, abandoned.state)
        f.reopen()
        assertTrue(f.ok(f.history.list(HistoryQuery())).isEmpty())
        assertEquals(0L, f.count("active_session_pointers"))
        assertEquals(0L, f.count("credit_adjustments"))
    }

    @Test fun unresolvedSetsRequireExplicitDiscardAndPendingNeverCounts() = f.test {
        val content = f.content(pending = true)
        assertEquals(SessionFinishGate.unresolvedDrafts, f.ok(f.finisher.gate(content.session.sessionID)))
        f.error(ApplicationErrorCode.invalidState, f.finisher.finish(content.session.sessionID, content.session.revision))
        assertEquals(2, f.ok(f.sessions.loadContent(content.session.sessionID))!!.exercises.single().sets.size)
        val result = f.ok(f.finisher.finish(content.session.sessionID, content.session.revision, true))
        assertEquals(SessionState.completed, result.session.state)
        f.reopen()
        val detail = f.ok(f.historyCases.detail(content.session.sessionID))
        assertEquals(1, detail.statistics.completedSetCount)
        assertEquals(0, detail.statistics.ordinaryTrainingVolume!!.decimal.compareTo(java.math.BigDecimal("80")))
        assertEquals(1, detail.content.exercises.single().sets.size)
    }

    @Test fun failedPendingSaveBlocksFinishInsteadOfOverwritingInput() = f.test {
        val content = f.content()
        val active = f.active
        val finisher = f.finisher(active)
        f.failWrites("sessions", "UPDATE")
        f.error(ApplicationErrorCode.persistenceFailed, active.saveDraft(SaveSessionDraftCommand(content.session.sessionID,
            content.session.revision, content.session.draftPayload().copy(privateCoachNote = "虚构待保存备注"))))
        f.clearFailure()
        f.error(ApplicationErrorCode.invalidState, finisher.finish(content.session.sessionID, content.session.revision))
        assertEquals(SessionState.inProgress, f.ok(f.sessions.find(content.session.sessionID))!!.state)
        assertEquals(0L, f.count("credit_adjustments"))
    }

    @Test fun completionWriteFailureLeavesActiveSessionAndNoSettlement() = f.test {
        val content = f.content()
        f.db.openHelper.writableDatabase.execSQL("CREATE TRIGGER t009_failure BEFORE UPDATE ON sessions WHEN NEW.state = 'completed' BEGIN SELECT RAISE(ABORT, 'injected'); END")
        f.error(ApplicationErrorCode.persistenceFailed, f.finisher.finish(content.session.sessionID, content.session.revision))
        assertEquals(SessionState.inProgress, f.ok(f.sessions.find(content.session.sessionID))!!.state)
        assertEquals(1L, f.count("active_session_pointers"))
        assertNull(f.ok(f.history.find(content.session.sessionID)))
        assertEquals(0L, f.count("credit_adjustments"))
        f.clearFailure(); f.reopen()
        val current = f.ok(f.sessions.loadContent(content.session.sessionID))!!
        assertEquals(SessionState.completed, f.finish(current).session.state)
    }

    @Test fun durationReviewBlocksCompletionUntilExplicitCoachAdjustment() = f.test {
        val content = f.content()
        val saved = f.ok(f.active.saveDraft(SaveSessionDraftCommand(content.session.sessionID, content.session.revision,
            content.session.draftPayload().copy(durationNeedsReview = true))))
        f.error(ApplicationErrorCode.invalidState, f.finisher.finish(saved.sessionID, saved.revision))
        val adjusted = saved.toDomain().applyingCoachAdjustedDuration(DecimalValue.parse("60"), f.now).toRecord()
        val updated = f.ok(f.active.saveDraft(SaveSessionDraftCommand(saved.sessionID, saved.revision, adjusted.draftPayload())))
        f.ok(f.finisher.finish(updated.sessionID, updated.revision))
        val detail = f.ok(f.historyCases.detail(saved.sessionID))
        assertEquals(0, detail.statistics.displayedDurationSeconds.decimal.compareTo(java.math.BigDecimal("60")))
    }

    @Test fun inProgressCannotSettleAndStaleFinishCannotOverwriteCurrentContent() = f.test {
        val content = f.content()
        f.error(ApplicationErrorCode.invalidState, f.finisher.settlement(content.session.sessionID))
        val saved = f.ok(f.active.saveDraft(SaveSessionDraftCommand(content.session.sessionID, content.session.revision,
            content.session.draftPayload().copy(studentFacingSummary = "虚构输入"))))
        f.error(ApplicationErrorCode.staleRevision, f.finisher.finish(content.session.sessionID, content.session.revision))
        assertEquals(saved.revision, f.ok(f.sessions.find(saved.sessionID))!!.revision)
        assertEquals(0L, f.count("credit_adjustments"))
    }

    @Test fun settlementReadFailureCannotMasqueradeAsNoPackageOrDebitSuccess() = f.test {
        val content = f.content()
        val repository = object : CoursePackageRepositoryPort by f.packages {
            override suspend fun active(studentID: StudentID, asOf: LocalDate): ApplicationResult<CoursePackageRecord?> =
                ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed))
        }
        val credits = CreditUseCases(repository, f.clock, f.ids, f.zone)
        val finisher = FinishSessionUseCases(f.sessions, f.active, credits, f.history, f.clock, f.zone)
        val finished = f.ok(finisher.finish(content.session.sessionID, content.session.revision))
        assertEquals(SessionState.completed, finished.session.state)
        f.error(ApplicationErrorCode.persistenceFailed, finished.settlement)
        assertNull(f.ok(f.history.find(content.session.sessionID)))
        assertEquals(SessionCreditOutcome.NoActivePackage, f.ok(f.finisher.settlement(content.session.sessionID)))
    }

    @Test fun sessionCompleteRefundIsDurableAndOnlyOnceEvenOnRepeatedCalls() = f.test {
        val pkg = f.coursePackage()
        val content = f.content()
        f.finish(content)
        f.ok(f.credits.debitOnSessionComplete(pkg.coursePackageID, content.session.sessionID))
        val first = f.ok(f.credits.refundOnSessionReopen(content.session.sessionID))!!
        assertEquals(CreditDirection.credit, first.direction)
        assertEquals(1L, first.amount)
        val ledger = f.ok(f.credits.ledger(f.studentID))
        repeat(2) { assertEquals(first, f.ok(f.credits.refundOnSessionReopen(content.session.sessionID))) }
        assertEquals(ledger, f.ok(f.credits.ledger(f.studentID)))
        f.reopen()
        assertEquals(first, f.ok(f.credits.refundOnSessionReopen(content.session.sessionID)))
        assertEquals(ledger, f.ok(f.credits.ledger(f.studentID)))
        assertEquals(2L, f.count("credit_adjustments"))
        assertEquals(2L, f.ok(f.credits.balance(f.studentID, pkg.coursePackageID)))
    }

    @Test fun noPriorDebitNeverRefunds() = f.test {
        f.coursePackage()
        val content = f.content()
        f.finish(content)
        repeat(2) { assertNull(f.ok(f.credits.refundOnSessionReopen(content.session.sessionID))) }
        f.reopen()
        assertNull(f.ok(f.credits.refundOnSessionReopen(content.session.sessionID)))
        assertEquals(0L, f.count("credit_adjustments"))
    }

    // S1-D12 负责人 2026-11-08 裁决 A；与 iOS CreditLedgerUseCases.swift:101 一致
    @Test fun priorAdhocDebitCurrentlyDoesNotRefundOrChangeLedger() = f.test {
        val pkg = f.coursePackage()
        val content = f.content()
        f.finish(content)
        val debit = f.ok(f.finisher.debitAdhoc(content.session.sessionID, pkg.coursePackageID)) as SessionCreditOutcome.Debited
        val ledger = f.ok(f.credits.ledger(f.studentID))
        assertEquals(listOf(debit.adjustment), ledger)
        repeat(2) { assertNull(f.ok(f.credits.refundOnSessionReopen(content.session.sessionID))) }
        assertEquals(ledger, f.ok(f.credits.ledger(f.studentID)))
        f.reopen()
        assertNull(f.ok(f.credits.refundOnSessionReopen(content.session.sessionID)))
        assertEquals(ledger, f.ok(f.credits.ledger(f.studentID)))
        assertEquals(1L, f.count("credit_adjustments"))
        assertEquals(1L, f.ok(f.credits.balance(f.studentID, pkg.coursePackageID)))
    }
}

internal class T009Fixture {
    val zone: ZoneId = ZoneId.of("America/Los_Angeles")
    var now: Instant = Instant.parse("2026-11-08T10:00:00Z")
    val clock = AppClock { now }
    val today: LocalDate get() = clock.today(zone)
    val ids: StableIDGenerator = T009IDs()
    val studentID = StudentID.parse("abcdef09-0000-4000-8000-000000000001")
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val worker = Executors.newSingleThreadExecutor()
    var db: FineCoachDatabase
        private set
    init {
        context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        db = FineCoachDatabaseFactory.create(context)
        test { db.s1Dao().insert(StudentEntity(UUID.fromString(studentID.value), "虚构学员", StudentSex.undisclosed,
            null, null, null, null, null, StudentLifecycle.active, now, now)) }
    }
    private val generation get() = UUID.fromString(db.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)!!.value)
    val sessions get() = SessionRepository(db, clock, ids, generation, ExerciseRepository(db, ExerciseCatalogLoader(context.assets), clock))
    val active get() = ActiveSessionUseCases(sessions, clock, ids)
    val packages get() = CoursePackageRepository(db, clock, ids, zone)
    val credits get() = CreditUseCases(packages, clock, ids, zone)
    val history get() = HistoryRepository(db, clock, generation, zone)
    val historyCases get() = HistoryUseCases(history, sessions, history, clock)
    val finisher get() = finisher(active)
    fun finisher(active: ActiveSessionUseCases) = FinishSessionUseCases(sessions, active, credits, history, clock, zone)
    fun test(action: suspend () -> Unit) { worker.submit(Callable { runBlocking { action() } }).get(60, TimeUnit.SECONDS) }
    fun <T> ok(result: ApplicationResult<T>): T {
        assertTrue("Expected ApplicationResult.Success", result is ApplicationResult.Success)
        return (result as ApplicationResult.Success).value
    }
    fun error(code: ApplicationErrorCode, result: ApplicationResult<*>) {
        assertTrue("Expected ApplicationResult.Failure", result is ApplicationResult.Failure)
        assertEquals(code, (result as ApplicationResult.Failure).error.code)
    }
    suspend fun coursePackage(total: Long = 2, endDate: LocalDate? = null): CoursePackageRecord =
        (ok(credits.createActivePackage(studentID, "虚构课包", total, endDate = endDate)) as SaveCoursePackageResult.Saved).record
    suspend fun content(completed: Boolean = true, pending: Boolean = false, sourceID: StableExerciseID? = null): SessionContentRecord {
        val session = ok(sessions.startOrOpen(StartOrOpenSessionCommand(studentID, nowUTC = now)))
        val exerciseID = ids.newSessionExerciseID()
        val draft = TrainingSet.makeDraft(ids.newTrainingSetID(), exerciseID, 0u,
            TrainingSetInput(RecordMode.weightReps, weightValue = "10", repetitionCount = "8", unit = MeasurementUnit.kilograms), now)
        val set = if (completed) draft.confirmed(now) else draft
        val sets = listOf(set) + if (pending) listOf(set.copiedAsPending(ids.newTrainingSetID(), 1u, now)) else emptyList()
        val exercise = SessionExercise(exerciseID, session.sessionID, 0u,
            if (sourceID == null) ExerciseSourceKind.sessionOnly else ExerciseSourceKind.builtIn,
            sourceID, NormalizedName.parse("虚构快照动作"), RecordMode.weightReps,
            ValidatedText.optional("虚构动作私密备注"), null, sets).toRecord()
        return ok(sessions.saveContent(SaveSessionContentCommand(session.sessionID, session.revision, emptyList(), listOf(exercise))))
    }
    suspend fun finish(content: SessionContentRecord) = ok(finisher.finish(content.session.sessionID, content.session.revision))
    fun count(table: String): Long = db.openHelper.writableDatabase.query("SELECT COUNT(*) FROM `$table`").use {
        check(it.moveToFirst()); it.getLong(0)
    }
    fun failWrites(table: String, operation: String) {
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER t009_failure BEFORE $operation ON `$table` BEGIN SELECT RAISE(ABORT, 'injected'); END")
    }
    fun clearFailure() { db.openHelper.writableDatabase.execSQL("DROP TRIGGER t009_failure") }
    fun reopen() { db.close(); db = FineCoachDatabaseFactory.create(context) }
    fun close() {
        try { worker.submit { db.close() }.get(30, TimeUnit.SECONDS) } finally {
            worker.shutdownNow(); context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        }
    }
}

private class T009IDs : StableIDGenerator {
    override fun newStudentID() = StudentID.fromUUID(UUID.randomUUID())
    override fun newCoursePackageID() = CoursePackageID.fromUUID(UUID.randomUUID())
    override fun newCreditAdjustmentID() = CreditAdjustmentID.fromUUID(UUID.randomUUID())
    override fun newSessionID() = SessionID.fromUUID(UUID.randomUUID())
    override fun newTemplateID() = TemplateID.fromUUID(UUID.randomUUID())
    override fun newSectionID() = SectionID.fromUUID(UUID.randomUUID())
    override fun newSessionExerciseID() = SessionExerciseID.fromUUID(UUID.randomUUID())
    override fun newTemplateExerciseID() = TemplateExerciseID.fromUUID(UUID.randomUUID())
    override fun newTrainingSetID() = TrainingSetID.fromUUID(UUID.randomUUID())
    override fun newExerciseID() = StableExerciseID.parse(UUID.randomUUID().toString())
}
