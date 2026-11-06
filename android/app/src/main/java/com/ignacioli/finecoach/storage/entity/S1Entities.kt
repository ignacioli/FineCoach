package com.ignacioli.finecoach.storage.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import com.ignacioli.finecoach.core.domain.common.*
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

// Storage primitives map to the frozen application records; they are not wire DTOs.
// Scalar claims, pointers, sections and catalog snapshots intentionally have no FK.

@Entity(
    tableName = "students",
    primaryKeys = ["id"],
    indices = [
        Index(value = ["lifecycle"]),
    ],
)
data class StudentEntity(
    val id: UUID,
    val displayName: String,
    val sex: StudentSex,
    val trainingGoal: String?,
    val injuryNotes: String?,
    val privateCoachNote: String?,
    val phone: String?,
    val wechatID: String?,
    val lifecycle: StudentLifecycle,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
) {
    init {
        storedName(displayName)
        storedOptionalText(trainingGoal)
        storedOptionalText(injuryNotes)
        storedOptionalText(privateCoachNote)
        storedOptionalText(phone)
        storedOptionalText(wechatID)
    }
}

@Entity(
    tableName = "course_packages",
    primaryKeys = ["id"],
    indices = [
        Index(value = ["studentID"]),
    ],
)
data class CoursePackageEntity(
    val id: UUID,
    val studentID: UUID,
    val name: String?,
    val totalCredits: Long,
    val remainingCreditsCache: Long,
    val startDate: LocalDate?,
    val endDate: LocalDate?,
    val status: CoursePackageStatus,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
) {
    init {
        require(totalCredits > 0)
        storedOptionalText(name)
    }
}

@Entity(
    tableName = "active_package_claims",
    primaryKeys = ["studentID"],
    indices = [
        Index(value = ["packageID"]),
    ],
)
data class ActivePackageClaimEntity(
    val studentID: UUID,
    val packageID: UUID,
)

@Entity(
    tableName = "credit_adjustments",
    primaryKeys = ["id"],
    indices = [
        Index(value = ["packageID"]),
        Index(value = ["sourceEventKey"], unique = true),
    ],
    foreignKeys = [
        ForeignKey(entity = CoursePackageEntity::class, parentColumns = ["id"],
            childColumns = ["packageID"], onDelete = ForeignKey.NO_ACTION, onUpdate = ForeignKey.NO_ACTION),
    ],
)
data class CreditAdjustmentEntity(
    val id: UUID,
    val packageID: UUID,
    val direction: CreditDirection,
    val amount: Long,
    val reasonKind: CreditReasonKind,
    val reasonText: String?,
    val linkedSessionID: UUID?,
    val linkedAppointmentID: UUID?,
    val sourceEventKey: String,
    val createdAtUTC: Instant,
) {
    init {
        require(amount > 0)
        storedOptionalText(reasonText)
        require(reasonKind != CreditReasonKind.manualCorrection || reasonText != null)
        require(SourceEventKey.parse(sourceEventKey).value == sourceEventKey)
    }
}

@Entity(
    tableName = "sessions",
    primaryKeys = ["id"],
    indices = [
        Index(value = ["studentID"]),
        Index(value = ["state"]),
    ],
    foreignKeys = [
        ForeignKey(entity = StudentEntity::class, parentColumns = ["id"],
            childColumns = ["studentID"], onDelete = ForeignKey.NO_ACTION, onUpdate = ForeignKey.NO_ACTION),
    ],
)
data class SessionEntity(
    val id: UUID,
    val studentID: UUID,
    val state: SessionState,
    val startedAtUTC: Instant,
    val lastCheckpointUTC: Instant,
    val elapsedSeconds: BigDecimal,
    val interruptionStartedAtUTC: Instant?,
    val durationNeedsReview: Boolean,
    val coachAdjustedDurationSeconds: BigDecimal?,
    val studentFacingSummary: String?,
    val privateCoachNote: String?,
    val revision: String,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
    val completedAtUTC: Instant?,
    val appointmentID: UUID?,
    val creditSettlementNote: String?,
) {
    init {
        storedRevision(revision)
        storedOptionalText(studentFacingSummary)
        storedOptionalText(privateCoachNote)
        require(creditSettlementNote == null || creditSettlementNote == "noActivePackage")
    }
}

