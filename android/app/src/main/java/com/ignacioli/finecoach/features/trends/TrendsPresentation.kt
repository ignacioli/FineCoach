package com.ignacioli.finecoach.features.trends

import com.ignacioli.finecoach.core.domain.common.RecordMode
import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import com.ignacioli.finecoach.core.domain.progress.Comparison
import com.ignacioli.finecoach.core.domain.progress.EstimatedOneRepMax
import com.ignacioli.finecoach.core.domain.progress.SessionGains
import com.ignacioli.finecoach.core.domain.training.CompletedSession
import com.ignacioli.finecoach.core.domain.training.DecimalValue
import com.ignacioli.finecoach.core.domain.training.DurationTextParser
import java.time.Instant
import java.time.ZoneId

enum class TrendMetric { weight, reps, volume, estimatedOneRepMax;

    val label: String
        get() = when (this) {
            weight -> "重量"
            reps -> "次数"
            volume -> "容量"
            estimatedOneRepMax -> "估算 1RM"
        }
    val unit: String
        get() = if (this == reps) "次" else "kg"

    companion object {
        fun options(exerciseID: StableExerciseID?): List<TrendMetric> {
            val base = listOf(weight, reps, volume)
            return if (exerciseID != null && exerciseID in EstimatedOneRepMax.exerciseIDs) base + estimatedOneRepMax else base
        }
    }
}

data class TrendExerciseOption(val id: StableExerciseID, val name: String, val mode: RecordMode, val assisted: Boolean)

data class TrendBestRow(val name: String, val kind: String, val value: String, val day: String?, val detail: String?)

data class TrendsContent(
    val exerciseName: String,
    val options: List<TrendExerciseOption>,
    val selected: TrendExerciseOption?,
    val metrics: List<TrendMetric>,
    val metric: TrendMetric,
    val caption: String?,
    val density: Comparison.TrendSampleDensity,
    val dashed: Boolean,
    val values: List<Float>,
    val chartX: List<Float>,
    val maxLabel: String?,
    val firstDate: String?,
    val lastDate: String?,
    val singleValue: String?,
    val singleDate: String?,
    val emptyText: String?,
    val rows: List<Pair<String, String>>,
    val bests: List<TrendBestRow>,
    val assisted: Boolean,
    val chartSamples: List<TrendChartSample> = emptyList(),
)

object TrendsPresentation {
    const val EMPTY = "练过这个动作后，这里会显示它的变化"
    const val SINGLE = "再练一次就能看出趋势"
    const val E1RM_CAPTION = "估算 1RM = 重量 × (1 + 次数 ÷ 30)，只算 1～10 次的组。这是推算值，不是实测的最大重量。"
    const val VOLUME_CAPTION = "训练容量 = 重量 × 次数"
    const val INCOMPATIBLE = "训练重点不同，无法对比，已分别展示。"

    fun content(sessions: List<CompletedSession>, assisted: Set<StableExerciseID>, zone: ZoneId,
        selectedID: StableExerciseID?, metric: TrendMetric): TrendsContent {
        val ordered = sessions.sortedWith(SessionGains.completedOrder)
        val options = options(ordered, assisted)
        val selected = options.firstOrNull { it.id == selectedID && (metric != TrendMetric.estimatedOneRepMax || it.mode == RecordMode.weightReps) }
            ?: options.firstOrNull { it.id == selectedID } ?: options.firstOrNull()
        val weightMode = selected?.mode == RecordMode.weightReps
        val metrics = selected?.takeIf { it.mode == RecordMode.weightReps }?.let { TrendMetric.options(it.id) }.orEmpty()
        val resolved = if (metric in metrics) metric else metrics.firstOrNull() ?: TrendMetric.weight
        val points = if (selected == null) emptyList() else if (resolved == TrendMetric.estimatedOneRepMax) estimatedPoints(selected.id, ordered)
            else Comparison.exerciseTrend(selected.id, selected.mode, ordered, direction(selected.assisted))
        val density = Comparison.TrendSampleDensity.classify(points)
        val plotted = if (!weightMode) emptyList() else points.mapNotNull { point -> value(resolved, point)?.let { point.completedAtUTC to it } }
        val caption = when (resolved) {
            TrendMetric.estimatedOneRepMax -> E1RM_CAPTION
            TrendMetric.volume -> VOLUME_CAPTION
            else -> null
        }
        return TrendsContent(
            exerciseName = selected?.name ?: "",
            options = options,
            selected = selected,
            metrics = metrics,
            metric = resolved,
            caption = if (selected?.mode == RecordMode.weightReps) caption else null,
            density = density,
            dashed = points.size == 2,
            chartSamples = plotted.map { TrendChartSample(day(it.first, zone), it.second.decimal, resolved.unit) },
            values = plotted.map { it.second.decimal.toFloat() },
            chartX = dateFractions(plotted.map { it.first }),
            maxLabel = plotted.maxOfOrNull { it.second }?.let { quantity(it, resolved.unit) },
            firstDate = points.firstOrNull()?.let { day(it.completedAtUTC, zone) },
            lastDate = points.lastOrNull()?.let { day(it.completedAtUTC, zone) },
            singleValue = if (weightMode) plotted.singleOrNull()?.second?.let { quantity(it, resolved.unit) } else points.singleOrNull()?.let { trendText(it) },
            singleDate = points.singleOrNull()?.let { day(it.completedAtUTC, zone) },
            emptyText = if (points.isEmpty()) EMPTY else null,
            rows = if (weightMode || points.size < 2) emptyList() else points.map { point -> day(point.completedAtUTC, zone) to trendText(point) },
            bests = bests(options, ordered, zone),
            assisted = selected?.assisted == true,
        )
    }

