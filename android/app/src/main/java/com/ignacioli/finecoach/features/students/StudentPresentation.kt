package com.ignacioli.finecoach.features.students

import com.ignacioli.finecoach.core.application.ApplicationError
import com.ignacioli.finecoach.core.application.ApplicationErrorCode
import com.ignacioli.finecoach.core.domain.common.BodyPart
import com.ignacioli.finecoach.core.domain.common.NormalizedName
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.StudentSex
import com.ignacioli.finecoach.designsystem.FcBodyParts
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

object StudentTestTags {
    const val STUDENT_LIST_ROOT = "studentList.root"
    const val STUDENT_LIST_SEGMENT = "studentList.segment"
    const val STUDENT_LIST_SEARCH = "studentList.search"
    const val STUDENT_LIST_EMPTY = "studentList.empty"
    const val STUDENT_LIST_EMPTY_ADD = "studentList.emptyAdd"
    const val STUDENT_LIST_ADD = "studentList.add"
    const val STUDENT_LIST_ARCHIVED = "studentList.archived"
    const val STUDENT_LIST_IN_PROGRESS = "studentList.inProgress"
    const val STUDENT_LIST_ERROR = "studentList.error"

    const val ARCHIVED_LIST_ROOT = "studentArchived.root"
    const val ARCHIVED_HEADER = "studentArchived"
    const val ARCHIVED_HEADER_BACK = "studentArchived-back"
    const val ARCHIVED_ERROR = "studentArchived.error"

    const val EDITOR_ROOT = "studentEditor.root"
    const val EDITOR_HEADER = "studentEditor"
    const val EDITOR_HEADER_BACK = "studentEditor-back"
    const val EDITOR_ROW_NAME = "studentEditor.row.displayName"
    const val EDITOR_ROW_SEX = "studentEditor.row.sex"
    const val EDITOR_ROW_GOAL = "studentEditor.row.trainingGoal"
    const val EDITOR_ROW_PHONE = "studentEditor.row.phone"
    const val EDITOR_ROW_WECHAT = "studentEditor.row.wechat"
    const val EDITOR_ROW_PRIVATE_NOTE = "studentEditor.row.privateCoachNote"
    const val EDITOR_ROW_INJURY_NOTES = "studentEditor.row.injuryNotes"
    const val EDITOR_NAME = "studentEditor.displayName"
    const val EDITOR_SEX_MALE = "studentEditor.sex.male"
    const val EDITOR_SEX_FEMALE = "studentEditor.sex.female"
    const val EDITOR_SEX_OTHER = "studentEditor.sex.other"
    const val EDITOR_SEX_UNDISCLOSED = "studentEditor.sex.undisclosed"
    const val EDITOR_GOAL = "studentEditor.trainingGoal"
    const val EDITOR_PHONE = "studentEditor.phone"
    const val EDITOR_WECHAT = "studentEditor.wechat"
    const val EDITOR_PRIVATE_NOTE = "studentEditor.privateCoachNote"
    const val EDITOR_INJURY_NOTES = "studentEditor.injuryNotes"
    const val EDITOR_NAME_ERROR = "studentEditor.nameError"
    const val EDITOR_SEX_ERROR = "studentEditor.sexError"
    const val EDITOR_SAVE_ERROR = "studentEditor.saveError"
    const val EDITOR_SAVE = "studentEditor.save"
    const val EDITOR_SKIP = "studentEditor.skip"

    const val DETAIL_ROOT = "studentDetail.root"
    const val DETAIL_HEADER = "studentDetail"
    const val DETAIL_HEADER_BACK = "studentDetail-back"
    const val DETAIL_HEADER_EDIT = "studentDetail-trailing"
    const val DETAIL_ERROR = "studentDetail.error"
    const val DETAIL_ARCHIVED_STATUS = "studentDetail.archivedStatus"
    const val DETAIL_CONTINUE_TRAINING = "studentDetail.continueTraining"
    const val DETAIL_COURSE_PACKAGES = "studentDetail.coursePackages"
    const val DETAIL_RECENT_TRAINING = "studentDetail.recentTraining"
    const val DETAIL_HISTORY = "studentDetail.history"
    const val DETAIL_PROFILE_SEX = "studentDetail.profile.sex"
    const val DETAIL_PROFILE_PHONE = "studentDetail.profile.phone"
    const val DETAIL_PROFILE_WECHAT = "studentDetail.profile.wechat"
    const val DETAIL_PROFILE_PRIVATE_NOTE = "studentDetail.profile.privateNote"
    const val DETAIL_NOTES_FOLD = "studentDetail.injuryNotesFold"
    const val DETAIL_NOTES_BODY = "studentDetail.injuryNotesBody"
    const val DETAIL_START_TRAINING = "studentDetail.startTraining"
    const val DETAIL_RESTORE = "studentDetail.restore"
    const val DETAIL_ARCHIVE = "studentDetail.archive"
    const val DETAIL_DELETE = "studentDetail.delete"

    const val ARCHIVE_ROOT = "studentArchive.root"
    const val ARCHIVE_ERROR = "studentArchive.error"
    const val ARCHIVE_CONFIRM = "archive.confirm"
    const val ARCHIVE_CANCEL = "student.archive.cancel"

    const val DELETE_ROOT = "deleteStudent.root"
    const val DELETE_BLOCKED = "deleteStudent.blocked"
    const val DELETE_CONTINUE_TRAINING = "deleteStudent.continueTraining"
    const val DELETE_BACK_TO_DETAIL = "deleteStudent.backToDetail"
    const val DELETE_NAME = "deleteStudent.confirmName"
    const val DELETE_ERROR = "deleteStudent.error"
    const val DELETE_RETRY = "deleteStudent.retry"
    const val DELETE_CONFIRM = "deleteStudent.confirm"
    const val DELETE_CANCEL = "student.delete.cancel"
    const val DELETE_DONE = "deleteStudent.done"
    const val DELETE_BACK_TO_LIST = "deleteStudent.backToList"

