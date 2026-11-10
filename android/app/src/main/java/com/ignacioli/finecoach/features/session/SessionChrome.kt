package com.ignacioli.finecoach.features.session

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.designsystem.*
import kotlinx.coroutines.delay
import java.time.Duration

@Composable
internal fun SessionHeader(student: String, content: SessionContentRecord?, clock: AppClock, back: () -> Unit) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(FcComponentMetrics.touch).testTag("active-session-back")
                .semantics { contentDescription = "返回" }.clickable(onClick = back), contentAlignment = Alignment.CenterStart) { FcSymbol(FcGlyph.PageBack) }
            Text("训练中", Modifier.semantics { heading() }, style = FcTypography.style("titleEmphasis", 700), color = FcColors.textPrimary)
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            val focus = content?.session?.trainingFocus.orEmpty().sortedBy { it.ordinal }.joinToString("、") { FcBodyParts[it.ordinal] }
            Text(student + if (focus.isNotEmpty()) " · $focus" else "", Modifier.weight(1f).testTag("session-student"), style = FcTypography.headline, color = FcColors.textSecondary)
            content?.let {
                var seconds by remember(it.session.startedAtUTC) { mutableLongStateOf(0) }
                LaunchedEffect(it.session.startedAtUTC) {
                    while (true) { seconds = Duration.between(it.session.startedAtUTC, clock.now()).seconds.coerceAtLeast(0); delay(1000) }
                }
                val elapsed = if (seconds >= 3600) "%d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60)
                    else "%02d:%02d".format(seconds / 60, seconds % 60)
                Text(elapsed, Modifier.testTag("session-clock"), style = FcTypography.headline, color = FcColors.textPrimary)
            }
        }
        Text("已完成组数 ${content?.exercises?.sumOf { row -> row.sets.count { it.state == SetRecordingState.completed } } ?: 0}",
            Modifier.testTag("session-stats"), style = FcTypography.caption, color = FcColors.textSecondary)
    }
}

@Composable
internal fun SessionExerciseHeader(row: SessionExerciseRecord, previous: TrainingSetRecord?, previousCount: Int, selected: Boolean, enabled: Boolean, onSelect: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.touch)
        .testTag("session-exercise-${row.sessionExerciseID.value}").semantics { this.selected = selected }
        .clickable(enabled = enabled, onClick = onSelect), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
        // 待 DS-EQUIPMENT-ICON：共享组件任务完成后回填。
        Text(row.displayNameSnapshot, Modifier.weight(1f), style = FcTypography.exerciseTitle, color = FcColors.textPrimary)
        Text(previous?.let { "上次 ${it.toDomain().displaySummary()} · $previousCount 组" } ?: when (row.recordModeSnapshot) {
            com.ignacioli.finecoach.core.domain.common.RecordMode.weightReps -> "重量与次数"
            com.ignacioli.finecoach.core.domain.common.RecordMode.reps -> "次数"
            com.ignacioli.finecoach.core.domain.common.RecordMode.duration -> "时长"
            com.ignacioli.finecoach.core.domain.common.RecordMode.cardio -> "有氧"
        }, Modifier.testTag(if (previous != null) "session-previous-${row.sessionExerciseID.value}" else "session-mode-${row.sessionExerciseID.value}"),
            style = FcTypography.caption, color = FcColors.textSecondary)
        if (selected) FcSymbol(FcGlyph.Check)
    }
}
