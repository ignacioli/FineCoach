// fictional-data: synthetic student and completed sets from the approved S1 board.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.features.history.*
import com.ignacioli.finecoach.storage.repository.*
import java.time.LocalDate

internal class SessionDetailConformanceFixture : AutoCloseable {
    val room = T009Fixture()
    val zone = room.zone
    private var seededSessionID: SessionID? = null
    val sessionID: SessionID get() = checkNotNull(seededSessionID)
    lateinit var state: HistoryUiState
    lateinit var templates: HistoryTemplateState
    init {
        room.test {
            val completedAt = LocalDate.of(2025, 9, 25).atTime(12, 0).atZone(zone).toInstant()
            room.now = completedAt.minusSeconds(58 * 60)
            room.db.openHelper.writableDatabase.execSQL("UPDATE students SET displayName = ?", arrayOf("王小明"))
            room.coursePackage()
            val started = room.ok(room.sessions.startOrOpen(StartOrOpenSessionCommand(room.studentID,
                setOf(BodyPart.thighs, BodyPart.glutes), room.now)))
            seededSessionID = started.sessionID
            val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>()
            val repository = ExerciseRepository(room.db, ExerciseCatalogLoader(context.assets), room.clock)
            repository.prepareCatalog()
            val catalog = room.ok(repository.listCatalog())
            val specs = listOf(
                "杠铃深蹲" to listOf("60" to "12", "80" to "10", "90" to "8", "90" to "8"),
                "腿屈伸" to listOf("35" to "15", "40" to "12", "40" to "12"),
                "髋外展" to listOf("45" to "15", "50" to "15", "50" to "12"),
                "哑铃箭步蹲" to listOf("12" to "10", "12" to "10"))
            val exercises = specs.mapIndexed { order, (name, values) ->
                val source = catalog.single { it.canonicalName == if (name == "髋外展") "器械髋外展" else name }
                val id = room.ids.newSessionExerciseID()
                SessionExercise(id, sessionID, order.toUInt(), ExerciseSourceKind.builtIn, source.exerciseID,
                    NormalizedName.parse(name), RecordMode.weightReps, null, null,
                    values.mapIndexed { index, (weight, reps) -> TrainingSet.makeDraft(room.ids.newTrainingSetID(), id, index.toUInt(),
                        TrainingSetInput(RecordMode.weightReps, weightValue = weight, repetitionCount = reps,
                            unit = MeasurementUnit.kilograms), room.now).confirmed(room.now) }).toRecord()
            }
            val saved = room.ok(room.sessions.saveContent(SaveSessionContentCommand(sessionID, started.revision, emptyList(), exercises)))
            room.now = completedAt
            room.ok(room.finisher.finish(sessionID, saved.session.revision))
            state = HistoryUiState(room.historyCases, room.studentID,
                StudentUseCases(StudentRepository(room.db, room.clock), room.clock, room.ids))
            templates = HistoryTemplateState(TemplateUseCases(TemplateRepository(room.db, room.clock, room.ids,
                java.util.UUID.fromString(room.db.storeMetadataDao().find(com.ignacioli.finecoach.storage.FineCoachDatabaseFactory.GENERATION_KEY)!!.value)), room.clock), room.clock, room.ids)
        }
    }
    override fun close() = room.close()
}
