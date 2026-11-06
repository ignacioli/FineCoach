package com.ignacioli.finecoach.core.domain.credit

import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.CreditAdjustmentID
import com.ignacioli.finecoach.core.domain.common.CreditDirection
import com.ignacioli.finecoach.core.domain.common.CreditReasonKind
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.SourceEventKey
import java.time.Instant

/**
 * A single append-only ledger entry against a [CoursePackage] (FR-015).
 *
 * Mirrors iOS `CreditAdjustment` (`ios/FineCoachApp/Core/Domain/CreditLedger.swift:37-86`).
 * There is no mutation API: a reversal appends an opposite-direction entry with
 * its own source event key. Source event keys are produced by the frozen
 * `CreditLedgerSourceEventKeyFactory`; persistence owns the actual
 * dedup-by-key transaction.
 *
 * `linkedAppointmentID` stays a raw UUID string because Appointment IDs are not
 * part of the S1 frozen identifier set.
 */
data class CreditAdjustment(
    val creditAdjustmentID: CreditAdjustmentID,
    val coursePackageID: CoursePackageID,
    val direction: CreditDirection,
    val amount: Long,
    val reasonKind: CreditReasonKind,
    val reasonText: String? = null,
    val linkedSessionID: SessionID? = null,
    val linkedAppointmentID: String? = null,
    val sourceEventKey: SourceEventKey,
    val createdAtUTC: Instant,
) {
    init {
        require(amount > 0) { "amount must be positive" }
        require(reasonKind != CreditReasonKind.manualCorrection || !reasonText.isNullOrBlank()) {
            "manualCorrection requires a non-blank reasonText"
        }
    }
}
