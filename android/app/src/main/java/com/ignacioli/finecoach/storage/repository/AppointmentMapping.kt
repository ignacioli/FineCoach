package com.ignacioli.finecoach.storage.repository

import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.storage.entity.*
import java.time.*
import java.util.UUID

internal fun Appointment.toEntity() = AppointmentEntity(id.toString(), studentID.value, seriesID?.toString(), date.toString(), startTime.toString(),
    durationMinutes, status.name, absentCreditChoice?.name, cancellationReason, isDetachedException, reminderEnabled,
    reminderLeadMinutes?.minutes, linkedSessionID?.toString(), trainingFocus.sortedBy { it.name }.joinToString(",") { it.name }, createdAtUTC.toString(), updatedAtUTC.toString())
internal fun AppointmentEntity.toDomain() = Appointment(UUID.fromString(id), StudentID.parse(studentID), seriesID?.let(UUID::fromString),
    LocalDate.parse(date), LocalTime.parse(startTime), durationMinutes, AppointmentStatus.valueOf(status), absentCreditChoice?.let(AbsentCreditChoice::valueOf),
    cancellationReason, isDetachedException, reminderEnabled, reminderLeadMinutes?.let { m -> ReminderLeadMinutes.entries.single { it.minutes == m } },
    linkedSessionID?.let(UUID::fromString), if (trainingFocus.isEmpty()) emptySet() else trainingFocus.split(',').map(BodyPart::valueOf).toSet(),
    Instant.parse(createdAtUTC), Instant.parse(updatedAtUTC))
internal fun RecurrenceSeries.toEntity() = RecurrenceSeriesEntity(id.toString(), studentID.value, intervalDays.days.toInt(),
    (termination as? RecurrenceTermination.EndDate)?.date?.toString(), (termination as? RecurrenceTermination.RepeatCount)?.count,
    defaultStartTime.toString(), defaultDurationMinutes, defaultReminderEnabled, defaultReminderLeadMinutes?.minutes, status.name,
    createdAtUTC.toString(), updatedAtUTC.toString())
internal fun RecurrenceSeriesEntity.toDomain(): RecurrenceSeries {
    require((endDate == null) != (repeatCount == null))
    return RecurrenceSeries(UUID.fromString(id), StudentID.parse(studentID), RecurrenceInterval.entries.single { it.days.toInt() == intervalDays },
        endDate?.let { RecurrenceTermination.EndDate(LocalDate.parse(it)) } ?: RecurrenceTermination.RepeatCount(requireNotNull(repeatCount)),
        LocalTime.parse(defaultStartTime), defaultDurationMinutes, defaultReminderEnabled,
        defaultReminderLeadMinutes?.let { m -> ReminderLeadMinutes.entries.single { it.minutes == m } }, RecurrenceSeriesStatus.valueOf(status),
        Instant.parse(createdAtUTC), Instant.parse(updatedAtUTC))
}
