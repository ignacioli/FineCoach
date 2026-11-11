package com.ignacioli.finecoach.features.history

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
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
internal fun HistoryRecordCard(detail: HistoryDetail, zone: ZoneId, studentName: String = "") {
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
    Column(Modifier.fillMaxWidth().padding(vertical = FcSpacing.space4).testTag("history-record-card"),
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
                FcText(value, style = FcTypography.numeralLarge, color = FcColors.textPrimary)
                HistoryCaption(label)
            } }
        }
        if (exercises.isNotEmpty()) HistoryRecordSection("动作", "history-record-exercises") {
            exercises.forEach { exercise ->
                Column(Modifier.fillMaxWidth().padding(bottom = FcSpacing.space4), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(FcSpacing.space3)) {
                    FcEquipmentIconForExercise(exercise.sourceID.takeUnless { exercise.sourceKind == ExerciseSourceKind.sessionOnly })
                    FcText(exercise.displayNameSnapshot, Modifier.testTag("history-snapshot-${exercise.sessionExerciseID.value}"),
                        style = FcTypography.headline, color = FcColors.textPrimary)
                    }
                    exercise.sets.filter { it.state == SetRecordingState.completed }.sortedBy { it.orderIndex }.chunked(3).forEachIndexed { rowIndex, row ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                            row.forEachIndexed { index, set ->
                                Row(Modifier.weight(1f).testTag("history-set-${set.trainingSetID.value}"), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space1)) {
                                    FcText("${rowIndex * 3 + index + 1}", style = FcTypography.caption, color = FcColors.textDisabled)
                                    FcText(set.toDomain().displaySummary(), style = FcTypography.style("callout", 400), color = FcColors.textPrimary)
                                }
                            }
                            repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
        }
        session.studentFacingSummary?.takeIf { it.isNotEmpty() }?.let { summary ->
            HistoryRecordSection("课后总结", "history-record-summary") {
                FcText(summary, style = FcTypography.body, color = FcColors.textPrimary)
            }
        }
    }
}

@Composable
private fun HistoryRecordSection(title: String, tag: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().testTag(tag), verticalArrangement = Arrangement.spacedBy(FcSpacing.space3)) {
        FcListRowDivider()
        FcSectionLabel(title)
        content()
    }
}

private fun historyGrouped(value: BigDecimal): String = java.text.NumberFormat.getNumberInstance(Locale.SIMPLIFIED_CHINESE).apply {
    maximumFractionDigits = 1
}.format(value)
