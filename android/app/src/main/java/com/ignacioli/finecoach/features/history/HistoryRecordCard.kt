package com.ignacioli.finecoach.features.history

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.text.modifiers.TextAutoSizeLayoutScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.unit.constrainWidth
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.designsystem.*
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

internal fun historyDay(instant: Instant, zone: ZoneId): String =
    DateTimeFormatter.ofPattern("M月d日 EEE", Locale.SIMPLIFIED_CHINESE).format(instant.atZone(zone))

internal fun historyMinutes(seconds: String): String =
    BigDecimal(seconds).divide(BigDecimal(60), 0, RoundingMode.HALF_UP).max(BigDecimal.ONE).toPlainString()

internal fun historyDuration(seconds: String): String = "${historyMinutes(seconds)} 分钟"

internal fun historyFocus(focus: Set<BodyPart>): String = BodyPart.entries.filter { it in focus }
    .joinToString("、") { FcBodyParts[BodyPart.entries.indexOf(it)] }

@Composable
internal fun HistoryCaption(text: String, modifier: Modifier = Modifier) {
    FcText(text, modifier, style = FcTypography.caption, color = FcColors.textSecondary)
}

@Composable
internal fun HistoryEmpty(title: String, body: String, tag: String) {
    Column(Modifier.fillMaxWidth().padding(vertical = FcSpacing.space4).testTag(tag),
        verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
        FcText(title, style = FcTypography.headline, color = FcColors.textPrimary)
        HistoryCaption(body)
    }
}

/** Page-only allowlist: completed sets, focus, date, statistics and nonempty student summary. */
@Composable
internal fun HistoryRecordCard(detail: HistoryDetail, zone: ZoneId, studentName: String = "",
    gains: com.ignacioli.finecoach.core.domain.progress.SessionGains = com.ignacioli.finecoach.core.domain.progress.SessionGains()) {
    val session = detail.content.session
    val exercises = detail.content.exercises.sortedBy { it.orderIndex }
    val sets = exercises.flatMap { it.sets }.filter { it.state == SetRecordingState.completed }
    val reps = sets.mapNotNull { it.repetitionCount }.fold(BigDecimal.ZERO, BigDecimal::add)
    val stats = buildList {
        if (exercises.isNotEmpty()) {
            add(detail.statistics.completedSetCount.toString() to "总组数")
            if (reps > BigDecimal.ZERO) add(historyGrouped(reps) to "总次数")
        }
        // The page's default iOS report shows duration; volume disclosure is a later slice.
        if (BigDecimal(detail.statistics.displayedDurationSeconds.canonicalString) > BigDecimal.ZERO)
            add(historyMinutes(detail.statistics.displayedDurationSeconds.canonicalString) to "分钟")
    }
    Column(Modifier.fillMaxWidth().testTag("history-record-card"),
        verticalArrangement = Arrangement.spacedBy(FcSpacing.space6)) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(FcSpacing.space1)) {
            session.completedAtUTC?.let {
                FcText(historyDay(it, zone), Modifier.testTag("history-record-date"), style = FcTypography.style("callout", 400), color = FcColors.textSecondary)
            }
            FcText(historyFocus(session.trainingFocus).let { if (it.isEmpty()) "训练报告" else "${it}训练" },
                Modifier.testTag("history-record-title"), style = FcTypography.titleLarge, color = FcColors.textPrimary)
            if (studentName.isNotEmpty()) FcText(studentName, Modifier.testTag("history-student-name"),
                style = FcTypography.style("callout", 400), color = FcColors.textSecondary)
        }
        if (stats.isNotEmpty()) Row(Modifier.fillMaxWidth().testTag("history-record-stats"), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
            stats.forEach { (value, label) -> Column(Modifier.weight(1f).testTag("history-stat-$label"), verticalArrangement = Arrangement.spacedBy(FcSpacing.space1)) {
                FcText(value, Modifier.then(if (label == "总次数") Modifier.testTag("history-total-reps") else Modifier), style = FcTypography.numeralLarge, color = FcColors.textPrimary)
                HistoryCaption(label)
            } }
        }
        if (exercises.isNotEmpty()) HistoryRecordSection("动作", "history-record-exercises") {
            exercises.forEachIndexed { exerciseIndex, exercise ->
                if (exerciseIndex > 0) Spacer(Modifier.height(FcSpacing.space4))
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                    FcEquipmentIconForExercise(exercise.sourceID.takeUnless { exercise.sourceKind == ExerciseSourceKind.sessionOnly },
                        Modifier.testTag("conformance:icon / ${historyEquipmentName(exercise.sourceID)}"))
                    FcText(exercise.displayNameSnapshot, Modifier.testTag("history-snapshot-${exercise.sessionExerciseID.value}"),
                        style = FcTypography.headline, color = FcColors.textPrimary)
                    }
                    exercise.sets.filter { it.state == SetRecordingState.completed }.sortedBy { it.orderIndex }.chunked(3).forEachIndexed { rowIndex, row ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                            row.forEachIndexed { index, set ->
                                HistorySetCell("${rowIndex * 3 + index + 1}", set.toDomain().displaySummary(),
                                    Modifier.weight(1f).alignByBaseline().testTag("history-set-${set.trainingSetID.value}"))
                            }
                            repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
        }
        SessionGainsSection(gains, "history-gains")
        session.studentFacingSummary?.takeIf { it.isNotEmpty() }?.let { summary ->
            HistoryRecordSection("课后总结", "history-record-summary") {
                FcText(summary, style = FcTypography.body, color = FcColors.textPrimary)
            }
        }
    }
}

