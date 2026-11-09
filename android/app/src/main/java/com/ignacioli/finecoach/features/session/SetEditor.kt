package com.ignacioli.finecoach.features.session

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.exercises.exerciseErrorTitle
import kotlinx.coroutines.launch

@Composable
fun SetEditor(state: ActiveSessionUiState, exercise: SessionExerciseRecord, target: TrainingSetRecord?,
    unilateral: Boolean, assisted: Boolean, onDismiss: () -> Unit) {
    val initial = target ?: (exercise.sets.lastOrNull { it.state == SetRecordingState.completed } ?: exercise.sets.lastOrNull() ?: state.previous[exercise.sessionExerciseID])
        .takeIf { exercise.recordModeSnapshot == RecordMode.weightReps || exercise.recordModeSnapshot == RecordMode.reps }
    var weight by remember { mutableStateOf(initial?.weightValue?.toPlainString() ?: "") }
    var reps by remember { mutableStateOf(initial?.repetitionCount?.toPlainString() ?: "") }
    var duration by remember { mutableStateOf(DurationTextParser.formatForEditing(initial?.durationSeconds?.toPlainString())) }
    var distance by remember { mutableStateOf(initial?.distanceValue?.toPlainString() ?: "") }
    var speed by remember { mutableStateOf(initial?.speedValue?.toPlainString() ?: "") }
    var resistance by remember { mutableStateOf(initial?.resistanceValue?.toPlainString() ?: "") }
    var left by remember { mutableStateOf(initial?.leftValue?.toPlainString() ?: "") }
    var right by remember { mutableStateOf(initial?.rightValue?.toPlainString() ?: "") }
    var split by remember { mutableStateOf(initial?.leftValue != initial?.rightValue) }
    val sideEntry = exercise.recordModeSnapshot == RecordMode.weightReps && (unilateral || initial?.side == SetSide.bilateral)
    val scope = rememberCoroutineScope()
    val keyboard = LocalSoftwareKeyboardController.current
    BackHandler { if (!state.busy) onDismiss() }
    FcBottomSheet(if (target == null) "记录一组" else "编辑组", { if (!state.busy) onDismiss() }, skipPartiallyExpanded = true) {
        Column(Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).testTag("set-editor-content"),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            if (assisted) FcListRow("辅助重量")
            if (exercise.recordModeSnapshot == RecordMode.weightReps) {
                if (sideEntry && split) {
                    SetNumber("左侧重量", left, { left = it }, SetValueStepping.Field.weight, "set-left")
                    SetNumber("右侧重量", right, { right = it }, SetValueStepping.Field.weight, "set-right")
                } else SetNumber(if (sideEntry) "每侧重量" else "重量", weight, { weight = it }, SetValueStepping.Field.weight, "set-weight")
                FcListRow("重量每次调整 2.5")
            }
            when (exercise.recordModeSnapshot) {
                RecordMode.weightReps, RecordMode.reps -> SetNumber("次数", reps, { reps = it }, SetValueStepping.Field.reps, "set-reps")
                RecordMode.duration, RecordMode.cardio -> FcTextField("时长（秒或分秒）", duration, { duration = it }, Modifier.testTag("set-duration"), enabled = !state.busy)
            }
            if (sideEntry) FcLinkButton(if (split) "左右相同" else "左右不同", Modifier.testTag("set-split"), !state.busy) {
                if (!split) { left = weight; right = weight } else weight = recordedSideWeight(left, right, assisted)
                split = !split
            }
            if (initial?.side == SetSide.left || initial?.side == SetSide.right) {
                FcTextField("左侧", left, { left = it }, Modifier.testTag("set-left"))
                FcTextField("右侧", right, { right = it }, Modifier.testTag("set-right"))
            }
            if (exercise.recordModeSnapshot == RecordMode.cardio) {
                FcTextField("距离", distance, { distance = it }, Modifier.testTag("set-distance"), enabled = !state.busy)
                FcTextField("速度（可选）", speed, { speed = it }, Modifier.testTag("set-speed"), enabled = !state.busy)
                FcTextField("阻力（可选）", resistance, { resistance = it }, Modifier.testTag("set-resistance"), enabled = !state.busy)
            }
            state.error?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("set-error")) }
            FcButton(if (target == null) "确认本组" else "保存修改", Modifier.testTag("set-save"), !state.busy) {
                keyboard?.hide()
                val mode = exercise.recordModeSnapshot
                val input = TrainingSetInput(mode,
                    weightValue = if (mode == RecordMode.weightReps) if (sideEntry && split) recordedSideWeight(left, right, assisted) else weight else null,
                    repetitionCount = reps.takeIf { mode == RecordMode.weightReps || mode == RecordMode.reps },
                    durationSeconds = if (mode == RecordMode.duration || mode == RecordMode.cardio) DurationTextParser.parseSeconds(duration) ?: duration else null,
                    unit = initial?.unit ?: when (mode) { RecordMode.weightReps -> MeasurementUnit.kilograms; RecordMode.reps -> MeasurementUnit.repetitions; else -> MeasurementUnit.seconds },
                    side = if (sideEntry) SetSide.bilateral else initial?.side ?: SetSide.none,
                    leftValue = if (sideEntry) if (split) left else weight else left.takeIf { initial?.side == SetSide.left || initial?.side == SetSide.right },
                    rightValue = if (sideEntry) if (split) right else weight else right.takeIf { initial?.side == SetSide.left || initial?.side == SetSide.right },
                    distanceValue = distance.takeIf { mode == RecordMode.cardio }, speedValue = speed.takeIf { mode == RecordMode.cardio }, resistanceValue = resistance.takeIf { mode == RecordMode.cardio })
                scope.launch { if (state.saveSet(exercise.sessionExerciseID, target?.trainingSetID, input) is ApplicationResult.Success) onDismiss() }
            }
            FcSecondaryButton(if (target == null) "取消" else "取消修改", Modifier.testTag("set-cancel"), !state.busy, onDismiss)
        }
    }
}

@Composable
private fun SetNumber(title: String, text: String, change: (String) -> Unit, field: SetValueStepping.Field, tag: String) {
    FcLabelValueRow(title) {
        FcStepperField(title, text, change, SetValueStepping.canStepDown(text, field),
            painterResource(R.drawable.ic_ms_remove), painterResource(R.drawable.ic_ms_add),
            { change(SetValueStepping.stepped(text, field, false)) }, { change(SetValueStepping.stepped(text, field, true)) }, tag = tag)
    }
}

internal fun recordedSideWeight(left: String, right: String, assisted: Boolean): String {
    val l = left.trim().toBigDecimalOrNull() ?: return ""
    val r = right.trim().toBigDecimalOrNull() ?: return ""
    return (if (assisted) minOf(l, r) else maxOf(l, r)).stripTrailingZeros().toPlainString()
}
