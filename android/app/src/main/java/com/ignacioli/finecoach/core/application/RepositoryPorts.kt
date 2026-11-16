package com.ignacioli.finecoach.core.application

import com.ignacioli.finecoach.core.domain.common.BodyPart
import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.CoursePackageStatus
import com.ignacioli.finecoach.core.domain.common.CreditAdjustmentID
import com.ignacioli.finecoach.core.domain.common.CreditDirection
import com.ignacioli.finecoach.core.domain.common.CreditReasonKind
import com.ignacioli.finecoach.core.domain.common.ExerciseClaimScope
import com.ignacioli.finecoach.core.domain.common.ExerciseKind
import com.ignacioli.finecoach.core.domain.common.ExerciseLifecycle
import com.ignacioli.finecoach.core.domain.common.ExerciseSourceKind
import com.ignacioli.finecoach.core.domain.common.MeasurementUnit
import com.ignacioli.finecoach.core.domain.common.RecordMode
import com.ignacioli.finecoach.core.domain.common.Revision
import com.ignacioli.finecoach.core.domain.common.SectionID
import com.ignacioli.finecoach.core.domain.common.SessionExerciseID
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.SessionSectionOwnerKind
import com.ignacioli.finecoach.core.domain.common.SessionState
import com.ignacioli.finecoach.core.domain.common.SetRecordingState
import com.ignacioli.finecoach.core.domain.common.SetSide
import com.ignacioli.finecoach.core.domain.common.SourceEventKey
import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.StudentLifecycle
import com.ignacioli.finecoach.core.domain.common.StudentSex
import com.ignacioli.finecoach.core.domain.common.TemplateID
import com.ignacioli.finecoach.core.domain.common.TemplateExerciseID
import com.ignacioli.finecoach.core.domain.common.TrainingSetID
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate

data class StudentRecord(
    val studentID: StudentID,
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
)

data class StudentQuery(
    val includeArchived: Boolean = false,
    val searchText: String? = null,
)

data class CoursePackageRecord(
    val coursePackageID: CoursePackageID,
    val studentID: StudentID,
    val name: String?,
    val totalCredits: Long,
    val remainingCreditsCache: Long,
    val startDate: LocalDate?,
    val endDate: LocalDate?,
    val status: CoursePackageStatus,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
)

data class CreditAdjustmentRecord(
    val creditAdjustmentID: CreditAdjustmentID,
    val coursePackageID: CoursePackageID,
    val direction: CreditDirection,
    val amount: Long,
    val reasonKind: CreditReasonKind,
    val reasonText: String?,
    val linkedSessionID: SessionID?,
    val linkedAppointmentID: String?,
    val sourceEventKey: SourceEventKey,
    val createdAtUTC: Instant,
)

data class ExerciseRecord(
    val exerciseID: StableExerciseID,
    val kind: ExerciseKind,
    val canonicalName: String,
    val recordMode: RecordMode,
    val metadataVersion: String,
    val lifecycle: ExerciseLifecycle,
    val isRetired: Boolean,
    val provenanceRef: String?,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
)

data class ExercisePreferenceRecord(
    val exerciseID: StableExerciseID,
    val alias: String?,
    val isFavorite: Boolean,
    val isHidden: Boolean,
    val isAssisted: Boolean,
    val isUnilateral: Boolean?,
)

data class SessionRecord(
    val sessionID: SessionID,
    val studentID: StudentID,
    val state: SessionState,
    val startedAtUTC: Instant,
    val lastCheckpointUTC: Instant,
    val elapsedSeconds: BigDecimal,
    val interruptionStartedAtUTC: Instant?,
    val durationNeedsReview: Boolean,
    val coachAdjustedDurationSeconds: BigDecimal?,
    val trainingFocus: Set<BodyPart>,
    val studentFacingSummary: String?,
    val privateCoachNote: String?,
    val revision: Revision,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
    val completedAtUTC: Instant?,
)

data class TemplateRecord(
    val templateID: TemplateID,
    val name: String,
    val trainingFocus: Set<BodyPart>,
    val revision: Revision,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
)

