package com.ignacioli.finecoach.storage.dao

import androidx.room.*
import com.ignacioli.finecoach.storage.entity.*

@Dao
interface AppointmentDao {
    @Query("SELECT * FROM appointments ORDER BY date, startTime, id") fun all(): List<AppointmentEntity>
    @Query("SELECT * FROM appointments WHERE id = :id") fun find(id: String): AppointmentEntity?
    @Query("SELECT * FROM recurrence_series WHERE id = :id") fun series(id: String): RecurrenceSeriesEntity?
    @Insert fun insert(row: AppointmentEntity)
    @Insert fun insert(row: RecurrenceSeriesEntity)
    @Update fun update(row: AppointmentEntity): Int
    @Update fun update(row: RecurrenceSeriesEntity): Int
    @Query("DELETE FROM appointments WHERE id = :id") fun delete(id: String): Int
    @Query("UPDATE sessions SET appointmentID = :appointmentID WHERE id = :sessionID AND (:appointmentID IS NULL OR appointmentID IS NULL OR appointmentID = :appointmentID)")
    fun linkSession(sessionID: String, appointmentID: String?): Int
    @Query("SELECT * FROM appointments WHERE linkedSessionID = :sessionID") fun forSession(sessionID: String): AppointmentEntity?
}
