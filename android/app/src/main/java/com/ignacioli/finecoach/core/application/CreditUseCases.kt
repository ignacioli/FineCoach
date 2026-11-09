package com.ignacioli.finecoach.core.application

import com.ignacioli.finecoach.core.domain.common.AppointmentID
import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.CreditAdjustmentID
import com.ignacioli.finecoach.core.domain.common.CreditDirection
import com.ignacioli.finecoach.core.domain.common.CreditLedgerSourceEventKeyFactory
import com.ignacioli.finecoach.core.domain.common.CreditReasonKind
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.SourceEventKey
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.ValidatedText
import com.ignacioli.finecoach.core.domain.credit.CoursePackage
import com.ignacioli.finecoach.core.domain.credit.CreditAdjustment
import com.ignacioli.finecoach.core.domain.credit.CreditLedger
import java.time.LocalDate
import java.time.ZoneId

/**
 * Snapshot loaded when preparing to create a new course package for a Student (FR-010/FR-011, S1-D01).
 *
 * - [existingActivePackage] is the Student's currently active package, or `null` if none exists.
 * - [existingActivePackageBalance] is the authoritative ledger balance for that active package (0 when none exists).
 * - [requiresConfirmation] is `true` iff an active package exists, is not expired as of [asOf], and has a non-zero
 *   ledger balance (`!isExpired(asOf) && balance != 0`).
 * - [observedActivePackageID] is the token to pass back when saving or confirming replacement.
 */
data class CoursePackageCreationContext(
    val studentID: StudentID,
    val asOf: LocalDate,
    val existingActivePackage: CoursePackageRecord?,
    val existingActivePackageBalance: Long,
    val requiresConfirmation: Boolean,
) {
    val observedActivePackageID: CoursePackageID?
        get() = existingActivePackage?.coursePackageID
}

/**
 * Orchestrates [CoursePackage] lifecycle, confirmation-gated replacement (S1-D01),
 * and [CreditAdjustment] ledger operations (FR-009..FR-015, S1-D02).
 *
 * Mirrors iOS `CreditLedgerUseCases` (`ios/FineCoachApp/Core/Application/CreditLedgerUseCases.swift:10-255`)
 * and the confirmation rules in `CoursePackageEditorViewModel`
 * (`ios/FineCoachApp/Features/CoursePackages/CoursePackageEditorView.swift:45-119`), with S1-D01's
 * conservative Android guards:
 * 1. A failure loading the current active package is never treated as "no active package"; saving is blocked and
 *    returns a retryable error (`ApplicationErrorCode.persistenceFailed`).
 * 2. Confirmation carries `observedActivePackageID` and is re-verified inside the repository save transaction;
 *    if the active package changed, `SaveCoursePackageResult.RequiresReconfirmation` is returned with zero writes.
 * 3. Local calendar date (`ZoneId`, defaulting to [ZoneId.systemDefault]) is used for expiry checks so UTC midnight
 *    never prematurely marks a locally unexpired package as expired.
 */
