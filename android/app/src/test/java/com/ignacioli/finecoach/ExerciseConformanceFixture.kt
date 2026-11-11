// fictional-data: synthetic catalog order uses persisted aliases to reproduce the approved screen sample.
package com.ignacioli.finecoach

import androidx.test.core.app.ApplicationProvider
import android.content.Context
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.template.*
import com.ignacioli.finecoach.features.exercises.*
import com.ignacioli.finecoach.storage.repository.ExerciseRepository

internal class ExerciseConformanceFixture : AutoCloseable {
    val room = T008Fixture()
    val names = listOf("杠铃平板卧推", "哑铃上斜卧推", "蝴蝶机夹胸", "器械推胸", "史密斯上斜卧推", "绳索夹胸", "俯卧撑")
    private val equipment = listOf("杠铃", "哑铃", "固定器械", "固定器械", "史密斯机", "绳索", "徒手")
    private val records = (0 until 21).map { index -> ExerciseRecord(StableExerciseID.parse("fictional-conformance-$index"),
        ExerciseKind.builtIn, "${index.toString().padStart(2, '0')} 虚构动作", RecordMode.weightReps, "fictional.1",
        ExerciseLifecycle.active, false, "fictional-source", room.now, room.now) }
    private val metadata = records.mapIndexed { index, record -> record.exerciseID to ExerciseCatalogMetadata("胸",
        equipment.getOrElse(index) { "杠铃" }, if (index in listOf(2, 5)) listOf("肩") else listOf("肩", "臂"), false) }.toMap()
    private val repository = ExerciseRepository(room.db, ExerciseCatalogLoader(ApplicationProvider.getApplicationContext<Context>().assets),
        room.clock, readCatalog = { LoadedExerciseCatalog(records, emptyMap(), metadata) })
    val state = ExerciseUiState(ExerciseUseCases(repository, room.clock, room.ids), repository)
    init { room.test {
        room.ok(repository.synchronizeCatalog())
        records.forEachIndexed { index, record -> room.ok(state.useCases.updatePreference(UpdateExercisePreferenceCommand(record.exerciseID,
            names.getOrElse(index) { "虚构动作 $index" }, false, false, false, null))) }
        state.reload("")
        check(state.entries.size == 21 && state.sections("胸", null).single().entries.size == 21)
        check(room.count("sessions") == 0L)
    } }
    override fun close() = room.close()
}

internal fun seedConformanceTemplates(fixture: TrainingConformanceFixture): Map<String, String> {
    val bindings = mutableMapOf<String, String>()
    fixture.room.test {
    val room = fixture.room
    val specs = listOf(Triple("下肢力量 A", setOf(BodyPart.thighs, BodyPart.glutes), 5),
        Triple("上肢推", setOf(BodyPart.chest, BodyPart.shoulders, BodyPart.arms), 6),
        Triple("核心激活", setOf(BodyPart.core), 4))
    specs.asReversed().forEachIndexed { index, (name, focus, count) ->
        room.time = room.now.minusSeconds((3 - index).toLong())
        val record = room.ok(room.templates.save(SaveTemplateCommand(null, name, focus, null)))
        bindings["template${3 - index}ID"] = record.templateID.value
        val exercises = (0 until count).map { n -> TemplateExercise(room.ids.newTemplateExerciseID(), record.templateID, null,
            n.toUInt(), ExerciseSourceKind.sessionOnly, null, NormalizedName.parse("虚构计划动作 $n"), RecordMode.weightReps, emptyList()).toRecord() }
        room.ok(room.templates.saveContent(SaveTemplateContentCommand(record.templateID, record.revision, emptyList(), exercises)))
    }
    room.time = room.now
    }
    return bindings.toMap()
}
