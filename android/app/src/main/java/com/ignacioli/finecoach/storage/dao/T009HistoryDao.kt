package com.ignacioli.finecoach.storage.dao

import androidx.room.Dao
import androidx.room.Query
import com.ignacioli.finecoach.storage.entity.SessionEntity
import java.util.UUID

@Dao
interface T009HistoryDao {
    @Query("SELECT * FROM sessions WHERE state = 'completed' AND completedAtUTC IS NOT NULL")
    fun completedSessions(): List<SessionEntity>

    @Query("UPDATE sessions SET creditSettlementNote = :note WHERE id = :id")
    fun updateSettlementNote(id: UUID, note: String?): Int
}
