package com.ignacioli.finecoach.storage.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Update
import com.ignacioli.finecoach.storage.entity.*
import java.util.UUID

@Dao
interface T008SessionDao {
    @Query("SELECT * FROM active_session_pointers ORDER BY `key`")
    fun pointers(): List<ActiveSessionPointerEntity>
    @Query("SELECT * FROM sessions WHERE state = 'inProgress'")
    fun activeSessions(): List<SessionEntity>
    @Query("DELETE FROM active_session_pointers WHERE `key` = :key")
    fun deletePointer(key: String)
    @Update
    fun update(row: SessionEntity): Int
    @Update
    fun update(row: TrainingTemplateEntity): Int
    @Query("DELETE FROM session_training_focus WHERE sessionID = :id")
    fun deleteSessionFocus(id: UUID)
    @Query("DELETE FROM training_sets WHERE sessionExerciseID IN (SELECT id FROM session_exercises WHERE sessionID = :id)")
    fun deleteSessionSets(id: UUID)
    @Query("DELETE FROM session_exercises WHERE sessionID = :id")
    fun deleteSessionExercises(id: UUID)
    @Query("DELETE FROM session_sections WHERE ownerKind = :kind AND ownerID = :id")
    fun deleteSections(kind: com.ignacioli.finecoach.core.domain.common.SessionSectionOwnerKind, id: UUID)
    @Query("SELECT id, name, revision, createdAtUTC, updatedAtUTC FROM training_templates")
    fun templates(): List<TrainingTemplateEntity>
    @Query("DELETE FROM template_training_focus WHERE templateID = :id")
    fun deleteTemplateFocus(id: UUID)
    @Query("DELETE FROM template_planned_sets WHERE templateExerciseID IN (SELECT id FROM template_exercises WHERE templateID = :id)")
    fun deletePlannedSets(id: UUID)
    @Query("DELETE FROM template_exercises WHERE templateID = :id")
    fun deleteTemplateExercises(id: UUID)
    @Query("DELETE FROM training_templates WHERE id = :id")
    fun deleteTemplate(id: UUID)
}
