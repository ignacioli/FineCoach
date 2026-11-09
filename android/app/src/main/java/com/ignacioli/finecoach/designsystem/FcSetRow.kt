package com.ignacioli.finecoach.designsystem

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag

/** DS-SET-ROW: state action, ordinal, values, status, explicit edit action. */
@Composable
fun FcSetRow(ordinal: Int, values: String, completed: Boolean, pending: Boolean,
    onConfirm: () -> Unit, onEdit: () -> Unit, modifier: Modifier = Modifier,
    enabled: Boolean = true, tag: String = "set-row") {
    Row(modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.row), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
        FcLinkButton(if (completed) "✓" else if (pending) "○" else "◌", Modifier.testTag("$tag-confirm"), enabled && !completed, onConfirm)
        Text("第 $ordinal 组", style = FcTypography.body, color = if (completed) FcColors.textPrimary else FcColors.textSecondary)
        Text(values, Modifier.weight(1f), style = FcTypography.body, color = FcColors.textPrimary)
        Text(if (completed) "已完成" else if (pending) "待确认" else "草稿", style = FcTypography.style("callout", 400), color = FcColors.textSecondary)
        FcLinkButton("编辑", Modifier.testTag("$tag-edit"), enabled, onEdit)
    }
}
