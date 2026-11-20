package com.ignacioli.finecoach.core.application

import com.ignacioli.finecoach.core.domain.body.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.DecimalValue
import com.ignacioli.finecoach.core.domain.training.DomainException
import java.time.*
import java.util.UUID

class BodyDataUseCases(private val repository: BodyDataRepositoryPort, private val clock: AppClock, private val zone: ZoneId, private val newID: () -> UUID) {
    suspend fun metrics(studentID: StudentID) = repository.metrics(studentID)
    suspend fun createCustomMetric(studentID: StudentID, name: String, unit: String): ApplicationResult<BodyMetricDefinition> = validated {
        val now = clock.now()
        repository.saveMetric(BodyMetricDefinition(newID(), studentID, BodyMetricKind.custom, NormalizedName.parse(name), BodyMetricUnitRuleKind.customUnit, unit, BodyMetricLifecycle.active, now, now))
    }
    suspend fun renameCustomMetric(studentID: StudentID, id: UUID, name: String) = change(studentID, id) { it.renamed(name, clock.now()) }
    suspend fun changeCurrentUnit(studentID: StudentID, id: UUID, unit: String) = change(studentID, id) { it.changingCurrentUnit(unit, clock.now()) }
    suspend fun archiveCustomMetric(studentID: StudentID, id: UUID) = change(studentID, id) { it.archived(clock.now()) }
    suspend fun restoreCustomMetric(studentID: StudentID, id: UUID) = change(studentID, id) { it.restored(clock.now()) }
    suspend fun recordMeasurement(studentID: StudentID, metricID: UUID, value: String, enteredUnit: String, at: Instant = clock.now()): ApplicationResult<BodyMeasurement> = validated {
        repository.recordMeasurement(BodyMeasurement.recordedNow(newID(), studentID, metricID, at, zone, DecimalValue.parse(value), enteredUnit))
    }
    suspend fun history(studentID: StudentID, metricID: UUID) = repository.history(studentID, metricID)
    suspend fun latestMeasurements(studentID: StudentID) = repository.latestMeasurements(studentID)
    /** Call only after the visible confirmation flow has accepted deletion. */
    suspend fun deleteMeasurement(id: UUID) = repository.deleteMeasurement(id)
    suspend fun deleteAllMeasurements(studentID: StudentID, metricID: UUID) = repository.deleteAllMeasurements(studentID, metricID)
    suspend fun deleteCustomMetricIfUnused(id: UUID) = repository.deleteCustomMetricIfUnused(id)
    private suspend fun change(studentID: StudentID, id: UUID, transform: (BodyMetricDefinition) -> BodyMetricDefinition): ApplicationResult<BodyMetricDefinition> = validated {
        val metrics = when (val r = repository.metrics(studentID)) { is ApplicationResult.Failure -> return@validated r; is ApplicationResult.Success -> r.value }
        val current = metrics.firstOrNull { it.id == id } ?: return@validated ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.notFound))
        repository.saveMetric(transform(current))
    }
    private suspend fun <T> validated(action: suspend () -> ApplicationResult<T>): ApplicationResult<T> = try { action() }
        catch (e: DomainException) { ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.valueOf(e.error.name))) }
        catch (_: IllegalArgumentException) { ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.incompatibleInput)) }
}