@Entity(
    tableName = "active_session_pointers",
    primaryKeys = ["key"],
    indices = [
        Index(value = ["sessionID"], unique = true),
    ],
)
data class ActiveSessionPointerEntity(
    val key: String,
    val sessionID: UUID,
) {
    init {
        require(UUID.fromString(key).toString() == key)
    }
}

@Entity(
    tableName = "session_training_focus",
    primaryKeys = ["sessionID", "bodyPart"],
    foreignKeys = [
        ForeignKey(entity = SessionEntity::class, parentColumns = ["id"],
            childColumns = ["sessionID"], onDelete = ForeignKey.NO_ACTION, onUpdate = ForeignKey.NO_ACTION),
    ],
)
data class SessionTrainingFocusEntity(
    val sessionID: UUID,
    val bodyPart: BodyPart,
)

@Entity(
    tableName = "session_exercises",
    primaryKeys = ["id"],
    indices = [
        Index(value = ["sessionID", "orderIndex"], unique = true),
        Index(value = ["sectionID"]),
    ],
    foreignKeys = [
        ForeignKey(entity = SessionEntity::class, parentColumns = ["id"],
            childColumns = ["sessionID"], onDelete = ForeignKey.NO_ACTION, onUpdate = ForeignKey.NO_ACTION),
    ],
)
data class SessionExerciseEntity(
    val id: UUID,
    val sessionID: UUID,
    val orderIndex: Long,
    val sourceKind: ExerciseSourceKind,
    val sourceID: String?,
    val displayNameSnapshot: String,
    val recordModeSnapshot: RecordMode,
    val actionPrivateNote: String?,
    val sectionID: UUID?,
) {
    init {
        storedOrder(orderIndex)
        storedName(displayNameSnapshot)
        storedOptionalText(actionPrivateNote)
        sourceID?.let { storedExerciseID(it) }
    }
}

@Entity(
    tableName = "training_sets",
    primaryKeys = ["id"],
    indices = [
        Index(value = ["sessionExerciseID", "orderIndex"], unique = true),
    ],
    foreignKeys = [
        ForeignKey(entity = SessionExerciseEntity::class, parentColumns = ["id"],
            childColumns = ["sessionExerciseID"], onDelete = ForeignKey.NO_ACTION, onUpdate = ForeignKey.NO_ACTION),
    ],
)
data class TrainingSetEntity(
    val id: UUID,
    val sessionExerciseID: UUID,
    val orderIndex: Long,
    val state: SetRecordingState,
    val recordMode: RecordMode,
    val weightValue: BigDecimal?,
    val repetitionCount: BigDecimal?,
    val durationSeconds: BigDecimal?,
    val leftValue: BigDecimal?,
    val rightValue: BigDecimal?,
    val distanceValue: BigDecimal?,
    val speedValue: BigDecimal?,
    val resistanceValue: BigDecimal?,
    val unit: MeasurementUnit,
    val side: SetSide,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
    val completedAtUTC: Instant?,
) {
    init {
        storedOrder(orderIndex)
    }
}

@Entity(
    tableName = "training_templates",
    primaryKeys = ["id"],
)
data class TrainingTemplateEntity(
    val id: UUID,
    val name: String,
    val revision: String = "0",
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
) {
    init {
        storedName(name)
        storedRevision(revision)
    }
}

@Entity(
    tableName = "template_training_focus",
    primaryKeys = ["templateID", "bodyPart"],
    foreignKeys = [
        ForeignKey(entity = TrainingTemplateEntity::class, parentColumns = ["id"],
            childColumns = ["templateID"], onDelete = ForeignKey.NO_ACTION, onUpdate = ForeignKey.NO_ACTION),
    ],
)
data class TemplateTrainingFocusEntity(
    val templateID: UUID,
    val bodyPart: BodyPart,
)

