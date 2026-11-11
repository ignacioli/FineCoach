// fictional-data: in-memory Room data and invented names only.
package com.ignacioli.finecoach

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.features.exercises.*
import com.ignacioli.finecoach.storage.*
import com.ignacioli.finecoach.storage.repository.*
import kotlinx.coroutines.runBlocking
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.Instant
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class ExerciseStateCommandTests {
    private lateinit var db: FineCoachDatabase
    private lateinit var repository: ExerciseRepository
    private lateinit var state: ExerciseUiState
    private val clock = AppClock { Instant.parse("2026-11-11T00:00:00Z") }
    @Before fun prepare() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, FineCoachDatabase::class.java).allowMainThreadQueries().build()
        repository = ExerciseRepository(db, ExerciseCatalogLoader(context.assets), clock)
        state = ExerciseUiState(ExerciseUseCases(repository, clock, SequentialIDGenerator()), repository)
    }
    @After fun close() { db.close() }
    private suspend fun custom(): ExerciseRecord {
        state.saveCustomExercise(null, "虚构动作", RecordMode.reps) {}
        return repository.listCatalog().requireSuccess().single()
    }
    @Test fun createLibraryExercisePersistsAndRefreshesSearch() = runBlocking {
        state.createLibraryExercise("虚构动作", RecordMode.reps)
        assertNull(state.error)
        assertEquals("虚构动作", state.entries.single().canonicalName)
        assertEquals(RecordMode.reps, repository.listCatalog().requireSuccess().single().recordMode)
        assertFalse(state.busy)
    }
    @Test fun createLibraryExerciseRejectsBlankAndRetainsResults() = runBlocking {
        custom(); state.search("虚构")
        val before = state.entries
        state.createLibraryExercise(" ", RecordMode.reps)
        assertEquals(ApplicationErrorCode.emptyText, state.error?.code)
        assertEquals(before, state.entries)
        assertEquals(1, repository.listCatalog().requireSuccess().size)
        assertFalse(state.busy)
    }
    @Test fun preferencePersistsAllFieldsAndCallsSuccess() = runBlocking {
        val item = custom()
        val command = UpdateExercisePreferenceCommand(item.exerciseID, "虚构别名", true, true, true, false)
        var calls = 0
        state.updateLibraryPreference(command) { calls++ }
        val stored = repository.preference(item.exerciseID).requireSuccess()!!
        assertEquals("虚构别名", stored.alias)
        assertTrue(stored.isFavorite && stored.isHidden && stored.isAssisted)
        assertEquals(false, stored.isUnilateral)
        assertEquals(1, calls); assertNull(state.error); assertFalse(state.busy)
    }
    @Test fun preferenceFailureDoesNotCallSuccess() = runBlocking {
        var calls = 0
        state.updateLibraryPreference(UpdateExercisePreferenceCommand(StableExerciseID.parse("fictional-missing"), null, true, false, false, null)) { calls++ }
        assertEquals(0, calls); assertNotNull(state.error); assertFalse(state.busy)
    }
    @Test fun saveCreatesThenUpdatesSameIdentity() = runBlocking {
        val item = custom()
        var calls = 0
        state.saveCustomExercise(item, "虚构改名", RecordMode.duration) { calls++ }
        val stored = repository.listCatalog().requireSuccess().single()
        assertEquals(item.exerciseID, stored.exerciseID)
        assertEquals("虚构改名", stored.canonicalName); assertEquals(RecordMode.duration, stored.recordMode)
        assertEquals(1, calls); assertNull(state.error); assertFalse(state.busy)
    }
    @Test fun saveFailureDoesNotNavigateOrReplaceRecord() = runBlocking {
        val item = custom()
        var calls = 0
        state.saveCustomExercise(item, "", RecordMode.duration) { calls++ }
        assertEquals(0, calls); assertNotNull(state.error)
        assertEquals(item, repository.listCatalog().requireSuccess().single()); assertFalse(state.busy)
    }
    @Test fun archiveThenRestoreReturnsDurableRecord() = runBlocking {
        val item = custom()
        var updated = item
        state.setCustomExerciseArchived(item, true) { updated = it }
        assertEquals(ExerciseLifecycle.archived, updated.lifecycle)
        assertEquals(updated, repository.listCatalog().requireSuccess().single())
        state.setCustomExerciseArchived(updated, false) { updated = it }
        assertEquals(ExerciseLifecycle.active, updated.lifecycle)
        assertEquals(updated, repository.listCatalog().requireSuccess().single()); assertFalse(state.busy)
    }
    @Test fun invalidArchiveAndRestoreDoNotCallSuccess() = runBlocking {
        val item = custom()
        var calls = 0
        state.setCustomExerciseArchived(item, false) { calls++ }
        assertNotNull(state.error); assertEquals(0, calls)
        state.setCustomExerciseArchived(item, true) { calls++ }
        state.setCustomExerciseArchived(item, true) { calls++ }
        assertEquals(1, calls); assertNotNull(state.error); assertFalse(state.busy)
    }
}
