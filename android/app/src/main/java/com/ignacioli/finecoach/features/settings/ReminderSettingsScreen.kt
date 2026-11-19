package com.ignacioli.finecoach.features.settings

import android.content.Context
import android.content.Intent
import android.content.ActivityNotFoundException
import android.provider.Settings
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.designsystem.*
import kotlinx.coroutines.launch

/** Reads system permission; it never requests permission or changes appointment defaults. */
class ReminderSettingsState(private val readStatus: suspend () -> Status) {
    enum class Status { enabled, notRequested, denied }
    var status by mutableStateOf<Status?>(null); private set
    var error by mutableStateOf<String?>(null); private set
    suspend fun refresh() {
        try { status = readStatus(); error = null }
        catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (_: Exception) { error = "读取通知设置失败，请重试。" }
    }
    fun openSettings(open: () -> Boolean) { if (!open()) error = "无法打开系统设置，请稍后重试。" }
}

fun openNotificationSettings(context: Context): Boolean = try {
    context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    true
} catch (_: ActivityNotFoundException) { false } catch (_: SecurityException) { false }

@Composable
fun ReminderSettingsScreen(state: ReminderSettingsState, onBack: () -> Unit, onOpenSettings: () -> Boolean) {
    val scope=rememberCoroutineScope()
    LaunchedEffect(state) { state.refresh() }
    FcPlatformShell(onBack) {
        Column(Modifier.fillMaxWidth().weight(1f).testTag("settings-content")) {
            FcPageHeader("设置",onBack=onBack,tag="settings")
            Spacer(Modifier.height(FcSpacing.space4))
            FcListRowDivider()
            val denied=state.status==ReminderSettingsState.Status.denied
            FcHubRow("通知",painterResource(R.drawable.ic_ms_notifications),Modifier.testTag("settings-notifications"),
                subtitle=when(state.status) { ReminderSettingsState.Status.enabled -> "提醒已开启"; ReminderSettingsState.Status.notRequested -> "尚未请求"; else -> null },
                mode=FcRowMode.Action { state.openSettings(onOpenSettings) },
                subtitleContent=if(denied) ({ FcStatusLabel(FcStatus.PermissionDenied,painterResource(R.drawable.ic_ms_info_i)) }) else null,
                trailingContent=if(denied) ({ FcText("前往设置",style=FcTypography.style("callout",600),color=FcColors.actionPrimary) }) else null)
            FcListRowDivider()
            state.error?.let { FcText(it,Modifier.testTag("settings-error"),style=FcTypography.caption,color=FcColors.statusDestructive)
                FcButton("重试",Modifier.testTag("settings-retry")) { scope.launch { state.refresh() } } }
        }
    }
}
