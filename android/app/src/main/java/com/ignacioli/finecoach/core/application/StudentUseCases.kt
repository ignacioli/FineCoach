package com.ignacioli.finecoach.core.application

import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.student.Student
import com.ignacioli.finecoach.core.domain.student.StudentDomainException
import com.ignacioli.finecoach.core.domain.student.StudentDraft

class StudentUseCases(
    private val repository: StudentRepositoryPort,
    private val clock: AppClock,
    private val ids: StableIDGenerator,
    private val reminders: AppointmentReminderPort = AppointmentReminderPort {},
) {
    suspend fun list(query: StudentQuery = StudentQuery()) = repository.list(query)
    suspend fun displayNames(ids: Set<StudentID>) = repository.displayNames(ids)
    suspend fun find(studentID: StudentID) = repository.find(studentID)

    suspend fun create(draft: StudentDraft): ApplicationResult<StudentRecord> = studentValidation {
        val student = draft.makeStudent(ids.newStudentID(), clock.now())
        repository.save(student.toRecord())
    }

    suspend fun update(studentID: StudentID, draft: StudentDraft): ApplicationResult<StudentRecord> {
        return when (val found = repository.find(studentID)) {
            is ApplicationResult.Failure -> found
            is ApplicationResult.Success -> {
                val current = found.value ?: return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.notFound))
                studentValidation {
                    repository.save(current.toStudent().updateFromDraft(draft, clock.now()).toRecord())
                }
            }
        }
    }

    suspend fun archive(studentID: StudentID) = repository.archive(studentID)
    suspend fun restore(studentID: StudentID) = repository.restore(studentID)
    suspend fun delete(studentID: StudentID, confirmedDisplayName: String) =
        repository.delete(studentID, confirmedDisplayName).also { if (it is ApplicationResult.Success) reminders.reconcile() }
}

internal fun StudentRecord.toStudent(): Student = Student.fromDraft(
    studentID,
    StudentDraft(displayName, sex, trainingGoal.orEmpty(), injuryNotes.orEmpty(), privateCoachNote.orEmpty(),
        phone.orEmpty(), wechatID.orEmpty()),
    lifecycle, createdAtUTC, updatedAtUTC,
)

internal fun Student.toRecord() = StudentRecord(
    studentID, displayName.value, sex, trainingGoal?.value, injuryNotes?.value, privateCoachNote?.value,
    phone?.value, wechatID?.value, lifecycle, createdAtUTC, updatedAtUTC,
)

internal suspend fun <T> studentValidation(action: suspend () -> ApplicationResult<T>): ApplicationResult<T> = try {
    action()
} catch (error: StudentDomainException) {
    ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.valueOf(error.code.name)))
}
