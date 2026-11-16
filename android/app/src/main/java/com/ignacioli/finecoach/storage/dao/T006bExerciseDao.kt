package com.ignacioli.finecoach.storage.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.ignacioli.finecoach.core.domain.common.ExerciseClaimScope
import com.ignacioli.finecoach.storage.entity.*

@Dao
interface T006bExerciseDao {
    @Query("SELECT * FROM exercise_catalog ORDER BY canonicalName, id")
    fun catalog(): List<ExerciseCatalogEntity>

    @Query("SELECT * FROM exercise_preferences")
    fun preferences(): List<ExercisePreferenceEntity>

    @Query("SELECT * FROM exercise_name_claims")
    fun claims(): List<ExerciseNameClaimEntity>

    @Update
    fun update(row: ExerciseCatalogEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    fun save(row: ExercisePreferenceEntity)

    @Query("DELETE FROM exercise_name_claims WHERE ownerID = :ownerID AND scope = :scope")
    fun release(ownerID: String, scope: ExerciseClaimScope)

    @Query("DELETE FROM exercise_name_claims WHERE ownerID = :ownerID AND normalizedName = :name")
    fun releaseName(ownerID: String, name: String)
}