// Match iOS ShareReportCardView.swift:250 minimumScaleFactor; Android then wraps (AD-09).
private const val HistorySetMinimumScale = 0.8f

/** Publish the value baseline for the enclosing three-cell row as well as the index/value pair. */
@Composable
private fun HistorySetCell(index: String, value: String, modifier: Modifier) {
    val style = FcTypography.style("callout", 400)
    val glued = remember(value) { value.replace(Regex("(?<=\\d) (?=[^\\s\\d×])|(?<=×) (?=\\d)"), "\u00a0") }
    val autoSize = remember(style.fontSize) { object : TextAutoSize {
        override fun TextAutoSizeLayoutScope.getFontSize(constraints: Constraints, text: AnnotatedString): TextUnit {
            for (step in 100 downTo (HistorySetMinimumScale * 100).toInt()) {
                val size = style.fontSize * (step / 100f)
                val result = performLayout(constraints, text, size)
                if (result.lineCount == 1 && !result.hasVisualOverflow) return size
            }
            return style.fontSize * HistorySetMinimumScale
        }
        override fun equals(other: Any?) = this === other
        override fun hashCode() = System.identityHashCode(this)
    } }
    Layout(modifier = modifier, content = {
        FcText(index, style = FcTypography.caption, color = FcColors.textDisabled)
        FcText(glued, style = style, color = FcColors.textPrimary, autoSize = autoSize,
            softWrap = true, maxLines = Int.MAX_VALUE, overflow = TextOverflow.Visible)
    }) { measurables, constraints ->
        val indexPlaceable = measurables[0].measure(constraints.copy(minWidth = 0, minHeight = 0))
        val gap = FcSpacing.space1.roundToPx()
        val valuePlaceable = measurables[1].measure(constraints.copy(minWidth = 0, minHeight = 0,
            maxWidth = (constraints.maxWidth - indexPlaceable.width - gap).coerceAtLeast(0)))
        val baseline = maxOf(indexPlaceable[FirstBaseline], valuePlaceable[FirstBaseline])
        val indexY = baseline - indexPlaceable[FirstBaseline]
        val valueY = baseline - valuePlaceable[FirstBaseline]
        layout(constraints.constrainWidth(indexPlaceable.width + gap + valuePlaceable.width),
            constraints.constrainHeight(maxOf(indexY + indexPlaceable.height, valueY + valuePlaceable.height)),
            alignmentLines = mapOf(FirstBaseline to baseline)) {
            indexPlaceable.placeRelative(0, indexY)
            valuePlaceable.placeRelative(indexPlaceable.width + gap, valueY)
        }
    }
}

@Composable
private fun HistoryRecordSection(title: String, tag: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().testTag(tag), verticalArrangement = Arrangement.spacedBy(FcSpacing.space3)) {
        FcListRowDivider(Modifier.testTag("conformance:Divider"))
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            FcSectionLabel(title)
            Column(Modifier.fillMaxWidth(), content = content)
        }
    }
}

private fun historyGrouped(value: BigDecimal): String = java.text.NumberFormat.getNumberInstance(Locale.SIMPLIFIED_CHINESE).apply {
    maximumFractionDigits = 1
}.format(value)

@Composable
private fun historyEquipmentName(id: StableExerciseID?): String {
    val metadata = rememberExerciseCatalogMetadata()
    val facet = metadata[id]
    return FcEquipmentIcon.icon(facet?.equipmentClass, facet?.primaryMuscleGroup)?.name?.replace('_', '-') ?: "unmapped"
}