class CreditUseCases(
    private val repository: CoursePackageRepositoryPort,
    private val clock: AppClock,
    private val ids: StableIDGenerator,
    private val zoneID: ZoneId = ZoneId.systemDefault(),
    private val keyBuilder: CreditLedgerSourceEventKeyBuilder = DefaultCreditSourceEventKeyBuilder,
) {
    /**
     * Loads the Student's current active package and its authoritative ledger balance prior to package creation
     * (FR-010/FR-011, S1-D01).
     *
     * Unlike iOS `try? useCases.activePackage(...)`, any query failure is surfaced as [ApplicationResult.Failure]
     * so callers disable saving and prompt for retry instead of treating failure as "no active package".
     */
    suspend fun loadCreationContext(
        studentID: StudentID,
        asOf: LocalDate = clock.today(zoneID),
    ): ApplicationResult<CoursePackageCreationContext> {
        val activeRecord = when (val activeResult = repository.active(studentID, asOf)) {
            is ApplicationResult.Failure -> return activeResult
            is ApplicationResult.Success -> activeResult.value
        }
        if (activeRecord == null) {
            return ApplicationResult.Success(
                CoursePackageCreationContext(
                    studentID = studentID,
                    asOf = asOf,
                    existingActivePackage = null,
                    existingActivePackageBalance = 0L,
                    requiresConfirmation = false,
                ),
            )
        }
        val ledgerEntries = when (val ledgerResult = repository.ledger(studentID)) {
            is ApplicationResult.Failure -> return ledgerResult
            is ApplicationResult.Success -> ledgerResult.value
        }
        val packageAdjustments = ledgerEntries
            .filter { it.coursePackageID == activeRecord.coursePackageID }
            .map { record ->
                when (val domainResult = record.toDomainResult()) {
                    is ApplicationResult.Failure -> return domainResult
                    is ApplicationResult.Success -> domainResult.value
                }
            }
        val balance = try {
            CreditLedger.balance(activeRecord.totalCredits, packageAdjustments)
        } catch (_: ArithmeticException) {
            return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidNumber))
        }
        val domainPackage = when (val domainResult = activeRecord.toDomainResult(balance)) {
            is ApplicationResult.Failure -> return domainResult
            is ApplicationResult.Success -> domainResult.value
        }
        val needsConfirm = !domainPackage.isExpired(asOf) && balance != 0L
        return ApplicationResult.Success(
            CoursePackageCreationContext(
                studentID = studentID,
                asOf = asOf,
                existingActivePackage = activeRecord.copy(remainingCreditsCache = balance),
                existingActivePackageBalance = balance,
                requiresConfirmation = needsConfirm,
            ),
        )
    }

    /**
     * Saves a new active course package using a previously loaded [CoursePackageCreationContext] result.
     *
     * Per S1-D01, if [contextResult] failed, saving is rejected immediately without touching persistence.
     * Since [loadCreationContext] already pre-read the active package, this path delegates straight to
     * `repository.save` after input validation without a duplicate pre-read.
     */
    suspend fun createPackageWithContext(
        contextResult: ApplicationResult<CoursePackageCreationContext>,
        name: String?,
        totalCredits: Long,
        startDate: LocalDate? = null,
        endDate: LocalDate? = null,
        confirmedByCoach: Boolean = false,
        coursePackageID: CoursePackageID? = null,
    ): ApplicationResult<SaveCoursePackageResult> {
        val context = when (contextResult) {
            is ApplicationResult.Failure -> return contextResult
            is ApplicationResult.Success -> contextResult.value
        }
        if (context.requiresConfirmation && !confirmedByCoach) {
            return ApplicationResult.Success(
                SaveCoursePackageResult.RequiresReconfirmation(context.existingActivePackage),
            )
        }
        validateDraftInputs(name = name, totalCredits = totalCredits)?.let { return it }
        return repository.save(
            SaveCoursePackageCommand(
                coursePackageID = coursePackageID ?: ids.newCoursePackageID(),
                studentID = context.studentID,
                name = name,
                totalCredits = totalCredits,
                startDate = startDate,
                endDate = endDate,
                observedActivePackageID = context.observedActivePackageID,
                confirmReplaceActivePackage = confirmedByCoach,
            ),
        )
    }

    /**
     * Queries the current active package first and then saves a new active package (FR-009..FR-011, S1-D01, S1-D02).
     *
     * - If querying the current active package fails, saving is aborted and returns the query error.
     * - If an active package exists and does not match [observedActivePackageID], or is in effect and not confirmed,
     *   returns [SaveCoursePackageResult.RequiresReconfirmation] with zero writes.
     * - If the observed active package is expired or has balance == 0, saves immediately and ends the old package in one transaction.
     */
    suspend fun createActivePackage(
        studentID: StudentID,
        name: String?,
        totalCredits: Long,
        startDate: LocalDate? = null,
        endDate: LocalDate? = null,
        observedActivePackageID: CoursePackageID? = null,
        confirmReplaceActivePackage: Boolean = false,
        coursePackageID: CoursePackageID? = null,
    ): ApplicationResult<SaveCoursePackageResult> =
        savePackage(
            SaveCoursePackageCommand(
                coursePackageID = coursePackageID,
                studentID = studentID,
                name = name,
                totalCredits = totalCredits,
                startDate = startDate,
                endDate = endDate,
                observedActivePackageID = observedActivePackageID,
                confirmReplaceActivePackage = confirmReplaceActivePackage,
            ),
        )

    /**
     * Executes [SaveCoursePackageCommand] after pre-validating inputs and performing a single active-package pre-read (S1-D01).
     */
    suspend fun savePackage(
        command: SaveCoursePackageCommand,
    ): ApplicationResult<SaveCoursePackageResult> {
        validateDraftInputs(name = command.name, totalCredits = command.totalCredits)?.let { return it }
        val activeLookup = repository.active(command.studentID, clock.today(zoneID))
        if (activeLookup is ApplicationResult.Failure) {
            return activeLookup
        }
        val resolvedCommand = if (command.coursePackageID != null) {
            command
        } else {
            command.copy(coursePackageID = ids.newCoursePackageID())
        }
        return repository.save(resolvedCommand)
    }

    private fun validateDraftInputs(
        name: String?,
        totalCredits: Long,
    ): ApplicationResult.Failure? {
        if (totalCredits <= 0L) {
            return ApplicationResult.Failure(
                ApplicationError(ApplicationErrorCode.invalidNumber, field = "totalCredits"),
            )
        }
        try {
            ValidatedText.optional(name)
        } catch (_: IllegalArgumentException) {
            return ApplicationResult.Failure(
                ApplicationError(ApplicationErrorCode.textTooLong, field = "name"),
            )
        }
        return null
    }

    /**
     * Explicit cancel handler for package replacement confirmation: performs zero mutations.
     */
    fun cancelPackageReplacement() {
        // Deliberate no-op: cancelling confirmation must never mutate packages or claims (FR-010).
    }

    /**
     * Ends an active course package while retaining its record and ledger history (FR-013).
     */
    suspend fun endPackage(
        coursePackageID: CoursePackageID,
        endedAt: LocalDate = clock.today(zoneID),
    ): ApplicationResult<CoursePackageRecord> =
        repository.end(EndCoursePackageCommand(coursePackageID = coursePackageID, endedAt = endedAt))

    /**
     * Lists all packages (active and ended) for a Student, newest first (FR-009).
     */
    suspend fun packages(
        studentID: StudentID,
        asOf: LocalDate = clock.today(zoneID),
    ): ApplicationResult<List<CoursePackageRecord>> = repository.list(studentID, asOf)

    /**
     * Returns the Student's currently active package, or `null` if none exists (FR-009/FR-010).
     */
    suspend fun activePackage(
        studentID: StudentID,
        asOf: LocalDate = clock.today(zoneID),
    ): ApplicationResult<CoursePackageRecord?> = repository.active(studentID, asOf)

    /**
     * Finds a specific package by ID for a Student (FR-009).
     */
    suspend fun packageById(
        studentID: StudentID,
        coursePackageID: CoursePackageID,
        asOf: LocalDate = clock.today(zoneID),
    ): ApplicationResult<CoursePackageRecord> {
        val list = when (val res = repository.list(studentID, asOf)) {
            is ApplicationResult.Failure -> return res
            is ApplicationResult.Success -> res.value
        }
        val match = list.firstOrNull { it.coursePackageID == coursePackageID }
            ?: return ApplicationResult.Failure(
                ApplicationError(ApplicationErrorCode.notFound, field = "coursePackageID"),
            )
        return ApplicationResult.Success(match)
    }

    /**
     * Computes the authoritative ledger balance (`totalCredits + credits - debits`) for a package (FR-012).
     */
    suspend fun balance(
        studentID: StudentID,
        coursePackageID: CoursePackageID,
        asOf: LocalDate = clock.today(zoneID),
    ): ApplicationResult<Long> {
        val pkg = when (val pkgRes = packageById(studentID, coursePackageID, asOf)) {
            is ApplicationResult.Failure -> return pkgRes
            is ApplicationResult.Success -> pkgRes.value
        }
        val adjustments = when (val adjRes = adjustmentsForPackage(studentID, coursePackageID)) {
            is ApplicationResult.Failure -> return adjRes
            is ApplicationResult.Success -> adjRes.value
        }
        val domainAdjustments = adjustments.map { record ->
            when (val domainRes = record.toDomainResult()) {
                is ApplicationResult.Failure -> return domainRes
                is ApplicationResult.Success -> domainRes.value
            }
        }
        return try {
            ApplicationResult.Success(CreditLedger.balance(pkg.totalCredits, domainAdjustments))
        } catch (_: ArithmeticException) {
            ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidNumber))
        }
    }

    /**
     * Returns the full ledger trail for a Student across all packages (FR-014).
     */
    suspend fun ledger(studentID: StudentID): ApplicationResult<List<CreditAdjustmentRecord>> =
        repository.ledger(studentID)

    /**
     * Returns the traceable ledger trail for a specific package (FR-014).
     */
    suspend fun adjustmentsForPackage(
        studentID: StudentID,
        coursePackageID: CoursePackageID,
    ): ApplicationResult<List<CreditAdjustmentRecord>> {
        val all = when (val res = repository.ledger(studentID)) {
            is ApplicationResult.Failure -> return res
            is ApplicationResult.Success -> res.value
        }
        return ApplicationResult.Success(all.filter { it.coursePackageID == coursePackageID })
    }

    /**
     * Records a coach-entered manual credit or debit adjustment (FR-014).
     *
     * Requires `amount > 0` and a non-blank `reasonText` (<= 64 KiB UTF-8).
     * Debit adjustments that would push the balance negative are rejected with `ApplicationErrorCode.invalidState`.
     */
    suspend fun recordManualCorrection(
        coursePackageID: CoursePackageID,
        direction: CreditDirection,
        amount: Long,
        reasonText: String?,
        creditAdjustmentID: CreditAdjustmentID? = null,
    ): ApplicationResult<CreditAdjustmentRecord> {
        if (amount <= 0L) {
            return ApplicationResult.Failure(
                ApplicationError(ApplicationErrorCode.invalidNumber, field = "amount"),
            )
        }
        val validatedReason = try {
            ValidatedText.optional(reasonText)
        } catch (_: IllegalArgumentException) {
            return ApplicationResult.Failure(
                ApplicationError(ApplicationErrorCode.textTooLong, field = "reasonText"),
            )
        }
        if (validatedReason == null || validatedReason.isEmpty) {
            return ApplicationResult.Failure(
                ApplicationError(ApplicationErrorCode.emptyText, field = "reasonText"),
            )
        }
        val adjustmentID = creditAdjustmentID ?: ids.newCreditAdjustmentID()
        val key = keyBuilder.manualCorrection(adjustmentID)
        return repository.appendAdjustment(
            CreditAdjustmentCommand(
                creditAdjustmentID = adjustmentID,
                coursePackageID = coursePackageID,
                direction = direction,
                amount = amount,
                reasonKind = CreditReasonKind.manualCorrection,
                reasonText = validatedReason.value,
                linkedSessionID = null,
                linkedAppointmentID = null,
                sourceEventKey = key,
            ),
        )
    }

    /**
     * Normal session completion debit: debits 1 credit at most once per [sessionID] (FR-015).
     */
    suspend fun debitOnSessionComplete(
        coursePackageID: CoursePackageID,
        sessionID: SessionID,
        creditAdjustmentID: CreditAdjustmentID? = null,
    ): ApplicationResult<CreditAdjustmentRecord> =
        recordAutomaticDebit(
            coursePackageID = coursePackageID,
            amount = 1L,
            reasonKind = CreditReasonKind.sessionComplete,
            linkedSessionID = sessionID,
            linkedAppointmentID = null,
            sourceEventKey = keyBuilder.sessionComplete(sessionID),
            creditAdjustmentID = creditAdjustmentID,
        )

    /**
     * Ad-hoc session completion debit where the coach chose to debit 1 credit: at most once per [sessionID] (FR-015/FR-036).
     */
    suspend fun debitOnAdhocSession(
        coursePackageID: CoursePackageID,
        sessionID: SessionID,
        creditAdjustmentID: CreditAdjustmentID? = null,
    ): ApplicationResult<CreditAdjustmentRecord> =
        recordAutomaticDebit(
            coursePackageID = coursePackageID,
            amount = 1L,
            reasonKind = CreditReasonKind.adhocSession,
            linkedSessionID = sessionID,
            linkedAppointmentID = null,
            sourceEventKey = keyBuilder.adhocSession(sessionID),
            creditAdjustmentID = creditAdjustmentID,
        )

    /**
     * Appointment absence debit: debits 1 credit at most once per [appointmentID] when charged (FR-015).
     */
    suspend fun debitOnAppointmentAbsent(
        coursePackageID: CoursePackageID,
        appointmentID: String,
        creditAdjustmentID: CreditAdjustmentID? = null,
    ): ApplicationResult<CreditAdjustmentRecord> {
        val parsedAppointmentID = try {
            AppointmentID.parse(appointmentID)
        } catch (_: IllegalArgumentException) {
            return ApplicationResult.Failure(
                ApplicationError(ApplicationErrorCode.invalidIdentifier, field = "linkedAppointmentID"),
            )
        }
        val key = try {
            keyBuilder.appointmentAbsent(parsedAppointmentID.value)
        } catch (_: IllegalArgumentException) {
            return ApplicationResult.Failure(
                ApplicationError(ApplicationErrorCode.invalidIdentifier, field = "linkedAppointmentID"),
            )
        }
        return recordAutomaticDebit(
            coursePackageID = coursePackageID,
            amount = 1L,
            reasonKind = CreditReasonKind.appointmentAbsent,
            linkedSessionID = null,
            linkedAppointmentID = parsedAppointmentID.value,
            sourceEventKey = key,
            creditAdjustmentID = creditAdjustmentID,
        )
    }

    /**
     * Reopening a previously completed session refunds 1 credit at most once per [sessionID] (FR-015, S1-D04).
     *
     * If the session was never debited via `sessionComplete`, returns `ApplicationResult.Success(null)`.
     */
    suspend fun refundOnSessionReopen(
        sessionID: SessionID,
    ): ApplicationResult<CreditAdjustmentRecord?> =
        repository.refundOnSessionReopen(
            RefundOnSessionReopenCommand(
                sessionID = sessionID,
                requestedAtUTC = clock.now(),
            ),
        )

    /**
     * Appends an arbitrary [CreditAdjustmentCommand] through the repository transaction.
     */
    suspend fun appendAdjustment(
        command: CreditAdjustmentCommand,
    ): ApplicationResult<CreditAdjustmentRecord> = repository.appendAdjustment(command)

    private suspend fun recordAutomaticDebit(
        coursePackageID: CoursePackageID,
        amount: Long,
        reasonKind: CreditReasonKind,
        linkedSessionID: SessionID?,
        linkedAppointmentID: String?,
        sourceEventKey: SourceEventKey,
        creditAdjustmentID: CreditAdjustmentID?,
    ): ApplicationResult<CreditAdjustmentRecord> {
        val adjustmentID = creditAdjustmentID ?: ids.newCreditAdjustmentID()
        return repository.appendAdjustment(
            CreditAdjustmentCommand(
                creditAdjustmentID = adjustmentID,
                coursePackageID = coursePackageID,
                direction = CreditDirection.debit,
                amount = amount,
                reasonKind = reasonKind,
                reasonText = null,
                linkedSessionID = linkedSessionID,
                linkedAppointmentID = linkedAppointmentID,
                sourceEventKey = sourceEventKey,
            ),
        )
    }

    private object DefaultCreditSourceEventKeyBuilder : CreditLedgerSourceEventKeyBuilder {
        override fun sessionComplete(sessionID: SessionID): SourceEventKey =
            CreditLedgerSourceEventKeyFactory.sessionComplete(sessionID)

        override fun sessionReopen(sessionID: SessionID): SourceEventKey =
            CreditLedgerSourceEventKeyFactory.sessionReopen(sessionID)

        override fun appointmentAbsent(appointmentID: String): SourceEventKey =
            CreditLedgerSourceEventKeyFactory.appointmentAbsent(appointmentID)

        override fun adhocSession(sessionID: SessionID): SourceEventKey =
            CreditLedgerSourceEventKeyFactory.adhocSession(sessionID)

        override fun manualCorrection(adjustmentID: CreditAdjustmentID): SourceEventKey =
            CreditLedgerSourceEventKeyFactory.manualCorrection(adjustmentID)
    }
}

