package com.ignacioli.finecoach.features.session

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.training.DurationTextParser
import com.ignacioli.finecoach.designsystem.*
import kotlinx.coroutines.launch

@Composable
fun SessionRecoveryReview(state: ActiveSessionUiState, onCancel: () -> Unit, onSaved: () -> Unit) {
    val session = state.content?.session ?: return
    var text by remember(session.sessionID) { mutableStateOf(DurationTextParser.formatSessionDurationForEditing(session.elapsedSeconds.toPlainString())) }
    var invalid by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    FcPlatformShell({ if (!state.busy) onCancel() }) {
        FcPageHeader("确认训练时长", onBack = { if (!state.busy) onCancel() }, tag = "duration-review")
        Column(Modifier.fillMaxWidth().weight(1f).imePadding().verticalScroll(rememberScrollState()).testTag("duration-review-content")) {
            FcListRow("训练曾中断，请确认本次训练的实际时长。")
            FcTextField("训练时长", text, { text = it }, Modifier.testTag("duration-review-input"), enabled = !state.busy)
            FcListRow("输入分钟，例如20分钟或1小时20分")
            if (invalid || state.error != null) FcListRow("请输入有效的非负整数时长，或重试保存", Modifier.testTag("duration-review-error"))
            FcButton("确认时长", Modifier.testTag("duration-review-confirm"), !state.busy) {
                val seconds = DurationTextParser.parseSessionDurationSeconds(text)
                if (seconds == null) invalid = true else scope.launch {
                    invalid = false
                    if (state.reviewDuration(seconds) is ApplicationResult.Success) onSaved()
                }
            }
            FcSecondaryButton("取消", Modifier.testTag("duration-review-cancel"), !state.busy, onCancel)
        }
    }
}

class SessionRecoveryState(private val coordinator: RecoveryCoordinator) {
    var loading by mutableStateOf(true); private set
    var error by mutableStateOf<ApplicationError?>(null); private set
    var sessions by mutableStateOf<List<SessionContentRecord>>(emptyList()); private set
    suspend fun recover() {
        loading = true
        when (val result = coordinator.reconcileOnLaunch()) {
            is ApplicationResult.Failure -> error = result.error
            is ApplicationResult.Success -> { sessions = result.value; error = null }
        }
        loading = false
    }
}

@Composable
fun SessionRecoveryEntry(state: SessionRecoveryState, onOpen: (com.ignacioli.finecoach.core.domain.common.SessionID) -> Unit) {
    val scope = rememberCoroutineScope()
    LaunchedEffect(state) { state.recover() }
    Column(Modifier.fillMaxWidth().testTag("recovery-content")) {
        when {
            state.loading -> FcListRow("正在恢复训练", Modifier.testTag("recovery-loading"))
            state.error != null -> {
                FcListRow("恢复失败，请重试", Modifier.testTag("recovery-error"))
                FcButton("重试", Modifier.testTag("recovery-retry")) { scope.launch { state.recover() } }
            }
            else -> state.sessions.forEachIndexed { index, row ->
                FcButton("继续训练 ${index + 1}", Modifier.testTag("recovery-open-${row.session.sessionID.value}")) { onOpen(row.session.sessionID) }
            }
        }
    }
}