data class SectionRecord(
    val sectionID: SectionID,
    val ownerKind: SessionSectionOwnerKind,
    val ownerSessionID: SessionID?,
    val ownerTemplateID: TemplateID?,
    val name: String,
    val orderIndex: UInt,
) {
    init {
        when (ownerKind) {
            SessionSectionOwnerKind.session -> require(ownerSessionID != null && ownerTemplateID == null)
            SessionSectionOwnerKind.template -> require(ownerTemplateID != null && ownerSessionID == null)
        }
    }
}

data class TrainingSetRecord(
    val trainingSetID: TrainingSetID,
    val sessionExerciseID: SessionExerciseID,
    val orderIndex: UInt,
    val state: SetRecordingState,
    val recordMode: RecordMode,
    val weightValue: BigDecimal?,
    val repetitionCount: BigDecimal?,
    val durationSeconds: BigDecimal?,
    val unit: MeasurementUnit,
    val side: SetSide,
    val leftValue: BigDecimal?,
    val rightValue: BigDecimal?,
    val distanceValue: BigDecimal?,
    val speedValue: BigDecimal?,
    val resistanceValue: BigDecimal?,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
    val completedAtUTC: Instant?,
)

data class SessionExerciseRecord(
    val sessionExerciseID: SessionExerciseID,
    val sessionID: SessionID,
    val orderIndex: UInt,
    val sourceKind: ExerciseSourceKind,
    val sourceID: StableExerciseID?,
    val displayNameSnapshot: String,
    val recordModeSnapshot: RecordMode,
    val actionPrivateNote: String?,
    val sectionID: SectionID?,
    val sets: List<TrainingSetRecord>,
)

data class TemplatePlannedSetRecord(
    val recordMode: RecordMode,
    val weightValue: BigDecimal?,
    val repetitionCount: BigDecimal?,
    val durationSeconds: BigDecimal?,
    val unit: MeasurementUnit,
    val side: SetSide,
    val leftValue: BigDecimal?,
    val rightValue: BigDecimal?,
    val distanceValue: BigDecimal?,
    val speedValue: BigDecimal?,
    val resistanceValue: BigDecimal?,
)

data class TemplateExerciseRecord(
    val templateExerciseID: TemplateExerciseID,
    val templateID: TemplateID,
    val sectionID: SectionID?,
    val orderIndex: UInt,
    val sourceKind: ExerciseSourceKind,
    val sourceID: StableExerciseID?,
    val displayNameSnapshot: String,
    val recordModeSnapshot: RecordMode,
    val plannedSets: List<TemplatePlannedSetRecord>,
)

data class SessionContentRecord(
    val session: SessionRecord,
    val sections: List<SectionRecord>,
    val exercises: List<SessionExerciseRecord>,
)

data class TemplateContentRecord(
    val template: TemplateRecord,
    val sections: List<SectionRecord>,
    val exercises: List<TemplateExerciseRecord>,
)

data class ActiveSessionSnapshot(
    val sessionID: SessionID,
    val studentID: StudentID,
    val startedAtUTC: Instant,
    val lastCheckpointUTC: Instant,
    val durationNeedsReview: Boolean,
)

data class SessionHistoryRecord(
    val sessionID: SessionID,
    val studentID: StudentID,
    val completedAtUTC: Instant,
    val trainingFocus: Set<BodyPart>,
    val studentFacingSummary: String?,
    val privateCoachNote: String?,
)

/**
 * Coach-only billing annotation for completed sessions.
 *
 * This note is private coach context and must never be included in share/export payloads.
 */
enum class SessionCreditSettlementNote {
    noActivePackage,
}

data class SessionSettlementNoteRecord(
    val sessionID: SessionID,
    val note: SessionCreditSettlementNote,
)

data class SaveCoursePackageCommand(
    val coursePackageID: CoursePackageID?,
    val studentID: StudentID,
    val name: String?,
    val totalCredits: Long,
    val startDate: LocalDate?,
    val endDate: LocalDate?,
    val observedActivePackageID: CoursePackageID?,
    val confirmReplaceActivePackage: Boolean,
)

data class EndCoursePackageCommand(
    val coursePackageID: CoursePackageID,
    val endedAt: LocalDate,
)

data class CreditAdjustmentCommand(
    val creditAdjustmentID: CreditAdjustmentID,
    val coursePackageID: CoursePackageID,
    val direction: CreditDirection,
    val amount: Long,
    val reasonKind: CreditReasonKind,
    val reasonText: String?,
    val linkedSessionID: SessionID?,
    val linkedAppointmentID: String?,
    val sourceEventKey: SourceEventKey,
)

