package com.ignacioli.finecoach.storage.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Update
import com.ignacioli.finecoach.storage.entity.StudentEntity
import java.util.UUID

@Dao
interface T006aStudentDao {
    @Query("SELECT * FROM students WHERE :includeArchived OR lifecycle = 'active'")
    fun list(includeArchived: Boolean): List<StudentEntity>

    @Update
    fun update(row: StudentEntity): Int

    @Query("SELECT EXISTS(SELECT 1 FROM sessions WHERE studentID = :id AND state = 'inProgress')")
    fun hasInProgressSession(id: UUID): Boolean

    @Query("DELETE FROM appointments WHERE studentID = :id")
    fun deleteAppointments(id: UUID)

    @Query("DELETE FROM recurrence_series WHERE studentID = :id")
    fun deleteRecurrenceSeries(id: UUID)

    @Query("DELETE FROM training_sets WHERE sessionExerciseID IN (SELECT id FROM session_exercises WHERE sessionID IN (SELECT id FROM sessions WHERE studentID = :id))")
    fun deleteSets(id: UUID)

    @Query("DELETE FROM session_exercises WHERE sessionID IN (SELECT id FROM sessions WHERE studentID = :id)")
    fun deleteExercises(id: UUID)

    @Query("DELETE FROM session_training_focus WHERE sessionID IN (SELECT id FROM sessions WHERE studentID = :id)")
    fun deleteFocus(id: UUID)

    @Query("DELETE FROM sessions WHERE studentID = :id")
    fun deleteSessions(id: UUID)

    @Query("DELETE FROM store_metadata WHERE `key` = :key")
    fun deleteArchiveIdentity(key: String)

    @Query("DELETE FROM students WHERE id = :id")
    fun deleteStudent(id: UUID)
}
