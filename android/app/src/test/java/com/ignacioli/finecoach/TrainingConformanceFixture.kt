// fictional-data: all student/training values are the approved synthetic design example.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.features.session.*
import com.ignacioli.finecoach.features.exercises.*
import com.ignacioli.finecoach.features.templates.*
import com.ignacioli.finecoach.storage.repository.HistoryRepository
import java.time.ZoneOffset

internal class TrainingConformanceFixture : AutoCloseable {
    val room = T008Fixture()
    lateinit var state: ActiveSessionUiState
    lateinit var exercises: ExerciseUiState
    lateinit var templates: TemplateUiState
    lateinit var content: SessionContentRecord
    lateinit var squat: SessionExerciseRecord
    lateinit var bench: SessionExerciseRecord
    init {
        room.test {
            room.student(1)
            room.db.openHelper.writableDatabase.execSQL("UPDATE students SET displayName = ?", arrayOf("王小明"))
            room.time = room.now.minusSeconds(1920)
            val started = room.ok(room.sessions.startOrOpen(StartOrOpenSessionCommand(room.studentID(1), setOf(BodyPart.thighs, BodyPart.glutes), room.time)))
            room.exercises.prepareCatalog()
            val catalog = room.ok(room.exercises.listCatalog())
            fun row(name: String, order: UInt, count: Int, weight: String, reps: String): SessionExerciseRecord {
                val source = catalog.single { it.canonicalName == if (name.startsWith("深蹲")) "杠铃深蹲" else "杠铃平板卧推" }
                val id = room.ids.newSessionExerciseID()
                return SessionExercise(id, started.sessionID, order, ExerciseSourceKind.builtIn, source.exerciseID,
                    NormalizedName.parse(name.substringBefore("（")), RecordMode.weightReps, null, null,
                    (0 until count).map { n -> TrainingSet.makeDraft(room.ids.newTrainingSetID(), id, n.toUInt(),
                        TrainingSetInput(RecordMode.weightReps, weightValue = weight, repetitionCount = reps, unit = MeasurementUnit.kilograms), room.time).confirmed(room.time) }).toRecord()
            }
            // Current training records use the real Room/use-case path; previous references are fixture UI state.
            squat = row("深蹲（杠铃）", 0u, 1, "120", "8")
            bench = row("卧推（杠铃）", 1u, 0, "80", "10")
            content = room.ok(room.sessions.saveContent(SaveSessionContentCommand(started.sessionID, started.revision, emptyList(), listOf(squat, bench))))
            room.time = room.now
            val useCases = ExerciseUseCases(room.exercises, room.clock, room.ids)
            exercises = ExerciseUiState(useCases, room.exercises)
            templates = TemplateUiState(room.templateUseCases, room.clock, room.ids)
            state = ActiveSessionUiState(room.useCases, room.clock, room.ids, room.sessions,
                HistoryRepository(room.db, room.clock, room.generation, ZoneOffset.UTC), useCases)
        }
    }
    fun confirmSecondAndReferences() = room.test {
        val second = room.ids.newTrainingSetID()
        room.ok(state.mutate { sectioned -> sectioned.copy(session = sectioned.session.addingSet(squat.sessionExerciseID, second,
            TrainingSetInput(RecordMode.weightReps, weightValue = "120", repetitionCount = "8", unit = MeasurementUnit.kilograms), room.now).confirmingSet(second, room.now)) })
        state.previous[squat.sessionExerciseID] = squat.sets.first()
        state.previousCounts[squat.sessionExerciseID] = 4
        state.previous[bench.sessionExerciseID] = squat.sets.first().copy(sessionExerciseID = bench.sessionExerciseID,
            weightValue = "80".toBigDecimal(), repetitionCount = "10".toBigDecimal())
        state.previousCounts[bench.sessionExerciseID] = 3
        state.rests.adjust(content.session.sessionID, -15)
    }
    override fun close() = room.close()
}
