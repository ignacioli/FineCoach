package com.ignacioli.finecoach.core.domain.credit

import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.CoursePackageStatus
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.ValidatedText
import java.time.Instant
import java.time.LocalDate

/**
 * Pure course-package value (FR-009/FR-012/FR-013).
 *
 * Mirrors iOS `CoursePackage` (`ios/FineCoachApp/Core/Domain/CoursePackage.swift:19-130`).
 * There is deliberately no `expired`/`depleted` status: expiry and low balance are
 * derived facts. `remainingCreditsCache` is a non-authoritative cache; the
 * authoritative balance is [CreditLedger.balance].
 *
 * Per S1-D02 the end date is not required to be on or after the start date.
 * No date-order validation is performed here.
 */
data class CoursePackage(
    val coursePackageID: CoursePackageID,
    val studentID: StudentID,
    val name: ValidatedText? = null,
    val totalCredits: Long,
    val remainingCreditsCache: Long = totalCredits,
    val startDate: LocalDate? = null,
    val endDate: LocalDate? = null,
    val status: CoursePackageStatus = CoursePackageStatus.active,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
) {
    init {
        require(totalCredits > 0) { "totalCredits must be positive" }
    }

    /**
     * Understandable display name even when the coach left `name` empty
     * (`CoursePackage.swift:62-72`).
     */
    val displayName: String
        get() = name?.takeIf { !it.isEmpty }?.value
            ?: startDate?.let { "课包 · $it" }
            ?: "课包"

    /**
     * Ends this package while retaining its history (`CoursePackage.swift:74-93`).
     * Only an active package can be ended; ending twice is rejected.
     */
    fun ending(now: Instant): CoursePackage {
        check(status == CoursePackageStatus.active) { "only an active course package can be ended" }
        return copy(status = CoursePackageStatus.ended, updatedAtUTC = now)
    }

    /**
     * Refreshes the non-authoritative balance cache (`CoursePackage.swift:95-111`).
     * Callers must pass a value derived by [CreditLedger.balance], never an
     * arbitrary number.
     */
    fun cachingRemaining(ledgerBalance: Long, now: Instant): CoursePackage =
        copy(remainingCreditsCache = ledgerBalance, updatedAtUTC = now)

    /**
     * Derived presentation fact (`CoursePackage.swift:113-122`). A package is
     * expired only when today is strictly after `endDate`; expiry never changes
     * [status] and never blocks training.
     */
    fun isExpired(asOf: LocalDate): Boolean {
        val end = endDate ?: return false
        return asOf.isAfter(end)
    }

    /**
     * Derived presentation fact (`CoursePackage.swift:124-129`). Informational
     * only; it never mutates status or produces a negative balance on its own.
     */
    fun isBalanceLow(ledgerBalance: Long): Boolean = ledgerBalance <= 0
}
