package com.ignacioli.finecoach.core.application

import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.core.domain.progress.SessionGains
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** One history snapshot feeds both gains and the existing last-performance lookup. */
class ProgressUseCases(private val history: HistoryRepositoryPort, private val sessions: SessionRepositoryPort) {
    data class Snapshot(val completed: List<CompletedSession>, val last: LastExercisePerformanceLookup)
    suspend fun load(studentID: StudentID, displayName: NormalizedName): ApplicationResult<Snapshot> = withContext(Dispatchers.IO) {
        val rows = when (val result = history.list(HistoryQuery(studentID = studentID))) {
            is ApplicationResult.Failure -> return@withContext result
            is ApplicationResult.Success -> result.value
        }
        val domain = mutableListOf<Session>()
        for (row in rows) {
            val content = when (val result = sessions.loadContent(row.sessionID)) {
                is ApplicationResult.Failure -> return@withContext result
                is ApplicationResult.Success -> result.value ?: return@withContext ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.notFound))
            }
            try { domain += content.toDomain().session } catch (e: DomainException) {
                return@withContext ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.valueOf(e.error.name)))
            } catch (_: IllegalArgumentException) {
                return@withContext ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.incompatibleInput))
            }
        }
        val completed = domain.map { CompletedSession.make(it, displayName) }.sortedWith(SessionGains.completedOrder)
        ApplicationResult.Success(Snapshot(completed, LastExercisePerformanceLookup(domain)))
    }
    fun gains(current: Session, snapshot: Snapshot, zone: ZoneId, assisted: Set<StableExerciseID> = emptySet()) =
        SessionGains.evaluate(current, snapshot.completed, zone, assisted)
}
