// fictional-data: in-memory Room data and generic resource names only.
package com.ignacioli.finecoach

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.features.resources.ResourceHubState
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
class ResourceHubStateTests {
    private lateinit var db: FineCoachDatabase
    private lateinit var exercises: ExerciseRepository
    private lateinit var templates: TemplateUseCases
    private val clock = AppClock { Instant.parse("2026-11-11T00:00:00Z") }
    private val ids = SequentialIDGenerator()
    @Before fun prepare() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, FineCoachDatabase::class.java).allowMainThreadQueries().build()
        val generation = UUID.fromString("10000000-0000-4000-8000-000000000001")
        db.storeMetadataDao().insert(StoreMetadata(FineCoachDatabaseFactory.GENERATION_KEY, generation.toString()))
        exercises = ExerciseRepository(db, ExerciseCatalogLoader(context.assets), clock)
        templates = TemplateUseCases(TemplateRepository(db, clock, ids, generation), clock)
    }
    @After fun close() { db.close() }
    @Test fun loadCountsActiveNonRetiredExercisesAndTemplates() = runBlocking {
        exercises.synchronizeCatalog().requireSuccess()
        val commands = ExerciseUseCases(exercises, clock, ids)
        commands.createCustom("虚构保留", RecordMode.reps).requireSuccess()
        val archived = commands.createCustom("虚构归档", RecordMode.duration).requireSuccess()
        commands.archiveCustom(archived.exerciseID).requireSuccess()
        templates.save(SaveTemplateCommand(null, "虚构模板", emptySet(), null)).requireSuccess()
        val state = ResourceHubState()
        assertNull(state.exerciseSummary); assertNull(state.templateSummary)
        state.load(exercises, templates)
        val builtIn = exercises.listCatalog().requireSuccess().count {
            it.kind == ExerciseKind.builtIn && it.lifecycle == ExerciseLifecycle.active && !it.isRetired
        }
        assertTrue(builtIn > 0)
        assertEquals("内置 $builtIn 个 · 自定义 1 个", state.exerciseSummary)
        assertEquals("1 个模板", state.templateSummary)
    }
    @Test fun failedReadsShowErrorsRatherThanZeroCounts() = runBlocking {
        db.close()
        val state = ResourceHubState()
        state.load(exercises, templates)
        assertEquals("动作数量加载失败", state.exerciseSummary)
        assertEquals("模板数量加载失败", state.templateSummary)
    }
    @Test fun unavailableCatalogPreservesTemplateCount() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val unavailable = ExerciseRepository(db, ExerciseCatalogLoader(context.assets), clock) {
            throw java.io.IOException("fictional unavailable catalog")
        }
        unavailable.prepareCatalog()
        val state = ResourceHubState()
        state.load(unavailable, templates)
        assertEquals("动作库暂不可用", state.exerciseSummary)
        assertEquals("0 个模板", state.templateSummary)
    }
}