    fun options(sessions: List<CompletedSession>, assisted: Set<StableExerciseID>): List<TrendExerciseOption> {
        val seen = linkedSetOf<Pair<StableExerciseID, RecordMode>>()
        val rows = mutableListOf<TrendExerciseOption>()
        for (session in sessions) for (exercise in session.exercises) {
            val id = exercise.sourceID ?: continue
            if (seen.add(id to exercise.recordModeSnapshot)) rows += TrendExerciseOption(id, exercise.displayNameSnapshot.value, exercise.recordModeSnapshot, id in assisted)
        }
        return rows
    }

    fun estimatedPoints(exerciseID: StableExerciseID, sessions: List<CompletedSession>): List<Comparison.SetTrendPoint> {
        if (exerciseID !in EstimatedOneRepMax.exerciseIDs) return emptyList()
        return sessions.sortedWith(SessionGains.completedOrder).mapNotNull { session ->
            val best = session.exercises.filter { it.sourceID == exerciseID && it.recordModeSnapshot == RecordMode.weightReps }
                .flatMap { it.sets }.filter { it.contributesToStatistics }.mapNotNull { set ->
                    val weight = set.weightValue ?: return@mapNotNull null
                    val reps = set.repetitionCount ?: return@mapNotNull null
                    EstimatedOneRepMax.value(weight, reps, exerciseID)
                }.maxOrNull() ?: return@mapNotNull null
            Comparison.SetTrendPoint(session.sessionID, session.completedAtUTC, RecordMode.weightReps, best, null, null, null, null, null, null)
        }
    }

    fun bests(options: List<TrendExerciseOption>, sessions: List<CompletedSession>, zone: ZoneId): List<TrendBestRow> =
        options.mapNotNull { option ->
            val records = Comparison.personalRecords(option.id, option.mode, sessions, direction(option.assisted))
            val reps = records.mostRepsAtWeight
            val weight = records.highestWeight
            val duration = records.longestDuration
            val distance = records.longestDistance
            when {
                reps != null -> TrendBestRow(option.name, "最高重量", quantity(reps.weight, "kg"), dayOf(sessions, reps.sessionID, zone),
                    "${reps.weight.canonicalString} kg × ${reps.reps.canonicalString}")
                weight != null -> TrendBestRow(option.name, "最高重量", quantity(weight.value, "kg"), dayOf(sessions, weight.sessionID, zone), null)
                duration != null -> TrendBestRow(option.name, "最长时长", DurationTextParser.formatForEditing(duration.value.canonicalString),
                    dayOf(sessions, duration.sessionID, zone), null)
                distance != null -> TrendBestRow(option.name, "最远距离", quantity(distance.value, "km"), dayOf(sessions, distance.sessionID, zone), null)
                else -> null
            }
        }

    fun quantity(value: DecimalValue, unit: String): String {
        val shown = com.ignacioli.finecoach.features.body.BodyDataDisplay.format(value.decimal, unit)
        return "$shown $unit"
    }

    fun day(instant: Instant, zone: ZoneId): String {
        val date = instant.atZone(zone).toLocalDate()
        return "${date.monthValue}月${date.dayOfMonth}日"
    }

    private fun dayOf(sessions: List<CompletedSession>, id: com.ignacioli.finecoach.core.domain.common.SessionID, zone: ZoneId) =
        sessions.firstOrNull { it.sessionID == id }?.let { day(it.completedAtUTC, zone) }

    private fun trendText(point: Comparison.SetTrendPoint): String = when (point.recordMode) {
        RecordMode.weightReps -> point.maxWeight?.let { quantity(it, "kg") } ?: "-"
        RecordMode.reps -> point.bestReps?.let { "${it.canonicalString} 次" } ?: "-"
        RecordMode.duration -> point.bestDurationSeconds?.let { DurationTextParser.formatForEditing(it.canonicalString) } ?: "-"
        RecordMode.cardio -> {
            val parts = buildList {
                point.bestDurationSeconds?.let { add(DurationTextParser.formatForEditing(it.canonicalString)) }
                point.bestDistance?.let { add("${it.canonicalString} km") }
            }
            if (parts.isEmpty()) "-" else parts.joinToString(" · ")
        }
    }

    private fun value(metric: TrendMetric, point: Comparison.SetTrendPoint): DecimalValue? = when (metric) {
        TrendMetric.weight, TrendMetric.estimatedOneRepMax -> point.maxWeight
        TrendMetric.reps -> point.bestReps
        TrendMetric.volume -> point.volume
    }

    private fun direction(assisted: Boolean) = if (assisted) Comparison.LoadDirection.decreaseIsImprovement else Comparison.LoadDirection.increaseIsImprovement

    private fun dateFractions(instants: List<Instant>): List<Float> {
        if (instants.size < 2) return emptyList()
        val origin = instants.first().toEpochMilli()
        val span = (instants.last().toEpochMilli() - origin).coerceAtLeast(1L)
        return instants.map { (it.toEpochMilli() - origin).toFloat() / span }
    }
}
