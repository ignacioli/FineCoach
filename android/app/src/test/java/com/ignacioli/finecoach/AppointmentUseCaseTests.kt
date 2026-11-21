// fictional-data: deterministic invented students, appointments, packages and sessions.
package com.ignacioli.finecoach

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.storage.*
import com.ignacioli.finecoach.storage.repository.*
import java.math.BigDecimal
import java.time.*
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

internal class S2Environment(val context: Context) {
    val now = Instant.parse("2026-03-08T10:00:00Z")
    val zone = ZoneId.of("America/Los_Angeles")
    val db = FineCoachDatabaseFactory.create(context)
    val ids = VectorIDs((1..200).map { UUID(0, it.toLong()).toString() })
    val clock = MutableAppClock(now)
    val graph = S1AppGraph(db, clock, ids, UUID.fromString(db.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)!!.value), context, zone)
    val repository = AppointmentRepository(db, clock, ids, graph.generation, graph.sessions, zone)
    val cases = AppointmentUseCases(repository)
    suspend fun student() = graph.students.create(StudentDraft("虚构排课", StudentSex.female)).requireSuccess().studentID
    fun row(student: StudentID, date: String = "2026-03-09", time: String = "09:00") = Appointment(UUID.randomUUID(), student,
        date = LocalDate.parse(date), startTime = LocalTime.parse(time), trainingFocus = setOf(BodyPart.back), createdAtUTC = now, updatedAtUTC = now)
    suspend fun series(student: StudentID, count: Int = 4): List<Appointment> = cases.createRecurring(RecurrenceSeries(UUID.randomUUID(), student,
        RecurrenceInterval.everyOtherDay, RecurrenceTermination.RepeatCount(count), LocalTime.of(9, 0), createdAtUTC = now, updatedAtUTC = now),
        LocalDate.parse("2026-03-07")).requireSuccess()
}
internal fun s2Run(action: suspend S2Environment.() -> Unit) {
    val worker = Executors.newSingleThreadExecutor()
    try { worker.submit(Callable { runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        val env = S2Environment(context)
        try { env.action() } finally { env.db.close(); context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME) }
    } }).get() } finally { worker.shutdownNow() }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class AppointmentUseCaseTests {
    @Test fun conflictsRequireOverrideAndExposeTimeAndName() = s2Run {
        val a = row(student()); cases.createSingle(a).requireSuccess()
        val b = row(student())
        val conflict = cases.conflicts(b).requireSuccess().single()
        assertEquals(a.id, conflict.appointmentID); assertEquals(a.startInstant(zone), conflict.start)
        assertEquals("虚构排课", conflict.displayName)
        assertTrue(cases.createSingle(b) is ApplicationResult.Failure)
        assertEquals(1, cases.all().requireSuccess().size)
        cases.createSingle(b, true).requireSuccess()
        cases.cancel(a.id).requireSuccess()
        cases.cancel(b.id).requireSuccess()
        assertTrue(cases.conflicts(b).requireSuccess().isEmpty())
    }
    @Test fun seriesAndOnlyThisSurviveReopen() = s2Run {
        val rows = series(student()); val target = rows[1]
        val edited = cases.editSingle(target.id, AppointmentEdit(startTime = LocalTime.of(11, 30), reminderEnabled = false)).requireSuccess()
        assertTrue(edited.isDetachedException); assertEquals(target.seriesID, edited.seriesID)
        val other = FineCoachDatabaseFactory.create(context)
        try {
            assertEquals(edited, other.appointmentDao().find(target.id.toString())!!.toDomain())
            assertEquals(RecurrenceTermination.RepeatCount(4), other.appointmentDao().series(target.seriesID.toString())!!.toDomain().termination)
            assertEquals(rows[0], other.appointmentDao().find(rows[0].id.toString())!!.toDomain())
        } finally { other.close() }
    }
    @Test fun focusOnlyEditRemainsInSeriesAndFollowsFutureTimeAndReminderChanges() = s2Run {
        val rows = series(student())
        val edited = cases.updateTrainingFocus(rows[2].id, setOf(BodyPart.thighs)).requireSuccess()
        assertFalse(edited.isDetachedException)
        assertEquals(rows[2].seriesID, edited.seriesID)
        val changed = cases.editFuture(rows[0].seriesID!!, rows[1].date,
            FutureAppointmentEdit(startTime = LocalTime.of(11, 30), reminderLeadMinutes = ReminderLeadMinutes.thirty)).requireSuccess()
        val replacement = changed.single { it.date == edited.date }
        assertEquals(setOf(BodyPart.thighs), replacement.trainingFocus)
        assertEquals(LocalTime.of(11, 30), replacement.startTime)
        assertEquals(ReminderLeadMinutes.thirty, replacement.reminderLeadMinutes)
        assertFalse(replacement.isDetachedException)
        assertNull(cases.find(edited.id).requireSuccess())
    }
    @Test fun thisAndFutureKeepsPastDetachedResolvedAndPerDateFocus() = s2Run {
        val result = s2FutureScenario()
        assertEquals(true, result["pastUnchanged"]); assertEquals(true, result["detachedUnchanged"])
        assertEquals(true, result["resolvedUnchanged"]); assertEquals(true, result["oldEnded"])
        assertEquals(listOf("11:30", "11:30"), result["times"])
        assertEquals(listOf(listOf("thighs"), listOf("back")), result["focus"])
    }
    @Test fun unlinkedAdhocSessionIsAssociatedAndAbandonRestoresAtomically() = s2Run {
        val s = student(); val other = graph.active.startOrOpen(student()).requireSuccess()
        val existing = graph.active.startOrOpen(s).requireSuccess()
        val a = row(s); cases.createSingle(a).requireSuccess()
        val session = cases.startTraining(a.id).requireStarted()
        assertEquals(existing.sessionID, session.sessionID)
        assertNotEquals(other.sessionID, session.sessionID)
        assertEquals(a.id.toString(), graph.sessions.linkedAppointmentID(session.sessionID).requireSuccess())
        graph.finisher.abandonEmpty(session.sessionID, session.revision, true).requireSuccess()
        val restored = cases.find(a.id).requireSuccess()!!
        assertEquals(AppointmentStatus.scheduled, restored.status); assertNull(restored.linkedSessionID)
        assertNull(graph.sessions.linkedAppointmentID(session.sessionID).requireSuccess())
        assertEquals(SessionState.abandonedEmpty, graph.sessions.find(session.sessionID).requireSuccess()!!.state)
    }
    @Test fun newSessionPrefillsFocusAndSecondAppointmentRequiresPreviousTrainingWithoutWrites() = s2Run {
        val s = student(); graph.credits.createActivePackage(s, null, 5).requireSuccess(); val a = row(s); cases.createSingle(a).requireSuccess()
        val started = cases.startTraining(a.id).requireStarted()
        assertEquals(a.trainingFocus, started.trainingFocus)
        val b = row(s, time = "11:00"); cases.createSingle(b).requireSuccess()
        // Even a missing pointer must not be repaired on this read-only outcome.
        db.t008SessionDao().deletePointer(s.value)
        val before = persistedRows(db)
        val outcome = cases.startTraining(b.id).requireSuccess()
        assertEquals(AppointmentTrainingStartResult.PreviousTrainingNeedsHandling(a.id, started.sessionID), outcome)
        assertTrue("S2-D06 must leave all table rows unchanged", before == persistedRows(db))
        assertEquals(AppointmentStatus.scheduled, cases.find(b.id).requireSuccess()!!.status)
        assertNull(cases.find(b.id).requireSuccess()!!.linkedSessionID)
        assertEquals(AppointmentStatus.inProgress, cases.find(a.id).requireSuccess()!!.status)
        assertEquals(a.id.toString(), graph.sessions.linkedAppointmentID(started.sessionID).requireSuccess())
        assertTrue(graph.credits.ledger(s).requireSuccess().isEmpty())
        assertEquals(1, graph.sessions.listActiveSessions().requireSuccess().size)
    }
    @Test fun secondAppointmentStartsAfterCoachAbandonsPreviousEmptyTraining() = s2Run {
        val s = student(); graph.credits.createActivePackage(s, null, 5).requireSuccess()
        val a = row(s); val b = row(s, time = "11:00")
        cases.createSingle(a).requireSuccess(); cases.createSingle(b).requireSuccess()
        val previous = cases.startTraining(a.id).requireStarted()
        assertEquals(AppointmentTrainingStartResult.PreviousTrainingNeedsHandling(a.id, previous.sessionID), cases.startTraining(b.id).requireSuccess())
        graph.finisher.abandonEmpty(previous.sessionID, previous.revision, true).requireSuccess()
        val next = cases.startTraining(b.id).requireStarted()
        assertNotEquals(previous.sessionID, next.sessionID)
        assertEquals(SessionState.abandonedEmpty, graph.sessions.find(previous.sessionID).requireSuccess()!!.state)
        val restored = cases.find(a.id).requireSuccess()!!
        assertEquals(AppointmentStatus.scheduled, restored.status); assertNull(restored.linkedSessionID)
        assertEquals(AppointmentStatus.inProgress, cases.find(b.id).requireSuccess()!!.status)
        assertEquals(UUID.fromString(next.sessionID.value), cases.find(b.id).requireSuccess()!!.linkedSessionID)
        assertEquals(b.id.toString(), graph.sessions.linkedAppointmentID(next.sessionID).requireSuccess())
        assertTrue(graph.credits.ledger(s).requireSuccess().isEmpty())
    }
    @Test fun deletingScheduledStudentClearsAppointmentsAndSeriesButRetainsBillingHistory() = s2Run {
        val s = student(); val pkg = graph.credits.createActivePackage(s, null, 5).requireSuccess().requireSaved()
        val rows = series(s)
        val other = row(student(), time = "16:00"); cases.createSingle(other).requireSuccess()
        val started = cases.startTraining(rows[0].id).requireStarted()
        val eid = ids.newSessionExerciseID()
        val set = TrainingSet.makeDraft(ids.newTrainingSetID(), eid, 0u, TrainingSetInput(RecordMode.weightReps,
            weightValue = "10", repetitionCount = "10", unit = MeasurementUnit.kilograms), now).confirmed(now)
        val exercise = SessionExerciseRecord(eid, started.sessionID, 0u, ExerciseSourceKind.sessionOnly, null,
            "虚构动作", RecordMode.weightReps, null, null, listOf(set.toRecord()))
        val content = graph.active.saveContent(SaveSessionContentCommand(started.sessionID, started.revision, emptyList(), listOf(exercise))).requireSuccess()
        graph.finisher.finish(started.sessionID, content.session.revision).requireSuccess().settlement.requireSuccess()
        cases.markAbsent(rows[1].id, AbsentCreditChoice.charged, true).requireSuccess().settlement.requireSuccess()
        val ledger = graph.credits.ledger(s).requireSuccess()
        assertEquals(2, ledger.size)
        val packageBefore = db.s1Dao().findCoursePackage(UUID.fromString(pkg.coursePackageID.value))
        val claimBefore = db.s1Dao().findActivePackageClaim(UUID.fromString(s.value))
        graph.students.delete(s, "虚构排课").requireSuccess()
        assertNull(graph.students.find(s).requireSuccess())
        assertTrue(cases.all().requireSuccess().none { it.studentID == s })
        assertNull(cases.series(rows[0].seriesID!!).requireSuccess())
        assertNull(graph.sessions.find(started.sessionID).requireSuccess())
        assertEquals(other, cases.find(other.id).requireSuccess())
        assertEquals(packageBefore, db.s1Dao().findCoursePackage(UUID.fromString(pkg.coursePackageID.value)))
        assertEquals(claimBefore, db.s1Dao().findActivePackageClaim(UUID.fromString(s.value)))
        for (entry in ledger) {
            val retained = db.s1Dao().findCreditAdjustment(UUID.fromString(entry.creditAdjustmentID.value))!!
            assertEquals(entry.amount, retained.amount)
            assertEquals(entry.linkedAppointmentID, retained.linkedAppointmentID?.toString())
            assertEquals(entry.sourceEventKey.value, retained.sourceEventKey)
        }
        assertNull(db.storeMetadataDao().find("s2.deletingStudent"))
    }
    @Test fun futureDeletionStillRejectsSessionAndLedgerReferences() = s2Run {
        val s = student(); graph.credits.createActivePackage(s, null, 5).requireSuccess()
        val sessionRef = row(s); val ledgerRef = row(s, time = "12:00")
        cases.createSingle(sessionRef).requireSuccess(); cases.createSingle(ledgerRef).requireSuccess()
        val session = graph.active.startOrOpen(s).requireSuccess()
        assertEquals(1, db.appointmentDao().linkSession(session.sessionID.value, sessionRef.id.toString()))
        graph.credits.debitOnAppointmentAbsent(graph.credits.activePackage(s, clock.today(zone)).requireSuccess()!!.coursePackageID,
            ledgerRef.id.toString()).requireSuccess()
        val before = persistedRows(db)
        assertTrue(cases.deleteFuture(sessionRef.id, true) is ApplicationResult.Failure)
        assertTrue(cases.deleteFuture(ledgerRef.id, true) is ApplicationResult.Failure)
        assertTrue(before == persistedRows(db))
    }
    @Test fun absenceConfirmedIdempotentAndCancellationNoDebit() = s2Run {
        val actual = s2AbsentScenario()
        assertEquals(mapOf("balance" to 4L, "ledgerCount" to 1L, "sameID" to true), actual)
    }
    @Test fun absenceWithoutPackagePersistsAndDeletionRequiresConfirmationAndFuture() = s2Run {
        val a = row(student()); cases.createSingle(a).requireSuccess()
        val absence = cases.markAbsent(a.id, AbsentCreditChoice.charged, true).requireSuccess()
        assertNull(absence.settlement.requireSuccess())
        assertEquals(AppointmentStatus.absent, cases.find(a.id).requireSuccess()!!.status)
        assertTrue(cases.deleteFuture(a.id, true) is ApplicationResult.Failure)
        val future = row(student(), time = "16:00"); cases.createSingle(future).requireSuccess()
        assertTrue(cases.deleteFuture(future.id, false) is ApplicationResult.Failure)
        cases.deleteFuture(future.id, true).requireSuccess(); assertNull(cases.find(future.id).requireSuccess())
        val past = row(student(), "2026-03-07"); cases.createSingle(past).requireSuccess()
        assertTrue(cases.deleteFuture(past.id, true) is ApplicationResult.Failure)
        cases.cancel(past.id).requireSuccess()
        assertTrue(cases.deleteFuture(past.id, true) is ApplicationResult.Failure)
    }
    @Test fun absenceDebitFailureIsExplicitAndStatusRemainsDurable() = s2Run {
        val s = student(); val pkg = graph.credits.createActivePackage(s, null, 1).requireSuccess().requireSaved()
        graph.credits.debitOnSessionComplete(pkg.coursePackageID, ids.newSessionID()).requireSuccess()
        val a = row(s); cases.createSingle(a).requireSuccess()
        val result = cases.markAbsent(a.id, AbsentCreditChoice.charged, true).requireSuccess()
        assertTrue(result.settlement is ApplicationResult.Failure)
        assertEquals(AppointmentStatus.absent, cases.find(a.id).requireSuccess()!!.status)
        assertEquals(1, graph.credits.ledger(s).requireSuccess().size)
    }
    @Test fun linkedCompletionDebitsOnceWithoutAdhocChoiceAndAllowsNextAppointment() = s2Run {
        val s = student(); val pkg = graph.credits.createActivePackage(s, null, 5).requireSuccess().requireSaved()
        val a = row(s); cases.createSingle(a).requireSuccess()
        val b = row(s, time = "11:00"); cases.createSingle(b).requireSuccess()
        val session = cases.startTraining(a.id).requireStarted()
        assertEquals(AppointmentTrainingStartResult.PreviousTrainingNeedsHandling(a.id, session.sessionID), cases.startTraining(b.id).requireSuccess())
        val eid = ids.newSessionExerciseID()
        val set = TrainingSet.makeDraft(ids.newTrainingSetID(), eid, 0u, TrainingSetInput(RecordMode.weightReps, weightValue = "10",
            repetitionCount = "10", unit = MeasurementUnit.kilograms), now).confirmed(now)
        val exercise = SessionExerciseRecord(eid, session.sessionID, 0u, ExerciseSourceKind.sessionOnly, null, "虚构动作", RecordMode.weightReps, null, null, listOf(set.toRecord()))
        val content = graph.active.saveContent(SaveSessionContentCommand(session.sessionID, session.revision, emptyList(), listOf(exercise))).requireSuccess()
        val result = graph.finisher.finish(session.sessionID, content.session.revision).requireSuccess()
        assertTrue(result.settlement.requireSuccess() is SessionCreditOutcome.Debited)
        assertTrue(graph.finisher.settlement(session.sessionID).requireSuccess() is SessionCreditOutcome.Debited)
        assertEquals(AppointmentStatus.completed, cases.find(a.id).requireSuccess()!!.status)
        assertEquals(1, graph.credits.ledger(s).requireSuccess().size)
        assertEquals(4L, graph.credits.activePackage(s, clock.today(zone)).requireSuccess()!!.remainingCreditsCache)
        assertTrue(graph.finisher.skipDebit(session.sessionID) is ApplicationResult.Failure)
        assertEquals(pkg.coursePackageID, graph.credits.ledger(s).requireSuccess().single().coursePackageID)
        val ledgerBeforeNext = graph.credits.ledger(s).requireSuccess()
        val next = cases.startTraining(b.id).requireStarted()
        assertNotEquals(session.sessionID, next.sessionID)
        assertEquals(AppointmentStatus.completed, cases.find(a.id).requireSuccess()!!.status)
        assertEquals(AppointmentStatus.inProgress, cases.find(b.id).requireSuccess()!!.status)
        assertEquals(UUID.fromString(next.sessionID.value), cases.find(b.id).requireSuccess()!!.linkedSessionID)
        assertEquals(b.id.toString(), graph.sessions.linkedAppointmentID(next.sessionID).requireSuccess())
        assertEquals(ledgerBeforeNext, graph.credits.ledger(s).requireSuccess())
    }
}

