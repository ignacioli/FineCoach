package com.ignacioli.finecoach.features.session

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.designsystem.*
import kotlinx.coroutines.delay

@Composable
fun RestTimerView(store: RestTimerStore, id: SessionID) {
    val end = store.end(id) ?: return
    var remaining by remember(id, end) { mutableLongStateOf(store.remaining(id)) }
    LaunchedEffect(id, end) {
        while (remaining > 0L) {
            delay(1000)
            remaining = store.remaining(id)
        }
    }
    Column(Modifier.fillMaxWidth().testTag("rest-content")) {
        com.ignacioli.finecoach.notifications.RestPermissionEntry()
        FcLabelValueText("休息", if (remaining == 0L) "休息结束" else "%d:%02d".format(remaining / 60, remaining % 60), Modifier.testTag("rest-remaining"))
        if (remaining > 0) {
            FcActionRow("−15秒", Modifier.testTag("rest-minus")) { store.adjust(id, -15) }
            FcActionRow("+15秒", Modifier.testTag("rest-plus")) { store.adjust(id, 15) }
            FcSecondaryButton("跳过", Modifier.testTag("rest-skip")) { store.clear(id) }
        } else FcSecondaryButton("关闭", Modifier.testTag("rest-close")) { store.clear(id) }
    }
}
