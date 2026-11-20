package com.ignacioli.finecoach.storage.repository

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.ValidatedText
import com.ignacioli.finecoach.core.domain.student.StudentDeletionPolicy
import com.ignacioli.finecoach.storage.StoreMetadata
import com.ignacioli.finecoach.storage.migration.STUDENT_DELETION_SCOPE_KEY
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.entity.StudentEntity
import java.text.Normalizer
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Callable
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class StudentRepository(
    private val database: FineCoachDatabase,
    private val clock: AppClock,
) : StudentRepositoryPort {
    private val dao get() = database.t006aStudentDao()

    override suspend fun list(query: StudentQuery): ApplicationResult<List<StudentRecord>> = operation {
        val search = searchKey(ValidatedText.optional(query.searchText)?.value.orEmpty())
        dao.list(query.includeArchived)
            .filter { searchKey(it.displayName).contains(search) }
            .sortedWith(compareBy<StudentEntity> { it.displayName }.thenBy { it.id.toString() })
            .map { it.toRecord() }
    }

    override suspend fun displayNames(ids: Set<StudentID>): ApplicationResult<Map<StudentID,String>> = operation {
        if (ids.isEmpty()) emptyMap() else database.s1Dao().displayNames(ids.map { it.uuid() })
            .associate { StudentID.fromUUID(it.id) to it.displayName }
    }

    override suspend fun find(studentID: StudentID): ApplicationResult<StudentRecord?> = operation {
        database.s1Dao().findStudent(studentID.uuid())?.toRecord()
    }

    override suspend fun save(record: StudentRecord): ApplicationResult<StudentRecord> = transaction {
        val current = database.s1Dao().findStudent(record.studentID.uuid())
        // Save is the frozen port's upsert; existing identity and creation time are immutable.
        val canonical = record.copy(createdAtUTC = current?.createdAtUTC ?: record.createdAtUTC)
            .toStudent().toRecord()
        val row = canonical.toEntity()
        if (current == null) database.s1Dao().insert(row) else check(dao.update(row) == 1)
        requireNotNull(database.s1Dao().findStudent(row.id)).toRecord()
    }

    override suspend fun archive(studentID: StudentID): ApplicationResult<Unit> = changeLifecycle(studentID, true)
    override suspend fun restore(studentID: StudentID): ApplicationResult<Unit> = changeLifecycle(studentID, false)

    private suspend fun changeLifecycle(studentID: StudentID, archive: Boolean): ApplicationResult<Unit> = transaction {
        val student = requireStudent(studentID).toRecord().toStudent()
        val changed = if (archive) student.archived(clock.now()) else student.restored(clock.now())
        check(dao.update(changed.toRecord().toEntity()) == 1)
    }

    override suspend fun delete(studentID: StudentID, expectedDisplayName: String): ApplicationResult<Unit> = transaction {
        val student = requireStudent(studentID).toRecord().toStudent()
        val id = studentID.uuid()
        StudentDeletionPolicy.ensureCanDelete(dao.hasInProgressSession(id))
        StudentDeletionPolicy.confirmDisplayName(student.displayName, expectedDisplayName)
        // S2-D07: scope the trigger exception to this student and this transaction.
        database.storeMetadataDao().insert(StoreMetadata(STUDENT_DELETION_SCOPE_KEY, id.toString()))
        dao.deleteAppointments(id)
        dao.deleteRecurrenceSeries(id)
        dao.deleteSets(id)
        dao.deleteExercises(id)
        dao.deleteFocus(id)
        dao.deleteSessions(id)
        // Match the iOS UUID.uuidString key, as well as Android's canonical lower-case UUID.
        dao.deleteArchiveIdentity("archive.studentID.${studentID.value.uppercase(Locale.ROOT)}")
        dao.deleteArchiveIdentity("archive.studentID.${studentID.value}")
        dao.deleteStudent(id)
        dao.deleteArchiveIdentity(STUDENT_DELETION_SCOPE_KEY)
    }

    private fun requireStudent(id: StudentID): StudentEntity =
        database.s1Dao().findStudent(id.uuid()) ?: throw MissingStudent()

    private suspend fun <T> transaction(action: () -> T): ApplicationResult<T> = operation {
        database.runInTransaction(Callable { action() })
    }

    private suspend fun <T> operation(action: () -> T): ApplicationResult<T> = studentValidation {
        withContext(Dispatchers.IO) {
            try {
                ApplicationResult.Success(action())
            } catch (error: CancellationException) {
                throw error
            } catch (error: com.ignacioli.finecoach.core.domain.student.StudentDomainException) {
                throw error
            } catch (_: MissingStudent) {
                ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.notFound))
            } catch (_: Exception) {
                // Do not expose SQLite messages or sensitive row contents.
                ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed))
            }
        }
    }

    private class MissingStudent : RuntimeException()
}

private fun StudentID.uuid(): UUID = UUID.fromString(value)
private fun StudentEntity.toRecord() = StudentRecord(
    StudentID.fromUUID(id), displayName, sex, trainingGoal, injuryNotes, privateCoachNote, phone, wechatID,
    lifecycle, createdAtUTC, updatedAtUTC,
)
private fun StudentRecord.toEntity() = StudentEntity(
    studentID.uuid(), displayName, sex, trainingGoal, injuryNotes, privateCoachNote, phone, wechatID,
    lifecycle, createdAtUTC, updatedAtUTC,
)

// iOS CONTAINS[cd] searches literal text, ignoring case and diacritics (no SQL wildcard semantics).
private fun searchKey(text: String): String = Normalizer.normalize(text, Normalizer.Form.NFD)
    .replace(Regex("\\p{M}+"), "").lowercase(Locale.ROOT)
