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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogWindowProvider

// fictional-data: infrastructure sample only; no student/coach data or persistence.
internal class S0DebugApplication : Application(), ShellContentProvider {
    @Composable override fun Content(privacyCover: PrivacyCoverPolicy) = PrivacySample(privacyCover)
}

@Composable
private fun PrivacySample(privacyCover: PrivacyCoverPolicy) {
    var dialogOpen by remember { mutableStateOf(false) }
    var count by remember { mutableIntStateOf(0) }
    val background = Color(PrivacyCoverPolicy.backgroundColor(LocalContext.current))
    Column(Modifier.fillMaxSize().background(background).safeDrawingPadding().padding(16.dp)
        .testTag("s0-privacy-shell").semantics { testTagsAsResourceId = true }) {
        SampleText("S0SENTINEL-recents", "s0-shell-sentinel")
        SampleButton("打开虚构弹层", "s0-open-dialog") { dialogOpen = true }
        SampleButton("交互探针 +1", "s0-probe") { count++ }
        SampleText("计数：$count", "s0-probe-count")
    }
    if (dialogOpen) {
        Dialog(onDismissRequest = { dialogOpen = false }) {
            val window = (LocalView.current.parent as DialogWindowProvider).window
            DisposableEffect(window, privacyCover) {
                privacyCover.registerWindow(window)
                onDispose { privacyCover.unregisterWindow(window) }
            }
            Column(Modifier.fillMaxWidth().background(background).padding(16.dp)
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
    val color = LocalContext.current.obtainStyledAttributes(intArrayOf(android.R.attr.textColorPrimary)).let {
        try { Color(it.getColor(0, android.graphics.Color.BLACK)) } finally { it.recycle() }
    }
    BasicText(text, Modifier.fillMaxWidth().testTag(tag), style = TextStyle(color = color))
}

@Composable
private fun SampleButton(text: String, tag: String, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag(tag)
        .clickable(role = Role.Button, onClick = onClick).padding(8.dp)) {
        SampleText(text, "$tag-label")
    }
}
