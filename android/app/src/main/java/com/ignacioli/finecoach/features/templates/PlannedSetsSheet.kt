package com.ignacioli.finecoach.features.templates

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.template.TemplatePlannedSet
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.exercises.exerciseErrorTitle
import kotlinx.coroutines.launch

/** Drafts contain only input values; no completion state or training identity is written. */
private data class PlannedInput(
    val weight: String = "", val reps: String = "", val duration: String = "", val left: String = "",
    val right: String = "", val distance: String = "", val speed: String = "", val resistance: String = "",
    val unit: MeasurementUnit, val side: SetSide = SetSide.none,
) {
    fun input(mode: RecordMode) = TrainingSetInput(mode, weight.ifBlank { null }, reps.ifBlank { null },
        duration.ifBlank { null }, unit, side, left.ifBlank { null }, right.ifBlank { null },
        distance.ifBlank { null }, speed.ifBlank { null }, resistance.ifBlank { null })
}

@Composable
internal fun PlannedSetsSheet(state: TemplateUiState, row: TemplateExerciseRecord, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    fun initial(record: TemplatePlannedSetRecord) = PlannedInput(record.weightValue?.toPlainString() ?: "",
        record.repetitionCount?.toPlainString() ?: "", record.durationSeconds?.toPlainString() ?: "",
        record.leftValue?.toPlainString() ?: "", record.rightValue?.toPlainString() ?: "", record.distanceValue?.toPlainString() ?: "",
        record.speedValue?.toPlainString() ?: "", record.resistanceValue?.toPlainString() ?: "", record.unit, record.side)
    fun blank() = PlannedInput(unit = when (row.recordModeSnapshot) {
        RecordMode.weightReps -> MeasurementUnit.kilograms
        RecordMode.reps -> MeasurementUnit.repetitions
        RecordMode.duration, RecordMode.cardio -> MeasurementUnit.seconds
    })
    var drafts by remember(row.templateExerciseID) { mutableStateOf(row.plannedSets.map(::initial)) }
    var editing by remember { mutableIntStateOf(-1) }
    var input by remember { mutableStateOf(blank()) }
    FcBottomSheet("计划组 · ${row.displayNameSnapshot}", { if (!state.busy) onDismiss() }, skipPartiallyExpanded = true) {
        Column(Modifier.fillMaxWidth().heightIn(max = FcComponentMetrics.row * 8).imePadding()
            .verticalScroll(rememberScrollState()).testTag("planned-content"), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            drafts.forEachIndexed { index, _ ->
                FcListRow("第 ${index + 1} 个计划组", Modifier.testTag("planned-edit-$index"), mode = FcRowMode.Action { editing = index; input = drafts[index] })
                FcActionRow("删除计划组", Modifier.testTag("planned-delete-$index"), enabled = !state.busy) {
                    drafts = drafts.filterIndexed { position, _ -> position != index }; editing = -1; input = blank()
                }
            }
            if (row.recordModeSnapshot == RecordMode.weightReps) {
                FcTextField("重量", input.weight, { input = input.copy(weight = it) }, Modifier.testTag("planned-weight"))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                    listOf(MeasurementUnit.kilograms to "kg", MeasurementUnit.pounds to "lb").forEach { (unit, title) ->
                        FcFilterChip(title, input.unit == unit, Modifier.testTag("planned-unit-${unit.name}")) { input = input.copy(unit = unit) }
                    }
                    SetSide.entries.forEach { side ->
                        FcFilterChip(when (side) { SetSide.none -> "非单侧"; SetSide.left -> "左侧"; SetSide.right -> "右侧"; SetSide.bilateral -> "双侧分别" },
                            input.side == side, Modifier.testTag("planned-side-${side.name}")) { input = input.copy(side = side) }
                    }
                }
                if (input.side != SetSide.none) {
                    FcTextField("左侧重量", input.left, { input = input.copy(left = it) }, Modifier.testTag("planned-left"))
                    FcTextField("右侧重量", input.right, { input = input.copy(right = it) }, Modifier.testTag("planned-right"))
                }
            }
            if (row.recordModeSnapshot == RecordMode.weightReps || row.recordModeSnapshot == RecordMode.reps)
                FcTextField("次数", input.reps, { input = input.copy(reps = it) }, Modifier.testTag("planned-reps"))
            if (row.recordModeSnapshot == RecordMode.duration || row.recordModeSnapshot == RecordMode.cardio)
                FcTextField("时长（秒）", input.duration, { input = input.copy(duration = it) }, Modifier.testTag("planned-duration"))
            if (row.recordModeSnapshot == RecordMode.cardio) {
                FcTextField("距离（km）", input.distance, { input = input.copy(distance = it) }, Modifier.testTag("planned-distance"))
                FcTextField("速度", input.speed, { input = input.copy(speed = it) }, Modifier.testTag("planned-speed"))
                FcTextField("阻力", input.resistance, { input = input.copy(resistance = it) }, Modifier.testTag("planned-resistance"))
            }
            FcSecondaryButton(if (editing < 0) "添加计划组" else "更新计划组", Modifier.testTag("planned-stage"), !state.busy) {
                drafts = if (editing < 0) drafts + input else drafts.mapIndexed { index, previous -> if (index == editing) input else previous }
                editing = -1; input = blank()
            }
            state.error?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("planned-error")) }
            FcButton("保存计划组", Modifier.testTag("planned-save"), !state.busy) {
                scope.launch {
                    val result = state.mutate { template ->
                        val values = drafts.map { draft -> TemplatePlannedSet.copyingValuesFrom(TrainingSet.makeDraft(
                            state.ids.newTrainingSetID(), state.ids.newSessionExerciseID(), 0u, draft.input(row.recordModeSnapshot), state.clock.now())) }
                        template.replacingPlannedSets(row.templateExerciseID, values, state.clock.now())
                    }
                    if (result is ApplicationResult.Success) onDismiss()
                }
            }
            FcSecondaryButton("取消", Modifier.testTag("planned-cancel"), !state.busy, onDismiss)
        }
    }
}
