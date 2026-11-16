package com.ignacioli.finecoach.features.packages

import com.ignacioli.finecoach.designsystem.FcText
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.ignacioli.finecoach.core.application.CoursePackageRecord
import com.ignacioli.finecoach.core.application.CreditAdjustmentRecord
import com.ignacioli.finecoach.core.domain.common.CoursePackageStatus
import com.ignacioli.finecoach.core.domain.common.CreditDirection
import com.ignacioli.finecoach.designsystem.FcColors
import com.ignacioli.finecoach.designsystem.FcComponentMetrics
import com.ignacioli.finecoach.designsystem.FcListRowDivider
import com.ignacioli.finecoach.designsystem.FcLabelValueText
import com.ignacioli.finecoach.designsystem.FcSectionLabel
import com.ignacioli.finecoach.designsystem.FcSpacing
import com.ignacioli.finecoach.designsystem.FcSymbol
import com.ignacioli.finecoach.designsystem.FcTypography
import java.time.ZoneId

@Composable
internal fun PackageDetailBody(
    studentName: String?,
    packageRecord: CoursePackageRecord,
    balance: Long,
    adjustments: List<CreditAdjustmentRecord>,
    zoneID: ZoneId,
    plus: Painter,
    minus: Painter,
    tagPrefix: String,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
        if (!studentName.isNullOrEmpty()) {
            FcText(studentName, style = FcTypography.headline, color = FcColors.textSecondary)
        }
        FcText(
            balance.toString(),
            modifier = Modifier
                .testTag("$tagPrefix-balance")
                .semantics { contentDescription = "剩余 $balance 课时" },
            style = FcTypography.numeralHero,
            color = FcColors.textPrimary,
        )
        Column(Modifier.fillMaxWidth()) {
            FcLabelValueText("剩余课时", "共 ${packageRecord.totalCredits} 课时")
            FcLabelValueText("有效期", packageValidity(packageRecord.endDate))
            if (packageRecord.status == CoursePackageStatus.ended) {
                FcLabelValueText("状态", "已结束")
            }
            FcListRowDivider()
        }
        FcSectionLabel("课时调整")
        if (adjustments.isEmpty()) {
            FcText(
                ledgerEmpty,
                modifier = Modifier.testTag("$tagPrefix-empty"),
                style = FcTypography.style("callout", 400),
                color = FcColors.textSecondary,
            )
        } else {
            Column(Modifier.fillMaxWidth()) {
                adjustments.forEach { adjustment ->
                    AdjustmentRow(adjustment, zoneID, plus, minus, "$tagPrefix-adjustment-${adjustment.creditAdjustmentID.value}")
                    FcListRowDivider()
                }
            }
        }
    }
}

@Composable
private fun AdjustmentRow(
    adjustment: CreditAdjustmentRecord,
    zoneID: ZoneId,
    plus: Painter,
    minus: Painter,
    tag: String,
) {
    val debit = adjustment.direction == CreditDirection.debit
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = FcComponentMetrics.row)
            .testTag(tag)
            .padding(vertical = FcSpacing.space3),
        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space3),
        verticalAlignment = Alignment.Top,
    ) {
        FcSymbol(if (debit) minus else plus)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(FcSpacing.space1)) {
            FcText(adjustmentTitle(adjustment), style = FcTypography.body, color = FcColors.textPrimary)
            FcText(adjustmentReason(adjustment), style = FcTypography.caption, color = FcColors.textSecondary)
        }
        FcText(adjustmentDay(adjustment.createdAtUTC, zoneID), style = FcTypography.caption, color = FcColors.textSecondary)
    }
}
