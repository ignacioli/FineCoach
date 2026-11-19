package com.ignacioli.finecoach.features.appointments

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.common.BodyPart
import com.ignacioli.finecoach.designsystem.*
import kotlinx.coroutines.launch

@Composable
fun AppointmentEditorScreen(state: AppointmentEditorState, onBack: () -> Unit, onSaved: () -> Unit) {
    val scope = rememberCoroutineScope()
    var field by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(state) { state.load() }
    LaunchedEffect(state.saved) { if (state.saved) onSaved() }
    FcPlatformShell(onBack) {
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = FcSpacing.space6)
            .testTag("appointment-editor-content")) {
            FcPageHeader(if (state.editing) "编辑课程安排" else "新建课程安排", onBack = onBack, tag = "appointment-editor")
            Spacer(Modifier.height(FcSpacing.space4))
            FcListRowDivider(Modifier.testTag("conformance:Divider"))
            FcLabelValueRow("学员", Modifier.testTag("appointment-student"), onClick = if (state.editing) null else ({ field = if (field == "student") null else "student" })) {
                FcText(state.students.firstOrNull { it.studentID == state.studentID }?.displayName.orEmpty(), style = FcTypography.body, color = FcColors.textPrimary)
            }
            if (field == "student") state.students.forEach { student ->
                FcListRow(student.displayName, Modifier.testTag("appointment-student-${student.studentID.value}"),
                    mode = FcRowMode.Selection(student.studentID == state.studentID) { state.studentID = student.studentID; field = null })
            }
            FcListRowDivider(Modifier.testTag("conformance:Divider"))
            EditorValueRow("日期", state.date.chineseDay(), "appointment-date") { field = if (field == "date") null else "date" }
            if (field == "date") FcAppointmentDatePicker(state.date) { state.date = it }
            FcListRowDivider(Modifier.testTag("conformance:Divider"))
            EditorValueRow("开始时间", state.time.hourMinute(), "appointment-time") { field = "time" }
            FcListRowDivider(Modifier.testTag("conformance:Divider"))
            EditorValueRow("预计时长", "${state.duration} 分钟", "appointment-duration") { field = if (field == "duration") null else "duration" }
            if (field == "duration") FlowRow(horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                for (minutes in 15..240 step 15) FcFilterChip("$minutes 分钟", state.duration == minutes,
                    Modifier.testTag("appointment-duration-$minutes")) { state.duration = minutes; field = null }
            }
            FcListRowDivider(Modifier.testTag("conformance:Divider"))
            Column(Modifier.fillMaxWidth().padding(vertical = FcSpacing.space3), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    FcText("训练重点", style = FcTypography.style("callout", 400), color = FcColors.textSecondary)
                    Spacer(Modifier.weight(1f))
                    FcText("选填，可多选", style = FcTypography.caption, color = FcColors.textSecondary)
                }
                FcBodyPartPicker(state.focus.map { it.ordinal }.toSet(), { index ->
                    val part = BodyPart.entries[index]; state.focus = if (part in state.focus) state.focus - part else state.focus + part
                }, Modifier.fillMaxWidth(), tag = "appointment-focus", conformanceTags = true)
            }
            FcListRowDivider(Modifier.testTag("conformance:Divider"))
            if (!state.editing) {
                Column(Modifier.fillMaxWidth().padding(vertical = FcSpacing.space3), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                    FcText("重复", style = FcTypography.style("callout", 400), color = FcColors.textSecondary)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                        (listOf<RecurrenceInterval?>(null) + RecurrenceInterval.entries).forEachIndexed { index, repeat ->
                            FcFilterChip(intervalLabel(repeat), state.interval == repeat, Modifier.testTag("appointment-repeat-$index"), Modifier.testTag("conformance:Chip")) { state.interval = repeat }
                        }
                    }
                }
                FcListRowDivider(Modifier.testTag("conformance:Divider"))
                if (state.interval != null) {
                    FcLabelValueRow("结束方式") {
                        FcFilterChip("按结束日期", !state.endByCount, Modifier.testTag("appointment-end-date-mode"), Modifier.testTag("conformance:Chip")) { state.endByCount = false }
                        Spacer(Modifier.width(FcSpacing.space2))
                        FcFilterChip("按重复次数", state.endByCount, Modifier.testTag("appointment-end-count-mode"), Modifier.testTag("conformance:Chip")) { state.endByCount = true }
                    }
                    FcListRowDivider(Modifier.testTag("conformance:Divider"))
                    if (state.endByCount) {
                        FcLabelValueRow("重复次数") {
                            FcTextField("重复次数", state.count.toString(), { state.count = it.toIntOrNull() ?: 0 },
                                Modifier.testTag("appointment-count"), inline = true,
                                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number))
                        }
                    } else {
                        EditorValueRow("结束日期", "${state.endDate.monthValue}月${state.endDate.dayOfMonth}日", "appointment-end-date") { field = if (field == "end-date") null else "end-date" }
                        if (field == "end-date") FcAppointmentDatePicker(state.endDate, state.date) { state.endDate = it }
                    }
                    FcListRowDivider(Modifier.testTag("conformance:Divider"))
                }
            } else state.series?.let { series ->
                FcLabelValueText("重复", intervalLabel(series.intervalDays))
                FcListRowDivider(Modifier.testTag("conformance:Divider"))
                FcLabelValueText("结束方式", when (val end = series.termination) {
                    is RecurrenceTermination.EndDate -> "${end.date.monthValue}月${end.date.dayOfMonth}日结束"
                    is RecurrenceTermination.RepeatCount -> "重复 ${end.count} 次"
                })
                FcListRowDivider(Modifier.testTag("conformance:Divider"))
            }
            FcLabelValueRow("提醒") {
                Box(Modifier.heightIn(min = FcComponentMetrics.touch).testTag("appointment-reminder-lead")
                    .clickable(enabled = state.reminderEnabled, role = Role.Button) { field = if (field == "lead") null else "lead" },
                    contentAlignment = Alignment.CenterStart) {
                    FcText("提前 ${state.lead.minutes} 分钟", style = FcTypography.body,
                        color = if (state.reminderEnabled) FcColors.textPrimary else FcColors.textSecondary)
                }
                Spacer(Modifier.weight(1f))
                FcToggle("提醒", state.reminderEnabled, { state.reminderEnabled = it }, Modifier.testTag("appointment-reminder"),
                    trackModifier = Modifier.testTag("conformance:Switch track on"), knobModifier = Modifier.testTag("conformance:Switch knob"))
            }
            if (field == "lead" && state.reminderEnabled) FlowRow(horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                ReminderLeadMinutes.entries.forEach { lead -> FcFilterChip("提前 ${lead.minutes} 分钟", state.lead == lead,
                    Modifier.testTag("appointment-lead-${lead.minutes}")) { state.lead = lead; field = null } }
            }
            FcListRowDivider(Modifier.testTag("conformance:Divider"))
            state.preview?.let { FcText(it, Modifier.padding(top = FcSpacing.space3).testTag("appointment-preview"), style = FcTypography.caption, color = FcColors.textSecondary) }
            state.error?.let { FcText(it, Modifier.padding(top = FcSpacing.space3).testTag("appointment-error"), style = FcTypography.caption, color = FcColors.statusDestructive) }
            if (!state.loaded && state.error != null) FcButton("重试", Modifier.testTag("appointment-retry")) { scope.launch { state.load() } }
        }
        FcPinnedAction { FcButton("保存", Modifier.testTag("appointment-save"), enabled = state.loaded && !state.busy) { scope.launch { state.save() } } }
    }
    if (field == "time") FcAppointmentTimePicker(state.time, { state.time = it; field = null }, { field = null })
    if (state.scopeRequested) FcBottomSheet("编辑范围", state::dismissScope) {
        FcActionRow("仅本次", Modifier.testTag("appointment-scope-single")) { scope.launch { state.save(AppointmentEditorState.Scope.single) } }
        FcActionRow("本次及以后", Modifier.testTag("appointment-scope-future"), enabled = state.original?.date == state.date) { scope.launch { state.save(AppointmentEditorState.Scope.future) } }
    }
    state.conflict?.let { message -> FcConfirmationDialog("时间冲突", message, "覆盖并保存", { scope.launch { state.overrideConflict() } },
        state::dismissConflict, tag = "appointment-conflict") }
}

@Composable
private fun EditorValueRow(label: String, value: String, tag: String, onClick: () -> Unit) {
    FcLabelValueRow(label, Modifier.testTag(tag), onClick = onClick) { FcText(value, style = FcTypography.body, color = FcColors.textPrimary) }
}

internal fun intervalLabel(interval: RecurrenceInterval?) = when (interval) {
    null -> "不重复"
    RecurrenceInterval.everyOtherDay -> "每隔一天"
    RecurrenceInterval.everyTwoDays -> "每隔两天"
    RecurrenceInterval.everyWeek -> "每隔一周"
}
