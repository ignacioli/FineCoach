// fictional-data: synthetic completed sessions establish product sorting without overriding it.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.features.exercises.ExerciseUiState
import com.ignacioli.finecoach.storage.entity.*
import com.ignacioli.finecoach.storage.repository.HistoryRepository
import com.ignacioli.finecoach.storage.repository.ExerciseRepository
import androidx.test.core.app.ApplicationProvider
import android.content.Context
import java.math.BigDecimal
import java.time.ZoneOffset

internal class AddExerciseConformanceFixture : AutoCloseable {
    val training = TrainingConformanceFixture()
    val names = listOf("杠铃平板卧推", "蝴蝶机夹胸", "绳索夹胸", "哑铃上斜卧推", "俯卧撑")
    lateinit var state: ExerciseUiState
        private set
    init {
        val room = training.room
        val records = names.mapIndexed { index, _ -> ExerciseRecord(StableExerciseID.parse("fictional-add-exercise-$index"),
            ExerciseKind.builtIn, "${index.toString().padStart(2, '0')} 虚构动作", RecordMode.weightReps,
            "fictional.1", ExerciseLifecycle.active, false, "fictional-source", room.now, room.now) }
        val equipment = listOf("杠铃", "固定器械", "绳索", "哑铃", "徒手")
        val metadata = records.mapIndexed { index, row -> row.exerciseID to ExerciseCatalogMetadata("胸", equipment[index],
            if (index == 1 || index == 2) listOf("肩") else listOf("肩", "臂"), false) }.toMap()
        val repository = ExerciseRepository(room.db, ExerciseCatalogLoader(ApplicationProvider.getApplicationContext<Context>().assets),
            room.clock, readCatalog = { LoadedExerciseCatalog(records, emptyMap(), metadata) })
        val useCases = ExerciseUseCases(repository, room.clock, room.ids)
        room.test {
            room.ok(repository.synchronizeCatalog())
            records.forEachIndexed { index, record -> room.ok(useCases.updatePreference(UpdateExercisePreferenceCommand(
                record.exerciseID, names[index], false, false, false, null))) }
            val catalog = records
            names.forEachIndexed { index, name ->
                val item = catalog[index]
                val time = room.now.minusSeconds(3600L + index * 60)
                val sessionID = room.ids.newSessionID()
                val exerciseID = room.ids.newSessionExerciseID()
                room.db.s1Dao().insert(SessionEntity(java.util.UUID.fromString(sessionID.value), java.util.UUID.fromString(room.studentID(1).value), SessionState.completed,
                    time, time, BigDecimal.TEN, null, false, null, null, null, "1", time, time, time, null, null))
                room.db.s1Dao().insert(SessionExerciseEntity(java.util.UUID.fromString(exerciseID.value), java.util.UUID.fromString(sessionID.value), 0,
                    ExerciseSourceKind.builtIn, item.exerciseID.value, item.canonicalName, item.recordMode, null, null))
                room.db.s1Dao().insert(TrainingSetEntity(java.util.UUID.fromString(room.ids.newTrainingSetID().value),
                    java.util.UUID.fromString(exerciseID.value), 0, SetRecordingState.completed, RecordMode.weightReps,
                    BigDecimal.TEN, BigDecimal.TEN, null, null, null, null, null, null, MeasurementUnit.kilograms,
                    SetSide.none, time, time, time))
            }
        }
        room.test {
        state = ExerciseUiState(useCases, repository,
            HistoryRepository(room.db, room.clock, room.generation, ZoneOffset.UTC), room.sessions)
            state.reload("", studentID = room.studentID(1))
            check(state.recentEntries.map { state.selection(it).name } == names) { "Synthetic recent history mismatch; error=${state.error}, historyError=${state.historyError}" }
        }
    }
    override fun close() = training.close()
}
