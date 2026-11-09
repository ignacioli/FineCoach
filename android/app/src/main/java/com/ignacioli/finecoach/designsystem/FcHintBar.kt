package com.ignacioli.finecoach.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics

@Composable
fun FcHintBar(
    text: String,
    modifier: Modifier = Modifier,
    actionTitle: String? = null,
    onClick: (() -> Unit)? = null,
) {
    val shape = RoundedCornerShape(FcShapes.md)
    val title = actionTitle
    val click = onClick
    val bar = modifier
        .fillMaxWidth()
        .heightIn(min = FcComponentMetrics.touch)
        .clip(shape)
        .background(FcColors.surfaceSelected)
    if (title == null || click == null) {
        Box(
            modifier = bar
                .semantics(mergeDescendants = true) { contentDescription = text }
                .padding(horizontal = FcSpacing.space4),
            contentAlignment = Alignment.CenterStart,
        ) {
            Text(text = text, style = FcTypography.caption, color = FcColors.actionPrimary)
        }
    } else {
        Row(
            modifier = bar
                .semantics(mergeDescendants = true) { }
                .clickable(role = Role.Button, onClick = click)
                .padding(horizontal = FcSpacing.space4),
            horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = text,
                modifier = Modifier.weight(1f),
                style = FcTypography.caption,
                color = FcColors.actionPrimary,
            )
            Text(
                text = title,
                style = FcTypography.style("callout", 600),
                color = FcColors.actionPrimary,
            )
        }
    }
}