data class RefundOnSessionReopenCommand(
    val sessionID: SessionID,
    val requestedAtUTC: Instant,
)

data class StartOrOpenSessionCommand(
    val studentID: StudentID,
    val initialTrainingFocus: Set<BodyPart> = emptySet(),
    val nowUTC: Instant,
)

data class SessionDraftPayload(
    val elapsedSeconds: BigDecimal,
    val interruptionStartedAtUTC: Instant?,
    val durationNeedsReview: Boolean,
    val coachAdjustedDurationSeconds: BigDecimal?,
    val trainingFocus: Set<BodyPart>,
    val studentFacingSummary: String?,
    val privateCoachNote: String?,
    val lastCheckpointUTC: Instant,
)

data class SaveSessionDraftCommand(
    val sessionID: SessionID,
    val expectedRevision: Revision,
    val payload: SessionDraftPayload,
)

data class SaveSessionContentCommand(
    val sessionID: SessionID,
    val expectedRevision: Revision,
    val sections: List<SectionRecord>,
    val exercises: List<SessionExerciseRecord>,
)

data class CompleteSessionCommand(
    val sessionID: SessionID,
    val expectedRevision: Revision,
    val completedAtUTC: Instant,
    val settleCredits: Boolean,
)

data class AbandonEmptySessionCommand(
    val sessionID: SessionID,
    val expectedRevision: Revision,
    val abandonedAtUTC: Instant,
)

data class SaveTemplateCommand(
    val templateID: TemplateID?,
    val name: String,
    val trainingFocus: Set<BodyPart>,
    val expectedRevision: Revision?,
)

data class SaveTemplateContentCommand(
    val templateID: TemplateID,
    val expectedRevision: Revision,
    val sections: List<SectionRecord>,
    val exercises: List<TemplateExerciseRecord>,
)

data class ApplyTemplateSnapshotCommand(
    val templateID: TemplateID,
    val targetSessionID: SessionID,
    val expectedTemplateRevision: Revision,
    val expectedSessionRevision: Revision,
    val appliedAtUTC: Instant,
)

data class SaveSessionSettlementNoteCommand(
    val sessionID: SessionID,
    val expectedRevision: Revision,
    val note: SessionCreditSettlementNote,
)

data class SaveCompletedSessionSummaryCommand(
    val sessionID: SessionID,
    val expectedRevision: Revision,
    val trainingFocus: Set<BodyPart>,
    val studentFacingSummary: String?,
    val privateCoachNote: String?,
    val savedAtUTC: Instant,
)

data class UpdateExercisePreferenceCommand(
    val exerciseID: StableExerciseID,
    val alias: String?,
    val isFavorite: Boolean,
    val isHidden: Boolean,
    val isAssisted: Boolean,
    val isUnilateral: Boolean?,
)

data class UpdateHistoryTrainingFocusCommand(
    val sessionID: SessionID,
    val expectedRevision: Revision,
    val trainingFocus: Set<BodyPart>,
)

enum class HistoryWindowDays(val days: Int) {
    days7(7),
    days30(30),
    days90(90),
}

data class HistoryQuery(
    val studentID: StudentID? = null,
    val window: HistoryWindowDays? = null,
    val trainingFocus: Set<BodyPart> = emptySet(),
    val exerciseIDs: Set<StableExerciseID> = emptySet(),
)

sealed interface SaveCoursePackageResult {
    data class Saved(val record: CoursePackageRecord) : SaveCoursePackageResult
    data class RequiresReconfirmation(val currentActivePackage: CoursePackageRecord?) : SaveCoursePackageResult
}

interface StudentRepositoryPort {
    suspend fun list(query: StudentQuery): ApplicationResult<List<StudentRecord>>
    suspend fun find(studentID: StudentID): ApplicationResult<StudentRecord?>
    suspend fun save(record: StudentRecord): ApplicationResult<StudentRecord>
    suspend fun archive(studentID: StudentID): ApplicationResult<Unit>
    suspend fun restore(studentID: StudentID): ApplicationResult<Unit>
    suspend fun delete(studentID: StudentID, expectedDisplayName: String): ApplicationResult<Unit>
}

