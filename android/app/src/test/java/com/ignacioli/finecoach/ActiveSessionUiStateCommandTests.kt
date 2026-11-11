// fictional-data: invented student and exercises in an isolated in-memory Room database.
package com.ignacioli.finecoach

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.features.exercises.ExerciseSelection
import com.ignacioli.finecoach.features.session.*
import com.ignacioli.finecoach.storage.*
import com.ignacioli.finecoach.storage.entity.StudentEntity
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class ActiveSessionUiStateCommandTests {
    private lateinit var db: FineCoachDatabase
    private lateinit var graph: S1AppGraph
    private lateinit var state: ActiveSessionUiState
    private val now = Instant.parse("2026-11-11T10:00:00Z")
    private var time = now
    private val ids = SequentialIDGenerator()
    private val student = ids.newStudentID()
    private val content get() = state.content!!
    private val exercise get() = content.exercises.first()
    private fun <T> ok(result: ApplicationResult<T>): T {
        assertTrue("Expected success: $result", result is ApplicationResult.Success)
        return (result as ApplicationResult.Success).value
    }
    private fun failed(result: ApplicationResult<*>) {
        assertTrue("Expected failure: $result", result is ApplicationResult.Failure)
        assertFalse(state.busy)
        assertNotNull(state.error)
        assertEquals((result as ApplicationResult.Failure).error, state.error)
    }
    private suspend fun persisted() = ok(graph.sessions.loadContent(content.session.sessionID))!!

    @Before fun prepare() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, FineCoachDatabase::class.java).allowMainThreadQueries().build()
        val generation = UUID.randomUUID()
        db.openHelper.writableDatabase.execSQL("INSERT INTO store_metadata (`key`, value) VALUES (?, ?)",
            arrayOf(FineCoachDatabaseFactory.GENERATION_KEY, generation.toString()))
        graph = S1AppGraph(db, AppClock { time }, ids, generation, context)
        db.s1Dao().insert(StudentEntity(UUID.fromString(student.value), "虚构学员", StudentSex.undisclosed,
            null, null, null, null, null, StudentLifecycle.active, now, now))
        state = ActiveSessionUiState(graph.active, graph.clock, ids, graph.sessions, graph.historyRepository, graph.exercises)
        state.load(ok(graph.sessions.startOrOpen(StartOrOpenSessionCommand(student, nowUTC = now))).sessionID)
        ok(state.addExercise(ExerciseSelection("虚构动作", RecordMode.weightReps, ExerciseSourceKind.sessionOnly, null)))
    }
    @After fun close() { db.close() }

    @Test fun confirmSetPersistsAndStartsRestOnlyAfterSuccess() = runBlocking {
        val id = ids.newTrainingSetID()
        ok(state.mutate { it.copy(session = it.session.addingSet(exercise.sessionExerciseID, id,
            TrainingSetInput(RecordMode.weightReps, weightValue = "10", repetitionCount = "8", unit = MeasurementUnit.kilograms), now)) })
        ok(state.confirmSet(id))
        assertEquals(SetRecordingState.completed, persisted().exercises.first().sets.single().state)
        assertEquals(id, state.undoableSetID)
        assertEquals(now.plusSeconds(120), state.rests.end(content.session.sessionID))
    }
    @Test fun confirmMissingSetDoesNotPersistOrStartRest() = runBlocking {
        val before = persisted()
        val missing = ids.newTrainingSetID()
        repeat(2) {
            failed(state.confirmSet(missing))
            assertEquals(before, persisted())
            assertNull(state.rests.end(content.session.sessionID))
            assertNull(state.undoableSetID)
        }
    }
    @Test fun saveSectionCreatesAndRenamesButRejectsBlankName() = runBlocking {
        ok(state.saveSection(null, "虚构分区"))
        val id = content.sections.single().sectionID
        ok(state.saveSection(id, "虚构改名"))
        assertEquals("虚构改名", persisted().sections.single().name)
        val before = persisted()
        failed(state.saveSection(null, " "))
        assertEquals(before, persisted())
    }
    @Test fun saveSectionRejectsMissingRenameTarget() = runBlocking {
        val before = persisted()
        failed(state.saveSection(ids.newSectionID(), "虚构改名"))
        assertEquals(before, persisted())
    }
    @Test fun deleteSectionPreservesMembersWhenRequestedAndDeletesEmptySection() = runBlocking {
        ok(state.saveSection(null, "虚构分区"))
        val id = content.sections.single().sectionID
        ok(state.moveExercise(exercise.sessionExerciseID, id))
        ok(state.deleteSection(id, true))
        assertTrue(persisted().sections.isEmpty())
        assertNull(persisted().exercises.single().sectionID)
        ok(state.saveSection(null, "虚构空分区"))
        ok(state.deleteSection(content.sections.single().sectionID, false))
        assertTrue(persisted().sections.isEmpty())
        assertEquals(1, persisted().exercises.size)
    }
    @Test fun deleteMissingSectionRejectsBothDispositionsWithoutWrites() = runBlocking {
        val before = persisted()
        for (move in listOf(true, false)) {
            val missing = ids.newSectionID()
            repeat(2) {
                failed(state.deleteSection(missing, move))
                assertEquals(before, persisted())
            }
        }
    }
    @Test fun moveExercisePersistsMembershipAndUnsectionedDestination() = runBlocking {
        ok(state.saveSection(null, "虚构分区"))
        val id = content.sections.single().sectionID
        ok(state.moveExercise(exercise.sessionExerciseID, id))
        assertEquals(id, persisted().exercises.single().sectionID)
        ok(state.moveExercise(exercise.sessionExerciseID, null))
        assertNull(persisted().exercises.single().sectionID)
    }
    @Test fun moveExerciseRejectsUnknownDestinationAndUnknownExercise() = runBlocking {
        val before = persisted()
        failed(state.moveExercise(exercise.sessionExerciseID, ids.newSectionID()))
        assertEquals(before, persisted())
        failed(state.moveExercise(ids.newSessionExerciseID(), null))
        assertEquals(before, persisted())
    }
    @Test fun keyboardHiddenClearsExpiredRestAndPreservesRunningRest() {
        val id = content.session.sessionID
        state.rests.start(id)
        state.keyboardHidden(id)
        assertEquals(now.plusSeconds(120), state.rests.end(id))
        time = now.plusSeconds(120)
        state.keyboardHidden(id)
        assertNull(state.rests.end(id))
        state.keyboardHidden(id)
        assertNull(state.rests.end(id))
    }
    @Test fun studentDisplayNamePreservesSuccessMissingAndFailureText() = runBlocking {
        assertEquals("虚构学员", state.studentDisplayName(graph.studentRepository, student))
        assertEquals("", state.studentDisplayName(graph.studentRepository, ids.newStudentID()))
        assertNull(state.studentDisplayName(null, student))
        val failedRepository = object : StudentRepositoryPort by graph.studentRepository {
            override suspend fun find(studentID: StudentID): ApplicationResult<StudentRecord?> =
                ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed))
        }
        assertEquals("学员信息暂不可用", state.studentDisplayName(failedRepository, student))
    }
    @Test fun saveSetEntryAssemblesBilateralWeightAndRejectsInvalidInput() = runBlocking {
        ok(state.saveSetEntry(exercise, null, null, true, true,
            SetEntryValues(reps = "8", left = "15.125", right = "10.25", split = true)))
        val set = persisted().exercises.single().sets.single()
        assertEquals("10.25", set.weightValue!!.toPlainString())
        assertEquals(SetSide.bilateral, set.side)
        assertEquals("15.125", set.leftValue!!.toPlainString())
        assertEquals("10.25", set.rightValue!!.toPlainString())
        assertEquals(MeasurementUnit.kilograms, set.unit)
        assertEquals(now.plusSeconds(120), state.rests.end(content.session.sessionID))
        val before = persisted()
        failed(state.saveSetEntry(exercise, null, null, false, false, SetEntryValues(weight = "invalid", reps = "8")))
        assertEquals(before, persisted())
    }
    @Test fun saveSetEntryEditsWithoutStartingNewRestAndParsesDuration() = runBlocking {
        ok(state.addExercise(ExerciseSelection("虚构计时", RecordMode.duration, ExerciseSourceKind.sessionOnly, null)))
        val timed = content.exercises.last()
        ok(state.saveSetEntry(timed, null, null, false, false, SetEntryValues(duration = "1分30秒")))
        val set = persisted().exercises.last().sets.single()
        assertEquals("90", set.durationSeconds!!.toPlainString())
        state.rests.clear(content.session.sessionID)
        ok(state.saveSetEntry(content.exercises.last(), set, set, false, false, SetEntryValues(duration = "45")))
        assertEquals("45", persisted().exercises.last().sets.single().durationSeconds!!.toPlainString())
        assertNull(state.rests.end(content.session.sessionID))
        val before = persisted()
        failed(state.saveSetEntry(content.exercises.last(), set, set, false, false, SetEntryValues(duration = "bad")))
        assertEquals(before, persisted())
    }
    @Test fun shiftAxisMovesWholeSectionBlockAndKeepsBoundaryUnchanged() = runBlocking {
        ok(state.saveSection(null, "虚构分区"))
        val section = content.sections.single().sectionID
        val moved = ActiveSessionUiState.sessionShiftAxis(content, section.value, -1)
        assertEquals(SessionSectionAxisItem.Section(section), moved.first())
        assertEquals(SessionSectionAxisItem.Exercise(exercise.sessionExerciseID.value), moved.last())
        assertEquals(listOf(SessionSectionAxisItem.Exercise(exercise.sessionExerciseID.value), SessionSectionAxisItem.Section(section)),
            ActiveSessionUiState.sessionShiftAxis(content, exercise.sessionExerciseID.value, -1))
        ok(state.moveExercise(exercise.sessionExerciseID, section))
        assertEquals(listOf(SessionSectionAxisItem.Section(section), SessionSectionAxisItem.Exercise(exercise.sessionExerciseID.value)),
            ActiveSessionUiState.sessionShiftAxis(content, exercise.sessionExerciseID.value, -1))
    }
    @Test fun recordedSideWeightUsesAssistanceRuleAndRejectsMalformedSides() {
        assertEquals("15.125", ActiveSessionUiState.recordedSideWeight("15.125", "10.25", false))
        assertEquals("10.25", ActiveSessionUiState.recordedSideWeight("15.125", "10.25", true))
        assertEquals("", ActiveSessionUiState.recordedSideWeight("invalid", "10", false))
        assertEquals("", ActiveSessionUiState.recordedSideWeight("10", "invalid", true))
    }
}