@Entity(
    tableName = "template_exercises",
    primaryKeys = ["id"],
    indices = [
        Index(value = ["templateID", "orderIndex"], unique = true),
        Index(value = ["sectionID"]),
    ],
    foreignKeys = [
        ForeignKey(entity = TrainingTemplateEntity::class, parentColumns = ["id"],
            childColumns = ["templateID"], onDelete = ForeignKey.NO_ACTION, onUpdate = ForeignKey.NO_ACTION),
    ],
)
data class TemplateExerciseEntity(
    val id: UUID,
    val templateID: UUID,
    val sectionID: UUID?,
    val orderIndex: Long,
    val sourceKind: ExerciseSourceKind,
    val sourceID: String?,
    val displayNameSnapshot: String,
    val recordModeSnapshot: RecordMode,
) {
    init {
        storedOrder(orderIndex)
        storedName(displayNameSnapshot)
        sourceID?.let { storedExerciseID(it) }
    }
}

@Entity(
    tableName = "template_planned_sets",
    primaryKeys = ["templateExerciseID", "position"],
    foreignKeys = [
        ForeignKey(entity = TemplateExerciseEntity::class, parentColumns = ["id"],
            childColumns = ["templateExerciseID"], onDelete = ForeignKey.NO_ACTION, onUpdate = ForeignKey.NO_ACTION),
    ],
)
data class TemplatePlannedSetEntity(
    val templateExerciseID: UUID,
    val position: Long,
    val recordMode: RecordMode,
    val unit: MeasurementUnit,
    val side: SetSide,
    val weightValue: BigDecimal?,
    val repetitionCount: BigDecimal?,
    val durationSeconds: BigDecimal?,
    val leftValue: BigDecimal?,
    val rightValue: BigDecimal?,
    val distanceValue: BigDecimal?,
    val speedValue: BigDecimal?,
    val resistanceValue: BigDecimal?,
) {
    init {
        storedOrder(position)
    }
}

@Entity(
    tableName = "session_sections",
    primaryKeys = ["id"],
    indices = [
        Index(value = ["ownerKind", "ownerID", "orderIndex"], unique = true),
    ],
)
data class SessionSectionEntity(
    val id: UUID,
    val ownerKind: SessionSectionOwnerKind,
    val ownerID: UUID,
    val name: String,
    val orderIndex: Long,
) {
    init {
        storedName(name)
        storedOrder(orderIndex)
    }
}

@Entity(
    tableName = "exercise_catalog",
    primaryKeys = ["id"],
    indices = [
        Index(value = ["normalizedName"]),
    ],
)
data class ExerciseCatalogEntity(
    val id: String,
    val kind: ExerciseKind,
    val canonicalName: String,
    val normalizedName: String,
    val recordMode: RecordMode,
    val metadataVersion: String,
    val lifecycle: ExerciseLifecycle,
    val isRetired: Boolean,
    val provenanceRef: String?,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
) {
    init {
        storedExerciseID(id)
        storedName(canonicalName)
        require(normalizedName == canonicalName)
        require((kind == ExerciseKind.builtIn) == (provenanceRef != null))
    }
}

@Entity(
    tableName = "exercise_preferences",
    primaryKeys = ["exerciseID"],
)
data class ExercisePreferenceEntity(
    val exerciseID: String,
    val alias: String?,
    val isFavorite: Boolean,
    val isHidden: Boolean,
    val isAssisted: Boolean,
    val isUnilateral: Boolean?,
) {
    init {
        storedExerciseID(exerciseID)
        alias?.let { storedName(it) }
    }
}

@Entity(
    tableName = "exercise_name_claims",
    primaryKeys = ["normalizedName"],
    indices = [
        Index(value = ["ownerKind", "ownerID"]),
    ],
)
data class ExerciseNameClaimEntity(
    val normalizedName: String,
    val ownerKind: ExerciseSourceKind,
    val ownerID: String,
    val scope: ExerciseClaimScope,
) {
    init {
        storedName(normalizedName)
        storedExerciseID(ownerID)
    }
}

private fun storedName(value: String) {
    require(NormalizedName.parse(value).value == value) { "Non-canonical name" }
}

private fun storedOptionalText(value: String?) {
    require(ValidatedText.optional(value)?.value == value) { "Non-canonical optional text" }
}

private fun storedExerciseID(value: String) {
    require(StableExerciseID.parse(value).value == value) { "Non-canonical exercise ID" }
}

private fun storedOrder(value: Long) {
    require(value in 0L..4294967295L) { "Order outside UInt32 range" }
}

private fun storedRevision(value: String) {
    require(value.toULong().toString() == value) { "Non-canonical UInt64 revision" }
}
