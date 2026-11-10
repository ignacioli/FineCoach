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
        FcPageHeader("训练总结", onBack = { if (!state.busy) onBack() }, tag = "summary")
        Column(Modifier.fillMaxWidth().weight(1f).imePadding().verticalScroll(rememberScrollState()).testTag("summary-content"),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            state.detail?.let { detail ->
                FcLabelValueText("训练时长", detail.statistics.displayedDurationSeconds.canonicalString)
                FcLabelValueText("完成组数", detail.statistics.completedSetCount.toString())
                FcBodyPartPicker(state.focus.map { BodyPart.entries.indexOf(it) }.toSet(), { index -> if (!state.busy) {
                    val part = BodyPart.entries[index]; state.focus = if (part in state.focus) state.focus - part else state.focus + part
                } }, tag = "summary-focus")
                FcTextField("教练私密备注", state.privateNote, { state.privateNote = it }, Modifier.testTag("summary-private"), enabled = !state.busy)
                FcTextField("学员可见总结", state.publicSummary, { state.publicSummary = it }, Modifier.testTag("summary-public"), enabled = !state.busy)
                templateSlot()
                FcButton("保存并返回今日", Modifier.testTag("summary-save"), !state.busy) { scope.launch { state.save(onSaved) } }
            }
            state.error?.let { FcListRow("保存失败，请检查输入后重试", Modifier.testTag("summary-error")) }
        }
    }
}
