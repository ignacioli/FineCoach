package com.ignacioli.finecoach.designsystem

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.res.painterResource
import com.ignacioli.finecoach.R
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag

/** DS-SET-ROW: state action, ordinal, values, status, explicit edit action. */
@Composable
fun FcSetRow(ordinal: Int, values: String, completed: Boolean, pending: Boolean,
    onConfirm: () -> Unit, onEdit: () -> Unit, modifier: Modifier = Modifier,
    enabled: Boolean = true, tag: String = "set-row", onUndo: (() -> Unit)? = null) {
    Row(modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.row).semantics(mergeDescendants = true) {
        stateDescription = if (completed) "已完成" else if (pending) "待完成" else "草稿"
        customActions = buildList {
            if (enabled && !completed) add(CustomAccessibilityAction("确认") { onConfirm(); true })
            if (enabled) add(CustomAccessibilityAction("编辑") { onEdit(); true })
            if (enabled && onUndo != null) add(CustomAccessibilityAction("撤销") { onUndo(); true })
        }
    }, verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
        Box(Modifier.size(FcComponentMetrics.touch).testTag("$tag-confirm")
            .semantics { contentDescription = if (completed) "已完成" else "确认本组" }
            .clickable(enabled = enabled && !completed, onClick = onConfirm), contentAlignment = Alignment.Center) {
            if (completed) Box(Modifier.size(FcComponentMetrics.badge).background(FcColors.actionPrimary, CircleShape), contentAlignment = Alignment.Center) {
                FcSymbol(FcGlyph.CheckOnFill)
            } else Canvas(Modifier.size(FcComponentMetrics.badge)) {
                drawCircle(if (pending) FcColors.borderControl else FcColors.textSecondary,
                    style = Stroke(width = (if (pending) FcComponentMetrics.stroke else FcComponentMetrics.hairline).toPx(), pathEffect = if (pending) null else
                        PathEffect.dashPathEffect(floatArrayOf((FcSpacing.space1 - FcComponentMetrics.hairline).toPx(), (FcSpacing.space1 / 2).toPx()))))
            }
        }
        Text("第 $ordinal 组", style = FcTypography.body, color = if (completed) FcColors.textPrimary else FcColors.textSecondary)
        BasicText(values, Modifier.weight(1f).testTag("$tag-values"),
            style = FcTypography.body.copy(color = FcColors.textPrimary, textAlign = TextAlign.End),
            maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis,
            autoSize = TextAutoSize.StepBased(minFontSize = FcTypography.body.fontSize * 0.8f,
                maxFontSize = FcTypography.body.fontSize))
        if (onUndo != null) FcLinkButton("撤销", Modifier.testTag("$tag-undo"), enabled, onUndo)
        else Text(if (completed) "已完成" else if (pending) "待完成" else "草稿", style = FcTypography.style("callout", 400), color = FcColors.textSecondary)
        Box(Modifier.size(FcComponentMetrics.touch).testTag("$tag-edit")
            .semantics { contentDescription = "编辑组" }.clickable(enabled = enabled, onClick = onEdit), contentAlignment = Alignment.Center) {
            FcSymbol(painterResource(R.drawable.ic_ms_edit), Modifier.size(FcSpacing.space4 + FcComponentMetrics.hairline), tint = FcColors.textSecondary)
        }
    }
}
