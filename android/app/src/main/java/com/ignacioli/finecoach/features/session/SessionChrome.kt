package com.ignacioli.finecoach.features.session

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.layout.layout
import androidx.compose.ui.semantics.*
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.designsystem.*
import kotlinx.coroutines.delay
import java.time.Duration

@Composable
internal fun SessionHeader(student: String, content: SessionContentRecord?, clock: AppClock, back: () -> Unit) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(FcSpacing.space3)) {
        Box(Modifier.fillMaxWidth()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.width(FcSpacing.space4).alignByBaseline()) {
                    FcSymbol(FcGlyph.PageBack, visualTag = "active-session-back-glyph")
                }
                Text("训练中", Modifier.alignByBaseline().semantics { heading() }, style = FcTypography.style("titleEmphasis", 700), color = FcColors.textPrimary)
            }
            // DS-PAGE-HEADER: the 44dp hit area overlays the 16dp leading slot.
            Box(Modifier.matchParentSize(), contentAlignment = Alignment.TopStart) {
                Box(Modifier.wrapContentSize(Alignment.TopStart, unbounded = true)
                    .offset(x = -(FcComponentMetrics.touch - FcSpacing.space4) / 2).requiredSize(FcComponentMetrics.touch)
                    .testTag("active-session-back").semantics { contentDescription = "返回" }
                    .clickable(onClick = back)) { }
            }
        }
        Row(Modifier.fillMaxWidth().padding(end = FcSpacing.space6 + FcSpacing.space1).testTag("session-meta"), verticalAlignment = Alignment.CenterVertically) {
            val focus = content?.session?.trainingFocus.orEmpty().sortedBy { it.ordinal }.joinToString("、") { FcBodyParts[it.ordinal] }
            Text(student + if (focus.isNotEmpty()) " · $focus" else "", Modifier.testTag("session-student"), style = FcTypography.headline, color = FcColors.textSecondary)
            Spacer(Modifier.weight(1f))
            content?.let {
                var seconds by remember(it.session.startedAtUTC) { mutableLongStateOf(0) }
                LaunchedEffect(it.session.startedAtUTC) {
                    while (true) { seconds = Duration.between(it.session.startedAtUTC, clock.now()).seconds.coerceAtLeast(0); delay(1000) }
                }
                val elapsed = if (seconds >= 3600) "%d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60)
                    else "%02d:%02d".format(seconds / 60, seconds % 60)
                Text(elapsed, Modifier.testTag("session-clock"), style = FcTypography.headline, color = FcColors.actionPrimary)
            }
        }
    }
}

@Composable
internal fun SessionExerciseHeader(row: SessionExerciseRecord, previous: TrainingSetRecord?, previousCount: Int, selected: Boolean, enabled: Boolean, onSelect: () -> Unit) {
    Row(Modifier.fillMaxWidth().layout { measurable, constraints ->
        val natural = measurable.minIntrinsicHeight(constraints.maxWidth)
        val measured = measurable.measure(constraints.copy(minHeight = FcComponentMetrics.touch.roundToPx()))
        // Keep the full hit region; its trailing padding does not push the visible set rows down.
        layout(measured.width, maxOf(natural, measured.height - (FcSpacing.space2 + FcComponentMetrics.hairline).roundToPx())) { measured.placeRelative(0, 0) }
    }
        .testTag("session-exercise-${row.sessionExerciseID.value}").semantics { this.selected = selected }
        .clickable(enabled = enabled, onClick = onSelect), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
        FcEquipmentIconForExercise(row.sourceID.takeUnless { row.sourceKind == ExerciseSourceKind.sessionOnly }, Modifier.testTag("session-icon-${row.sessionExerciseID.value}"))
        Text(row.displayNameSnapshot, style = FcTypography.exerciseTitle, color = FcColors.textPrimary)
        Spacer(Modifier.weight(1f))
        Text(previous?.let { "上次 ${it.toDomain().displaySummary()} · $previousCount 组" } ?: when (row.recordModeSnapshot) {
            com.ignacioli.finecoach.core.domain.common.RecordMode.weightReps -> "重量与次数"
            com.ignacioli.finecoach.core.domain.common.RecordMode.reps -> "次数"
            com.ignacioli.finecoach.core.domain.common.RecordMode.duration -> "时长"
            com.ignacioli.finecoach.core.domain.common.RecordMode.cardio -> "有氧"
        }, Modifier.offset(y = -FcComponentMetrics.hairline).testTag(if (previous != null) "session-previous-${row.sessionExerciseID.value}" else "session-mode-${row.sessionExerciseID.value}"),
            style = FcTypography.caption, color = FcColors.textSecondary)
    }
}
