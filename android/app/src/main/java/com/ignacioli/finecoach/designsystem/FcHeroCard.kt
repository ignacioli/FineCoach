package com.ignacioli.finecoach.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics

@Composable
fun FcHeroCard(
    badgeText: String,
    title: String,
    subtitle: String,
    modifier: Modifier = Modifier,
    actionTitle: String? = null,
    onClick: (() -> Unit)? = null,
) {
    val shape = RoundedCornerShape(FcShapes.lg)
    val minCardHeight = FcComponentMetrics.row + FcComponentMetrics.field
    val badgeMinWidth = FcComponentMetrics.touch + FcSpacing.space3
    val click = onClick
    Column(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = minCardHeight)
            .clip(shape)
            .background(FcColors.actionPrimary)
            .then(
                if (click != null) {
                    Modifier.clickable(role = Role.Button, onClick = click)
                } else {
                    Modifier
                },
            )
            .padding(FcSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(FcSpacing.space3),
    ) {
        Box(
            modifier = Modifier
                .widthIn(min = badgeMinWidth)
                .height(FcComponentMetrics.icon)
                .clip(FcShapes.capsule)
                .background(FcColors.surfaceCanvas)
                .padding(horizontal = FcSpacing.space2),
            contentAlignment = Alignment.Center,
        ) {
            FcText(
                text = badgeText,
                style = FcTypography.sectionLabel,
                color = FcColors.actionPrimary,
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2),
        ) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .alignBy(FirstBaseline),
                verticalArrangement = Arrangement.spacedBy(FcSpacing.space1),
            ) {
                FcText(
                    text = title,
                    modifier = Modifier.semantics { heading() },
                    style = FcTypography.headline,
                    color = FcColors.actionOn,
                )
                if (subtitle.isNotEmpty()) {
                    FcText(
                        text = subtitle,
                        style = FcTypography.callout,
                        color = FcColors.textOnActionSecondary,
                    )
                }
            }
            if (actionTitle != null) {
                FcText(
                    text = actionTitle,
                    modifier = Modifier.alignBy(FirstBaseline),
                    style = FcTypography.style("callout", 600),
                    color = FcColors.actionOn,
                )
            }
        }
    }
}

data class FcHeroEntry(val id: String, val title: String, val subtitle: String)

@Composable
fun FcMultiHeroCard(entries: List<FcHeroEntry>, onOpen: (String) -> Unit, modifier: Modifier = Modifier) {
    require(entries.isNotEmpty() && entries.map { it.id }.distinct().size == entries.size)
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(FcShapes.lg)).background(FcColors.actionPrimary)
        .padding(FcSpacing.space4), verticalArrangement = Arrangement.spacedBy(FcSpacing.space3)) {
        Box(Modifier.widthIn(min = FcComponentMetrics.touch + FcSpacing.space3).height(FcComponentMetrics.icon)
            .clip(FcShapes.capsule).background(FcColors.surfaceCanvas).padding(horizontal = FcSpacing.space2), contentAlignment = Alignment.Center) {
            FcText("进行中 · ${entries.size}", style = FcTypography.sectionLabel, color = FcColors.actionPrimary)
        }
        entries.forEachIndexed { index, entry ->
            if (index > 0) Box(Modifier.fillMaxWidth().height(FcComponentMetrics.hairline).background(FcColors.surfaceDividerOnAction))
            Row(Modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.touch).then(Modifier.clickable(role = Role.Button) { onOpen(entry.id) })
                .then(Modifier.semantics { }).testTag("hero-${entry.id}"), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                Column(Modifier.weight(1f)) {
                    FcText(entry.title, style = FcTypography.headline, color = FcColors.actionOn)
                    FcText(entry.subtitle, style = FcTypography.callout, color = FcColors.textOnActionSecondary)
                }
                FcText("继续 ›", style = FcTypography.style("callout", 600), color = FcColors.actionOn)
            }
        }
    }
}
