package com.ignacioli.finecoach

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.text.BasicText
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogWindowProvider
import com.ignacioli.finecoach.designsystem.*
import androidx.compose.runtime.CompositionLocalProvider

// fictional-data: infrastructure sample only; no student/coach data or persistence.
internal class S0DebugApplication : Application(), ShellContentProvider {
    @Composable override fun Content(privacyCover: PrivacyCoverPolicy) {
        var catalog by remember { mutableStateOf(false) }
        val registry = remember(privacyCover) { FcWindowRegistry(privacyCover::registerWindow, privacyCover::unregisterWindow) }
        CompositionLocalProvider(LocalFcWindowRegistry provides registry) {
            if (catalog) S0ComponentCatalog { catalog = false }
            else PrivacySample(privacyCover) { catalog = true }
        }
    }
}

@Composable
private fun PrivacySample(privacyCover: PrivacyCoverPolicy, onCatalog: () -> Unit) {
    var dialogOpen by remember { mutableStateOf(false) }
    var count by remember { mutableIntStateOf(0) }
    val background = MaterialTheme.colorScheme.background
    Column(Modifier.fillMaxSize().background(background).safeDrawingPadding().padding(FcSpacing.space4)
        .testTag("s0-privacy-shell").semantics { testTagsAsResourceId = true }) {
        SampleText("S0SENTINEL-recents", "s0-shell-sentinel")
        SampleButton("打开虚构弹层", "s0-open-dialog") { dialogOpen = true }
        SampleButton("交互探针 +1", "s0-probe") { count++ }
        SampleText("计数：$count", "s0-probe-count")
        SampleButton("基础组件样例", "s0-open-catalog", onCatalog)
    }
    if (dialogOpen) {
        Dialog(onDismissRequest = { dialogOpen = false }) {
            val window = (LocalView.current.parent as DialogWindowProvider).window
            DisposableEffect(window, privacyCover) {
                privacyCover.registerWindow(window)
                onDispose { privacyCover.unregisterWindow(window) }
            }
            Column(Modifier.fillMaxWidth().background(background).padding(FcSpacing.space4)
                .testTag("s0-privacy-dialog").semantics { testTagsAsResourceId = true }) {
                SampleText("S0SENTINEL-recents-dialog", "s0-dialog-sentinel")
                SampleButton("交互探针 +1", "s0-dialog-probe") { count++ }
                SampleText("计数：$count", "s0-dialog-probe-count")
                SampleButton("关闭弹层", "s0-close-dialog") { dialogOpen = false }
            }
        }
    }
}

@Composable
private fun SampleText(text: String, tag: String) {
    BasicText(text, Modifier.fillMaxWidth().testTag(tag),
        style = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onBackground))
}

@Composable
private fun SampleButton(text: String, tag: String, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.field).testTag(tag)
        .clickable(role = Role.Button, onClick = onClick).padding(FcSpacing.space2)) {
        SampleText(text, "$tag-label")
    }
}
