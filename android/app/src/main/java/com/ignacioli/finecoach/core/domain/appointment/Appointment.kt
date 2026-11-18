package com.ignacioli.finecoach.core.domain.appointment

import com.ignacioli.finecoach.core.domain.common.BodyPart
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.ValidatedText
import java.time.*
import java.time.temporal.ChronoUnit
import java.util.UUID

enum class AppointmentStatus { scheduled, inProgress, completed, cancelled, absent }
enum class AbsentCreditChoice { charged, notCharged }
enum class ReminderLeadMinutes(val minutes: Int) { fifteen(15), thirty(30), sixty(60), oneTwenty(120) }
enum class RecurrenceInterval(val days: Long) { everyOtherDay(2), everyTwoDays(3), everyWeek(7) }
enum class RecurrenceSeriesStatus { active, ended }
sealed interface RecurrenceTermination {
    data class EndDate(val date: LocalDate) : RecurrenceTermination
    data class RepeatCount(val count: Int) : RecurrenceTermination
}

data class Appointment(
    val id: UUID,
    val studentID: StudentID,
    val seriesID: UUID? = null,
    val date: LocalDate,
    val startTime: LocalTime,
    val durationMinutes: Int = 60,
    val status: AppointmentStatus = AppointmentStatus.scheduled,
    val absentCreditChoice: AbsentCreditChoice? = null,
    val cancellationReason: String? = null,
    val isDetachedException: Boolean = false,
    val reminderEnabled: Boolean = true,
    val reminderLeadMinutes: ReminderLeadMinutes? = ReminderLeadMinutes.sixty,
    val linkedSessionID: UUID? = null,
    val trainingFocus: Set<BodyPart> = emptySet(),
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
) {
    init {
        require(durationMinutes > 0)
        require(!reminderEnabled || reminderLeadMinutes != null)
        require(status == AppointmentStatus.absent || absentCreditChoice == null)
        cancellationReason?.let { ValidatedText.optional(it) }
    }
    fun startInstant(zone: ZoneId): Instant = date.atTime(startTime).atZone(zone).toInstant()
    fun endInstant(zone: ZoneId): Instant = startInstant(zone).plusSeconds(durationMinutes.toLong() * 60)
    fun overlaps(other: Appointment, zone: ZoneId) = startInstant(zone) < other.endInstant(zone) && other.startInstant(zone) < endInstant(zone)
    fun isOverdue(now: Instant, zone: ZoneId) = status == AppointmentStatus.scheduled && endInstant(zone) <= now
    fun canPermanentlyDelete(now: Instant, zone: ZoneId) = status == AppointmentStatus.scheduled && linkedSessionID == null && startInstant(zone) > now
    fun startingTraining(sessionID: UUID, now: Instant): Appointment {
        require(status == AppointmentStatus.scheduled && linkedSessionID == null)
        return copy(status = AppointmentStatus.inProgress, linkedSessionID = sessionID, updatedAtUTC = now)
    }
    fun abandoningEmptySession(now: Instant): Appointment {
        require(status == AppointmentStatus.inProgress)
        return copy(status = AppointmentStatus.scheduled, linkedSessionID = null, updatedAtUTC = now)
    }
    fun completingSession(now: Instant): Appointment {
        require(status == AppointmentStatus.inProgress && linkedSessionID != null)
        return copy(status = AppointmentStatus.completed, updatedAtUTC = now)
    }
    fun cancelling(reason: String?, now: Instant): Appointment {
        require(status == AppointmentStatus.scheduled)
        return copy(status = AppointmentStatus.cancelled, cancellationReason = reason, updatedAtUTC = now)
    }
    fun markingAbsent(choice: AbsentCreditChoice, now: Instant): Appointment {
        require(status == AppointmentStatus.scheduled)
        return copy(status = AppointmentStatus.absent, absentCreditChoice = choice, updatedAtUTC = now)
    }
    fun updatingTrainingFocus(value: Set<BodyPart>, now: Instant): Appointment {
        require(status == AppointmentStatus.scheduled)
        return copy(trainingFocus = value, updatedAtUTC = now)
    }
    fun reschedulingDetached(edit: AppointmentEdit, now: Instant): Appointment {
        require(status == AppointmentStatus.scheduled)
        if (!edit.hasScheduleChanges) return updatingTrainingFocus(edit.trainingFocus ?: trainingFocus, now)
        return copy(date = edit.date ?: date, startTime = edit.startTime ?: startTime,
            durationMinutes = edit.durationMinutes ?: durationMinutes,
            reminderEnabled = edit.reminderEnabled ?: reminderEnabled,
            reminderLeadMinutes = edit.reminderLeadMinutes ?: reminderLeadMinutes,
            trainingFocus = edit.trainingFocus ?: trainingFocus, isDetachedException = true, updatedAtUTC = now)
    }
}

