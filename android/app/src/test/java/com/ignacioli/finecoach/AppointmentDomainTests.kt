// fictional-data: invented appointments and fixed DST calendar dates only.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.common.StudentID
import java.time.*
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class AppointmentDomainTests {
    private val now = Instant.parse("2026-03-08T10:00:00Z")
    private val zone = ZoneId.of("America/Los_Angeles")
    private fun row(time: String = "01:00") = Appointment(UUID(0, 1), StudentID.fromUUID(UUID(0, 2)), date = LocalDate.parse("2026-03-08"), startTime = LocalTime.parse(time), createdAtUTC = now, updatedAtUTC = now)
    private fun rejected(action: () -> Unit) { assertThrows(IllegalArgumentException::class.java, action) }
    @Test fun terminationAndIntervals() {
        for (interval in RecurrenceInterval.entries) {
            val first = LocalDate.parse("2026-03-07")
            val count = RecurrenceSeries.materializedDates(interval, first, RecurrenceTermination.RepeatCount(3))
            assertEquals(listOf(first, first.plusDays(interval.days), first.plusDays(interval.days * 2)), count)
            assertEquals(count, RecurrenceSeries.materializedDates(interval, first, RecurrenceTermination.EndDate(count.last())))
        }
    }
    @Test fun materializationBound() {
        val first = row().date
        RecurrenceSeries.validateBound(first, RecurrenceTermination.RepeatCount(366))
        RecurrenceSeries.validateBound(first, RecurrenceTermination.EndDate(first.plusDays(366)))
        for (count in listOf(0, -1, 367)) rejected { RecurrenceSeries.validateBound(first, RecurrenceTermination.RepeatCount(count)) }
        rejected { RecurrenceSeries.validateBound(first, RecurrenceTermination.EndDate(first.minusDays(1))) }
        rejected { RecurrenceSeries.validateBound(first, RecurrenceTermination.EndDate(first.plusDays(367))) }
        assertEquals(366, RecurrenceSeries.materializedDates(RecurrenceInterval.everyOtherDay, first, RecurrenceTermination.RepeatCount(999)).size)
    }
    @Test fun dstUsesLocalDateAndElapsedDuration() {
        assertEquals(Instant.parse("2026-03-08T09:00:00Z"), row().startInstant(zone))
        assertEquals(now, row().endInstant(zone))
        assertEquals(Instant.parse("2026-03-08T10:30:00Z"), row("02:30").startInstant(zone))
        assertEquals(Instant.parse("2026-11-01T08:30:00Z"), row("01:30").copy(date = LocalDate.parse("2026-11-01")).startInstant(zone))
    }
    @Test fun overdueDerivedAtEndAndPersistsAcrossDays() {
        assertFalse(row().isOverdue(now.minusNanos(1), zone))
        assertTrue(row().isOverdue(now, zone))
        assertTrue(row().isOverdue(now.plusSeconds(86400), zone))
        assertEquals(AppointmentStatus.scheduled, row().status)
        assertFalse(row().cancelling(null, now).isOverdue(now, zone))
        assertFalse(row().isOverdue(now, ZoneId.of("Pacific/Honolulu")))
    }
    @Test fun halfOpenConflictAcrossStudents() {
        assertFalse(row().overlaps(row("03:00"), zone))
        assertTrue(row().overlaps(row("01:30").copy(studentID = StudentID.fromUUID(UUID(0, 9))), zone))
    }
    @Test fun lifecycleAndDeletionBoundary() {
        val future = row("04:00")
        assertTrue(future.canPermanentlyDelete(now, zone))
        assertFalse(future.canPermanentlyDelete(future.startInstant(zone), zone))
        val started = future.startingTraining(UUID(0, 3), now)
        assertFalse(started.canPermanentlyDelete(now, zone))
        assertEquals(future.copy(updatedAtUTC = now), started.abandoningEmptySession(now))
        assertEquals(AppointmentStatus.completed, started.completingSession(now).status)
        rejected { future.completingSession(now) }
        rejected { started.cancelling(null, now) }
        assertEquals(AbsentCreditChoice.notCharged, future.markingAbsent(AbsentCreditChoice.notCharged, now).absentCreditChoice)
    }
    @Test fun detachedKeepsSeriesAndOptionalLead() {
        val original = row().copy(seriesID = UUID(0, 4))
        val edited = original.reschedulingDetached(AppointmentEdit(reminderEnabled = false), now)
        assertTrue(edited.isDetachedException)
        assertEquals(original.seriesID, edited.seriesID)
        assertEquals(ReminderLeadMinutes.sixty, edited.reminderLeadMinutes)
        rejected { original.copy(durationMinutes = 0) }
        rejected { original.copy(reminderLeadMinutes = null) }
        rejected { original.copy(absentCreditChoice = AbsentCreditChoice.charged) }
    }
    @Test fun focusOnlyChangesPreserveDetachmentAndSchedule() {
        for (detached in listOf(false, true)) {
            val original = row().copy(seriesID = UUID(0, 4), isDetachedException = detached)
            val updated = original.updatingTrainingFocus(setOf(com.ignacioli.finecoach.core.domain.common.BodyPart.back), now)
            assertEquals(detached, updated.isDetachedException)
            assertEquals(updated, original.reschedulingDetached(AppointmentEdit(trainingFocus = updated.trainingFocus), now))
            assertEquals(original.startTime, updated.startTime)
            assertEquals(original.reminderLeadMinutes, updated.reminderLeadMinutes)
        }
    }
    @Test fun todaySections() {
        val rows = listOf(row("05:00"), row("04:00"), row(), row("00:00").startingTraining(UUID(0, 5), now), row("06:00").cancelling(null, now), row().copy(date = row().date.minusDays(1)))
        assertEquals(TodayOrderingSection.entries, TodayOrderingPolicy.order(rows, row().date, now, zone).map { it.section })
    }
    @Test fun remindersAreGeneric() {
        assertEquals(listOf(15, 30, 60, 120), ReminderLeadMinutes.entries.map { it.minutes })
        assertEquals("训练提醒", AppointmentNotificationContentBuilder.title())
        assertEquals("01:00 有一节训练安排。", AppointmentNotificationContentBuilder.body(row().startInstant(zone), zone))
    }
}
