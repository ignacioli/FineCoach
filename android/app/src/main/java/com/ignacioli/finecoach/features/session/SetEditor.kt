package com.ignacioli.finecoach.features.session

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
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
    val initial = target ?: state.entryPrefill?.takeIf { it.sessionExerciseID == exercise.sessionExerciseID } ?: (exercise.sets.lastOrNull { it.state == SetRecordingState.completed } ?: exercise.sets.lastOrNull() ?: state.previous[exercise.sessionExerciseID])
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
    LaunchedEffect(state.entryPrefillVersion) {
        val restored = state.entryPrefill?.takeIf { target == null && it.sessionExerciseID == exercise.sessionExerciseID }
        if (restored != null) {
            weight = restored.weightValue?.toPlainString().orEmpty(); reps = restored.repetitionCount?.toPlainString().orEmpty()
            duration = DurationTextParser.formatForEditing(restored.durationSeconds?.toPlainString())
            distance = restored.distanceValue?.toPlainString().orEmpty(); speed = restored.speedValue?.toPlainString().orEmpty()
            resistance = restored.resistanceValue?.toPlainString().orEmpty()
            left = restored.leftValue?.toPlainString().orEmpty(); right = restored.rightValue?.toPlainString().orEmpty()
            split = restored.leftValue != restored.rightValue
        }
    }
    val numberKeyboard = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done)
    val done = KeyboardActions(onDone = { keyboard?.hide() })
    BackHandler { if (!state.busy) onDismiss() }
    key(exercise.sessionExerciseID, target?.trainingSetID) {
        Column(Modifier.fillMaxWidth().testTag(if (target == null) "set-add-editor-content" else "set-editor-content"),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            if (assisted) FcListRow("辅助重量")
            if (exercise.recordModeSnapshot == RecordMode.weightReps) {
                if (sideEntry && split) {
                    SetNumber("左侧重量", left, { left = it }, SetValueStepping.Field.weight, "set-left")
                    SetNumber("右侧重量", right, { right = it }, SetValueStepping.Field.weight, "set-right")
                } else SetNumber(if (sideEntry) "每侧重量 kg" else "重量 kg", weight, { weight = it }, SetValueStepping.Field.weight, "set-weight")
            }
            // S1-D42: the stepping hint is helper text of the last field row, space.1 below it (P0-a2).
            if (exercise.recordModeSnapshot != RecordMode.cardio) Column(verticalArrangement = Arrangement.spacedBy(FcSpacing.space1)) {
                when (exercise.recordModeSnapshot) {
                    RecordMode.weightReps, RecordMode.reps -> SetNumber("次数", reps, { reps = it }, SetValueStepping.Field.reps, "set-reps")
                    RecordMode.duration -> FcTextField("时长（秒或分秒）", duration, { duration = it }, Modifier.testTag("set-duration"), enabled = !state.busy, keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = done)
                    RecordMode.cardio -> Unit
                }
                if (exercise.recordModeSnapshot == RecordMode.weightReps) Box(Modifier.fillMaxWidth()) {
                    FcText("每次 ±2.5 kg · 点数字可直接输入",
                        Modifier.padding(start = FcComponentMetrics.label).testTag("set-weight-hint"),
                        style = FcTypography.caption, color = FcColors.textSecondary)
                    // Overlay the label-column link: its expanded touch area does not size the helper row.
                    if (sideEntry) Box(Modifier.matchParentSize(), contentAlignment = Alignment.CenterStart) {
                        Box(Modifier.width(FcComponentMetrics.label).wrapContentHeight(unbounded = true)) {
                            FcLinkButton(if (split) "左右相同" else "左右不同", Modifier.testTag("set-split"),
                                !state.busy, contentAlignment = Alignment.CenterStart, compactLayout = true) {
                                if (!split) { left = weight; right = weight } else weight = recordedSideWeight(left, right, assisted)
                                split = !split
                            }
                        }
                    }
                }
            }
            if (initial?.side == SetSide.left || initial?.side == SetSide.right) {
                FcTextField("左侧", left, { left = it }, Modifier.testTag("set-left"), keyboardOptions = numberKeyboard, keyboardActions = done)
                FcTextField("右侧", right, { right = it }, Modifier.testTag("set-right"), keyboardOptions = numberKeyboard, keyboardActions = done)
            }
            if (exercise.recordModeSnapshot == RecordMode.cardio) {
                Column(Modifier.fillMaxWidth()) {
                    CardioValue("时长", "时长，如 5 分 30 秒 / 5m30s", duration, { duration = it }, "", true, "set-duration", !state.busy, KeyboardOptions(imeAction = ImeAction.Done), done)
                    CardioValue("距离", "距离（km）", distance, { distance = it }, "km", true, "set-distance", !state.busy, numberKeyboard, done)
                    CardioValue("速度", "速度（选填）", speed, { speed = it }, "km/h", false, "set-speed", !state.busy, numberKeyboard, done)
                    CardioValue("阻力", "阻力（选填）", resistance, { resistance = it }, "", false, "set-resistance", !state.busy, numberKeyboard, done)
                }
                FcHintBar("时长与距离均大于 0，才可标记完成", Modifier.testTag("set-cardio-validation-hint"))
            }
            state.error?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("set-error")) }
            // S1-D42: actions sit space.4 below the fields (column space.2 + space.2 top inset).
            Row(Modifier.fillMaxWidth().padding(top = FcSpacing.space2).testTag("set-editor-actions"), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            FcButton(if (target == null) "确认" else "保存", Modifier.weight(1f).testTag("set-save"), !state.busy) {
                keyboard?.hide()
                val values = SetEntryValues(weight, reps, duration, distance, speed, resistance, left, right, split)
                scope.launch { if (state.saveSetEntry(exercise, target, initial, sideEntry, assisted, values) is ApplicationResult.Success && target != null) onDismiss() }
            }
            if (target != null) FcLinkButton("取消", Modifier.testTag("set-cancel"), !state.busy) { keyboard?.hide(); onDismiss() }
            }
        }
    }
}

