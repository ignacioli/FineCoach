package com.ignacioli.finecoach.features.history

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.application.toDomain
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.navigation.S1Routes
import java.time.ZoneId
import kotlinx.coroutines.launch

@Composable
fun HistoryListScreen(state: HistoryUiState, zone: ZoneId, onNavigate: (String) -> Unit, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var exerciseFilter by remember { mutableStateOf(false) }
    LaunchedEffect(state) { state.list() }
    FcPlatformShell(onBack) {
        FcPageHeader("训练历史", onBack = onBack, tag = "history-list")
        Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).testTag("history-list-content")) {
            FlowRow(Modifier.fillMaxWidth()) {
                HistoryWindowDays.entries.forEach { window -> FcFilterChip("最近${window.days}天", state.query.window == window,
                    Modifier.testTag("history-window-${window.days}")) { scope.launch { state.list(state.query.copy(window = if (state.query.window == window) null else window)) } } }
            }
            FcBodyPartPicker(state.query.trainingFocus.map { BodyPart.entries.indexOf(it) }.toSet(), { index ->
                val part = BodyPart.entries[index]; scope.launch { state.list(state.query.copy(trainingFocus = if (part in state.query.trainingFocus) state.query.trainingFocus - part else state.query.trainingFocus + part)) }
            }, tag = "history-filter-focus")
            FcSecondaryButton("动作筛选", Modifier.testTag("history-filter-exercise"), !state.busy) { exerciseFilter = true }
            FcSecondaryButton("清除筛选", Modifier.testTag("history-filter-clear"), !state.busy) { scope.launch { state.list(HistoryQuery(studentID = state.studentID)) } }
            state.error?.let { FcListRow("加载失败，请重试", Modifier.testTag("history-error")); FcButton("重试", Modifier.testTag("history-retry"), !state.busy) { scope.launch { state.list() } } }
            if (state.busy && state.records.isEmpty()) FcListRow("正在加载", Modifier.testTag("history-loading"))
            else when (state.emptyState) {
                HistoryEmptyState.noHistory -> FcListRow("还没有训练记录", Modifier.testTag("history-empty"))
                HistoryEmptyState.noMatches -> FcListRow("没有符合筛选的训练", Modifier.testTag("history-no-matches"))
                null -> Unit
            }
            state.records.forEach { row -> FcListRow(row.completedAtUTC.atZone(zone).toLocalDate().toString(), Modifier.testTag("history-open-${row.sessionID.value}"),
                subtitle = row.trainingFocus.joinToString("、") { FcBodyParts[BodyPart.entries.indexOf(it)] }, mode = FcRowMode.Action { onNavigate(S1Routes.historyDetail(row.sessionID)) }) }
        }
    }
    if (exerciseFilter) FcBottomSheet("动作筛选", { exerciseFilter = false }, skipPartiallyExpanded = true) {
        Column(Modifier.fillMaxWidth().heightIn(max = FcComponentMetrics.row * 6).verticalScroll(rememberScrollState())) {
            state.exerciseOptions.forEach { (id, name) -> FcActionRow(name, Modifier.testTag("history-filter-exercise-${id.value}"), enabled = !state.busy) {
                scope.launch { state.list(state.query.copy(exerciseIDs = setOf(id))); exerciseFilter = false }
            } }
            FcSecondaryButton("取消", Modifier.testTag("history-filter-cancel")) { exerciseFilter = false }
        }
    }
}

@Composable
fun HistoryDetailScreen(state: HistoryUiState, id: SessionID, zone: ZoneId, onBack: () -> Unit, templates: HistoryTemplateState? = null) {
    var edit by remember { mutableStateOf(false) }
    LaunchedEffect(id) { state.load(id) }
    if (edit) { HistoryFocusEditor(state, { edit = false }) { edit = false }; return }
    FcPlatformShell(onBack) {
        FcPageHeader("训练详情", onBack = onBack, tag = "history-detail", trailingTitle = "编辑", trailingEnabled = state.detail != null && !state.busy, onTrailing = { state.focus = state.detail!!.content.session.trainingFocus; edit = true })
        Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).testTag("history-detail-content")) {
            state.error?.let { FcListRow("加载失败，请返回重试", Modifier.testTag("history-detail-error")) }
            state.detail?.let { detail ->
                val session = detail.content.session
                FcLabelValueText("日期", session.completedAtUTC?.atZone(zone)?.toLocalDate()?.toString().orEmpty())
                FcLabelValueText("训练时长", detail.statistics.displayedDurationSeconds.canonicalString)
                FcLabelValueText("完成组数", detail.statistics.completedSetCount.toString())
                FcLabelValueText("训练量", detail.statistics.ordinaryTrainingVolume?.canonicalString ?: "—")
                FcLabelValueText("训练重点", session.trainingFocus.joinToString("、") { FcBodyParts[BodyPart.entries.indexOf(it)] })
                detail.content.exercises.sortedBy { it.orderIndex }.forEach { exercise ->
                    FcSectionLabel(exercise.displayNameSnapshot, Modifier.testTag("history-snapshot-${exercise.sessionExerciseID.value}"))
                    exercise.sets.filter { it.state == SetRecordingState.completed }.sortedBy { it.orderIndex }.forEachIndexed { index, set ->
                        FcListRow("第 ${index + 1} 组", Modifier.testTag("history-set-${set.trainingSetID.value}"), subtitle = set.toDomain().displaySummary())
                    }
                }
                session.studentFacingSummary?.let { FcListRow("学员可见总结", subtitle = it) }
                templates?.let { HistoryTemplateEntry(it, detail.content) }
                if (detail.creditNote?.note == SessionCreditSettlementNote.noActivePackage) FcListRow("未扣课 · 无有效课包", Modifier.testTag("history-credit-note"))
            }
        }
    }
}

@Composable
private fun HistoryFocusEditor(state: HistoryUiState, onBack: () -> Unit, onSaved: () -> Unit) {
    val scope = rememberCoroutineScope()
    FcPlatformShell({ if (!state.busy) onBack() }) {
        FcPageHeader("编辑训练重点", onBack = { if (!state.busy) onBack() }, tag = "history-edit")
        Column(Modifier.fillMaxWidth().weight(1f).imePadding().verticalScroll(rememberScrollState()).testTag("history-edit-content")) {
            FcBodyPartPicker(state.focus.map { BodyPart.entries.indexOf(it) }.toSet(), { index -> if (!state.busy) {
                val part = BodyPart.entries[index]; state.focus = if (part in state.focus) state.focus - part else state.focus + part
            } }, tag = "history-edit-focus")
            state.error?.let { FcListRow("保存失败，请重试", Modifier.testTag("history-edit-error")) }
            FcButton("保存", Modifier.testTag("history-edit-save"), !state.busy) { scope.launch { state.saveFocus(onSaved) } }
            FcSecondaryButton("取消", Modifier.testTag("history-edit-cancel"), !state.busy, onBack)
        }
    }
}
