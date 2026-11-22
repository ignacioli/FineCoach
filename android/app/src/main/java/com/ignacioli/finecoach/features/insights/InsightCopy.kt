package com.ignacioli.finecoach.features.insights

import com.ignacioli.finecoach.core.domain.insight.Insight
import com.ignacioli.finecoach.features.trends.TrendsPresentation
import com.ignacioli.finecoach.core.domain.training.DurationTextParser
import java.time.LocalDate

enum class InsightContext { today, list, studentDetail }

data class InsightRowCopy(val title: String, val subtitle: String?, val accessibilityLabel: String)

/** Same assembly as iOS InsightRowContent. Visible title adds the student name except on the student page. */
fun insightCopy(insight: Insight, studentName: String, exerciseName: String, context: InsightContext): InsightRowCopy {
    val group: String
    var title: String
    var subtitle: String?
    when (insight.kind) {
        Insight.Kind.packageExhausted -> {
            group = "课包"; title = "课包已用完"; subtitle = "余额 ${insight.balance ?: 0} 节"
        }
        Insight.Kind.packageExpired -> {
            group = "课包"; title = "课包已过期"
            subtitle = insight.packageEndDate?.let { "有效期至 ${monthDay(it)}" }
        }
        Insight.Kind.packageLow -> {
            group = "课包"
            val balance = insight.balance
            if (balance != null && balance <= 2) {
                title = "课包剩 $balance 节"
                subtitle = insight.packageEndDate?.let { "有效期至 ${monthDay(it)}" }
            } else {
                val days = insight.daysUntilExpiry
                title = if (days == 0L) "课包今天到期" else "课包 ${days ?: 0} 天后到期"
                subtitle = "剩 ${balance ?: 0} 节"
            }
        }
        Insight.Kind.inactive -> {
            group = "很久没来"
            val days = insight.daysInactive ?: 0
            title = if (insight.hasNeverTrained) "建档 $days 天还没上过课" else "$days 天没来"
            subtitle = "也没约下次课"
        }
        Insight.Kind.stagnant -> {
            group = "进步停滞"
            val unchanged = "连续 3 节没有创新高"
            val best = baseline(insight)
            when (context) {
                InsightContext.today -> { title = exerciseName; subtitle = unchanged }
                InsightContext.list -> { title = exerciseName; subtitle = listOfNotNull(unchanged, best).joinToString(" · ") }
                InsightContext.studentDetail -> { title = "$exerciseName · $unchanged"; subtitle = best }
            }
        }
    }
    val label = listOf(group, studentName.takeIf { context != InsightContext.studentDetail }, title, subtitle).filter { !it.isNullOrBlank() }.joinToString("，")
    if (context != InsightContext.studentDetail) title = "$studentName · $title"
    return InsightRowCopy(title, subtitle, label)
}

fun insightUndoMessage(studentName: String, context: InsightContext): String =
    if (context == InsightContext.studentDetail) "已暂不提醒 14 天" else "$studentName · 已暂不提醒 14 天"

private fun monthDay(date: LocalDate) = "${date.monthValue}月${date.dayOfMonth}日"

private fun baseline(insight: Insight): String? {
    val value = insight.baselineBest ?: return null
    val metric = insight.baselineMetric ?: return null
    return when (metric) {
        Insight.Metric.estimatedOneRepMax -> "估算 1RM ${TrendsPresentation.quantity(value, "kg")}"
        Insight.Metric.highestWeight -> "最大 ${TrendsPresentation.quantity(value, "kg")}"
        Insight.Metric.lowestAssistance -> "最轻辅助 ${TrendsPresentation.quantity(value, "kg")}"
        Insight.Metric.mostReps -> "最多 ${value.canonicalString} 次"
        Insight.Metric.longestDuration -> "最长 ${DurationTextParser.formatForEditing(value.canonicalString)}"
    }
}
