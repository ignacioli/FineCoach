package com.ignacioli.finecoach.features.trends

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
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
fun FcTrendChart(values: List<Float>, dashed: Boolean, modifier: Modifier = Modifier, x: List<Float> = emptyList()) {
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
    Box(modifier.background(FcColors.surfacePage).testTag("conformance:Trend chart (M1 TrendsView)")) {
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
            drawPath(path, FcColors.actionPrimary, style = Stroke(width = stroke,
                pathEffect = if (dashed) PathEffect.dashPathEffect(floatArrayOf(dash, dash)) else null))
        }
        Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(FcComponentMetrics.hairline)
            .background(FcColors.surfaceDivider).testTag("conformance:svg-line"))
        if (values.size >= 2) Layout(content = {
            Box(Modifier.testTag("conformance:svg-polyline"))
            values.forEach { _ ->
                Box(Modifier.clip(CircleShape).background(FcColors.actionPrimary).testTag("conformance:svg-circle"))
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
            val dots = measurables.drop(1).map { it.measure(Constraints.fixed(dot, dot)) }
            layout(width, height) {
                line.place(0, top)
                positions.forEachIndexed { index, (x, y) -> dots[index].place(x, y) }
            }
        }
    }
}
