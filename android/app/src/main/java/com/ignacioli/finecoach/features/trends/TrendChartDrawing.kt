package com.ignacioli.finecoach.features.trends

import com.ignacioli.finecoach.features.body.BodyDataDisplay
import java.math.BigDecimal
import kotlin.math.abs

/** S3-D22: beyond eight samples, the latest marker alone identifies the end. */
object TrendChartDrawing {
    const val MAX_VISIBLE_MARKERS = 8
    const val AREA_FILL_ALPHA = 0.08f // S3-D23 approved chart.line fill, not a new token.
    fun markerIndices(count: Int): List<Int> = when {
        count < 2 -> emptyList()
        count <= MAX_VISIBLE_MARKERS -> (0 until count).toList()
        else -> listOf(count - 1)
    }
    fun nearest(fractions: List<Float>, fraction: Float): Int? =
        fractions.indices.minByOrNull { abs(fractions[it] - fraction) }
}

class TrendChartSample(val date: String, val value: BigDecimal, val unit: String, val custom: Boolean = false) {
    val quantity get() = "${BodyDataDisplay.format(value, unit, custom)} $unit"
    val label get() = "$date · $quantity"
    override fun toString() = "TrendChartSample(redacted)"
}

fun trendChartSummary(samples: List<TrendChartSample>): String {
    if (samples.isEmpty()) return "暂无趋势数据"
    val low = samples.minBy { it.value }
    val high = samples.maxBy { it.value }
    return "${samples.first().date}至${samples.last().date}；最小值 ${low.quantity}；最大值 ${high.quantity}；最新值 ${samples.last().quantity}"
}
