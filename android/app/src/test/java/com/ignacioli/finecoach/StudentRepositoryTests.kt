package com.ignacioli.finecoach

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.storage.*
import com.ignacioli.finecoach.storage.entity.*
import com.ignacioli.finecoach.storage.repository.StudentRepository
import java.math.BigDecimal
import java.time.Instant
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// fictional-data: isolated temporary databases and invented student values only.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class StudentRepositoryTests {
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var context: Context
    private lateinit var db: FineCoachDatabase
    private val now = Instant.parse("2026-11-06T08:09:10.123456789Z")
    private var clockNow = now
    private val clock = AppClock { clockNow }
    private val repository get() = StudentRepository(db, clock)
    private val dao get() = db.s1Dao()
    private fun id(n: Int) = UUID.fromString("abcdef00-0000-4000-8000-${n.toString().padStart(12, '0')}")
    private fun sid(n: Int) = StudentID.fromUUID(id(n))
    private fun record(n: Int = 1, name: String = "虚构学员") = StudentRecord(
        sid(n), name, StudentSex.undisclosed, "虚构目标", "虚构伤情", "虚构私密备注",
        "fictional-phone", "fictional-wechat", StudentLifecycle.active, now, now,
    )
    private fun <T> success(result: ApplicationResult<T>): T {
        assertTrue("Expected success", result is ApplicationResult.Success)
        return (result as ApplicationResult.Success).value
    }
    private fun failure(code: ApplicationErrorCode, result: ApplicationResult<*>) {
        assertEquals(ApplicationResult.Failure(ApplicationError(code)), result)
    }
    private fun test(action: suspend () -> Unit) {
        worker.submit(Callable { runBlocking { action() } }).get(30, TimeUnit.SECONDS)
    }
    private fun reopen() { db.close(); db = FineCoachDatabaseFactory.create(context) }

    @Before fun prepare() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        db = FineCoachDatabaseFactory.create(context)
    }
    @After fun cleanUp() {
        try { worker.submit { db.close() }.get(30, TimeUnit.SECONDS) } finally {
            worker.shutdownNow()
            context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        }
    }

    @Test fun sameNameStudentsAndFullProfilesSurviveReopen() = test {
        val first = success(repository.save(record()))
        val second = success(repository.save(record(2)))
        reopen()
        assertEquals(first, success(repository.find(sid(1))))
        assertEquals(second, success(repository.find(sid(2))))
        assertEquals(listOf(first, second), success(repository.list(StudentQuery())))
    }

    @Test fun saveNormalizesAndClearsAllOptionalFieldsWithoutChangingIdentityOrCreation() = test {
        success(repository.save(record()))
        val saved = success(repository.save(record().copy(displayName = " \u00a0虚构e\u0301 \n", trainingGoal = " ",
            injuryNotes = "\u00a0", privateCoachNote = "\n", phone = "", wechatID = "\t",
            createdAtUTC = now.plusSeconds(5), updatedAtUTC = now.plusSeconds(10))))
        assertEquals("虚构é", saved.displayName)
        assertEquals(now, saved.createdAtUTC)
        assertEquals(now.plusSeconds(10), saved.updatedAtUTC)
        assertEquals(listOf(null, null, null, null, null), listOf(saved.trainingGoal, saved.injuryNotes,
            saved.privateCoachNote, saved.phone, saved.wechatID))
        reopen()
        assertEquals(saved, success(repository.find(sid(1))))
    }

    @Test fun searchIsLiteralCaseAndDiacriticInsensitiveAndStableByNameThenID() = test {
        success(repository.save(record(2, "虚构École")))
        success(repository.save(record(1, "虚构École")))
        success(repository.save(record(3, "虚构%_")))
        assertEquals(listOf(sid(1), sid(2)), success(repository.list(StudentQuery(searchText = " ECoLe "))).map { it.studentID })
        assertEquals(listOf(sid(3)), success(repository.list(StudentQuery(searchText = "%_"))).map { it.studentID })
        assertTrue(success(repository.list(StudentQuery(searchText = "不存在的虚构名字"))).isEmpty())
    }

    @Test fun archiveRestorePersistsAndRejectsRepeatedTransitions() = test {
        success(repository.save(record()))
        clockNow = now.plusSeconds(10)
        success(repository.archive(sid(1)))
        failure(ApplicationErrorCode.invalidState, repository.archive(sid(1)))
        reopen()
        assertTrue(success(repository.list(StudentQuery())).isEmpty())
        val archived = success(repository.list(StudentQuery(includeArchived = true))).single()
        assertEquals(StudentLifecycle.archived, archived.lifecycle)
        assertEquals(clockNow, archived.updatedAtUTC)
        clockNow = now.plusSeconds(20)
        success(repository.restore(sid(1)))
        failure(ApplicationErrorCode.invalidState, repository.restore(sid(1)))
        reopen()
        val restored = success(repository.list(StudentQuery())).single()
        assertEquals(StudentLifecycle.active, restored.lifecycle)
        assertEquals(now, restored.createdAtUTC)
        assertEquals(clockNow, restored.updatedAtUTC)
    }

    @Test fun missingStudentIsExplicitAndDoesNotWrite() = test {
        assertNull(success(repository.find(sid(99))))
        val before = snapshot()
        failure(ApplicationErrorCode.notFound, repository.archive(sid(99)))
        failure(ApplicationErrorCode.notFound, repository.restore(sid(99)))
        failure(ApplicationErrorCode.notFound, repository.delete(sid(99), "虚构学员"))
        assertEquals(before, snapshot())
    }

    @Test fun invalidProfileDoesNotOverwritePersistedData() = test {
        success(repository.save(record()))
        val before = snapshot()
        failure(ApplicationErrorCode.emptyText, repository.save(record().copy(displayName = " ")))
        failure(ApplicationErrorCode.textTooLong, repository.save(record().copy(privateCoachNote = "字".repeat(22000))))
        assertEquals(before, snapshot())
        reopen()
        assertEquals(record(), success(repository.find(sid(1))))
    }

    @Test fun wrongOrBlankConfirmationDeletesNothingEvenAfterReopen() = test {
        seedGraph()
        val before = snapshot()
        for (name in listOf("另一个虚构学员", "", "\u00a0")) {
            failure(ApplicationErrorCode.invalidState, repository.delete(sid(1), name))
            assertEquals(before, snapshot())
        }
        reopen()
        assertEquals(before, snapshot())
    }

    @Test fun inProgressSessionBlocksDeletionWithoutRelyingOnPointer() = test {
        seedGraph()
        dao.insert(session(90, 1, SessionState.inProgress))
        val before = snapshot()
        failure(ApplicationErrorCode.invalidState, repository.delete(sid(1), "虚构学员"))
        assertEquals(before, snapshot())
        reopen()
        assertEquals(before, snapshot())
    }

    @Test fun successfulDeletionChecksEveryTableAndPreservesOtherStudentAndScalarResidue() = test {
        seedGraph()
        val before = snapshot()
        val deleted = mapOf("students" to 1, "sessions" to 2, "session_exercises" to 2,
            "training_sets" to 2, "session_training_focus" to 2, "store_metadata" to 2)
        val targetKeys = setOf(archiveKey(1), archiveKey(1).uppercaseUUID())
        val removedKeys = mapOf(
            "students" to setOf(id(1).toString()),
            "sessions" to setOf(id(10).toString(), id(30).toString()),
            "session_exercises" to setOf(id(11).toString(), id(31).toString()),
            "training_sets" to setOf(id(12).toString(), id(32).toString()),
            "session_training_focus" to setOf(id(10).toString(), id(30).toString()),
            "store_metadata" to targetKeys,
        )
        val otherStudent = success(repository.find(sid(2)))
        success(repository.delete(sid(1), " \u00a0虚构学员\n"))
        val actual = snapshot()
        for (table in tables) {
            assertEquals("Row count: $table", before.getValue(table).size - (deleted[table] ?: 0), actual.getValue(table).size)
            assertEquals("Retained row contents: $table",
                before.getValue(table).filterNot { it.first() in removedKeys[table].orEmpty() }, actual[table])
        }
        assertNull(success(repository.find(sid(1))))
        assertEquals(otherStudent, success(repository.find(sid(2))))
        for (key in targetKeys) assertNull(db.storeMetadataDao().find(key))
        assertNotNull(db.storeMetadataDao().find(archiveKey(2)))
        assertNotNull(dao.findSession(id(20)))
        assertNotNull(dao.findSessionExercise(id(21)))
        assertNotNull(dao.findTrainingSet(id(22)))
        assertEquals(listOf(SessionTrainingFocusEntity(id(20), BodyPart.back)), dao.sessionFocus(id(20)))
        val after = snapshot()
        reopen()
        assertEquals(after, snapshot())
        assertNull(success(repository.find(sid(1))))
        assertEquals(otherStudent, success(repository.find(sid(2))))
    }

    @Test fun failureAfterChildDeletesRollsBackWholeTransactionAndCanRetry() = test {
        seedGraph()
        val before = snapshot()
        db.openHelper.writableDatabase.execSQL("""
            CREATE TRIGGER fictional_fail_session_delete BEFORE DELETE ON sessions
            BEGIN SELECT RAISE(ABORT, 'fictional failure'); END
        """.trimIndent())
        failure(ApplicationErrorCode.persistenceFailed, repository.delete(sid(1), "虚构学员"))
        assertEquals(before, snapshot())
        reopen()
        assertEquals(before, snapshot())
        db.openHelper.writableDatabase.execSQL("DROP TRIGGER fictional_fail_session_delete")
        success(repository.delete(sid(1), "虚构学员"))
        assertNull(success(repository.find(sid(1))))
    }

    @Test fun failureAtFinalStudentDeleteAlsoRestoresArchiveIdentity() = test {
        seedGraph()
        val before = snapshot()
        db.openHelper.writableDatabase.execSQL("""
            CREATE TRIGGER fictional_fail_student_delete BEFORE DELETE ON students
            BEGIN SELECT RAISE(ABORT, 'fictional failure'); END
        """.trimIndent())
        failure(ApplicationErrorCode.persistenceFailed, repository.delete(sid(1), "虚构学员"))
        assertEquals(before, snapshot())
        reopen()
        assertEquals(before, snapshot())
    }

    @Test fun useCasesCreateUpdateValidateAndPropagateSaveFailureForRetry() = test {
        val useCases = StudentUseCases(repository, clock, ids)
        failure(ApplicationErrorCode.invalidState, useCases.create(StudentDraft("虚构学员")))
        failure(ApplicationErrorCode.emptyText, useCases.create(StudentDraft(" ", StudentSex.other)))
        assertTrue(success(useCases.list()).isEmpty())
        val created = success(useCases.create(StudentDraft("虚构学员", StudentSex.other, phone = "fictional-phone")))
        clockNow = now.plusSeconds(10)
        db.openHelper.writableDatabase.execSQL("""
            CREATE TRIGGER fictional_fail_update BEFORE UPDATE ON students
            BEGIN SELECT RAISE(ABORT, 'fictional failure'); END
        """.trimIndent())
        val draft = StudentDraft("虚构新名字", StudentSex.female)
        failure(ApplicationErrorCode.persistenceFailed, useCases.update(created.studentID, draft))
        assertEquals(created, success(useCases.find(created.studentID)))
        db.openHelper.writableDatabase.execSQL("DROP TRIGGER fictional_fail_update")
        val updated = success(useCases.update(created.studentID, draft))
        assertEquals(created.studentID, updated.studentID)
        assertEquals(created.createdAtUTC, updated.createdAtUTC)
        assertEquals(clockNow, updated.updatedAtUTC)
        assertNull(updated.phone)
        failure(ApplicationErrorCode.notFound, useCases.update(sid(99), draft))
        success(useCases.archive(updated.studentID))
        success(useCases.restore(updated.studentID))
        reopen()
        val reopenedUseCases = StudentUseCases(repository, clock, ids)
        assertEquals(updated, success(reopenedUseCases.find(updated.studentID)))
        success(reopenedUseCases.delete(updated.studentID, draft.displayName))
    }

    private fun session(n: Int, student: Int, state: SessionState = SessionState.completed) = SessionEntity(
        id(n), id(student), state, now, now, BigDecimal("60"), null, false, null, null, null,
        "1", now, now, if (state == SessionState.completed) now else null, null, null,
    )
    private fun archiveKey(n: Int) = "archive.studentID.${sid(n).value}"
    private fun String.uppercaseUUID() = "archive.studentID.${substringAfterLast('.').uppercase(Locale.ROOT)}"

    private suspend fun seedGraph() {
        success(repository.save(record()))
        success(repository.save(record(2)))
        // Two terminal sessions for target; another student's complete graph is untouched.
        for ((sessionID, studentID) in listOf(10 to 1, 30 to 1, 20 to 2)) {
            val initial = session(sessionID, studentID, SessionState.inProgress)
            dao.insert(initial)
            if (sessionID != 30) dao.insert(ActiveSessionPointerEntity(sid(studentID).value, initial.id))
            // Preserve a stale pointer to a terminal session, matching iOS scalar residue.
            db.openHelper.writableDatabase.execSQL("UPDATE sessions SET state = 'completed', completedAtUTC = ? WHERE id = ?",
                arrayOf(now.toString(), initial.id.toString()))
            dao.insert(SessionSectionEntity(id(sessionID + 3), SessionSectionOwnerKind.session, initial.id, "虚构分段", 0))
            dao.insert(SessionExerciseEntity(id(sessionID + 1), initial.id, 1, ExerciseSourceKind.builtIn,
                "fictional-catalog", "虚构动作", RecordMode.reps, null, id(sessionID + 3)))
            dao.insert(TrainingSetEntity(id(sessionID + 2), id(sessionID + 1), 0, SetRecordingState.completed,
                RecordMode.reps, null, BigDecimal.TEN, null, null, null, null, null, null,
                MeasurementUnit.repetitions, SetSide.none, now, now, now))
            dao.insert(SessionTrainingFocusEntity(initial.id, BodyPart.back))
        }
        for (studentID in 1..2) {
            dao.insert(CoursePackageEntity(id(40 + studentID), id(studentID), "虚构课包", 10, 9, null, null,
                CoursePackageStatus.active, now, now))
            dao.insert(ActivePackageClaimEntity(id(studentID), id(40 + studentID)))
            dao.insert(CreditAdjustmentEntity(id(50 + studentID), id(40 + studentID), CreditDirection.debit, 1,
                CreditReasonKind.sessionComplete, null, id(if (studentID == 1) 10 else 20), null,
                "fictional-event-$studentID", now))
            db.storeMetadataDao().insert(StoreMetadata(archiveKey(studentID), "fictional-archive"))
        }
        db.storeMetadataDao().insert(StoreMetadata(archiveKey(1).uppercaseUUID(), "fictional-ios-archive"))
        db.storeMetadataDao().insert(StoreMetadata("archive.studentID.${sid(1).value}.other", "fictional-unrelated"))
        dao.insert(ExerciseCatalogEntity("fictional-catalog", ExerciseKind.builtIn, "虚构动作", "虚构动作",
            RecordMode.reps, "fictional-v1", ExerciseLifecycle.active, false, "fictional-license", now, now))
        dao.insert(ExercisePreferenceEntity("fictional-catalog", null, true, false, false, null))
        dao.insert(ExerciseNameClaimEntity("虚构动作", ExerciseSourceKind.builtIn, "fictional-catalog", ExerciseClaimScope.activeCatalog))
        dao.insert(TrainingTemplateEntity(id(60), "虚构模板", createdAtUTC = now, updatedAtUTC = now))
        dao.insert(TemplateTrainingFocusEntity(id(60), BodyPart.chest))
        dao.insert(SessionSectionEntity(id(63), SessionSectionOwnerKind.template, id(60), "虚构模板分段", 0))
        dao.insert(TemplateExerciseEntity(id(61), id(60), id(63), 1, ExerciseSourceKind.builtIn,
            "fictional-catalog", "虚构模板动作", RecordMode.reps))
        dao.insert(TemplatePlannedSetEntity(id(61), 0, RecordMode.reps, MeasurementUnit.repetitions,
            SetSide.none, null, BigDecimal.TEN, null, null, null, null, null, null))
    }

    private val tables = listOf("students", "sessions", "session_exercises", "training_sets", "session_training_focus",
        "course_packages", "credit_adjustments", "active_package_claims", "session_sections", "active_session_pointers",
        "training_templates", "template_training_focus", "template_exercises", "template_planned_sets",
        "exercise_catalog", "exercise_preferences", "exercise_name_claims", "store_metadata")

    // Full row snapshots detect unintended updates as well as deletion; order by every column.
    private fun snapshot(): Map<String, List<List<String?>>> = tables.associateWith { table ->
        db.openHelper.readableDatabase.query("SELECT * FROM `$table`").use { cursor ->
            val rows = mutableListOf<List<String?>>()
            while (cursor.moveToNext()) rows += (0 until cursor.columnCount).map { cursor.getString(it) }
            rows.sortedBy { it.joinToString("\u0000") }
        }
    }

    private var nextStudent = 70
    private val ids = object : StableIDGenerator {
        override fun newStudentID() = sid(nextStudent++)
        override fun newCoursePackageID(): CoursePackageID = error("Unused")
        override fun newCreditAdjustmentID(): CreditAdjustmentID = error("Unused")
        override fun newSessionID(): SessionID = error("Unused")
        override fun newTemplateID(): TemplateID = error("Unused")
        override fun newSectionID(): SectionID = error("Unused")
        override fun newSessionExerciseID(): SessionExerciseID = error("Unused")
        override fun newTemplateExerciseID(): TemplateExerciseID = error("Unused")
        override fun newTrainingSetID(): TrainingSetID = error("Unused")
        override fun newExerciseID(): StableExerciseID = error("Unused")
    }
}
