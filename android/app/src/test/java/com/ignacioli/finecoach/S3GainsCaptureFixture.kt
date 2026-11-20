// fictional-data: approved design example values, names and entirely invented training history.
package com.ignacioli.finecoach

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.features.exercises.*
import com.ignacioli.finecoach.features.session.*
import com.ignacioli.finecoach.features.templates.*
import com.ignacioli.finecoach.storage.repository.*
import java.util.UUID

internal class S3GainsCaptureFixture(milestoneOnly: Boolean = false) : AutoCloseable {
    val room = T009Fixture()
    lateinit var active: ActiveSessionUiState
    lateinit var summary: SessionSummaryUiState
    lateinit var exercises: ExerciseUiState
    lateinit var templates: TemplateUiState
    lateinit var content: SessionContentRecord
    val squat get() = content.exercises.first()
    init { room.test {
        val repo = ExerciseRepository(room.db, ExerciseCatalogLoader(ApplicationProvider.getApplicationContext<Context>().assets), room.clock)
        repo.prepareCatalog()
        val catalog = room.ok(repo.listCatalog())
        val squatID = catalog.single { it.canonicalName == "杠铃深蹲" }.exerciseID
        val benchID = catalog.single { it.canonicalName == "杠铃平板卧推" }.exerciseID
        val cases = ExerciseUseCases(repo, room.clock, room.ids)
        val start = room.now.minusSeconds(24L * 86400)
        suspend fun training(number: Int, current: Boolean): SessionContentRecord {
            room.now = start.plusSeconds(number * 86400L)
            val initial = room.content(sourceID = squatID)
            fun exercise(name: String, source: StableExerciseID?, order: UInt, weights: List<String>, reps: String, duration: Boolean = false): SessionExerciseRecord {
                val id = room.ids.newSessionExerciseID()
                val mode = if (duration) RecordMode.duration else RecordMode.weightReps
                val sets = weights.mapIndexed { index, value -> TrainingSet.makeDraft(room.ids.newTrainingSetID(), id, index.toUInt(),
                    if (duration) TrainingSetInput(mode, durationSeconds = value, unit = MeasurementUnit.seconds)
                    else TrainingSetInput(mode, weightValue = value, repetitionCount = reps, unit = MeasurementUnit.kilograms), room.now).confirmed(room.now) }
                return SessionExercise(id, initial.session.sessionID, order, if (source == null) ExerciseSourceKind.sessionOnly else ExerciseSourceKind.builtIn,
                    source, NormalizedName.parse(name), mode, null, null, sets).toRecord()
            }
            val rows = if (milestoneOnly) listOf(exercise("深蹲", squatID, 0u, listOf("120"), "8")) else listOf(
                exercise("深蹲", squatID, 0u, if (current) listOf("120", "122.5") else listOf("120"), if (current) "6" else "8"),
                exercise("卧推", benchID, 1u, if (current) emptyList() else listOf(if (number == 0) "100" else "80"), "8"))
            return room.ok(room.sessions.saveContent(SaveSessionContentCommand(initial.session.sessionID, initial.session.revision, emptyList(), rows)))
        }
        val count = if (milestoneOnly) 9 else 24
        repeat(count) { room.finish(training(it, false)) }
        content = training(count, true)
        val progress = ProgressUseCases(room.history, room.sessions)
        active = ActiveSessionUiState(room.active, room.clock, room.ids, room.sessions, room.history, cases, progress = progress, zone = room.zone)
        exercises = ExerciseUiState(cases, repo)
        val generation = UUID.fromString(room.db.storeMetadataDao().find(com.ignacioli.finecoach.storage.FineCoachDatabaseFactory.GENERATION_KEY)!!.value)
        templates = TemplateUiState(TemplateUseCases(TemplateRepository(room.db, room.clock, room.ids, generation), room.clock), room.clock, room.ids)
        summary = SessionSummaryUiState(room.historyCases, room.clock, progress, room.zone)
    } }
    fun finishForSummary() = room.test {
        active.load(content.session.sessionID)
        if (content.exercises.size > 1) {
            room.ok(active.saveSet(content.exercises[1].sessionExerciseID, null,
                TrainingSetInput(RecordMode.weightReps, weightValue = "80", repetitionCount = "10", unit = MeasurementUnit.kilograms)))
        }
        room.finish(active.content!!)
    }
    override fun close() = room.close()
}
