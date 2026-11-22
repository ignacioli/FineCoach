package com.ignacioli.finecoach.features.history

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.progress.Comparison
import com.ignacioli.finecoach.core.domain.training.CompletedSession
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.navigation.S1Routes
import java.time.ZoneId
import kotlinx.coroutines.launch

@Composable
fun HistoryListScreen(state: HistoryUiState, zone: ZoneId, onNavigate: (String) -> Unit, onBack: () -> Unit, progress: ProgressUseCases? = null) {
    val scope = rememberCoroutineScope()
    var filter by remember { mutableStateOf<String?>(null) }
    var focusDraft by remember { mutableStateOf<Set<BodyPart>>(emptySet()) }
    var selecting by remember { mutableStateOf(false) }
    var picked by remember { mutableStateOf(listOf<SessionID>()) }
    var compared by remember { mutableStateOf<List<CompletedSession>>(emptyList()) }
    var comparison by remember { mutableStateOf<Comparison.SessionComparisonResult?>(null) }
    LaunchedEffect(state) { state.list() }
    val hasFilters = state.query.window != null || state.query.trainingFocus.isNotEmpty() || state.query.exerciseIDs.isNotEmpty()
    FcPlatformShell(onBack) {
        Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).testTag("history-list-content"),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                FcPageHeader("训练历史", onBack = onBack, tag = "history-list", trailingTitle = if (selecting) "完成" else "选择",
                    trailingEnabled = !state.busy, onTrailing = {
                        if (selecting) { selecting = false; picked = emptyList(); compared = emptyList(); comparison = null }
                        else selecting = true
                    })
                if (state.studentName.isNotEmpty()) FcText(state.studentName, Modifier.testTag("history-student-name"),
                    style = FcTypography.headline, color = FcColors.textSecondary)
            }
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                    FcFilterChip("日期范围", state.query.window != null, Modifier.testTag("history-filter-date")) { filter = "date" }
                    FcFilterChip("训练重点", state.query.trainingFocus.isNotEmpty(), Modifier.testTag("history-filter-focus-open")) {
                        focusDraft = state.query.trainingFocus; filter = "focus"
                    }
                    FcFilterChip("动作", state.query.exerciseIDs.isNotEmpty(), Modifier.testTag("history-filter-exercise")) { filter = "exercise" }
                }
                if (hasFilters) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        val summary = listOfNotNull(
                            historyFocus(state.query.trainingFocus).takeIf { it.isNotEmpty() }?.let { "训练重点 $it" },
                            state.query.window?.let { "近 ${it.days} 天" },
                            state.query.exerciseIDs.firstOrNull()?.let { state.exerciseOptions[it] })
                        HistoryCaption("已筛选：${summary.joinToString(" · ")}", Modifier.weight(1f).testTag("history-filter-summary"))
                        FcLinkButton("清除筛选", Modifier.testTag("history-filter-clear"), !state.busy) {
                            scope.launch { state.list(HistoryQuery(studentID = state.studentID)) }
                        }
                    }
                }
            }
            Column(Modifier.fillMaxWidth().testTag("history-results"), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                state.error?.let { FcText("加载失败，请返回重试", Modifier.testTag("history-error"), style = FcTypography.caption, color = FcColors.statusDestructive) }
                if (state.busy && state.records.isEmpty()) HistoryCaption("正在加载", Modifier.testTag("history-loading"))
                else when (state.emptyState) {
                    HistoryEmptyState.noHistory -> HistoryEmpty("还没有完成的训练", "完成一次训练后会出现在这里。", "history-empty")
                    HistoryEmptyState.noMatches -> HistoryEmpty("没有符合条件的训练", "换一个日期范围、部位或动作试试，或清除筛选。", "history-no-matches")
                    null -> Unit
                }
                if (state.records.isNotEmpty()) {
                    FcSectionLabel("${state.records.size} 次训练", Modifier.testTag("history-count"))
                    Column(Modifier.fillMaxWidth()) {
                        FcListRowDivider()
                        state.records.forEach { row ->
                            val detail = state.listDetails[row.sessionID]
                            val summary = listOfNotNull(historyFocus(row.trainingFocus).takeIf { it.isNotEmpty() },
                                detail?.statistics?.let { "${it.completedSetCount} 组" },
                                detail?.statistics?.let { historyDuration(it.displayedDurationSeconds.canonicalString) }).joinToString(" · ")
                            FcListRow(historyDay(row.completedAtUTC, zone), Modifier.testTag("history-open-${row.sessionID.value}"),
                                subtitle = listOfNotNull(summary, "未扣课 · 无有效课包".takeIf { detail?.creditNote?.note == SessionCreditSettlementNote.noActivePackage }).joinToString("\n"), mode = FcRowMode.Action { onNavigate(S1Routes.historyDetail(row.sessionID)) })
                            if (selecting) FcButton(if (row.sessionID in picked) "已选" else "选择这节课", Modifier.testTag("history-compare-pick-${row.sessionID.value}"), !state.busy) {
                                val next = if (row.sessionID in picked) picked - row.sessionID else if (picked.size < 2) picked + row.sessionID else picked
                                picked = next
                                val student = state.studentID
                                if (next.size == 2 && progress != null && student != null) scope.launch {
                                    when (val loaded = progress.load(student)) {
                                        is ApplicationResult.Failure -> comparison = null
                                        is ApplicationResult.Success -> {
                                            val pair = next.mapNotNull { id -> loaded.value.completed.firstOrNull { it.sessionID == id } }
                                            compared = pair
                                            comparison = if (pair.size == 2) Comparison.compareSessions(pair[0], pair[1]) else null
                                        }
                                    }
                                } else { compared = emptyList(); comparison = null }
                            }
                            FcListRowDivider()
                        }
                    }
                }
            }
            comparison?.let { result ->
                Column(Modifier.fillMaxWidth().testTag("history-compare-panel"), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                    FcSectionLabel("课程比较（已选 ${picked.size} / 2）")
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
                        compared.forEach { session ->
                            FcText(historyDay(session.completedAtUTC, zone), Modifier.weight(1f), style = FcTypography.headline, color = FcColors.textPrimary)
                        }
                    }
                    when (result) {
                        Comparison.SessionComparisonResult.IncompatibleTrainingFocus, Comparison.SessionComparisonResult.DifferentStudent ->
                            FcText("训练重点不同，无法对比，已分别展示。", Modifier.fillMaxWidth().testTag("history-compare-incompatible"),
                                style = FcTypography.body, color = FcColors.textPrimary)
                        is Comparison.SessionComparisonResult.Compatible -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
                            listOf(
                                Triple(result.detail.totalSetCountA, result.detail.totalRepCountA, result.detail.trainingVolumeA) to result.detail.exercisesOnlyInA,
                                Triple(result.detail.totalSetCountB, result.detail.totalRepCountB, result.detail.trainingVolumeB) to result.detail.exercisesOnlyInB,
                            ).forEach { (stats, only) ->
                                Column(Modifier.weight(1f).testTag("history-compare-column")) {
                                    FcText("总组数 ${stats.first}", style = FcTypography.body, color = FcColors.textPrimary)
                                    stats.second?.let { FcText("总次数 ${it.canonicalString}", style = FcTypography.body, color = FcColors.textPrimary) }
                                    stats.third?.let { FcText("训练容量 ${it.canonicalString} kg", style = FcTypography.body, color = FcColors.textPrimary) }
                                    FcText(if (only.isEmpty()) "动作相同" else "仅此次 · ${only.joinToString("、")}", style = FcTypography.caption, color = FcColors.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    filter?.let { panel -> FcBottomSheet(when (panel) { "date" -> "日期范围"; "focus" -> "训练重点"; else -> "动作" }, { filter = null }, subtitle = if (panel == "focus") "选中多个部位时，命中任一部位即显示。" else null, skipPartiallyExpanded = true) {
        Column(Modifier.fillMaxWidth().heightIn(max = FcComponentMetrics.row * 6).verticalScroll(rememberScrollState()).testTag("history-filter-content")) {
            when (panel) {
                "date" -> FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                    FcFilterChip("全部", state.query.window == null, Modifier.testTag("history-window-all")) {
                        scope.launch { state.list(state.query.copy(window = null)); filter = null }
                    }
                    HistoryWindowDays.entries.forEach { window -> FcFilterChip("近 ${window.days} 天", state.query.window == window,
                        Modifier.testTag("history-window-${window.days}")) {
                        scope.launch { state.list(state.query.copy(window = window)); filter = null }
                    } }
                }
                "focus" -> {
                    FcBodyPartPicker(focusDraft.map { BodyPart.entries.indexOf(it) }.toSet(), { index ->
                        val part = BodyPart.entries[index]; focusDraft = if (part in focusDraft) focusDraft - part else focusDraft + part
                    }, tag = "history-filter-focus")
                    FcButton("完成", Modifier.testTag("history-filter-done"), !state.busy) {
                        scope.launch { state.list(state.query.copy(trainingFocus = focusDraft)); filter = null }
                    }
                }
                else -> {
                    FcActionRow("全部动作", Modifier.testTag("history-filter-exercise-all"), detail = if (state.query.exerciseIDs.isEmpty()) "已选" else null, enabled = !state.busy) {
                        scope.launch { state.list(state.query.copy(exerciseIDs = emptySet())); filter = null }
                    }
                    state.exerciseOptions.entries.sortedBy { it.value }.forEach { (id, name) ->
                        FcListRowDivider()
                        FcActionRow(name, Modifier.testTag("history-filter-exercise-${id.value}"), detail = if (id in state.query.exerciseIDs) "已选" else null, enabled = !state.busy) {
                            scope.launch { state.list(state.query.copy(exerciseIDs = setOf(id))); filter = null }
                        }
                    }
                }
            }
            FcSecondaryButton("取消", Modifier.testTag("history-filter-cancel")) { filter = null }
        }
    } }
}