data class AppointmentEdit(
    val date: LocalDate? = null,
    val startTime: LocalTime? = null,
    val durationMinutes: Int? = null,
    val reminderEnabled: Boolean? = null,
    val reminderLeadMinutes: ReminderLeadMinutes? = null,
    val trainingFocus: Set<BodyPart>? = null,
) {
    val hasScheduleChanges: Boolean get() = date != null || startTime != null || durationMinutes != null || reminderEnabled != null || reminderLeadMinutes != null
}

/** This-and-future deliberately has no date, interval or termination mutation. */
data class FutureAppointmentEdit(
    val startTime: LocalTime? = null,
    val durationMinutes: Int? = null,
    val reminderEnabled: Boolean? = null,
    val reminderLeadMinutes: ReminderLeadMinutes? = null,
    val boundaryTrainingFocus: Set<BodyPart>? = null,
)

data class RecurrenceSeries(
    val id: UUID,
    val studentID: StudentID,
    val intervalDays: RecurrenceInterval,
    val termination: RecurrenceTermination,
    val defaultStartTime: LocalTime,
    val defaultDurationMinutes: Int = 60,
    val defaultReminderEnabled: Boolean = true,
    val defaultReminderLeadMinutes: ReminderLeadMinutes? = ReminderLeadMinutes.sixty,
    val status: RecurrenceSeriesStatus = RecurrenceSeriesStatus.active,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
) {
    init {
        require(defaultDurationMinutes > 0)
        require(!defaultReminderEnabled || defaultReminderLeadMinutes != null)
        if (termination is RecurrenceTermination.RepeatCount) require(termination.count > 0)
    }
    fun ended(now: Instant) = copy(status = RecurrenceSeriesStatus.ended, updatedAtUTC = now)
    companion object {
        const val MAXIMUM_INSTANCES = 366
        fun validateBound(first: LocalDate, termination: RecurrenceTermination) {
            when (termination) {
                is RecurrenceTermination.RepeatCount -> require(termination.count in 1..MAXIMUM_INSTANCES)
                is RecurrenceTermination.EndDate -> require(ChronoUnit.DAYS.between(first, termination.date) in 0..MAXIMUM_INSTANCES.toLong())
            }
        }
        fun materializedDates(interval: RecurrenceInterval, first: LocalDate, termination: RecurrenceTermination): List<LocalDate> {
            val dates = mutableListOf<LocalDate>()
            var cursor = first
            while (dates.size < MAXIMUM_INSTANCES) {
                when (termination) {
                    is RecurrenceTermination.RepeatCount -> if (dates.size >= termination.count) break
                    is RecurrenceTermination.EndDate -> if (cursor > termination.date) break
                }
                dates += cursor
                cursor = cursor.plusDays(interval.days)
            }
            return dates
        }
    }
}

enum class TodayOrderingSection { inProgress, overdue, nextUp, remainingToday, resolved }
data class TodayOrderedAppointment(val appointment: Appointment, val section: TodayOrderingSection)
object TodayOrderingPolicy {
    fun order(appointments: List<Appointment>, today: LocalDate, now: Instant, zone: ZoneId): List<TodayOrderedAppointment> {
        val rows = appointments.filter { it.date == today }.sortedBy { it.startTime }
        val pending = rows.filter { it.status == AppointmentStatus.scheduled && !it.isOverdue(now, zone) }
        return rows.filter { it.status == AppointmentStatus.inProgress }.map { TodayOrderedAppointment(it, TodayOrderingSection.inProgress) } +
            rows.filter { it.isOverdue(now, zone) }.map { TodayOrderedAppointment(it, TodayOrderingSection.overdue) } +
            pending.mapIndexed { index, it -> TodayOrderedAppointment(it, if (index == 0) TodayOrderingSection.nextUp else TodayOrderingSection.remainingToday) } +
            rows.filter { it.status in setOf(AppointmentStatus.completed, AppointmentStatus.cancelled, AppointmentStatus.absent) }
                .map { TodayOrderedAppointment(it, TodayOrderingSection.resolved) }
    }
}

object AppointmentNotificationContentBuilder {
    fun title() = "训练提醒"
    fun body(start: Instant, zone: ZoneId): String = "%02d:%02d 有一节训练安排。".format(java.util.Locale.ROOT, start.atZone(zone).hour, start.atZone(zone).minute)
}
