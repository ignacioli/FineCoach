package com.ignacioli.finecoach.notifications

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.designsystem.*

val LocalRestPermissionRequest = staticCompositionLocalOf<() -> Unit> { {} }

@Composable
fun RestPermissionEntry() {
    val context = LocalContext.current
    val adapter = remember(context) { RestNotifications(context) }
    var dismissed by remember { mutableStateOf(false) }
    val request = LocalRestPermissionRequest.current
    LocalRestPermissionRevision.current
    if (!adapter.enabled() && !dismissed) Column(Modifier.fillMaxWidth().testTag("rest-permission-content")) {
        FcListRow("休息提醒未开启；不影响记录与前台计时", Modifier.testTag("rest-permission-state"))
        if (adapter.needsRuntimePermission()) FcButton("开启休息提醒", Modifier.testTag("rest-permission-request")) { request() }
        else FcListRow("通知已被系统关闭，可在系统设置中开启")
        FcSecondaryButton("暂不开启", Modifier.testTag("rest-permission-cancel")) { dismissed = true }
    }
}

val LocalRestPermissionRevision = staticCompositionLocalOf { 0 }