    fun studentRow(studentID: StudentID): String = "studentList.row.${studentID.value}"

    fun studentListInProgressRow(studentID: StudentID): String =
        "studentList.inProgress.${studentID.value}"

    fun studentListRestore(studentID: StudentID): String =
        "studentList.restore.${studentID.value}"

    fun sexIdentifier(sex: StudentSex): String = when (sex) {
        StudentSex.male -> EDITOR_SEX_MALE
        StudentSex.female -> EDITOR_SEX_FEMALE
        StudentSex.other -> EDITOR_SEX_OTHER
        StudentSex.undisclosed -> EDITOR_SEX_UNDISCLOSED
    }
}

object StudentSexPresentation {
    fun title(sex: StudentSex): String = when (sex) {
        StudentSex.male -> "男"
        StudentSex.female -> "女"
        StudentSex.other -> "其他"
        StudentSex.undisclosed -> "不透露"
    }
}

data class StudentInProgressSummary(
    val sessionID: SessionID,
    val studentID: StudentID,
    val studentDisplayName: String,
    val startedAtUTC: Instant? = null,
    val trainingFocus: Set<BodyPart> = emptySet(),
) {
    fun elapsedMinutes(now: Instant): Long? =
        startedAtUTC?.let { start -> maxOf(0L, Duration.between(start, now).toMinutes()) }
}

data class StudentRecentSessionSummary(
    val sessionID: SessionID,
    val completedAtUTC: Instant,
    val trainingFocus: Set<BodyPart>,
    val completedSetCount: Int? = null,
)

object StudentPresentation {
    const val GENERIC_ERROR = "没有完成，再试一次。"
    const val NAME_REQUIRED_ERROR = "还没填写显示名称"
    const val SEX_REQUIRED_ERROR = "还没选择性别"
    const val TEXT_TOO_LONG_ERROR = "输入内容过长，请精简后再试。"
    const val DELETE_NAME_MISMATCH_ERROR = "显示名称不匹配"

    fun joinedBodyParts(parts: Set<BodyPart>, separator: String = "、"): String? {
        if (parts.isEmpty()) return null
        return BodyPart.entries
            .filter { it in parts }
            .map { FcBodyParts[it.ordinal] }
            .joinToString(separator)
    }

    fun focusText(parts: Set<BodyPart>): String {
        val names = joinedBodyParts(parts, separator = "、") ?: return "未设重点"
        return "训练重点 · $names"
    }

    fun packageRemainingText(balance: Long): String = "课包剩余 $balance 课时"

    fun trainingBarText(summary: StudentInProgressSummary, now: Instant): String {
        val minutes = summary.elapsedMinutes(now) ?: return "${summary.studentDisplayName} 训练中"
        return "${summary.studentDisplayName} 训练中 · 已训练 $minutes 分钟"
    }

    fun heroTitle(studentDisplayName: String, focus: Set<BodyPart>): String {
        val names = joinedBodyParts(focus, separator = "、") ?: return studentDisplayName
        return "$studentDisplayName · $names"
    }

    fun heroElapsedSubtitle(summary: StudentInProgressSummary, now: Instant): String {
        val minutes = summary.elapsedMinutes(now) ?: return ""
        return "已训练 $minutes 分钟"
    }

    fun monthDay(instant: Instant, zoneId: ZoneId): String {
        val localDate = instant.atZone(zoneId).toLocalDate()
        return "${localDate.monthValue}月${localDate.dayOfMonth}日"
    }

    fun archivedOnText(updatedAtUTC: Instant, zoneId: ZoneId): String =
        "归档于 ${monthDay(updatedAtUTC, zoneId)}"

    fun goalText(trainingGoal: String?): String {
        val clean = trainingGoal?.takeIf { it.isNotEmpty() } ?: return "未设训练目标"
        return "训练目标 · $clean"
    }

    fun filledOrUnfilled(value: String?): String =
        value?.takeIf { it.isNotEmpty() } ?: "未填写"

    fun packageDetailText(totalCredits: Long, endDate: LocalDate?): String {
        val total = "/ 共 $totalCredits 课时"
        if (endDate == null) return total
        return "$total · 有效期至 ${endDate.monthValue}月${endDate.dayOfMonth}日"
    }

    fun recentTrainingText(summary: StudentRecentSessionSummary?, zoneId: ZoneId): String {
        if (summary == null) return "上完第一节课后会显示在这里"
        val parts = mutableListOf(monthDay(summary.completedAtUTC, zoneId))
        joinedBodyParts(summary.trainingFocus, separator = "、")?.let { parts += it }
        summary.completedSetCount?.let { parts += "$it 组" }
        return parts.joinToString(" · ")
    }

    fun namesMatch(expectedDisplayName: String, typedName: String): Boolean {
        val normalizedTyped = try {
            NormalizedName.optional(typedName)?.value
        } catch (_: IllegalArgumentException) {
            null
        }
        return normalizedTyped != null && normalizedTyped == expectedDisplayName
    }

    fun errorMessage(error: ApplicationError): String = when (error.code) {
        ApplicationErrorCode.emptyText -> NAME_REQUIRED_ERROR
        ApplicationErrorCode.textTooLong -> TEXT_TOO_LONG_ERROR
        else -> GENERIC_ERROR
    }
}
