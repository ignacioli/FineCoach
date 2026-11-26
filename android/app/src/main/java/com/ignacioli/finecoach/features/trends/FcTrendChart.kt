package com.ignacioli.finecoach.features.trends

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.*
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntSize
import com.ignacioli.finecoach.designsystem.FcText
import com.ignacioli.finecoach.designsystem.FcShapes
import com.ignacioli.finecoach.designsystem.FcTypography
import kotlin.math.abs
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.Constraints
import com.ignacioli.finecoach.designsystem.FcColors
import com.ignacioli.finecoach.designsystem.FcComponentMetrics
import com.ignacioli.finecoach.designsystem.FcSpacing
import kotlin.math.roundToInt

/** Feature-owned trend line. Colors and stroke come from tokens; no chart library. */
@Composable
fun FcTrendChart(values: List<Float>, dashed: Boolean, modifier: Modifier = Modifier, x: List<Float> = emptyList(),
    samples: List<TrendChartSample> = emptyList(), onInspectingChange: (Boolean) -> Unit = {}) {
    val density = LocalDensity.current
    // Board polyline and iOS TrendLineChart are 2pt. The 1.5 component stroke is for borders.
    val stroke = with(density) { (FcSpacing.space1 / 2).toPx() }
    val dash = with(density) { FcSpacing.space1.toPx() }
    val dot = with(density) { FcSpacing.space2.toPx() }.roundToInt().coerceAtLeast(1)
    val leftInset = with(density) { FcSpacing.space1.toPx() }
    val rightInset = with(density) { (FcSpacing.space4 + FcSpacing.space1 / 2).toPx() }
    // Insets are inside the plot, which sits space.4 below the chart block. space.2 + space.4 = the old space.6 top.
    val topInset = with(density) { FcSpacing.space2.toPx() }
    val bottomInset = with(density) { FcSpacing.space6.toPx() }
    val fractions = if (x.size == values.size && values.size >= 2) x else List(values.size) { index ->
        if (values.size < 2) 0f else index.toFloat() / values.lastIndex
    }
    val low = values.minOrNull() ?: 0f
    val high = values.maxOrNull() ?: 1f
    val span = (high - low).takeIf { it > 0f } ?: 1f
    var selected by remember(values, x, samples) { mutableStateOf<Int?>(null) }
    var plotSize by remember { mutableStateOf(IntSize.Zero) }
    val publishInspection by rememberUpdatedState(onInspectingChange)
    val bubbleHeight = with(density) { FcSpacing.space6.roundToPx() }
    val ringRadius = with(density) { (FcSpacing.space3 / 2).toPx() }
    val hairline = with(density) { FcComponentMetrics.hairline.toPx() }
    fun selectAt(px: Float) {
        val width = plotSize.width - leftInset - rightInset
        selected = if (samples.size == values.size && width > 0f) TrendChartDrawing.nearest(fractions, (px - leftInset) / width) else null
        publishInspection(selected != null)
    }
    Box(modifier.background(FcColors.surfacePage).testTag("conformance:Trend chart (M1 TrendsView)")
        .onSizeChanged { plotSize = it }
        .semantics { contentDescription = trendChartSummary(samples) }
        .pointerInput(values, x, samples) {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                var current = down
                try {
                    val activated = withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) {
                        var decision: Boolean? = null
                        while (decision == null) {
                            current = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                            val delta = current.position - down.position
                            decision = when {
                                !current.pressed || current.isConsumed -> false
                                abs(delta.y) > viewConfiguration.touchSlop && abs(delta.y) >= abs(delta.x) -> false
                                abs(delta.x) > viewConfiguration.touchSlop -> true
                                else -> null
                            }
                        }
                        decision ?: false
                    }
                    // Timeout means a stationary hold. A vertical gesture exits without consuming.
                    if (activated != false && current.pressed) {
                        current.consume()
                        selectAt(current.position.x)
                        while (current.pressed) {
                            current = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                            if (current.pressed) selectAt(current.position.x)
                            current.consume()
                        }
                    }
                } finally {
                    selected = null
                    publishInspection(false)
                }
            }
        }) {
        Box(Modifier.matchParentSize().background(FcColors.surfacePage).testTag("conformance:base-background"))
        Canvas(Modifier.matchParentSize()) {
            if (values.size < 2) return@Canvas
            fun point(index: Int): Offset {
                val px = leftInset + (size.width - leftInset - rightInset) * fractions[index]
                val py = size.height - bottomInset - (size.height - topInset - bottomInset) * ((values[index] - low) / span)
                return Offset(px, py)
            }
            val path = Path().apply {
                val first = point(0)
                moveTo(first.x, first.y)
                for (index in 1..values.lastIndex) {
                    val next = point(index)
                    lineTo(next.x, next.y)
                }
            }
            val fill = Path().apply {
                val first = point(0)
                moveTo(0f, first.y)
                lineTo(first.x, first.y)
                for (index in 1..values.lastIndex) { val next = point(index); lineTo(next.x, next.y) }
                lineTo(point(values.lastIndex).x, size.height)
                lineTo(0f, size.height)
                close()
            }
            drawPath(fill, FcColors.chartLine.copy(alpha = TrendChartDrawing.AREA_FILL_ALPHA))
            drawPath(path, FcColors.chartLine, style = Stroke(width = stroke,
                pathEffect = if (dashed) PathEffect.dashPathEffect(floatArrayOf(dash, dash)) else null))
        }
        Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(FcComponentMetrics.hairline)
            .background(FcColors.surfaceDivider).testTag("conformance:svg-line"))
        if (values.size >= 2) Layout(content = {
            Box(Modifier.testTag("conformance:svg-polyline"))
            Box(Modifier.testTag("conformance:area-fill"))
            TrendChartDrawing.markerIndices(values.size).forEach { _ ->
                Box(Modifier.clip(CircleShape).background(FcColors.chartLine).testTag("conformance:svg-circle"))
            }
        }, modifier = Modifier.fillMaxSize()) { measurables, constraints ->
            val width = constraints.maxWidth
            val height = constraints.maxHeight
            val centers = values.indices.map { index ->
                val px = leftInset + (width - leftInset - rightInset) * fractions[index]
                val py = height - bottomInset - (height - topInset - bottomInset) * ((values[index] - low) / span)
                px to py
            }
            val positions = centers.map { (px, py) -> (px - dot / 2f).roundToInt() to (py - dot / 2f).roundToInt() }
            val top = centers.minOf { it.second }.roundToInt()
            val bottom = centers.maxOf { it.second }.roundToInt()
            val right = centers.maxOf { it.first }.roundToInt()
            val line = measurables.first().measure(Constraints.fixed(right.coerceAtLeast(1), (bottom - top).coerceAtLeast(1)))
            val area = measurables[1].measure(Constraints.fixed(right.coerceAtLeast(1), (height - top).coerceAtLeast(1)))
            val dots = measurables.drop(2).map { it.measure(Constraints.fixed(dot, dot)) }
            layout(width, height) {
                line.place(0, top)
                area.place(0, top)
                TrendChartDrawing.markerIndices(values.size).forEachIndexed { index, point -> val (x, y) = positions[point]; dots[index].place(x, y) }
            }
        }
        selected?.let { index ->
            Canvas(Modifier.matchParentSize().testTag("trend-inspection")) {
                val px = leftInset + (size.width - leftInset - rightInset) * fractions[index]
                val py = size.height - bottomInset - (size.height - topInset - bottomInset) * ((values[index] - low) / span)
                drawLine(FcColors.textSecondary, Offset(px, 0f), Offset(px, size.height), strokeWidth = hairline)
                drawCircle(FcColors.surfacePage, ringRadius, Offset(px, py))
                drawCircle(FcColors.chartLine, ringRadius, Offset(px, py), style = Stroke(width = stroke))
            }
            Layout(content = {
                Box(Modifier.clip(androidx.compose.foundation.shape.RoundedCornerShape(FcShapes.sm)).background(FcColors.actionPrimary)
                    .padding(horizontal = FcSpacing.space2).testTag("trend-bubble"), contentAlignment = Alignment.Center) {
                    FcText(samples[index].label, color = FcColors.actionOn, style = FcTypography.style("caption", 600), maxLines = 1)
                }
            }, modifier = Modifier.fillMaxSize()) { measurables, constraints ->
                val bubble = measurables.single().measure(Constraints(maxWidth = constraints.maxWidth, minHeight = bubbleHeight, maxHeight = bubbleHeight))
                val px = leftInset + (constraints.maxWidth - leftInset - rightInset) * fractions[index]
                val bx = (px - bubble.width / 2f).roundToInt().coerceIn(0, (constraints.maxWidth - bubble.width).coerceAtLeast(0))
                layout(constraints.maxWidth, constraints.maxHeight) { bubble.place(bx, -bubbleHeight) }
            }
        }
    }
}
