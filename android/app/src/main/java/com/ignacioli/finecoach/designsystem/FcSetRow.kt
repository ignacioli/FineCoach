package com.ignacioli.finecoach.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.text.modifiers.TextAutoSizeLayoutScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.*
import androidx.compose.animation.core.*
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
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
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import com.ignacioli.finecoach.R

// S1-D38: 38dp visual rhythm; each 44dp hit target is centered on its visible graphic (edit ±3dp, circle 0/+6dp); overlap bands go to the lower row.
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

@Composable
private fun SetValues(values: String, modifier: Modifier) {
    BasicText(values, modifier.fcLineBox(FcTypography.body, FcLineCount()),
        style = FcTypography.body.copy(color = FcColors.textPrimary, textAlign = TextAlign.Start),
        maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis, autoSize = SetValueAutoSize)
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
    enabled: Boolean = true, tag: String = "set-row", onUndo: (() -> Unit)? = null,
    isNewRecord: Boolean = false, recordFloatSequence: Int? = null) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val valueMinimum = with(density) { measurer.measure(values,
        FcTypography.body.copy(fontSize = FcTypography.body.fontSize * 0.8f), maxLines = 1).size.width.toDp() }
    val titleMinimum = with(density) { measurer.measure("第 $ordinal 组", FcTypography.body, maxLines = 1).size.width.toDp() }
    val titleMaximum = (maxWidth - FcComponentMetrics.badge - FcSpacing.space3 * 3 -
        FcComponentMetrics.field - FcSpacing.space1 * 2 - (FcSpacing.space4 + FcSpacing.space1) - valueMinimum).coerceAtLeast(titleMinimum)
    Row(modifier.fillMaxWidth().heightIn(min = setVisualRhythm).semantics(mergeDescendants = true) {
        stateDescription = (if (completed && isNewRecord) "新纪录，" else "") + if (completed) "已完成" else if (pending) "待完成" else "草稿"
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
                FcText(FcGlyph.CheckOnFill.glyph, Modifier.testTag("$tag-check").semantics { hideFromAccessibility() },
                    style = FcTypography.sectionLabel, color = FcColors.actionOn)
            } else Canvas(Modifier.size(FcComponentMetrics.badge).testTag("$tag-circle")) {
                drawCircle(if (pending) FcColors.borderControl else FcColors.textSecondary,
                    style = Stroke(width = (if (pending) FcComponentMetrics.stroke else FcComponentMetrics.hairline).toPx(),
                        pathEffect = if (pending) null else PathEffect.dashPathEffect(floatArrayOf(
                            (FcSpacing.space1 - FcComponentMetrics.hairline).toPx(), (FcSpacing.space1 / 2).toPx()))))
            }
        }
        if (completed && isNewRecord) {
            @OptIn(ExperimentalLayoutApi::class)
            FlowRow(Modifier.widthIn(max = titleMaximum),
                horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2), itemVerticalAlignment = Alignment.CenterVertically) {
                FcText("第 $ordinal 组", style = FcTypography.body, color = FcColors.textPrimary)
                FcSetRowRecordBadge(Modifier.testTag("$tag-record"))
            }
        } else FcText("第 $ordinal 组", style = FcTypography.body, color = if (completed) FcColors.textPrimary else FcColors.textSecondary)
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
            SetValues(values, Modifier.testTag("$tag-values"))
            val float = remember { Animatable(1f) }
            var floating by remember { mutableStateOf(false) }
            val distance = with(LocalDensity.current) { FcSpacing.space6.toPx() }
            LaunchedEffect(recordFloatSequence) {
                floating = false
                if (recordFloatSequence != null && completed && isNewRecord) {
                    float.snapTo(0f); floating = true
                    // motion.duration.emphasis + motion.curve.standard (easeOut), README §14.2.
                    float.animateTo(1f, tween(FcMotion.durationEmphasisMillis, easing = FcMotion.curveStandard))
                    floating = false
                }
            }
            if (floating) SetValues(values, Modifier.testTag("$tag-record-float").graphicsLayer {
                translationY = -distance * float.value; alpha = 1f - float.value
            }.clearAndSetSemantics { hideFromAccessibility() })
        }
        // S1-D42: P0-a2 trailing cluster on token gaps — values → space.3 + space.1 → status column
        // (field width) → space.1 → edit; keeps the 38dp rhythm and each 44dp hit box.
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(FcSpacing.space1)) {
            Box(Modifier.padding(start = FcSpacing.space1).widthIn(min = FcComponentMetrics.field), contentAlignment = Alignment.CenterStart) {
                if (onUndo != null) FcLinkButton("撤销", Modifier.setHitLayout().testTag("$tag-undo"), enabled, contentAlignment = Alignment.CenterStart, onClick = onUndo)
                else FcText(if (completed) "已完成" else if (pending) "待完成" else "草稿",
                    style = FcTypography.style("callout", 400), color = FcColors.textSecondary)
            }
            Box(Modifier.setHitLayout(FcSpacing.space4 + FcSpacing.space1).size(FcComponentMetrics.touch).testTag("$tag-edit")
                .semantics { contentDescription = "编辑组" }.clickable(enabled = enabled, onClick = onEdit), contentAlignment = Alignment.Center) {
                FcSymbol(painterResource(R.drawable.ic_ms_edit), Modifier.size(FcSpacing.space4 + FcSpacing.space1).testTag("$tag-edit-icon"), tint = FcColors.actionPrimary)
            }
        }
    }
    }
}

/** DS-SET-ROW's informational part, also used in the session-gains action slot. */
@Composable
fun FcSetRowRecordBadge(modifier: Modifier = Modifier) {
    FcText("新纪录", modifier.background(FcColors.surfaceSelected, FcShapes.capsule)
        .padding(horizontal = FcSpacing.space2, vertical = FcSpacing.space1)
        .clearAndSetSemantics { hideFromAccessibility() },
        style = FcTypography.sectionLabel, color = FcColors.actionPrimary)
}
