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
import kotlinx.coroutines.launch
import kotlinx.coroutines.CoroutineDispatcher
import kotlin.coroutines.CoroutineContext
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
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
    private val failPreferenceRead = java.util.concurrent.atomic.AtomicBoolean(false)
    private val failedReads = java.util.concurrent.atomic.AtomicInteger(0)
    private val batchPreferenceReads = java.util.concurrent.atomic.AtomicInteger(0)
    private val singlePreferenceReads = java.util.concurrent.atomic.AtomicInteger(0)
    private val clock = AppClock { Instant.parse("2026-11-11T00:00:00Z") }
    @Before fun prepare() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, FineCoachDatabase::class.java).allowMainThreadQueries()
            .openHelperFactory { configuration ->
                val helper = androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory().create(configuration)
                fun wrap(actual: androidx.sqlite.db.SupportSQLiteDatabase) = object : androidx.sqlite.db.SupportSQLiteDatabase by actual {
                    override fun query(query: androidx.sqlite.db.SupportSQLiteQuery): android.database.Cursor {
                        if (query.sql == "SELECT * FROM exercise_preferences WHERE `exerciseID` = ?") singlePreferenceReads.incrementAndGet()
                        if (query.sql == "SELECT * FROM exercise_preferences") batchPreferenceReads.incrementAndGet()
                        if (query.sql == "SELECT * FROM exercise_preferences" && failPreferenceRead.get()) {
                            failedReads.incrementAndGet()
                            throw android.database.sqlite.SQLiteException("fictional preference read failure")
                        }
                        return actual.query(query)
                    }
                }
                object : androidx.sqlite.db.SupportSQLiteOpenHelper by helper {
                    override val writableDatabase get() = wrap(helper.writableDatabase)
                    override val readableDatabase get() = wrap(helper.readableDatabase)
                }
            }.build()
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
    @Test fun searchReadsPreferencesOnceAndNeverPerResult() = runBlocking {
        val first = custom()
        state.createLibraryExercise("虚构第二动作", RecordMode.duration)
        val command = UpdateExercisePreferenceCommand(first.exerciseID, "虚构别名", true, false, true, false)
        state.updateLibraryPreference(command) {}
        batchPreferenceReads.set(0)
        singlePreferenceReads.set(0)
        state.search("")
        assertNull(state.error)
        assertEquals(2, state.entries.size)
        assertEquals("虚构别名", state.preference(first.exerciseID).alias)
        assertTrue(state.preference(first.exerciseID).isFavorite)
        assertEquals(false, state.preference(first.exerciseID).isUnilateral)
        assertEquals(1, batchPreferenceReads.get())
        assertEquals(0, singlePreferenceReads.get())
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
        state.updateLibraryPreference(command) {
            calls++
            assertTrue(state.busy)
            assertEquals(false, state.preference(item.exerciseID).isUnilateral)
            assertEquals("虚构别名", state.preference(item.exerciseID).alias)
        }
        val stored = repository.preference(item.exerciseID).requireSuccess()!!
        assertEquals("虚构别名", stored.alias)
        assertTrue(stored.isFavorite && stored.isHidden && stored.isAssisted)
        assertEquals(false, stored.isUnilateral)
        assertEquals(1, calls); assertNull(state.error); assertFalse(state.busy)
        state.openPreferenceID = item.exerciseID
        state.search("")
        assertTrue(state.entries.none { it.exerciseID == item.exerciseID })
        assertEquals(stored, state.preference(item.exerciseID))
        // The open sheet retains saved fields even when the refresh filters out the exercise.
        val reopened = state.preference(item.exerciseID)
        state.updateLibraryPreference(UpdateExercisePreferenceCommand(item.exerciseID, reopened.alias,
            false, reopened.isHidden, reopened.isAssisted, reopened.isUnilateral)) {}
        assertEquals(false, state.preference(item.exerciseID).isUnilateral)
        assertEquals(false, repository.preference(item.exerciseID).requireSuccess()!!.isUnilateral)
        state.openPreferenceID = null
        state.search("")
        assertFalse(state.preferences.containsKey(item.exerciseID))
    }
    @Test fun staleSearchCannotOverwriteSavedPreferenceOrNextCommand() = runBlocking {
        val item = custom()
        state.updateLibraryPreference(UpdateExercisePreferenceCommand(item.exerciseID, "虚构别名", false, false, false, null)) {}
        val pending = LinkedBlockingQueue<Runnable>()
        val dispatcher = object : CoroutineDispatcher() {
            override fun dispatch(context: CoroutineContext, block: Runnable) { pending.add(block) }
        }
        fun next(): Runnable = requireNotNull(pending.poll(15, TimeUnit.SECONDS)) { "Search continuation missing" }
        val search = launch(dispatcher) { state.search("") }
        next().run() // Start search; repository work runs on IO.
        val stalePreference = next() // The atomic search snapshot has not reached state yet.
        state.updateLibraryPreference(UpdateExercisePreferenceCommand(item.exerciseID, "虚构别名", false, true, true, false)) {}
        val saved = state.preference(item.exerciseID)
        stalePreference.run()
        search.join()
        assertEquals(saved, state.preference(item.exerciseID))
        val current = state.preference(item.exerciseID)
        state.updateLibraryPreference(UpdateExercisePreferenceCommand(item.exerciseID, current.alias,
            true, current.isHidden, current.isAssisted, current.isUnilateral)) {}
        val stored = repository.preference(item.exerciseID).requireSuccess()!!
        assertTrue(stored.isFavorite && stored.isHidden && stored.isAssisted)
        assertEquals(false, stored.isUnilateral)
        assertEquals("虚构别名", stored.alias)
    }
    @Test fun preferenceFailureDoesNotCallSuccess() = runBlocking {
        var calls = 0
        state.updateLibraryPreference(UpdateExercisePreferenceCommand(StableExerciseID.parse("fictional-missing"), null, true, false, false, null)) { calls++ }
        assertEquals(0, calls); assertNotNull(state.error); assertFalse(state.busy)
        assertTrue(state.preferences.isEmpty())
    }
    @Test fun stalePreferenceReadFailureCannotClearNewerSearchResults() = runBlocking {
        custom()
        val pending = LinkedBlockingQueue<Runnable>()
        val dispatcher = object : CoroutineDispatcher() {
            override fun dispatch(context: CoroutineContext, block: Runnable) { pending.add(block) }
        }
        fun next(): Runnable = requireNotNull(pending.poll(15, TimeUnit.SECONDS)) { "Search continuation missing" }
        failPreferenceRead.set(true)
        val oldSearch = launch(dispatcher) { state.search("") }
        next().run() // Start the failing batched preference read on IO.
        val staleFailure = next()
        assertEquals(1, failedReads.get())
        failPreferenceRead.set(false)
        state.search("虚构")
        val current = state.entries
        assertEquals(1, current.size)
        assertNull(state.error)
        staleFailure.run()
        oldSearch.join()
        assertEquals(current, state.entries)
        assertNull(state.error)
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
