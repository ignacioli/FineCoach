package com.ignacioli.finecoach.storage

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.ignacioli.finecoach.storage.dao.S1Dao
import com.ignacioli.finecoach.storage.entity.*
import com.ignacioli.finecoach.storage.value.StorageValueConverters

@Database(
    entities = [
        StoreMetadata::class,
        StudentEntity::class,
        CoursePackageEntity::class,
        ActivePackageClaimEntity::class,
        CreditAdjustmentEntity::class,
        SessionEntity::class,
        ActiveSessionPointerEntity::class,
        SessionTrainingFocusEntity::class,
        SessionExerciseEntity::class,
        TrainingSetEntity::class,
        TrainingTemplateEntity::class,
        TemplateTrainingFocusEntity::class,
        TemplateExerciseEntity::class,
        TemplatePlannedSetEntity::class,
        SessionSectionEntity::class,
        ExerciseCatalogEntity::class,
        ExercisePreferenceEntity::class,
        ExerciseNameClaimEntity::class,
    ],
    version = 2,
    exportSchema = true,
)
@TypeConverters(StorageValueConverters::class)
abstract class FineCoachDatabase : RoomDatabase() {
    abstract fun storeMetadataDao(): StoreMetadataDao
    abstract fun s1Dao(): S1Dao
    abstract fun t006aStudentDao(): com.ignacioli.finecoach.storage.dao.T006aStudentDao
    abstract fun t006bExerciseDao(): com.ignacioli.finecoach.storage.dao.T006bExerciseDao
    abstract fun t007PackageDao(): com.ignacioli.finecoach.storage.dao.T007PackageDao
    abstract fun t008SessionDao(): com.ignacioli.finecoach.storage.dao.T008SessionDao
    abstract fun t009HistoryDao(): com.ignacioli.finecoach.storage.dao.T009HistoryDao
}
