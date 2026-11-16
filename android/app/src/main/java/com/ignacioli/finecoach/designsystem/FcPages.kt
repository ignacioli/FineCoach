package com.ignacioli.finecoach.designsystem

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import com.ignacioli.finecoach.R

/** A reserved footer and a scrollable tail keep the last row clear of the primary action. */
@Composable
fun ColumnScope.FcScrollBody(modifier: Modifier = Modifier, scroll: ScrollState = rememberScrollState(),
    verticalArrangement: Arrangement.Vertical = Arrangement.Top,
    content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.weight(1f).fillMaxWidth().verticalScroll(scroll)
        .padding(bottom = FcComponentMetrics.row), verticalArrangement = verticalArrangement, content = content)
}

@Composable
fun FcPinnedAction(above: @Composable () -> Unit = {}, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().background(FcColors.surfacePage)
        .padding(top = FcSpacing.space4, bottom = FcSpacing.space8)) {
        above()
        content()
    }
}

/** §4.6: display title and optional date precede segmented navigation; the caller owns routes/actions. */
@Composable
fun FcPagePrimary(title: String, modifier: Modifier = Modifier, segments: (@Composable () -> Unit)? = null,
    subtitle: String? = null, subtitleModifier: Modifier = Modifier, actions: @Composable RowScope.() -> Unit = {}, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().background(FcColors.surfacePage), verticalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
        Column(Modifier.fillMaxWidth().padding(top = FcSpacing.space4), verticalArrangement = Arrangement.spacedBy(FcSpacing.space1)) {
            // S1-D42: header row keeps the 44dp touch row with or without actions
            Row(Modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.touch), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) {
                    FcText(title, Modifier.semantics { heading() }, style = FcTypography.display, color = FcColors.actionPrimary)
                }
                actions()
            }
            subtitle?.let { FcText(it, subtitleModifier, style = FcTypography.style("callout", 400), color = FcColors.textSecondary) }
        }
        segments?.invoke()
        content()
    }
}

/** Insets and system/header back share the existing platform shell's single owner. */
@Composable
fun FcPageSecondary(title: String, onBack: () -> Unit, modifier: Modifier = Modifier, subtitle: String? = null,
    tag: String = "page", bottom: (@Composable () -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    FcPlatformShell(onBack, modifier) {
        FcPageHeader(title, subtitle = subtitle, onBack = onBack, tag = tag)
        Column(Modifier.fillMaxWidth().weight(1f), content = content)
        bottom?.let { Box(Modifier.fillMaxWidth().padding(bottom = FcSpacing.space8)) { it() } }
    }
}

/** §4.6/C30: only Today/calendar use ambient; other empty surfaces retain the static mascot. */
@Composable
fun FcEmptyState(title: String, description: String, modifier: Modifier = Modifier, ambient: Boolean = false,
    illustrationTag: String = "empty-mascot", actionTitle: String? = null, actionTag: String = "empty-action",
    onAction: () -> Unit = {}) {
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(FcSpacing.space3)) {
        if (ambient) FcAmbientScene() else Image(painterResource(R.drawable.mascot_empty_state), null,
            Modifier.size(FcComponentMetrics.illustration).testTag(illustrationTag))
        FcText(title, style = FcTypography.headline, color = FcColors.actionPrimary, textAlign = TextAlign.Center)
        FcText(description, style = FcTypography.caption, color = FcColors.textSecondary, textAlign = TextAlign.Center)
        actionTitle?.let {
            Spacer(Modifier.weight(1f))
            FcButton(it, Modifier.padding(bottom = FcSpacing.space8).testTag(actionTag), onClick = onAction)
        }
    }
}

/** C31: a pure white, noninteractive surface with no animation, text or data work. */
@Composable
fun FcLaunch(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize().background(FcColors.surfacePage))
}
