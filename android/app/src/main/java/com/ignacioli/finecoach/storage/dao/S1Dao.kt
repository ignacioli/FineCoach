package com.ignacioli.finecoach.storage.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.storage.entity.*
import java.util.UUID

// Blocking storage primitives. Repository callers supply the encompassing transaction
// for multi-row operations, disposition, revision CAS, and user-facing behavior.
@Dao
abstract class S1Dao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract fun insert(row: StudentEntity)

    @Query("SELECT * FROM students WHERE `id` = :id")
    abstract fun findStudent(id: UUID): StudentEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract fun insert(row: CoursePackageEntity)

    @Query("SELECT * FROM course_packages WHERE `id` = :id")
    abstract fun findCoursePackage(id: UUID): CoursePackageEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    protected abstract fun insertRaw(row: ActivePackageClaimEntity)

    @Query("SELECT * FROM active_package_claims WHERE `studentID` = :studentID")
    abstract fun findActivePackageClaim(studentID: UUID): ActivePackageClaimEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract fun insert(row: CreditAdjustmentEntity)

    @Query("SELECT * FROM credit_adjustments WHERE `id` = :id")
    abstract fun findCreditAdjustment(id: UUID): CreditAdjustmentEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract fun insert(row: SessionEntity)

    @Query("SELECT * FROM sessions WHERE `id` = :id")
    abstract fun findSession(id: UUID): SessionEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    protected abstract fun insertRaw(row: ActiveSessionPointerEntity)

    @Query("SELECT * FROM active_session_pointers WHERE `key` = :key")
    abstract fun findActiveSessionPointer(key: String): ActiveSessionPointerEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract fun insert(row: SessionTrainingFocusEntity)

    @Query("SELECT * FROM session_training_focus WHERE `sessionID` = :sessionID AND `bodyPart` = :bodyPart")
    abstract fun findSessionTrainingFocus(sessionID: UUID, bodyPart: BodyPart): SessionTrainingFocusEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    protected abstract fun insertRaw(row: SessionExerciseEntity)

    @Query("SELECT * FROM session_exercises WHERE `id` = :id")
    abstract fun findSessionExercise(id: UUID): SessionExerciseEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract fun insert(row: TrainingSetEntity)

    @Query("SELECT * FROM training_sets WHERE `id` = :id")
    abstract fun findTrainingSet(id: UUID): TrainingSetEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract fun insert(row: TrainingTemplateEntity)

    @Query("SELECT id, name, revision, createdAtUTC, updatedAtUTC FROM training_templates WHERE `id` = :id")
    abstract fun findTrainingTemplate(id: UUID): TrainingTemplateEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract fun insert(row: TemplateTrainingFocusEntity)

    @Query("SELECT * FROM template_training_focus WHERE `templateID` = :templateID AND `bodyPart` = :bodyPart")
    abstract fun findTemplateTrainingFocus(templateID: UUID, bodyPart: BodyPart): TemplateTrainingFocusEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    protected abstract fun insertRaw(row: TemplateExerciseEntity)

    @Query("SELECT * FROM template_exercises WHERE `id` = :id")
    abstract fun findTemplateExercise(id: UUID): TemplateExerciseEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract fun insert(row: TemplatePlannedSetEntity)

    @Query("SELECT * FROM template_planned_sets WHERE `templateExerciseID` = :templateExerciseID AND `position` = :position")
    abstract fun findTemplatePlannedSet(templateExerciseID: UUID, position: Long): TemplatePlannedSetEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    protected abstract fun insertRaw(row: SessionSectionEntity)

    @Query("SELECT * FROM session_sections WHERE `id` = :id")
    abstract fun findSessionSection(id: UUID): SessionSectionEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract fun insert(row: ExerciseCatalogEntity)

    @Query("SELECT * FROM exercise_catalog WHERE `id` = :id")
    abstract fun findExerciseCatalog(id: String): ExerciseCatalogEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract fun insert(row: ExercisePreferenceEntity)

    @Query("SELECT * FROM exercise_preferences WHERE `exerciseID` = :exerciseID")
    abstract fun findExercisePreference(exerciseID: String): ExercisePreferenceEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract fun insert(row: ExerciseNameClaimEntity)

    @Query("SELECT * FROM exercise_name_claims WHERE `normalizedName` = :normalizedName")
    abstract fun findExerciseNameClaim(normalizedName: String): ExerciseNameClaimEntity?

    @Query("SELECT * FROM session_exercises WHERE sessionID = :sessionID ORDER BY orderIndex")
    abstract fun sessionExercises(sessionID: UUID): List<SessionExerciseEntity>

    @Query("SELECT * FROM training_sets WHERE sessionExerciseID = :exerciseID ORDER BY orderIndex")
    abstract fun trainingSets(exerciseID: UUID): List<TrainingSetEntity>

    @Query("SELECT * FROM template_exercises WHERE templateID = :templateID ORDER BY orderIndex")
    abstract fun templateExercises(templateID: UUID): List<TemplateExerciseEntity>

    @Query("SELECT t.id AS templateID, COUNT(e.id) AS exerciseCount FROM training_templates t LEFT JOIN template_exercises e ON e.templateID = t.id GROUP BY t.id")
    abstract fun templateExerciseCounts(): List<TemplateExerciseCount>

    @Query("SELECT * FROM template_planned_sets WHERE templateExerciseID = :exerciseID ORDER BY position")
    abstract fun plannedSets(exerciseID: UUID): List<TemplatePlannedSetEntity>

    @Query("SELECT * FROM session_sections WHERE ownerKind = :kind AND ownerID = :ownerID ORDER BY orderIndex")
    abstract fun sections(kind: SessionSectionOwnerKind, ownerID: UUID): List<SessionSectionEntity>

    @Query("SELECT * FROM session_training_focus WHERE sessionID = :sessionID")
    abstract fun sessionFocus(sessionID: UUID): List<SessionTrainingFocusEntity>

    @Query("SELECT * FROM template_training_focus WHERE templateID = :templateID")
    abstract fun templateFocus(templateID: UUID): List<TemplateTrainingFocusEntity>

    @Query("SELECT COUNT(*) FROM session_sections WHERE ownerKind = :kind AND ownerID = :ownerID AND orderIndex = :position")
    protected abstract fun sectionAt(kind: SessionSectionOwnerKind, ownerID: UUID, position: Long): Int

    @Query("SELECT COUNT(*) FROM session_exercises WHERE sessionID = :ownerID AND orderIndex = :position")
    protected abstract fun sessionExerciseAt(ownerID: UUID, position: Long): Int

    @Query("SELECT COUNT(*) FROM template_exercises WHERE templateID = :ownerID AND orderIndex = :position")
    protected abstract fun templateExerciseAt(ownerID: UUID, position: Long): Int

    @Transaction
    open fun insert(row: ActiveSessionPointerEntity) {
        val session = requireNotNull(findSession(row.sessionID)) { "Pointer session missing" }
        require(session.studentID.toString() == row.key && session.state == SessionState.inProgress) {
            "Pointer must reference the same student's inProgress session"
        }
        insertRaw(row)
    }

    @Transaction
    open fun insert(row: ActivePackageClaimEntity) {
        val coursePackage = requireNotNull(findCoursePackage(row.packageID)) { "Claim package missing" }
        require(coursePackage.studentID == row.studentID && coursePackage.status == CoursePackageStatus.active) {
            "Claim must reference the same student's active package"
        }
        insertRaw(row)
    }

    @Transaction
    open fun insert(row: SessionSectionEntity) {
        when (row.ownerKind) {
            SessionSectionOwnerKind.session -> {
                requireNotNull(findSession(row.ownerID)) { "Section owner missing" }
                require(sessionExerciseAt(row.ownerID, row.orderIndex) == 0) { "Occupied order index" }
            }
            SessionSectionOwnerKind.template -> {
                requireNotNull(findTrainingTemplate(row.ownerID)) { "Section owner missing" }
                require(templateExerciseAt(row.ownerID, row.orderIndex) == 0) { "Occupied order index" }
            }
        }
        insertRaw(row)
    }

    @Transaction
    open fun insert(row: SessionExerciseEntity) {
        requireNotNull(findSession(row.sessionID)) { "Exercise owner missing" }
        validateSection(row.sectionID, SessionSectionOwnerKind.session, row.sessionID)
        require(sectionAt(SessionSectionOwnerKind.session, row.sessionID, row.orderIndex) == 0) { "Occupied order index" }
        insertRaw(row)
    }

    @Transaction
    open fun insert(row: TemplateExerciseEntity) {
        requireNotNull(findTrainingTemplate(row.templateID)) { "Exercise owner missing" }
        validateSection(row.sectionID, SessionSectionOwnerKind.template, row.templateID)
        require(sectionAt(SessionSectionOwnerKind.template, row.templateID, row.orderIndex) == 0) { "Occupied order index" }
        insertRaw(row)
    }

    private fun validateSection(sectionID: UUID?, kind: SessionSectionOwnerKind, ownerID: UUID) {
        if (sectionID == null) return
        val section = requireNotNull(findSessionSection(sectionID)) { "Section missing" }
        require(section.ownerKind == kind && section.ownerID == ownerID) { "Section owner mismatch" }
    }
}

data class TemplateExerciseCount(val templateID: UUID, val exerciseCount: Int)
