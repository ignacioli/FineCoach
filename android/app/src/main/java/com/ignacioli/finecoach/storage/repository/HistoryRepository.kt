package com.ignacioli.finecoach.storage.repository

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.entity.SessionEntity
import java.time.ZoneId
import java.util.UUID

/** Calendar filtering and Instant ordering deliberately avoid SQLite TEXT timestamp ordering. */
class HistoryRepository(
    private val database: FineCoachDatabase,
    private val clock: AppClock,
    private val expectedGeneration: UUID,
    private val zoneID: ZoneId,
) : HistoryRepositoryPort, SessionSettlementNotePort {
    override suspend fun list(query: HistoryQuery): ApplicationResult<List<SessionHistoryRecord>> = transaction {
        val today = clock.today(zoneID)
        val firstDay = query.window?.let { today.minusDays(it.days.toLong() - 1) }
        database.t009HistoryDao().completedSessions().filter { row ->
            (query.studentID == null || row.studentID == query.studentID.t008UUID()) &&
                (firstDay == null || row.completedAtUTC!!.atZone(zoneID).toLocalDate().let { it >= firstDay && it <= today })
        }.mapNotNull { row ->
            val content = requireNotNull(loadSessionContent(database, SessionID.fromUUID(row.id)))
            if (content.toDomain().session.completedSetCount == 0) return@mapNotNull null
            if (query.trainingFocus.isNotEmpty() && content.session.trainingFocus.intersect(query.trainingFocus).isEmpty()) {
                return@mapNotNull null
            }
            if (query.exerciseIDs.isNotEmpty() && content.exercises.none { it.sourceID in query.exerciseIDs }) {
                return@mapNotNull null
            }
            projection(row)
        }.sortedWith(compareByDescending<SessionHistoryRecord> { it.completedAtUTC }.thenBy { it.sessionID.value })
    }

    override suspend fun detail(sessionID: SessionID): ApplicationResult<SessionHistoryRecord?> = transaction {
        val row = database.s1Dao().findSession(sessionID.t008UUID()) ?: return@transaction null
        if (row.state != SessionState.completed || row.completedAtUTC == null) return@transaction null
        val content = requireNotNull(loadSessionContent(database, sessionID))
        if (content.toDomain().session.completedSetCount == 0) null else projection(row)
    }

    override suspend fun updateTrainingFocus(command: UpdateHistoryTrainingFocusCommand): ApplicationResult<SessionHistoryRecord> = transaction {
        val row = requireCompleted(command.sessionID, command.expectedRevision)
        val original = sessionRecord(database, row)
        if (original.trainingFocus != command.trainingFocus) {
            val updated = original.toDomain().updatingTrainingFocus(command.trainingFocus, clock.now()).toRecord()
            updateSession(database, updated)
        }
        projection(requireNotNull(database.s1Dao().findSession(row.id)))
    }

    override suspend fun find(sessionID: SessionID): ApplicationResult<SessionSettlementNoteRecord?> = transaction {
        val row = database.s1Dao().findSession(sessionID.t008UUID()) ?: return@transaction null
        row.creditSettlementNote?.let { SessionSettlementNoteRecord(sessionID, SessionCreditSettlementNote.valueOf(it)) }
    }

    override suspend fun save(command: SaveSessionSettlementNoteCommand): ApplicationResult<SessionSettlementNoteRecord> = transaction {
        val row = requireCompleted(command.sessionID, command.expectedRevision)
        // A private billing annotation is separate from a training-content revision, matching iOS.
        if (row.creditSettlementNote != command.note.name) {
            check(database.t009HistoryDao().updateSettlementNote(row.id, command.note.name) == 1)
        }
        SessionSettlementNoteRecord(command.sessionID, command.note)
    }

    override suspend fun clear(sessionID: SessionID, expectedRevision: Revision): ApplicationResult<Unit> = transaction {
        val row = requireCompleted(sessionID, expectedRevision)
        if (row.creditSettlementNote != null) check(database.t009HistoryDao().updateSettlementNote(row.id, null) == 1)
    }

    private fun requireCompleted(id: SessionID, revision: Revision): SessionEntity {
        val row = database.s1Dao().findSession(id.t008UUID()) ?: trainingFailure(ApplicationErrorCode.notFound)
        if (row.state != SessionState.completed) trainingFailure(ApplicationErrorCode.invalidState)
        if (row.revision != revision.value.toString()) trainingFailure(ApplicationErrorCode.staleRevision)
        return row
    }

    private fun projection(row: SessionEntity): SessionHistoryRecord {
        val record = sessionRecord(database, row)
        return SessionHistoryRecord(record.sessionID, record.studentID, requireNotNull(record.completedAtUTC),
            record.trainingFocus, record.studentFacingSummary, record.privateCoachNote)
    }

    private suspend fun <T> transaction(action: () -> T) = trainingTransaction(database, expectedGeneration, action)
}
