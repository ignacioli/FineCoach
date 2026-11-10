package com.ignacioli.finecoach.features.history

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.designsystem.*
import java.time.ZoneId
import kotlinx.coroutines.launch

@Composable
fun HistoryDetailScreen(state: HistoryUiState, id: SessionID, zone: ZoneId, onBack: () -> Unit, templates: HistoryTemplateState? = null) {
    var edit by remember { mutableStateOf(false) }
    LaunchedEffect(id) { state.load(id) }
    if (edit) { HistoryFocusEditor(state, { edit = false }) { edit = false }; return }
    FcPlatformShell(onBack) {
        Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).testTag("history-detail-content"), verticalArrangement = Arrangement.spacedBy(FcSpacing.space6)) {
            FcPageHeader("训练记录", onBack = onBack, tag = "history-detail")
            state.error?.let { FcListRow("加载失败，请返回重试", Modifier.testTag("history-detail-error")) }
            state.detail?.let { detail ->
                val session = detail.content.session
                HistoryRecordCard(detail, zone, state.studentName)
                if (detail.creditNote?.note == SessionCreditSettlementNote.noActivePackage) HistoryCaption("未扣课 · 无有效课包", Modifier.testTag("history-credit-note"))
                Column(Modifier.fillMaxWidth().testTag("history-actions")) {
                    FcListRowDivider()
                    FcActionRow("编辑训练重点", Modifier.testTag("history-edit-focus-entry"), enabled = !state.busy) {
                        state.focus = session.trainingFocus; edit = true
                    }
                    templates?.let { FcListRowDivider(); HistoryTemplateEntry(it, detail.content) }
                    FcListRowDivider()
                    HistoryCaption("训练数据为只读记录，可编辑训练重点。", Modifier.padding(top = FcSpacing.space2).testTag("history-readonly"))
                }

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
            FcSectionLabel("训练重点")
            FcBodyPartPicker(state.focus.map { BodyPart.entries.indexOf(it) }.toSet(), { index -> if (!state.busy) {
                val part = BodyPart.entries[index]; state.focus = if (part in state.focus) state.focus - part else state.focus + part
            } }, tag = "history-edit-focus")
            state.error?.let { FcListRow("保存失败，请重试", Modifier.testTag("history-edit-error")) }
            FcButton("保存", Modifier.testTag("history-edit-save"), !state.busy) { scope.launch { state.saveFocus(onSaved) } }
        }
    }
}
