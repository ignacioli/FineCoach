package com.ignacioli.finecoach

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.ignacioli.finecoach.designsystem.FcColors

/** S1-D50: full viewport; the real shell consumes a simulated status-bar inset. */
@Composable
internal fun ConformanceViewport(content: @Composable () -> Unit) {
    Box(Modifier.requiredSize(390.dp, 844.dp).background(FcColors.surfacePage).testTag("conformance-viewport")) { content() }
}

/** Dispatch after composition so the shell's inset listener is installed. */
internal fun simulateConformanceStatusBar(activity: android.app.Activity) {
    ViewCompat.dispatchApplyWindowInsets(activity.window.decorView, WindowInsetsCompat.Builder()
        .setInsets(WindowInsetsCompat.Type.statusBars(), Insets.of(0, 104, 0, 0))
        .setVisible(WindowInsetsCompat.Type.statusBars(), true).build())
}
