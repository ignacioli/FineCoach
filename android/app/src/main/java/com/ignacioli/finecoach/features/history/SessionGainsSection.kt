package com.ignacioli.finecoach.features.history

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.progress.SessionGains
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.designsystem.*
import java.time.ZoneId

internal suspend fun loadSessionGains(detail: HistoryDetail, progress: ProgressUseCases?, zone: ZoneId): ApplicationResult<SessionGains> {
    if (progress == null) return ApplicationResult.Success(SessionGains())
    return when (val result = progress.load(detail.content.session.studentID)) {
        is ApplicationResult.Failure -> result
        is ApplicationResult.Success -> ApplicationResult.Success(progress.gains(detail.content.toDomain().session, result.value, zone))
    }
}

/** D-b: the same feature-owned composition for summary and coach history. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SessionGainsSection(gains: SessionGains, tag: String) {
    if (gains.isEmpty) return
    Column(Modifier.fillMaxWidth().testTag(tag), verticalArrangement = Arrangement.spacedBy(FcSpacing.space3)) {
        FcSectionLabel("本节收获")
        Column(Modifier.fillMaxWidth()) {
            gains.rows.forEachIndexed { index, row ->
                if (index > 0) FcListRowDivider()
                // DS-LIST-ROW's approved action slot; the shared Android row has no title slot.
                Column(Modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.row)
                    .semantics(mergeDescendants = true) { if (row.isNewRecord) stateDescription = "新纪录" }
                    .padding(vertical = FcSpacing.space2).testTag("$tag-action-$index"),
                    verticalArrangement = Arrangement.spacedBy(FcSpacing.space1)) {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2),
                        itemVerticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        FcText(row.displayName, style = FcTypography.headline, color = FcColors.textPrimary)
                        if (row.isNewRecord) FcSetRowRecordBadge()
                    }
                    FcText("上次 ${row.previous.displaySummary()} → 本次 ${row.current.displaySummary()}",
                        style = FcTypography.caption, color = FcColors.textSecondary)
                }
            }
            gains.milestoneSessionNumber?.let {
                if (gains.rows.isNotEmpty()) FcListRowDivider()
                FcListRow("第 $it 节课", Modifier.testTag("$tag-milestone"), subtitle = "累计完成的课程")
            }
            gains.attendanceStreakWeeks?.let {
                if (gains.rows.isNotEmpty() || gains.milestoneSessionNumber != null) FcListRowDivider()
                FcListRow("连续 $it 周", Modifier.testTag("$tag-streak"), subtitle = "每周练 2 次及以上")
            }
        }
    }
}
