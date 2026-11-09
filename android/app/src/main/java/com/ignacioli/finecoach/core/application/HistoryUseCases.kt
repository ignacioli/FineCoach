package com.ignacioli.finecoach.core.application

import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.SessionStatistics

enum class HistoryEmptyState { noHistory, noMatches }
data class HistoryListResult(val records: List<SessionHistoryRecord>, val emptyState: HistoryEmptyState?)

/** Coach-only local detail. Private notes and billing annotations are not share/export payloads. */
data class HistoryDetail(
    val content: SessionContentRecord,
    val statistics: SessionStatistics,
    val creditNote: SessionSettlementNoteRecord?,
)

class HistoryUseCases(
    private val history: HistoryRepositoryPort,
    private val sessions: SessionRepositoryPort,
    private val notes: SessionSettlementNotePort,
    private val clock: AppClock,
) {
    suspend fun list(query: HistoryQuery): ApplicationResult<HistoryListResult> = settlementValidation {
        val records = when (val result = history.list(query)) {
            is ApplicationResult.Failure -> return@settlementValidation result
            is ApplicationResult.Success -> result.value
        }
        if (records.isNotEmpty()) return@settlementValidation ApplicationResult.Success(HistoryListResult(records, null))
        val all = when (val result = history.list(HistoryQuery(studentID = query.studentID))) {
            is ApplicationResult.Failure -> return@settlementValidation result
            is ApplicationResult.Success -> result.value
        }
        ApplicationResult.Success(HistoryListResult(records, if (all.isEmpty()) HistoryEmptyState.noHistory else HistoryEmptyState.noMatches))
    }

    suspend fun clearFilters(studentID: StudentID? = null) = list(HistoryQuery(studentID = studentID))

    suspend fun detail(id: SessionID): ApplicationResult<HistoryDetail> = settlementValidation {
        when (val result = history.detail(id)) {
            is ApplicationResult.Failure -> return@settlementValidation result
            is ApplicationResult.Success -> if (result.value == null) trainingFailure(ApplicationErrorCode.notFound)
        }
        val content = when (val loaded = sessions.loadContent(id)) {
            is ApplicationResult.Failure -> return@settlementValidation loaded
            is ApplicationResult.Success -> loaded.value ?: trainingFailure(ApplicationErrorCode.notFound)
        }
        val note = when (val result = notes.find(id)) {
            is ApplicationResult.Failure -> return@settlementValidation result
            is ApplicationResult.Success -> result.value
        }
        ApplicationResult.Success(HistoryDetail(content, content.toDomain().session.statistics, note))
    }

    suspend fun saveSummary(command: SaveCompletedSessionSummaryCommand): ApplicationResult<SessionRecord> = settlementValidation {
        sessions.saveCompletedSummary(command.copy(savedAtUTC = clock.now()))
    }

    /** The historical editor exposes focus only; no dependency on credit settlement. */
    suspend fun saveFocusEdit(command: UpdateHistoryTrainingFocusCommand): ApplicationResult<SessionHistoryRecord> = settlementValidation {
        history.updateTrainingFocus(command)
    }
}
