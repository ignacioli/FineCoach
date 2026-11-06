package com.ignacioli.finecoach.core.domain.student

import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.StudentLifecycle
import com.ignacioli.finecoach.core.domain.common.StudentSex
import java.time.Instant

data class StudentDraft(
    val displayName: String = "",
    val sex: StudentSex? = null,
    val trainingGoal: String = "",
    val injuryNotes: String = "",
    val privateCoachNote: String = "",
    val phone: String = "",
    val wechatID: String = "",
) {
    fun makeStudent(studentID: StudentID, nowUTC: Instant): Student {
        return Student.fromDraft(
            studentID = studentID,
            draft = this,
            lifecycle = StudentLifecycle.active,
            createdAtUTC = nowUTC,
            updatedAtUTC = nowUTC,
        )
    }
}

data class Student(
    val studentID: StudentID,
    val displayName: NormalizedName,
    val sex: StudentSex,
    val trainingGoal: ValidatedText?,
    val injuryNotes: ValidatedText?,
    val privateCoachNote: ValidatedText?,
    val phone: ValidatedText?,
    val wechatID: ValidatedText?,
    val lifecycle: StudentLifecycle,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
) {
    val draft: StudentDraft
        get() {
            return StudentDraft(
                displayName = displayName.value,
                sex = sex,
                trainingGoal = trainingGoal?.value.orEmpty(),
                injuryNotes = injuryNotes?.value.orEmpty(),
                privateCoachNote = privateCoachNote?.value.orEmpty(),
                phone = phone?.value.orEmpty(),
                wechatID = wechatID?.value.orEmpty(),
            )
        }

    fun updateFromDraft(draft: StudentDraft, nowUTC: Instant): Student {
        return fromDraft(
            studentID = studentID,
            draft = draft,
            lifecycle = lifecycle,
            createdAtUTC = createdAtUTC,
            updatedAtUTC = nowUTC,
        )
    }

    fun archived(nowUTC: Instant): Student {
        if (lifecycle != StudentLifecycle.active) {
            throw StudentDomainException(StudentDomainError.invalidState, "Only active students can be archived")
        }
        return copy(lifecycle = StudentLifecycle.archived, updatedAtUTC = nowUTC)
    }

    fun restored(nowUTC: Instant): Student {
        if (lifecycle != StudentLifecycle.archived) {
            throw StudentDomainException(StudentDomainError.invalidState, "Only archived students can be restored")
        }
        return copy(lifecycle = StudentLifecycle.active, updatedAtUTC = nowUTC)
    }

    fun canStartSession(): Boolean = lifecycle == StudentLifecycle.active

    companion object {
        fun fromDraft(
            studentID: StudentID,
            draft: StudentDraft,
            lifecycle: StudentLifecycle,
            createdAtUTC: Instant,
            updatedAtUTC: Instant,
        ): Student {
            val sexValue = draft.sex
                ?: throw StudentDomainException(StudentDomainError.invalidState, "Student sex is required")
            return Student(
                studentID = studentID,
                displayName = NormalizedName.parse(draft.displayName),
                sex = sexValue,
                trainingGoal = optionalText(draft.trainingGoal),
                injuryNotes = optionalText(draft.injuryNotes),
                privateCoachNote = optionalText(draft.privateCoachNote),
                phone = optionalText(draft.phone),
                wechatID = optionalText(draft.wechatID),
                lifecycle = lifecycle,
                createdAtUTC = createdAtUTC,
                updatedAtUTC = updatedAtUTC,
            )
        }

        fun optionalText(rawValue: String): ValidatedText? {
            val canonical = ValidatedText.parse(rawValue, allowEmpty = true).value
            return if (canonical.isEmpty()) {
                null
            } else {
                ValidatedText.parse(canonical)
            }
        }
    }
}

object StudentDeletionPolicy {
    fun ensureCanDelete(hasInProgressSession: Boolean) {
        if (hasInProgressSession) {
            throw StudentDomainException(StudentDomainError.invalidState, "Cannot delete student with in-progress session")
        }
    }

    fun confirmDisplayName(expected: NormalizedName, typed: String) {
        val confirmed = try {
            NormalizedName.parse(typed)
        } catch (_: StudentDomainException) {
            throw StudentDomainException(StudentDomainError.invalidState, "Display name confirmation is invalid")
        }
        if (confirmed != expected) {
            throw StudentDomainException(StudentDomainError.invalidState, "Display name confirmation mismatch")
        }
    }
}
