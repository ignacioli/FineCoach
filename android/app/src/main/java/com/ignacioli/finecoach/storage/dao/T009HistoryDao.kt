package com.ignacioli.finecoach.storage.dao

import androidx.room.Dao
import androidx.room.Query
import com.ignacioli.finecoach.storage.entity.SessionEntity
import java.time.Instant
import java.util.UUID

data class RecentSessionCandidate(val id: UUID, val completedAtUTC: Instant)

@Dao
interface T009HistoryDao {
    @Query("SELECT * FROM sessions WHERE state = 'completed' AND completedAtUTC IS NOT NULL")
    fun completedSessions(): List<SessionEntity>

    // Match History.list's completed-set gate without materializing every session's content.
    @Query("""SELECT s.id, s.completedAtUTC FROM sessions s
        WHERE s.state = 'completed' AND s.completedAtUTC IS NOT NULL
        AND (:studentID IS NULL OR s.studentID = :studentID)
        AND EXISTS (SELECT 1 FROM session_exercises e
            INNER JOIN training_sets t ON t.sessionExerciseID = e.id
            WHERE e.sessionID = s.id AND t.state = 'completed')""")
    fun recentCandidates(studentID: UUID?): List<RecentSessionCandidate>

    @Query("UPDATE sessions SET creditSettlementNote = :note WHERE id = :id")
    fun updateSettlementNote(id: UUID, note: String?): Int
}