internal suspend fun S2Environment.s2FutureScenario(): Map<String, Any> {
    val initial = series(student(), 5); val seriesID = initial[0].seriesID!!
    val detached = cases.editSingle(initial[3].id, AppointmentEdit(startTime = LocalTime.NOON)).requireSuccess()
    val resolved = cases.cancel(initial[4].id).requireSuccess()
    cases.updateTrainingFocus(initial[2].id, setOf(BodyPart.back)).requireSuccess()
    val updated = cases.editFuture(seriesID, initial[1].date, FutureAppointmentEdit(startTime = LocalTime.of(11, 30), boundaryTrainingFocus = setOf(BodyPart.thighs)), true).requireSuccess()
    val firstTwo = updated.take(2)
    val allRows = cases.all().requireSuccess()
    val skippedDates = setOf(detached.date, resolved.date)
    return mapOf("pastUnchanged" to (cases.find(initial[0].id).requireSuccess() == initial[0]),
        "detachedUnchanged" to (cases.find(detached.id).requireSuccess() == detached),
        "resolvedUnchanged" to (cases.find(resolved.id).requireSuccess() == resolved),
        "oldEnded" to (cases.series(seriesID).requireSuccess()!!.status == RecurrenceSeriesStatus.ended),
        "totalAppointmentCount" to allRows.size.toLong(),
        "replacementAppointmentCount" to allRows.count { it.seriesID == updated.first().seriesID }.toLong(),
        "scheduledOnSkippedDates" to allRows.count { it.date in skippedDates && it.status == AppointmentStatus.scheduled && !it.isDetachedException }.toLong(),
        "times" to firstTwo.map { it.startTime.toString() }, "focus" to firstTwo.map { it.trainingFocus.map { it.name }.sorted() })
}
internal suspend fun S2Environment.s2AbsentScenario(): Map<String, Any> {
    val s = student(); graph.credits.createActivePackage(s, null, 5).requireSuccess()
    val a = row(s); cases.createSingle(a).requireSuccess()
    check(cases.markAbsent(a.id, AbsentCreditChoice.charged, false) is ApplicationResult.Failure)
    cases.markAbsent(a.id, AbsentCreditChoice.charged, true).requireSuccess()
    val first = graph.credits.ledger(s).requireSuccess().single()
    cases.markAbsent(a.id, AbsentCreditChoice.charged, true).requireSuccess()
    val last = graph.credits.ledger(s).requireSuccess()
    val cancelled = row(s, time = "12:00"); cases.createSingle(cancelled).requireSuccess(); cases.cancel(cancelled.id).requireSuccess()
    val notCharged = row(s, time = "14:00"); cases.createSingle(notCharged).requireSuccess()
    cases.markAbsent(notCharged.id, AbsentCreditChoice.notCharged, true).requireSuccess()
    return mapOf("balance" to graph.credits.activePackage(s, clock.today(zone)).requireSuccess()!!.remainingCreditsCache,
        "ledgerCount" to last.size.toLong(), "sameID" to (first.creditAdjustmentID == last.single().creditAdjustmentID))
}

internal fun ApplicationResult<AppointmentTrainingStartResult>.requireStarted(): SessionRecord =
    when (val outcome = requireSuccess()) {
        is AppointmentTrainingStartResult.Started -> outcome.session
        is AppointmentTrainingStartResult.PreviousTrainingNeedsHandling -> error("Expected started training")
    }

private fun persistedRows(db: FineCoachDatabase): Map<String, List<List<String?>>> {
    val sql = db.openHelper.readableDatabase
    val tables = mutableListOf<String>()
    sql.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name").use { cursor ->
        while (cursor.moveToNext()) tables += cursor.getString(0)
    }
    return tables.associateWith { table ->
        val rows = mutableListOf<List<String?>>()
        sql.query("SELECT * FROM \u0060$table\u0060").use { cursor ->
            while (cursor.moveToNext()) rows += (0 until cursor.columnCount).map { if (cursor.isNull(it)) null else cursor.getString(it) }
        }
        rows
    }
}
