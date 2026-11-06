package com.ignacioli.finecoach.core.application

import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.CreditAdjustmentID
import com.ignacioli.finecoach.core.domain.common.SessionExerciseID
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.SourceEventKey
import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.TemplateID
import com.ignacioli.finecoach.core.domain.common.SectionID
import com.ignacioli.finecoach.core.domain.common.TemplateExerciseID
import com.ignacioli.finecoach.core.domain.common.TrainingSetID
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

fun interface AppClock {
    fun now(): Instant

    fun today(zoneID: ZoneId): LocalDate = now().atZone(zoneID).toLocalDate()
}

interface StableIDGenerator {
    fun newStudentID(): StudentID
    fun newCoursePackageID(): CoursePackageID
    fun newCreditAdjustmentID(): CreditAdjustmentID
    fun newSessionID(): SessionID
    fun newTemplateID(): TemplateID
    fun newSectionID(): SectionID
    fun newSessionExerciseID(): SessionExerciseID
    fun newTemplateExerciseID(): TemplateExerciseID
    fun newTrainingSetID(): TrainingSetID
    fun newExerciseID(): StableExerciseID
}

interface CreditLedgerSourceEventKeyBuilder {
    fun sessionComplete(sessionID: SessionID): SourceEventKey
    fun sessionReopen(sessionID: SessionID): SourceEventKey
    fun appointmentAbsent(appointmentID: String): SourceEventKey
    fun adhocSession(sessionID: SessionID): SourceEventKey
    fun manualCorrection(adjustmentID: CreditAdjustmentID): SourceEventKey
}

enum class ApplicationErrorCode {
    emptyText,
    textTooLong,
    invalidDecimal,
    invalidNumber,
    invalidUnit,
    invalidMode,
    invalidState,
    invalidIdentifier,
    conflict,
    notFound,
    staleRevision,
    persistenceFailed,
    incompatibleInput,
}

data class ApplicationError(
    val code: ApplicationErrorCode,
    val field: String? = null,
)

sealed interface ApplicationResult<out T> {
    data class Success<T>(val value: T) : ApplicationResult<T>
    data class Failure(val error: ApplicationError) : ApplicationResult<Nothing>
}
