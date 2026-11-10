package com.ignacioli.finecoach.features.session

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.designsystem.*
import kotlinx.coroutines.launch

@Composable
fun SaveStatusView(state: ActiveSessionUiState) {
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxWidth().testTag("save-status-content")) {
        FcSaveStatusView(state.saveState, painterResource(if (state.saveState == FcSaveState.Failed) R.drawable.ic_ms_priority_high else R.drawable.ic_ms_check_circle),
            Modifier.testTag("save-status-${state.saveState.name.lowercase()}"))
        if (state.saveState == FcSaveState.Failed) {
            FcListRow("保存失败，重试成功后才能结束训练", Modifier.testTag("save-finish-blocked"))
            FcButton("重试", Modifier.testTag("save-retry"), !state.busy) { scope.launch { state.retrySave() } }
        }
    }
}
