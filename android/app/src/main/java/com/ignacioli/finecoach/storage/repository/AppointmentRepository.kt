package com.ignacioli.finecoach.storage.repository

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.storage.FineCoachDatabase
import java.time.*
import java.util.UUID

class AppointmentRepository(
    private val db: FineCoachDatabase, private val clock: AppClock, private val ids: StableIDGenerator,
    private val generation: UUID, private val sessions: SessionRepository, private val zone: ZoneId,
    private val makeID: () -> UUID = UUID::randomUUID,
) : AppointmentRepositoryPort {
    private val dao get() = db.appointmentDao()
    private suspend fun <T> tx(action: () -> T) = trainingTransaction(db, generation, action)
    private fun current(id: UUID) = dao.find(id.toString())?.toDomain() ?: trainingFailure(ApplicationErrorCode.notFound)
    private fun rows() = dao.all().map { it.toDomain() }
    private fun persist(row: Appointment): Appointment { check(dao.update(row.toEntity()) == 1); return row }
    override suspend fun all() = tx { rows() }
    override suspend fun inDateRange(first: LocalDate, last: LocalDate) = tx {
        require(!last.isBefore(first))
        dao.inDateRange(first.toString(),last.toString()).map { it.toDomain() }
    }
    override suspend fun find(id: UUID) = tx { dao.find(id.toString())?.toDomain() }
    override suspend fun series(id: UUID) = tx { dao.series(id.toString())?.toDomain() }
    private fun conflictsWith(candidate: Appointment, exclude: Set<UUID>) = rows().filter {
        it.id !in exclude && it.status in setOf(AppointmentStatus.scheduled, AppointmentStatus.inProgress) && it.overlaps(candidate, zone)
    }.map { other ->
        val student = db.s1Dao().findStudent(UUID.fromString(other.studentID.value)) ?: trainingFailure(ApplicationErrorCode.notFound)
        AppointmentConflict(other.id, other.studentID, student.displayName, other.startInstant(zone), other.endInstant(zone))
    }
    override suspend fun conflicts(candidate: Appointment, excluding: UUID?) = tx { conflictsWith(candidate, setOfNotNull(excluding)) }
    private fun checkConflicts(candidates: List<Appointment>, exclude: Set<UUID>, override: Boolean) {
        if (!override && candidates.any { conflictsWith(it, exclude).isNotEmpty() }) trainingFailure(ApplicationErrorCode.conflict)
    }
    private fun validateStudent(id: StudentID) {
        val student = db.s1Dao().findStudent(UUID.fromString(id.value)) ?: trainingFailure(ApplicationErrorCode.notFound)
        if (student.lifecycle != StudentLifecycle.active) trainingFailure(ApplicationErrorCode.invalidState)
    }
    override suspend fun create(appointments: List<Appointment>, series: RecurrenceSeries?, overrideConflict: Boolean) = tx {
        require(appointments.isNotEmpty())
        appointments.forEach { validateStudent(it.studentID); require(it.status == AppointmentStatus.scheduled && it.linkedSessionID == null) }
        if (series != null) {
            require(series.status == RecurrenceSeriesStatus.active)
            val first = appointments.minOf { it.date }
            RecurrenceSeries.validateBound(first, series.termination)
            require(appointments.map { it.date } == RecurrenceSeries.materializedDates(series.intervalDays, first, series.termination))
            require(appointments.all { it.seriesID == series.id && it.studentID == series.studentID })
        } else require(appointments.size == 1 && appointments.single().seriesID == null)
        checkConflicts(appointments, emptySet(), overrideConflict)
        series?.let { dao.insert(it.toEntity()) }
        appointments.forEach { dao.insert(it.toEntity()) }
        appointments
    }
    override suspend fun editSingle(id: UUID, edit: AppointmentEdit, overrideConflict: Boolean) = tx {
        val updated = current(id).reschedulingDetached(edit, clock.now())
        if (edit.hasScheduleChanges) checkConflicts(listOf(updated), setOf(id), overrideConflict)
        persist(updated)
    }
    override suspend fun editFuture(seriesID: UUID, boundary: LocalDate, edit: FutureAppointmentEdit, overrideConflict: Boolean) = tx {
        val series = dao.series(seriesID.toString())?.toDomain() ?: trainingFailure(ApplicationErrorCode.notFound)
        require(series.status == RecurrenceSeriesStatus.active)
        val existing = rows().filter { it.seriesID == seriesID }
        require(existing.any { it.date == boundary && it.status == AppointmentStatus.scheduled })
        val superseded = existing.filter { it.date >= boundary && it.status == AppointmentStatus.scheduled && !it.isDetachedException }
        val focus = superseded.associate { it.date to it.trainingFocus }.toMutableMap()
        edit.boundaryTrainingFocus?.let { focus[boundary] = it }
        RecurrenceSeries.validateBound(boundary, series.termination)
        val replacement = series.copy(id = makeID(), defaultStartTime = edit.startTime ?: series.defaultStartTime,
            defaultDurationMinutes = edit.durationMinutes ?: series.defaultDurationMinutes,
            defaultReminderEnabled = edit.reminderEnabled ?: series.defaultReminderEnabled,
            defaultReminderLeadMinutes = edit.reminderLeadMinutes ?: series.defaultReminderLeadMinutes,
            createdAtUTC = clock.now(), updatedAtUTC = clock.now())
        val appointments = RecurrenceSeries.materializedDates(series.intervalDays, boundary, series.termination).map {
            Appointment(makeID(), series.studentID, replacement.id, it, replacement.defaultStartTime, replacement.defaultDurationMinutes,
                reminderEnabled = replacement.defaultReminderEnabled, reminderLeadMinutes = replacement.defaultReminderLeadMinutes,
                trainingFocus = focus[it].orEmpty(), createdAtUTC = clock.now(), updatedAtUTC = clock.now())
        }
        checkConflicts(appointments, superseded.map { it.id }.toSet(), overrideConflict)
        check(dao.update(series.ended(clock.now()).toEntity()) == 1)
        superseded.forEach { check(dao.delete(it.id.toString()) == 1) }
        dao.insert(replacement.toEntity())
        appointments.forEach { dao.insert(it.toEntity()) }
        appointments
    }
    override suspend fun start(id: UUID): ApplicationResult<AppointmentTrainingStartResult> = tx {
        val appointment = current(id)
        require(appointment.status == AppointmentStatus.scheduled && appointment.linkedSessionID == null)
        // S2-D06: inspect before startOrOpen, which may repair an active pointer.
        // The previous-training outcome must leave every persisted row unchanged.
        val active = db.t008SessionDao().activeSessions().filter { it.studentID.toString() == appointment.studentID.value }
        if (active.size > 1) trainingFailure(ApplicationErrorCode.conflict)
        active.singleOrNull()?.let { previous ->
            val ownerID = dao.forSession(previous.id.toString())?.id?.let(UUID::fromString) ?: previous.appointmentID
            if (ownerID != null && ownerID != id) {
                return@tx AppointmentTrainingStartResult.PreviousTrainingNeedsHandling(ownerID, SessionID.fromUUID(previous.id))
            }
        }
        val session = sessions.startOrOpenInTransaction(StartOrOpenSessionCommand(appointment.studentID, appointment.trainingFocus, clock.now()))
        val sessionID = UUID.fromString(session.sessionID.value)
        persist(appointment.startingTraining(sessionID, clock.now()))
        check(dao.linkSession(session.sessionID.value, id.toString()) == 1)
        AppointmentTrainingStartResult.Started(session)
    }
    override suspend fun cancel(id: UUID, reason: String?) = tx { persist(current(id).cancelling(ValidatedText.optional(reason)?.value, clock.now())) }
    override suspend fun absent(id: UUID, choice: AbsentCreditChoice, confirmed: Boolean): ApplicationResult<AbsentAppointmentResult> {
        val saved = tx {
            require(confirmed)
            val appointment = current(id)
            if (appointment.status == AppointmentStatus.absent) {
                require(appointment.absentCreditChoice == choice)
                appointment
            } else persist(appointment.markingAbsent(choice, clock.now()))
        }
        if (saved is ApplicationResult.Failure) return saved
        val appointment = (saved as ApplicationResult.Success).value
        val settlement: ApplicationResult<CreditAdjustmentRecord?> = if (choice == AbsentCreditChoice.notCharged) ApplicationResult.Success(null)
            else settleAbsence(appointment)
        return ApplicationResult.Success(AbsentAppointmentResult(appointment, settlement))
    }
    private suspend fun settleAbsence(appointment: Appointment): ApplicationResult<CreditAdjustmentRecord?> {
        // Match iOS CourseActions: absence persists independently; report debit failure explicitly.
        val credits = CreditUseCases(CoursePackageRepository(db, clock, ids, zone), clock, ids, zone)
        val ledger = when (val result = credits.ledger(appointment.studentID)) {
            is ApplicationResult.Failure -> return result
            is ApplicationResult.Success -> result.value
        }
        val key = CreditLedgerSourceEventKeyFactory.appointmentAbsent(appointment.id.toString())
        ledger.firstOrNull { it.sourceEventKey == key }?.let { return ApplicationResult.Success(it) }
        val active = when (val result = credits.activePackage(appointment.studentID, clock.today(zone))) {
            is ApplicationResult.Failure -> return result
            is ApplicationResult.Success -> result.value ?: return ApplicationResult.Success(null)
        }
        return credits.debitOnAppointmentAbsent(active.coursePackageID, appointment.id.toString())
    }
    override suspend fun deleteFuture(id: UUID, confirmed: Boolean) = tx {
        require(confirmed && current(id).canPermanentlyDelete(clock.now(), zone))
        check(dao.delete(id.toString()) == 1)
        Unit
    }
}

internal fun completeLinkedAppointment(db: FineCoachDatabase, sessionID: SessionID, now: Instant) {
    val row = db.appointmentDao().forSession(sessionID.value) ?: return
    check(db.appointmentDao().update(row.toDomain().completingSession(now).toEntity()) == 1)
}
internal fun abandonLinkedAppointment(db: FineCoachDatabase, sessionID: SessionID, now: Instant) {
    val row = db.appointmentDao().forSession(sessionID.value) ?: return
    check(db.appointmentDao().update(row.toDomain().abandoningEmptySession(now).toEntity()) == 1)
    check(db.appointmentDao().linkSession(sessionID.value, null) == 1)
}
