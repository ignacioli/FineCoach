package com.ignacioli.finecoach.features.session

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.history.historyDuration
import kotlinx.coroutines.launch

class SessionSummaryUiState(val history: HistoryUseCases, val clock: AppClock) {
    var detail by mutableStateOf<HistoryDetail?>(null); private set
    var error by mutableStateOf<ApplicationError?>(null); private set
    var busy by mutableStateOf(false); private set
    var focus by mutableStateOf<Set<BodyPart>>(emptySet())
    var privateNote by mutableStateOf("")
    var publicSummary by mutableStateOf("")
    suspend fun load(id: SessionID) {
        busy = true
        when (val result = history.detail(id)) {
            is ApplicationResult.Failure -> error = result.error
            is ApplicationResult.Success -> {
                error = null; detail = result.value
                focus = result.value.content.session.trainingFocus
                privateNote = result.value.content.session.privateCoachNote.orEmpty()
                publicSummary = result.value.content.session.studentFacingSummary.orEmpty()
            }
        }; busy = false
    }
    suspend fun save(onSaved: () -> Unit) {
        val current = detail?.content?.session ?: return
        if (busy) return
        busy = true
        when (val result = history.saveSummary(SaveCompletedSessionSummaryCommand(current.sessionID,
            current.revision, focus, publicSummary, privateNote, clock.now()))) {
            is ApplicationResult.Failure -> error = result.error
            is ApplicationResult.Success -> { detail = detail!!.copy(content = detail!!.content.copy(session = result.value)); error = null; onSaved() }
        }; busy = false
    }
}

@Composable
fun SessionSummaryScreen(state: SessionSummaryUiState, id: SessionID, onBack: () -> Unit, onSaved: () -> Unit,
    templateSlot: @Composable () -> Unit = {}) {
    val scope = rememberCoroutineScope()
    LaunchedEffect(id) { state.load(id) }
    FcPlatformShell({ if (!state.busy) onBack() }) {
        FcPageHeader("训练总结", Modifier.padding(bottom = FcSpacing.space4),
            onBack = { if (!state.busy) onBack() }, tag = "summary")
        Column(Modifier.fillMaxWidth().weight(1f).imePadding()) {
            Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState())
                .padding(bottom = FcSpacing.space6).testTag("summary-content"),
                verticalArrangement = Arrangement.spacedBy(FcSpacing.space6)) {
                state.detail?.let { detail ->
                    FcText("时长 ${historyDuration(detail.statistics.displayedDurationSeconds.canonicalString)}",
                        style = FcTypography.headline, color = FcColors.textPrimary)
                    FcText("已完成 ${detail.statistics.completedSetCount} 组", style = FcTypography.body, color = FcColors.textPrimary)
                    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                        FcText("训练重点", style = FcTypography.style("callout", 400), color = FcColors.textSecondary)
                        FcBodyPartPicker(state.focus.map { BodyPart.entries.indexOf(it) }.toSet(), { index -> if (!state.busy) {
                            val part = BodyPart.entries[index]; state.focus = if (part in state.focus) state.focus - part else state.focus + part
                        } }, tag = "summary-focus")
                    }
                    SummaryNoteField("教练私有备注", state.privateNote, { state.privateNote = it }, "summary-private", !state.busy)
                    SummaryNoteField("课后可见总结", state.publicSummary, { state.publicSummary = it }, "summary-public", !state.busy)
                    templateSlot()
                }
                state.error?.let { FcListRow("保存失败，请检查输入后重试", Modifier.testTag("summary-error")) }
            }
            if (state.detail != null) {
                FcButton("保存并返回今日", Modifier.padding(bottom = FcSpacing.space8).testTag("summary-save"), !state.busy) {
                    scope.launch { state.save(onSaved) }
                }
            }
        }
    }
}

@Composable
private fun SummaryNoteField(title: String, value: String, onValueChange: (String) -> Unit, tag: String, enabled: Boolean) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
        FcText(title, style = FcTypography.style("callout", 400), color = FcColors.textSecondary)
        FcTextField(title, value, onValueChange, Modifier.testTag(tag), enabled = enabled,
            visualModifier = Modifier.heightIn(min = FcSpacing.space8 * 2 + FcSpacing.space6),
            singleLine = false, placeholder = "")
    }
}
