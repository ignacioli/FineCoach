// fictional-data: invented templates and students in an in-memory Room database.
package com.ignacioli.finecoach

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.features.exercises.ExerciseSelection
import com.ignacioli.finecoach.features.templates.*
import com.ignacioli.finecoach.storage.*
import com.ignacioli.finecoach.storage.entity.StudentEntity
import com.ignacioli.finecoach.storage.repository.*
import java.math.BigDecimal
import java.util.UUID
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class TemplateUiStateTests {
    private lateinit var f: T008Fixture
    private lateinit var db: FineCoachDatabase
    private lateinit var repository: TemplateRepository
    private lateinit var state: TemplateUiState
    private lateinit var sessions: SessionRepository
    @Before fun prepare() {
        f = T008Fixture()
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, FineCoachDatabase::class.java).build()
        f.test {
            FineCoachDatabaseFactory.initializeGeneration(db.openHelper.writableDatabase)
            val generation = UUID.fromString(db.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)!!.value)
            repository = TemplateRepository(db, f.clock, f.ids, generation)
            sessions = SessionRepository(db, f.clock, f.ids, generation, ExerciseRepository(db, ExerciseCatalogLoader(context.assets), f.clock))
            state = TemplateUiState(TemplateUseCases(repository, f.clock), f.clock, f.ids)
        }
    }
    @After fun close() { f.test { db.close() }; f.close() }
    private suspend fun seed(): TemplateContentRecord {
        state.create("虚构模板") { }
        val template = f.ok(repository.list()).single()
        state.load(template.templateID)
        f.ok(state.saveSection(null, "虚构分段甲"))
        f.ok(state.saveSection(null, "虚构分段乙"))
        repeat(2) { f.ok(state.addExercise(ExerciseSelection("虚构动作$it", RecordMode.weightReps, ExerciseSourceKind.sessionOnly, null))) }
        return state.content!!
    }
    private suspend fun target(): SessionRecord {
        db.s1Dao().insert(StudentEntity(UUID.fromString(f.studentID(1).value), "虚构学员", StudentSex.undisclosed,
            null, null, null, null, null, StudentLifecycle.active, f.now, f.now))
        return f.ok(sessions.startOrOpen(f.startCommand()))
    }
    private suspend fun unchanged(before: TemplateContentRecord, result: ApplicationResult<Unit>) {
        assertTrue(result is ApplicationResult.Failure)
        assertEquals(before, state.content)
        assertEquals(before, f.ok(repository.loadContent(before.template.templateID)))
        assertNotNull(state.error)
        assertFalse(state.busy)
    }
    @Test fun createPersistsBeforeCallback() = f.test {
        var called = false
        state.create(" 虚构新模板 ") { called = true; assertEquals("虚构新模板", it.name); assertFalse(it.trainingFocus.isNotEmpty()) }
        assertTrue(called); assertEquals("虚构新模板", f.ok(repository.list()).single().name)
        assertNull(state.error); assertFalse(state.busy)
    }
    @Test fun createInvalidNameDoesNotCallSuccessOrWrite() = f.test {
        state.create(" ") { fail("Invalid create succeeded") }
        assertNotNull(state.error); assertFalse(state.busy); assertTrue(f.ok(repository.list()).isEmpty())
    }
    @Test fun applyCopiesContentAndCallsSuccess() = f.test {
        val before = seed(); val session = target()
        var applied: SessionContentRecord? = null
        state.apply(before.template, session) { applied = it }
        assertNotNull(applied)
        assertEquals(before.exercises.map { it.displayNameSnapshot }, applied!!.exercises.map { it.displayNameSnapshot })
        assertEquals(applied, f.ok(sessions.loadContent(session.sessionID)))
        assertEquals(before, f.ok(repository.loadContent(before.template.templateID)))
        assertNull(state.error); assertFalse(state.busy)
    }
    @Test fun applyStaleRevisionDoesNotCallSuccessOrChangeSession() = f.test {
        val before = seed(); val session = target(); val original = f.ok(sessions.loadContent(session.sessionID))
        state.apply(before.template.copy(revision = Revision(999uL)), session) { fail("Stale apply succeeded") }
        assertEquals(ApplicationErrorCode.staleRevision, state.error?.code)
        assertEquals(original, f.ok(sessions.loadContent(session.sessionID))); assertFalse(state.busy)
    }
    @Test fun deletePersistsAndCallsSuccess() = f.test {
        val before = seed(); var called = false
        state.delete(before.template.templateID) { called = true }
        assertTrue(called); assertNull(f.ok(repository.loadContent(before.template.templateID)))
        assertNull(state.error); assertFalse(state.busy)
    }
    @Test fun deleteMissingDoesNotCallSuccessOrChangeExistingTemplate() = f.test {
        val before = seed()
        state.delete(f.ids.newTemplateID()) { fail("Missing delete succeeded") }
        assertEquals(ApplicationErrorCode.notFound, state.error?.code)
        assertEquals(before, f.ok(repository.loadContent(before.template.templateID))); assertFalse(state.busy)
    }
    @Test fun saveSectionCreatesAndRenames() = f.test {
        val before = seed(); val section = before.sections.first()
        f.ok(state.saveSection(section.sectionID, "虚构重命名"))
        assertEquals("虚构重命名", state.content!!.sections.first().name)
        f.ok(state.saveSection(null, "虚构新分段"))
        assertEquals(3, state.content!!.sections.size)
        assertEquals(state.content, f.ok(repository.loadContent(before.template.templateID)))
    }
    @Test fun saveSectionInvalidCreateAndRenamePreserveContent() = f.test {
        val before = seed()
        unchanged(before, state.saveSection(null, " "))
        unchanged(before, state.saveSection(before.sections.first().sectionID, " "))
    }
    @Test fun reorderMovesSectionBlocksAndMembersWithinSection() = f.test {
        val before = seed(); val section = before.sections.first().sectionID
        before.exercises.forEach { f.ok(state.moveExercise(it.templateExerciseID, section)) }
        val grouped = state.content!!
        f.ok(state.reorder(grouped, section.value, 1))
        assertEquals(before.sections.last().sectionID, state.content!!.sections.minBy { it.orderIndex }.sectionID)
        val moved = state.content!!
        f.ok(state.reorder(moved, moved.exercises.first().templateExerciseID.value, 1))
        assertEquals(moved.exercises.first().templateExerciseID, state.content!!.exercises.maxBy { it.orderIndex }.templateExerciseID)
        assertEquals(state.content, f.ok(repository.loadContent(before.template.templateID)))
    }
    @Test fun reorderStaleSnapshotPreservesContent() = f.test {
        val before = seed()
        f.ok(repository.save(SaveTemplateCommand(before.template.templateID, "虚构外部更新", emptySet(), before.template.revision)))
        assertTrue(state.reorder(before, before.sections.first().sectionID.value, 1) is ApplicationResult.Failure)
        assertEquals(ApplicationErrorCode.staleRevision, state.error?.code)
        assertEquals(before, state.content); assertEquals("虚构外部更新", f.ok(repository.find(before.template.templateID))!!.name)
    }
    @Test fun deleteSectionKeepsMembersAndPlannedValuesWhenMovedOut() = f.test {
        val before = seed(); val row = before.exercises.first(); val section = before.sections.first().sectionID
        f.ok(state.moveExercise(row.templateExerciseID, section))
        f.ok(state.savePlannedSets(row, listOf(PlannedInput(weight = "12.125", reps = "8", unit = MeasurementUnit.kilograms))))
        val sets = state.content!!.exercises.first().plannedSets
        f.ok(state.deleteSection(section, SessionSectionDeletionDisposition.MoveExercisesTo(null)))
        assertEquals(1, state.content!!.sections.size)
        assertNull(state.content!!.exercises.first().sectionID)
        assertEquals(sets, state.content!!.exercises.first().plannedSets)
        f.ok(state.deleteSection(before.sections.last().sectionID, SessionSectionDeletionDisposition.DeleteWithExercises))
        assertTrue(state.content!!.sections.isEmpty())
        assertEquals(before.exercises.size, state.content!!.exercises.size)
        assertEquals(before.exercises.map { it.templateExerciseID }, state.content!!.exercises.map { it.templateExerciseID })
    }
    @Test fun deleteSectionMissingPreservesContent() = f.test {
        val before = seed()
        unchanged(before, state.deleteSection(f.ids.newSectionID(), SessionSectionDeletionDisposition.DeleteWithExercises))
    }
    @Test fun moveExerciseIntoAndOutOfSection() = f.test {
        val before = seed(); val id = before.exercises.first().templateExerciseID; val section = before.sections.first().sectionID
        f.ok(state.moveExercise(id, section)); assertEquals(section, state.content!!.exercises.first().sectionID)
        f.ok(state.moveExercise(id, null)); assertNull(state.content!!.exercises.first().sectionID)
        assertEquals(state.content, f.ok(repository.loadContent(before.template.templateID)))
    }
    @Test fun moveExerciseMissingTargetPreservesContent() = f.test {
        val before = seed()
        unchanged(before, state.moveExercise(before.exercises.first().templateExerciseID, f.ids.newSectionID()))
    }
    @Test fun removeExerciseDeletesOnlySelectedRow() = f.test {
        val before = seed()
        f.ok(state.removeExercise(before.exercises.first().templateExerciseID))
        assertEquals(listOf(before.exercises.last().templateExerciseID), state.content!!.exercises.map { it.templateExerciseID })
        assertEquals(state.content, f.ok(repository.loadContent(before.template.templateID)))
    }
    @Test fun removeExerciseMissingPreservesContent() = f.test {
        val before = seed(); unchanged(before, state.removeExercise(f.ids.newTemplateExerciseID()))
    }
    @Test fun savePlannedSetsCopiesValuesAndCanClear() = f.test {
        val before = seed(); val row = before.exercises.first()
        f.ok(state.savePlannedSets(row, listOf(PlannedInput(weight = "12.125", reps = "8", unit = MeasurementUnit.kilograms))))
        val planned = state.content!!.exercises.first().plannedSets.single()
        assertEquals(BigDecimal("12.125"), planned.weightValue); assertEquals(BigDecimal("8"), planned.repetitionCount)
        assertEquals(row.templateExerciseID, state.content!!.exercises.first().templateExerciseID)
        assertEquals(state.content, f.ok(repository.loadContent(before.template.templateID)))
        f.ok(state.savePlannedSets(row, emptyList())); assertTrue(state.content!!.exercises.first().plannedSets.isEmpty())
    }
    @Test fun savePlannedSetsInvalidInputPreservesContent() = f.test {
        val before = seed()
        unchanged(before, state.savePlannedSets(before.exercises.first(), listOf(PlannedInput(weight = "invalid", reps = "8", unit = MeasurementUnit.kilograms))))
    }
}