interface CoursePackageRepositoryPort {
    suspend fun list(studentID: StudentID, asOf: LocalDate): ApplicationResult<List<CoursePackageRecord>>
    suspend fun active(studentID: StudentID, asOf: LocalDate): ApplicationResult<CoursePackageRecord?>
    suspend fun save(command: SaveCoursePackageCommand): ApplicationResult<SaveCoursePackageResult>
    suspend fun end(command: EndCoursePackageCommand): ApplicationResult<CoursePackageRecord>
    suspend fun appendAdjustment(command: CreditAdjustmentCommand): ApplicationResult<CreditAdjustmentRecord>
    suspend fun ledger(studentID: StudentID): ApplicationResult<List<CreditAdjustmentRecord>>
    suspend fun refundOnSessionReopen(command: RefundOnSessionReopenCommand): ApplicationResult<CreditAdjustmentRecord?>
}

interface ExerciseRepositoryPort {
    suspend fun search(query: String): ApplicationResult<List<ExerciseRecord>>
    suspend fun listCatalog(): ApplicationResult<List<ExerciseRecord>>
    suspend fun saveCustom(record: ExerciseRecord): ApplicationResult<ExerciseRecord>
    suspend fun renameClaim(exerciseID: StableExerciseID, normalizedName: String, scope: ExerciseClaimScope): ApplicationResult<Unit>
    suspend fun updatePreference(command: UpdateExercisePreferenceCommand): ApplicationResult<ExercisePreferenceRecord>
}

interface SessionRepositoryPort {
    suspend fun startOrOpen(command: StartOrOpenSessionCommand): ApplicationResult<SessionRecord>
    suspend fun listActiveSessions(): ApplicationResult<List<ActiveSessionSnapshot>>
    suspend fun active(studentID: StudentID): ApplicationResult<SessionRecord?>
    suspend fun find(sessionID: SessionID): ApplicationResult<SessionRecord?>
    suspend fun loadContent(sessionID: SessionID): ApplicationResult<SessionContentRecord?>
    suspend fun saveDraft(command: SaveSessionDraftCommand): ApplicationResult<SessionRecord>
    suspend fun saveCompletedSummary(command: SaveCompletedSessionSummaryCommand): ApplicationResult<SessionRecord>
    suspend fun saveContent(command: SaveSessionContentCommand): ApplicationResult<SessionContentRecord>
    suspend fun complete(command: CompleteSessionCommand): ApplicationResult<SessionRecord>
    suspend fun abandon(command: AbandonEmptySessionCommand): ApplicationResult<SessionRecord>
}

interface TemplateRepositoryPort {
    suspend fun list(): ApplicationResult<List<TemplateRecord>>
    suspend fun exerciseCounts(): ApplicationResult<Map<TemplateID, Int>>
    suspend fun find(templateID: TemplateID): ApplicationResult<TemplateRecord?>
    suspend fun save(command: SaveTemplateCommand): ApplicationResult<TemplateRecord>
    suspend fun loadContent(templateID: TemplateID): ApplicationResult<TemplateContentRecord?>
    suspend fun saveContent(command: SaveTemplateContentCommand): ApplicationResult<TemplateContentRecord>
    suspend fun delete(templateID: TemplateID): ApplicationResult<Unit>
    suspend fun applySnapshot(command: ApplyTemplateSnapshotCommand): ApplicationResult<SessionContentRecord>
}

interface HistoryRepositoryPort {
    suspend fun list(query: HistoryQuery): ApplicationResult<List<SessionHistoryRecord>>
    suspend fun detail(sessionID: SessionID): ApplicationResult<SessionHistoryRecord?>
    suspend fun updateTrainingFocus(command: UpdateHistoryTrainingFocusCommand): ApplicationResult<SessionHistoryRecord>
}

/**
 * Coach-only port for Session credit settlement note persistence.
 *
 * The note is private billing context and must not flow into share/export payloads.
 */
interface SessionSettlementNotePort {
    suspend fun find(sessionID: SessionID): ApplicationResult<SessionSettlementNoteRecord?>
    suspend fun save(command: SaveSessionSettlementNoteCommand): ApplicationResult<SessionSettlementNoteRecord>
    suspend fun clear(sessionID: SessionID, expectedRevision: Revision): ApplicationResult<Unit>
}
