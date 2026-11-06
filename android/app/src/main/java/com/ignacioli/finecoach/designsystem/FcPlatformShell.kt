package com.ignacioli.finecoach.designsystem

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag

// ADR §7.2 A/B. The Activity owns edge-to-edge, the shell consumes safe insets once.
@Composable
fun FcPlatformShell(onBack: () -> Unit, modifier: Modifier = Modifier,
    insets: WindowInsets = WindowInsets.safeDrawing, content: @Composable ColumnScope.() -> Unit) {
    BackHandler(onBack = onBack)
    Column(modifier.fillMaxSize().background(FcColors.surfacePage).testTag("platform-shell")) {
        Column(Modifier.fillMaxSize().windowInsetsPadding(insets).testTag("platform-safe")) {
            Column(Modifier.fillMaxSize().padding(horizontal = FcSpacing.space4).testTag("platform-content"), content = content)
        }
    }
}