private fun CoursePackageRecord.toDomainResult(balanceCache: Long = remainingCreditsCache): ApplicationResult<CoursePackage> =
    try {
        val validatedName = ValidatedText.optional(name)
        ApplicationResult.Success(
            CoursePackage(
                coursePackageID = coursePackageID,
                studentID = studentID,
                name = validatedName,
                totalCredits = totalCredits,
                remainingCreditsCache = balanceCache,
                startDate = startDate,
                endDate = endDate,
                status = status,
                createdAtUTC = createdAtUTC,
                updatedAtUTC = updatedAtUTC,
            ),
        )
    } catch (_: IllegalArgumentException) {
        ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.incompatibleInput))
    }

private fun CreditAdjustmentRecord.toDomainResult(): ApplicationResult<CreditAdjustment> =
    try {
        val validatedReason = ValidatedText.optional(reasonText)
        val appointmentID = linkedAppointmentID?.let { AppointmentID.parse(it) }
        ApplicationResult.Success(
            CreditAdjustment(
                creditAdjustmentID = creditAdjustmentID,
                coursePackageID = coursePackageID,
                direction = direction,
                amount = amount,
                reasonKind = reasonKind,
                reasonText = validatedReason,
                linkedSessionID = linkedSessionID,
                linkedAppointmentID = appointmentID,
                sourceEventKey = sourceEventKey,
                createdAtUTC = createdAtUTC,
            ),
        )
    } catch (_: IllegalArgumentException) {
        ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.incompatibleInput))
    }
