// fictional-data: invented recurrence dates and a fixed clock; no real people.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.application.ApplicationErrorCode
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.storage.FineCoachDatabase
import java.time.LocalDate
import java.time.LocalTime
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class AppointmentFutureEditTests {
    @Test fun repeatCountFromTheFifthKeepsTenDatesAndStoresSix() = s2Run {
        val initial = series(student(), 10)
        val dates = initial.map { it.date }
        val updated = cases.editFuture(initial[0].seriesID!!, initial[4].date,
            FutureAppointmentEdit(startTime = LocalTime.of(11, 30))).requireSuccess()
        val rows = cases.all().requireSuccess()
        assertEquals(dates, rows.map { it.date }.sorted())
        assertEquals(10, rows.size)
        assertEquals(dates.drop(4), updated.map { it.date })
        assertEquals(RecurrenceTermination.RepeatCount(6), cases.series(updated[0].seriesID!!).requireSuccess()!!.termination)
        assertEquals(RecurrenceSeriesStatus.ended, cases.series(initial[0].seriesID!!).requireSuccess()!!.status)
        assertEquals(initial.take(4), rows.filter { it.date < initial[4].date }.sortedBy { it.date })
    }

    @Test fun cancelledAbsentAndDetachedDatesStaySingleUnchangedRows() = s2Run {
        val initial = series(student(), 10)
        val cancelled = cases.cancel(initial[5].id).requireSuccess()
        cases.markAbsent(initial[6].id, AbsentCreditChoice.notCharged, true).requireSuccess()
        val absent = cases.find(initial[6].id).requireSuccess()!!
        val detached = cases.editSingle(initial[7].id, AppointmentEdit(startTime = LocalTime.of(15, 0))).requireSuccess()
        val kept = listOf(cancelled, absent, detached)
        cases.editFuture(initial[0].seriesID!!, initial[4].date, FutureAppointmentEdit(startTime = LocalTime.of(11, 30))).requireSuccess()
        val rows = cases.all().requireSuccess()
        for (row in kept) {
            assertEquals(row, cases.find(row.id).requireSuccess())
            assertEquals(listOf(row.id), rows.filter { it.date == row.date }.map { it.id })
        }
        assertTrue(rows.none { it.date == cancelled.date && it.status == AppointmentStatus.scheduled })
        assertTrue(rows.none { it.date == absent.date && it.status == AppointmentStatus.scheduled })
    }

    @Test fun deleteFutureDateDoesNotReturn() = s2Run {
        val initial = series(student(), 10)
        val removed = initial[6].date
        cases.deleteFuture(initial[6].id, true).requireSuccess()
        cases.editFuture(initial[0].seriesID!!, initial[4].date, FutureAppointmentEdit(startTime = LocalTime.of(11, 30))).requireSuccess()
        val rows = cases.all().requireSuccess()
        assertTrue(rows.none { it.date == removed })
        assertEquals(initial.map { it.date }.filter { it != removed }, rows.map { it.date }.sorted())
    }

    @Test fun endDateSeriesKeepsSupersededDatesAndTermination() = s2Run {
        val end = LocalDate.parse("2026-03-25")
        val initial = cases.createRecurring(RecurrenceSeries(UUID.randomUUID(), student(), RecurrenceInterval.everyOtherDay,
            RecurrenceTermination.EndDate(end), LocalTime.of(9, 0), createdAtUTC = now, updatedAtUTC = now),
            LocalDate.parse("2026-03-07")).requireSuccess()
        val superseded = initial.filter { it.date >= initial[2].date }.map { it.date }
        val updated = cases.editFuture(initial[0].seriesID!!, initial[2].date,
            FutureAppointmentEdit(durationMinutes = 45)).requireSuccess()
        assertEquals(superseded, updated.map { it.date })
        assertEquals(RecurrenceTermination.EndDate(end), cases.series(updated[0].seriesID!!).requireSuccess()!!.termination)
        assertEquals(initial.map { it.date }, cases.all().requireSuccess().map { it.date }.sorted())
    }

    @Test fun secondFutureEditDoesNotGrowOrDuplicateDates() = s2Run {
        val initial = series(student(), 10)
        val dates = initial.map { it.date }
        cases.editFuture(initial[0].seriesID!!, initial[4].date, FutureAppointmentEdit(startTime = LocalTime.of(11, 0))).requireSuccess()
        val eighth = cases.all().requireSuccess().single { it.date == initial[7].date }
        val second = cases.editFuture(eighth.seriesID!!, eighth.date, FutureAppointmentEdit(startTime = LocalTime.of(12, 0))).requireSuccess()
        val rows = cases.all().requireSuccess()
        assertEquals(dates, rows.map { it.date }.sorted())
        assertEquals(dates.toSet().size, rows.map { it.date }.toSet().size)
        assertEquals(dates.takeLast(3), second.map { it.date })
        assertTrue(second.all { it.startTime == LocalTime.of(12, 0) })
        assertTrue(rows.filter { it.date < initial[4].date }.all { it.startTime == LocalTime.of(9, 0) })
    }

    @Test fun conflictWritesNothingAndOverrideSucceeds() = s2Run {
        val initial = series(student(), 10)
        val boundary = initial[4]
        val blocker = row(boundary.studentID, boundary.date.toString(), "10:00")
        cases.createSingle(blocker).requireSuccess()
        val before = scheduleRows(db)
        assertEquals(ApplicationErrorCode.conflict, cases.editFuture(boundary.seriesID!!, boundary.date,
            FutureAppointmentEdit(startTime = LocalTime.of(10, 0))).requireFailure().code)
        assertEquals(before, scheduleRows(db))
        val updated = cases.editFuture(boundary.seriesID!!, boundary.date,
            FutureAppointmentEdit(startTime = LocalTime.of(10, 0)), true).requireSuccess()
        assertEquals(initial.drop(4).map { it.date }, updated.map { it.date })
        assertTrue(updated.all { it.startTime == LocalTime.of(10, 0) })
        assertEquals(blocker, cases.find(blocker.id).requireSuccess())
        val seriesDates = cases.all().requireSuccess().filter { it.seriesID != null }.map { it.date }.sorted()
        assertEquals(initial.map { it.date }, seriesDates)
    }
}

private fun scheduleRows(db: FineCoachDatabase): List<String> {
    val sql = db.openHelper.readableDatabase
    val lines = mutableListOf<String>()
    for (table in listOf("appointments", "recurrence_series")) {
        sql.query("SELECT * FROM $table ORDER BY 1").use { cursor ->
            while (cursor.moveToNext()) {
                lines += (0 until cursor.columnCount).joinToString("|") { if (cursor.isNull(it)) "" else cursor.getString(it) }
            }
        }
    }
    return lines
}
