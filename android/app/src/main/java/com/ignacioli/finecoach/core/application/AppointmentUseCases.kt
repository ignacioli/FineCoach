package com.ignacioli.finecoach.core.application

import com.ignacioli.finecoach.core.domain.appointment.*
import java.time.LocalDate
import java.util.UUID

/** Atomic persistence boundary; implementations re-read state and conflicts inside the write transaction. */
interface AppointmentRepositoryPort {
    suspend fun all(): ApplicationResult<List<Appointment>>
    suspend fun find(id: UUID): ApplicationResult<Appointment?>
    suspend fun series(id: UUID): ApplicationResult<RecurrenceSeries?>
    suspend fun create(appointments: List<Appointment>, series: RecurrenceSeries?, overrideConflict: Boolean): ApplicationResult<List<Appointment>>
    suspend fun editSingle(id: UUID, edit: AppointmentEdit, overrideConflict: Boolean): ApplicationResult<Appointment>
    suspend fun editFuture(seriesID: UUID, boundary: LocalDate, edit: FutureAppointmentEdit, overrideConflict: Boolean): ApplicationResult<List<Appointment>>
    suspend fun start(id: UUID): ApplicationResult<AppointmentTrainingStartResult>
    suspend fun cancel(id: UUID, reason: String?): ApplicationResult<Appointment>
    suspend fun absent(id: UUID, choice: AbsentCreditChoice, confirmed: Boolean): ApplicationResult<AbsentAppointmentResult>
    suspend fun deleteFuture(id: UUID, confirmed: Boolean): ApplicationResult<Unit>
    suspend fun conflicts(candidate: Appointment, excluding: UUID? = null): ApplicationResult<List<AppointmentConflict>>
}

/** S2-D06: callers offer entry to the prior training without mutating either appointment. */
sealed interface AppointmentTrainingStartResult {
    data class Started(val session: SessionRecord) : AppointmentTrainingStartResult
    data class PreviousTrainingNeedsHandling(val appointmentID: UUID, val sessionID: com.ignacioli.finecoach.core.domain.common.SessionID) : AppointmentTrainingStartResult
}

data class AbsentAppointmentResult(val appointment: Appointment, val settlement: ApplicationResult<CreditAdjustmentRecord?>)

data class AppointmentConflict(val appointmentID: UUID, val studentID: com.ignacioli.finecoach.core.domain.common.StudentID,
    val displayName: String, val start: java.time.Instant, val end: java.time.Instant)

class AppointmentUseCases(private val repository: AppointmentRepositoryPort) {
    suspend fun all() = repository.all()
    suspend fun find(id: UUID) = repository.find(id)
    suspend fun series(id: UUID) = repository.series(id)
    suspend fun createSingle(appointment: Appointment, overrideConflict: Boolean = false) = repository.create(listOf(appointment), null, overrideConflict)
    suspend fun createRecurring(series: RecurrenceSeries, firstDate: LocalDate, focus: Set<com.ignacioli.finecoach.core.domain.common.BodyPart> = emptySet(),
        overrideConflict: Boolean = false, makeID: () -> UUID = UUID::randomUUID): ApplicationResult<List<Appointment>> = settlementValidation {
        RecurrenceSeries.validateBound(firstDate, series.termination)
        val rows = RecurrenceSeries.materializedDates(series.intervalDays, firstDate, series.termination).map {
            Appointment(makeID(), series.studentID, series.id, it, series.defaultStartTime, series.defaultDurationMinutes,
                reminderEnabled = series.defaultReminderEnabled, reminderLeadMinutes = series.defaultReminderLeadMinutes,
                trainingFocus = focus, createdAtUTC = series.createdAtUTC, updatedAtUTC = series.updatedAtUTC)
        }
        repository.create(rows, series, overrideConflict)
    }
    suspend fun updateTrainingFocus(id: UUID, focus: Set<com.ignacioli.finecoach.core.domain.common.BodyPart>) =
        repository.editSingle(id, AppointmentEdit(trainingFocus = focus), false)
    suspend fun editSingle(id: UUID, edit: AppointmentEdit, overrideConflict: Boolean = false) = repository.editSingle(id, edit, overrideConflict)
    suspend fun editFuture(seriesID: UUID, boundary: LocalDate, edit: FutureAppointmentEdit, overrideConflict: Boolean = false) = repository.editFuture(seriesID, boundary, edit, overrideConflict)
    suspend fun startTraining(id: UUID) = repository.start(id)
    suspend fun cancel(id: UUID, reason: String? = null) = repository.cancel(id, reason)
    suspend fun markAbsent(id: UUID, choice: AbsentCreditChoice, confirmed: Boolean) = repository.absent(id, choice, confirmed)
    suspend fun deleteFuture(id: UUID, confirmed: Boolean) = repository.deleteFuture(id, confirmed)
    suspend fun conflicts(candidate: Appointment, excluding: UUID? = null) = repository.conflicts(candidate, excluding)
}
