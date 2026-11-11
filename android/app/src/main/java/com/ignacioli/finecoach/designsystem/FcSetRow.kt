package com.ignacioli.finecoach.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.text.modifiers.TextAutoSizeLayoutScope
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import com.ignacioli.finecoach.R

// S1-D38: 38dp visual rhythm, independent 44dp hit targets (3dp overlap per edge).
private val setVisualRhythm = FcComponentMetrics.touch - FcSpacing.space3 / 2

// Prefer the approved size whenever it fits. The default step grid (min=13.6,
// step=0.25) does not contain the 17sp endpoint and unnecessarily shrinks values.
private object SetValueAutoSize : TextAutoSize {
    override fun equals(other: Any?) = other === this
    override fun hashCode() = System.identityHashCode(this)
    private val fallback = TextAutoSize.StepBased(minFontSize = FcTypography.body.fontSize * 0.8f,
        maxFontSize = FcTypography.body.fontSize)
    override fun TextAutoSizeLayoutScope.getFontSize(constraints: Constraints, text: AnnotatedString): TextUnit {
        val normal = FcTypography.body.fontSize
        val result = performLayout(constraints, text, normal)
        return if (!result.didOverflowWidth && !result.didOverflowHeight && (0 until result.lineCount).none { result.isLineEllipsized(it) }) normal
            else with(fallback) { getFontSize(constraints, text) }
    }
}

private fun Modifier.setHitLayout(visualWidth: Dp? = null, circle: Boolean = false) = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints)
    val width = visualWidth?.roundToPx() ?: placeable.width
    val height = if (placeable.height > FcComponentMetrics.touch.roundToPx()) placeable.height else setVisualRhythm.roundToPx()
    layout(width, height) {
        placeable.placeRelative((width - placeable.width) / 2,
            (height - placeable.height) / 2 + if (circle) (FcSpacing.space3 / 4).roundToPx() else 0)
    }
}

/** DS-SET-ROW: visible state, ordinal, values, status/undo and edit; hit areas do not set row height. */
@Composable
fun FcSetRow(ordinal: Int, values: String, completed: Boolean, pending: Boolean,
    onConfirm: () -> Unit, onEdit: () -> Unit, modifier: Modifier = Modifier,
    enabled: Boolean = true, tag: String = "set-row", onUndo: (() -> Unit)? = null) {
    Row(modifier.fillMaxWidth().heightIn(min = setVisualRhythm).semantics(mergeDescendants = true) {
        stateDescription = if (completed) "已完成" else if (pending) "待完成" else "草稿"
        customActions = buildList {
            if (enabled && !completed) add(CustomAccessibilityAction("确认") { onConfirm(); true })
            if (enabled) add(CustomAccessibilityAction("编辑") { onEdit(); true })
            if (enabled && onUndo != null) add(CustomAccessibilityAction("撤销") { onUndo(); true })
        }
    }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(FcSpacing.space3)) {
        Box(Modifier.setHitLayout(FcComponentMetrics.badge, circle = true).size(FcComponentMetrics.touch).testTag("$tag-confirm")
            .semantics { contentDescription = if (completed) "已完成" else "确认本组" }
            .clickable(enabled = enabled && !completed, onClick = onConfirm), contentAlignment = Alignment.Center) {
            if (completed) Box(Modifier.size(FcComponentMetrics.badge).testTag("$tag-circle")
                .background(FcColors.actionPrimary, CircleShape), contentAlignment = Alignment.Center) {
                Text(FcGlyph.CheckOnFill.glyph, Modifier.testTag("$tag-check").semantics { hideFromAccessibility() },
                    style = FcTypography.sectionLabel, color = FcColors.actionOn)
            } else Canvas(Modifier.size(FcComponentMetrics.badge).testTag("$tag-circle")) {
                drawCircle(if (pending) FcColors.borderControl else FcColors.textSecondary,
                    style = Stroke(width = (if (pending) FcComponentMetrics.stroke else FcComponentMetrics.hairline).toPx(),
                        pathEffect = if (pending) null else PathEffect.dashPathEffect(floatArrayOf(
                            (FcSpacing.space1 - FcComponentMetrics.hairline).toPx(), (FcSpacing.space1 / 2).toPx()))))
            }
        }
        Text("第 $ordinal 组", style = FcTypography.body, color = if (completed) FcColors.textPrimary else FcColors.textSecondary)
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
            BasicText(values, Modifier.offset(x = FcSpacing.space1 / 2).testTag("$tag-values"),
                style = FcTypography.body.copy(color = FcColors.textPrimary, textAlign = TextAlign.Start),
                maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis,
                autoSize = SetValueAutoSize)
        }
        Box(Modifier.widthIn(min = FcComponentMetrics.field - FcComponentMetrics.hairline), contentAlignment = Alignment.CenterStart) {
            if (onUndo != null) FcLinkButton("撤销", Modifier.setHitLayout().testTag("$tag-undo"), enabled, onUndo)
            else Text(if (completed) "已完成" else if (pending) "待完成" else "草稿", Modifier.offset(x = FcSpacing.space1),
                style = FcTypography.style("callout", 400), color = FcColors.textSecondary)
        }
        Box(Modifier.setHitLayout(FcSpacing.space4 + FcSpacing.space1).size(FcComponentMetrics.touch).testTag("$tag-edit")
            .semantics { contentDescription = "编辑组" }.clickable(enabled = enabled, onClick = onEdit), contentAlignment = Alignment.Center) {
            FcSymbol(painterResource(R.drawable.ic_ms_edit), Modifier.size(FcSpacing.space4 + FcSpacing.space1).testTag("$tag-edit-icon"), tint = FcColors.actionPrimary)
        }
    }
}
