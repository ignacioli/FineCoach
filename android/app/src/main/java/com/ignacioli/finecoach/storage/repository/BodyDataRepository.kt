// fictional-data: no embedded person samples; bootstraps only public built-in metric definitions.
package com.ignacioli.finecoach.storage.repository

import androidx.room.withTransaction
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.body.*
import com.ignacioli.finecoach.core.domain.training.DecimalValue
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.entity.*
import java.time.*
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.CancellationException

class BodyDataRepository(private val database: FineCoachDatabase, private val clock: AppClock): BodyDataRepositoryPort {
    private val dao get() = database.bodyDataDao()
    override suspend fun metrics(studentID: StudentID) = transaction {
        seed(); dao.metrics(studentID.value).map { it.domain() }
    }
    override suspend fun saveMetric(metric: BodyMetricDefinition) = transaction {
        require(metric.kind == BodyMetricKind.custom) { "Invalid body metric state" }
        val old = dao.metric(metric.id.toString())
        if (old == null) dao.insert(metric.entity()) else {
            require(old.studentID == metric.studentID?.value && old.createdAtUTC == metric.createdAtUTC.toString() && old.kind == BodyMetricKind.custom.name) { "Invalid body metric state" }
            check(dao.update(metric.entity()) == 1)
        }
        dao.metric(metric.id.toString())!!.domain()
    }
    override suspend fun recordMeasurement(candidate: BodyMeasurement) = transaction {
        seed()
        val metric = dao.metric(candidate.metricID.toString())?.domain() ?: throw BodyFailure(ApplicationErrorCode.notFound)
        require(metric.studentID == null || metric.studentID == candidate.studentID) { "Invalid body metric scope" }
        val old = dao.onDay(candidate.studentID.value, candidate.metricID.toString(), candidate.localCalendarDay.toString())
        val saved = old?.domain()?.editingSameDay(candidate.value, candidate.enteredUnit, candidate.updatedAtUTC) ?: candidate
        if (old == null) dao.insert(saved.entity()) else check(dao.update(saved.entity()) == 1)
        dao.onDay(candidate.studentID.value, candidate.metricID.toString(), candidate.localCalendarDay.toString())!!.domain()
    }
    override suspend fun history(studentID: StudentID, metricID: UUID) = transaction { dao.history(studentID.value, metricID.toString()).map { it.domain() } }
    override suspend fun latestMeasurements(studentID: StudentID) = transaction {
        dao.allMeasurements(studentID.value).map { it.domain() }.groupBy { it.metricID }.mapValues { it.value.first() }
    }
    override suspend fun deleteMeasurement(id: UUID) = transaction { if (dao.deleteMeasurement(id.toString()) != 1) throw BodyFailure(ApplicationErrorCode.notFound); Unit }
    override suspend fun deleteAllMeasurements(studentID: StudentID, metricID: UUID) = transaction { dao.deleteAll(studentID.value, metricID.toString()); Unit }
    override suspend fun deleteCustomMetricIfUnused(id: UUID) = transaction {
        val metric = dao.metric(id.toString()) ?: throw BodyFailure(ApplicationErrorCode.notFound)
        require(metric.kind == BodyMetricKind.custom.name) { "Invalid body metric state" }
        if (dao.measurementCount(id.toString()) != 0) throw BodyFailure(ApplicationErrorCode.conflict)
        check(dao.deleteMetric(id.toString()) == 1); Unit
    }
    private fun seed() { for (builtIn in BuiltInBodyMetric.entries) if (dao.metric(builtIn.id.toString()) == null) dao.insert(builtIn.definition(clock.now()).entity()) }
    private suspend fun <T> transaction(action: () -> T): ApplicationResult<T> = withContext(Dispatchers.IO) {
        try { ApplicationResult.Success(database.withTransaction { action() }) }
        catch (e: CancellationException) { throw e }
        catch (e: BodyFailure) { ApplicationResult.Failure(ApplicationError(e.code)) }
        catch (_: IllegalArgumentException) { ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.incompatibleInput)) }
        catch (_: Exception) { ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed)) }
    }
}
private class BodyFailure(val code: ApplicationErrorCode): RuntimeException()
internal fun BodyMetricDefinition.entity() = BodyMetricDefinitionEntity(id.toString(), studentID?.value, kind.name, name.value, unitRuleKind.name, currentUnit, lifecycle.name, createdAtUTC.toString(), updatedAtUTC.toString())
internal fun BodyMetricDefinitionEntity.domain() = BodyMetricDefinition(UUID.fromString(id), studentID?.let { StudentID.parse(it) }, BodyMetricKind.valueOf(kind), NormalizedName.parse(name), BodyMetricUnitRuleKind.valueOf(unitRuleKind), currentUnit, BodyMetricLifecycle.valueOf(lifecycle), Instant.parse(createdAtUTC), Instant.parse(updatedAtUTC))
internal fun BodyMeasurement.entity() = BodyMeasurementEntity(id.toString(), studentID.value, metricID.toString(), localCalendarDay.toString(), value.canonicalString, enteredUnit, createdAtUTC.toString(), updatedAtUTC.toString())
internal fun BodyMeasurementEntity.domain() = BodyMeasurement(UUID.fromString(id), StudentID.parse(studentID), UUID.fromString(metricID), LocalDate.parse(localCalendarDay), DecimalValue.parse(value), enteredUnit, Instant.parse(createdAtUTC), Instant.parse(updatedAtUTC))