@Composable
private fun CardioValue(label: String, title: String, value: String, change: (String) -> Unit,
    unit: String, required: Boolean, tag: String, enabled: Boolean, options: KeyboardOptions, actions: KeyboardActions) {
    FcLabelValueRow(label, Modifier.testTag("$tag-row")) {
        Row(Modifier.fillMaxWidth().testTag("$tag-value-slot"), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2),
            verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            FcTextField(title, value, change, Modifier.weight(1f).testTag(tag), enabled = enabled,
                keyboardOptions = options, keyboardActions = actions, inline = true, placeholder = "")
            if (unit.isNotEmpty()) FcText(unit, style = FcTypography.body, color = FcColors.textPrimary)
            FcText(if (required) "必填" else "选填", style = FcTypography.caption, color = FcColors.textSecondary)
        }
    }
    FcListRowDivider(Modifier.testTag("$tag-divider"))
}

@Composable
private fun SetNumber(title: String, text: String, change: (String) -> Unit, field: SetValueStepping.Field, tag: String) {
    val keyboard = LocalSoftwareKeyboardController.current
    FcLabelValueRow(title, labelModifier = Modifier) {
        FcStepperField(title, text, change, SetValueStepping.canStepDown(text, field),
            painterResource(R.drawable.ic_ms_remove), painterResource(R.drawable.ic_ms_add),
            { change(SetValueStepping.stepped(text, field, false)) }, { change(SetValueStepping.stepped(text, field, true)) }, tag = tag,
            keyboardOptions = KeyboardOptions(keyboardType = if (field == SetValueStepping.Field.reps) KeyboardType.Number else KeyboardType.Decimal, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { keyboard?.hide() }))
    }
}
