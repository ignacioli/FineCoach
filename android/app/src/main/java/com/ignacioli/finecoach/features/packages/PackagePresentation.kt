package com.ignacioli.finecoach.features.packages

import com.ignacioli.finecoach.core.application.ApplicationError
import com.ignacioli.finecoach.core.application.ApplicationErrorCode
import com.ignacioli.finecoach.core.application.CreditAdjustmentRecord
import com.ignacioli.finecoach.core.domain.common.CreditDirection
import com.ignacioli.finecoach.core.domain.common.CreditReasonKind
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * Presentation copied from the shipped iOS course-package screens.
 * Date picker millis are UTC calendar days (AD-02): a UTC midnight must not
 * be read as the device-zone local date.
 */
internal fun localDateToUtcMillis(date: LocalDate): Long =
    date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()

internal fun utcMillisToLocalDate(millis: Long): LocalDate =
    Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()

internal fun packageDisplayName(name: String?, startDate: LocalDate?): String {
    val trimmed = name?.trim().orEmpty()
    if (trimmed.isNotEmpty()) return trimmed
    if (startDate != null) return "课包 · $startDate"
    return "课包"
}

internal fun packageDateText(date: LocalDate): String =
    "${date.year}年${date.monthValue}月${date.dayOfMonth}日"

internal fun packageValidity(endDate: LocalDate?): String =
    if (endDate == null) "长期有效" else packageDateText(endDate)

internal fun packageBalanceNote(balance: Long, total: Long): String = "剩余 $balance / 共 $total 课时"

internal fun replacementWarning(name: String, balance: Long): String =
    "该学员已有有效课包「$name」，剩余 $balance 课时。新建将结束当前课包。"

internal fun replacementConfirmMessage(name: String, balance: Long): String =
    "该学员已有有效课包「$name」，剩余 $balance 课时。新建将结束当前课包，历史记录会保留。确认继续？"

internal const val replacementChangedMessage =
    "刚才看到的课包已不再是当前有效课包。没有结束任何课包，也没有新建。请重新查看后再保存。"

internal const val packageLoadErrorTitle = "课包信息暂不可用，再试一次。"

internal const val packageLoadErrorDescription = "当前有效课包没有读取成功，保存已停用。"

internal const val packageSaveFailed = "保存失败，再试一次。"

internal const val packageCreditsInvalid = "总课时数需大于 0。"

internal const val manualNegativeBalance = "扣减后余额将为负，检查课时数。"

internal const val manualReasonRequired = "还没填写调整原因。"

internal const val ledgerEmpty = "完成训练、缺席扣课和人工调整都会记在这里"

internal const val noActivePackage = "新建课包后，上完课会按课时扣减"

internal const val endPackageMessage =
    "结束后这个课包不再扣课，调整记录保留，可在「课包管理」的历史课包里查看。"

internal fun editorSaveMessage(error: ApplicationError): String = when (error.code) {
    ApplicationErrorCode.invalidNumber -> packageCreditsInvalid
    else -> packageSaveFailed
}

internal fun manualSaveMessage(error: ApplicationError): String = when (error.code) {
    ApplicationErrorCode.invalidState -> manualNegativeBalance
    ApplicationErrorCode.emptyText -> manualReasonRequired
    else -> packageSaveFailed
}

internal fun adjustmentTitle(record: CreditAdjustmentRecord): String =
    if (record.direction == CreditDirection.debit) {
        "扣减 ${record.amount} 课时"
    } else {
        "返还 ${record.amount} 课时"
    }

internal fun adjustmentReason(record: CreditAdjustmentRecord): String {
    val title = when (record.reasonKind) {
        CreditReasonKind.sessionComplete -> "完成训练"
        CreditReasonKind.appointmentAbsent -> "学员缺席"
        CreditReasonKind.adhocSession -> "临时加课"
        CreditReasonKind.manualCorrection -> "人工调整"
        CreditReasonKind.sessionReopen -> "重新打开训练"
    }
    val extra = record.reasonText?.trim().orEmpty()
    return if (extra.isEmpty()) title else "$title · $extra"
}

internal fun adjustmentDay(instant: Instant, zoneID: ZoneId): String {
    val date = instant.atZone(zoneID).toLocalDate()
    return "${date.monthValue}月${date.dayOfMonth}日"
}

internal fun newestFirst(records: List<CreditAdjustmentRecord>): List<CreditAdjustmentRecord> =
    records.sortedWith(
        compareByDescending<CreditAdjustmentRecord> { it.createdAtUTC }
            .thenByDescending { it.creditAdjustmentID.value },
    )
