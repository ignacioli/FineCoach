package com.ignacioli.finecoach.storage.repository

import android.database.sqlite.SQLiteConstraintException
import android.database.sqlite.SQLiteException
import com.ignacioli.finecoach.core.application.AppClock
import com.ignacioli.finecoach.core.application.ApplicationError
import com.ignacioli.finecoach.core.application.ApplicationErrorCode
import com.ignacioli.finecoach.core.application.ApplicationResult
import com.ignacioli.finecoach.core.application.CoursePackageRecord
import com.ignacioli.finecoach.core.application.CoursePackageRepositoryPort
import com.ignacioli.finecoach.core.application.CreditAdjustmentCommand
import com.ignacioli.finecoach.core.application.CreditAdjustmentRecord
import com.ignacioli.finecoach.core.application.CreditLedgerSourceEventKeyBuilder
import com.ignacioli.finecoach.core.application.EndCoursePackageCommand
import com.ignacioli.finecoach.core.application.RefundOnSessionReopenCommand
import com.ignacioli.finecoach.core.application.SaveCoursePackageCommand
import com.ignacioli.finecoach.core.application.SaveCoursePackageResult
import com.ignacioli.finecoach.core.application.StableIDGenerator
import com.ignacioli.finecoach.core.domain.common.AppointmentID
import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.CoursePackageStatus
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
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.entity.ActivePackageClaimEntity
import com.ignacioli.finecoach.storage.entity.CoursePackageEntity
import com.ignacioli.finecoach.storage.entity.CreditAdjustmentEntity
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.Callable
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Room-backed implementation of [CoursePackageRepositoryPort] (FR-009..FR-015, S1-D01, S1-D02).
 *
 * Enforces two core invariants inside single Room transactions:
 * 1. At most one active [CoursePackage] per Student via `active_package_claims`.
 * 2. At most one effective [CreditAdjustment] per [SourceEventKey] via `credit_adjustments.sourceEventKey` UNIQUE.
 *
 * Per FR-009:
 * - Course package creation never rewrites an existing active or ended package in place; colliding IDs are rejected.
 *
 * Per S1-D01:
 * - Lookup failures return `ApplicationErrorCode.persistenceFailed` and never masquerade as "no active package".
 * - Inside the `save` transaction, the current active package, its ledger-derived balance, and local-date expiry are re-evaluated.
 * - If an active package exists in the transaction and `observedActivePackageID != currentActivePackage.coursePackageID`
 *   (including when `observedActivePackageID == null`), `RequiresReconfirmation` is returned with zero writes, even if
 *   the current active package is expired or has zero balance.
 * - If an active package is still in effect (not expired and ledger balance != 0), saving also requires
 *   `confirmReplaceActivePackage == true`; otherwise `RequiresReconfirmation` is returned with zero writes.
 *
 * Per S1-D02:
 * - `endDate < startDate` is not rejected and persists verbatim, matching iOS (`CoursePackage.swift:35-60`).
 */
class CoursePackageRepository(
    private val database: FineCoachDatabase,
    private val clock: AppClock,
    private val ids: StableIDGenerator,
    private val zoneID: ZoneId = ZoneId.systemDefault(),
    private val keyBuilder: CreditLedgerSourceEventKeyBuilder = DefaultSourceEventKeyBuilder,
    private val ioContext: CoroutineContext = Dispatchers.IO,
    private val writeLock: Any = defaultLockFor(database),
) : CoursePackageRepositoryPort {
    private val s1Dao get() = database.s1Dao()
    private val packageDao get() = database.t007PackageDao()

    override suspend fun list(
        studentID: StudentID,
        asOf: LocalDate,
    ): ApplicationResult<List<CoursePackageRecord>> = runStorage {
        val studentUUID = UUID.fromString(studentID.value)
        val packages = database.runInTransaction(
            Callable {
                packageDao.listCoursePackages(studentUUID)
                    .map { entity ->
                        val domain = entity.toDomain()
                        val adjustments = loadAdjustmentsForPackage(entity.id)
                        val balance = CreditLedger.balance(domain.totalCredits, adjustments)
                        domain.copy(remainingCreditsCache = balance).toRecord()
                    }
                    .sortedWith(
                        compareByDescending<CoursePackageRecord> { it.createdAtUTC }
                            .thenBy { it.coursePackageID.value },
                    )
            },
        )
        ApplicationResult.Success(packages)
    }

    override suspend fun active(
        studentID: StudentID,
        asOf: LocalDate,
    ): ApplicationResult<CoursePackageRecord?> = runStorage {
        val current = database.runInTransaction(
            Callable {
                loadCurrentActivePackageInTransaction(UUID.fromString(studentID.value))
            },
        )
        ApplicationResult.Success(current?.first?.toRecord())
    }

    override suspend fun save(
        command: SaveCoursePackageCommand,
    ): ApplicationResult<SaveCoursePackageResult> = runStorage {
        if (command.totalCredits <= 0L) {
            return@runStorage ApplicationResult.Failure(
                ApplicationError(ApplicationErrorCode.invalidNumber, field = "totalCredits"),
            )
        }
        val validatedName = try {
            ValidatedText.optional(command.name)
        } catch (_: IllegalArgumentException) {
            return@runStorage ApplicationResult.Failure(
                ApplicationError(ApplicationErrorCode.textTooLong, field = "name"),
            )
        }

        val now = clock.now()
        val today = clock.today(zoneID)
        val targetPackageID = command.coursePackageID ?: ids.newCoursePackageID()
        val draft = CoursePackage(
            coursePackageID = targetPackageID,
            studentID = command.studentID,
            name = validatedName,
            totalCredits = command.totalCredits,
            remainingCreditsCache = command.totalCredits,
            startDate = command.startDate,
            endDate = command.endDate,
            status = CoursePackageStatus.active,
            createdAtUTC = now,
            updatedAtUTC = now,
        )

        synchronized(writeLock) {
            database.runInTransaction(
                Callable {
                    val studentUUID = UUID.fromString(command.studentID.value)
                    val targetUUID = UUID.fromString(targetPackageID.value)
                    val activePair = loadCurrentActivePackageInTransaction(studentUUID)

                    if (activePair != null) {
                        val (activeDomain, activeBalance) = activePair

                        // S1-D01: Any drift between observedActivePackageID (including null) and the actual
                        // active package in the transaction requires reconfirmation with zero writes.
                        if (command.observedActivePackageID != activeDomain.coursePackageID) {
                            return@Callable ApplicationResult.Success(
                                SaveCoursePackageResult.RequiresReconfirmation(activeDomain.toRecord()),
                            )
                        }

                        // S1-D01 / FR-010 / FR-011: Unexpired active package with non-zero balance requires confirmation.
                        val needsConfirmation = !activeDomain.isExpired(today) && activeBalance != 0L
                        if (needsConfirmation && !command.confirmReplaceActivePackage) {
                            return@Callable ApplicationResult.Success(
                                SaveCoursePackageResult.RequiresReconfirmation(activeDomain.toRecord()),
                            )
                        }

                        // FR-009: S1 only creates new packages and never rewrites an existing package ID in place.
                        if (s1Dao.findCoursePackage(targetUUID) != null) {
                            throw DomainAbortException(
                                ApplicationError(ApplicationErrorCode.conflict, field = "coursePackageID"),
                            )
                        }

                        val endedOld = activeDomain.ending(now).cachingRemaining(activeBalance, now)
                        packageDao.updateCoursePackage(endedOld.toEntity())
                        packageDao.deleteActivePackageClaim(studentUUID)
                    } else {
                        // S1-D01: If the caller thought they were confirming or replacing an observed active package
                        // that is no longer active, require reconfirmation with null.
                        if (command.confirmReplaceActivePackage || command.observedActivePackageID != null) {
                            return@Callable ApplicationResult.Success(
                                SaveCoursePackageResult.RequiresReconfirmation(null),
                            )
                        }

                        // FR-009: Reject colliding IDs with any existing historical package.
                        if (s1Dao.findCoursePackage(targetUUID) != null) {
                            throw DomainAbortException(
                                ApplicationError(ApplicationErrorCode.conflict, field = "coursePackageID"),
                            )
                        }
                    }

                    val entityToInsert = draft.toEntity()
                    s1Dao.insert(entityToInsert)
                    s1Dao.insert(
                        ActivePackageClaimEntity(
                            studentID = studentUUID,
                            packageID = targetUUID,
                        ),
                    )
                    ApplicationResult.Success(SaveCoursePackageResult.Saved(draft.toRecord()))
                },
            )
        }
    }

    override suspend fun end(
        command: EndCoursePackageCommand,
    ): ApplicationResult<CoursePackageRecord> = runStorage {
        val now = clock.now()
        val packageUUID = UUID.fromString(command.coursePackageID.value)

        synchronized(writeLock) {
            database.runInTransaction(
                Callable {
                    val entity = s1Dao.findCoursePackage(packageUUID)
                        ?: throw DomainAbortException(
                            ApplicationError(ApplicationErrorCode.notFound, field = "coursePackageID"),
                        )
                    val current = entity.toDomain()
                    if (current.status != CoursePackageStatus.active) {
                        throw DomainAbortException(
                            ApplicationError(ApplicationErrorCode.invalidState, field = "status"),
                        )
                    }
                    val adjustments = loadAdjustmentsForPackage(packageUUID)
                    val balance = CreditLedger.balance(current.totalCredits, adjustments)
                    val ended = current.ending(now).cachingRemaining(balance, now)
                    packageDao.updateCoursePackage(ended.toEntity())

                    val studentUUID = UUID.fromString(current.studentID.value)
                    val claim = s1Dao.findActivePackageClaim(studentUUID)
                    if (claim != null && claim.packageID == packageUUID) {
                        packageDao.deleteActivePackageClaim(studentUUID)
                    }

                    ApplicationResult.Success(ended.toRecord())
                },
            )
        }
    }

    override suspend fun appendAdjustment(
        command: CreditAdjustmentCommand,
    ): ApplicationResult<CreditAdjustmentRecord> = runStorage {
        if (command.amount <= 0L) {
            return@runStorage ApplicationResult.Failure(
                ApplicationError(ApplicationErrorCode.invalidNumber, field = "amount"),
            )
        }
        val validatedReason = try {
            ValidatedText.optional(command.reasonText)
        } catch (_: IllegalArgumentException) {
            return@runStorage ApplicationResult.Failure(
                ApplicationError(ApplicationErrorCode.textTooLong, field = "reasonText"),
            )
        }
        if (command.reasonKind == CreditReasonKind.manualCorrection &&
            (validatedReason == null || validatedReason.isEmpty)
        ) {
            return@runStorage ApplicationResult.Failure(
                ApplicationError(ApplicationErrorCode.emptyText, field = "reasonText"),
            )
        }
        val appointmentID = try {
            command.linkedAppointmentID?.let { AppointmentID.parse(it) }
        } catch (_: IllegalArgumentException) {
            return@runStorage ApplicationResult.Failure(
                ApplicationError(ApplicationErrorCode.invalidIdentifier, field = "linkedAppointmentID"),
            )
        }

        val now = clock.now()
        val packageUUID = UUID.fromString(command.coursePackageID.value)

        synchronized(writeLock) {
            database.runInTransaction(
                Callable {
                    val existingByKey = packageDao.findCreditAdjustmentBySourceEventKey(command.sourceEventKey.value)
                    if (existingByKey != null) {
                        return@Callable ApplicationResult.Success(existingByKey.toDomain().toRecord())
                    }

                    val packageEntity = s1Dao.findCoursePackage(packageUUID)
                        ?: throw DomainAbortException(
                            ApplicationError(ApplicationErrorCode.notFound, field = "coursePackageID"),
                        )
                    val coursePackage = packageEntity.toDomain()
                    val existingAdjustments = loadAdjustmentsForPackage(packageUUID)
                    val currentBalance = CreditLedger.balance(coursePackage.totalCredits, existingAdjustments)

                    if (command.direction == CreditDirection.debit &&
                        !CreditLedger.canDebit(currentBalance, command.amount)
                    ) {
                        throw DomainAbortException(
                            ApplicationError(ApplicationErrorCode.invalidState, field = "amount"),
                        )
                    }

                    val adjustmentUUID = UUID.fromString(command.creditAdjustmentID.value)
                    if (s1Dao.findCreditAdjustment(adjustmentUUID) != null) {
                        throw DomainAbortException(
                            ApplicationError(ApplicationErrorCode.conflict, field = "creditAdjustmentID"),
                        )
                    }

                    val adjustment = CreditAdjustment(
                        creditAdjustmentID = command.creditAdjustmentID,
                        coursePackageID = command.coursePackageID,
                        direction = command.direction,
                        amount = command.amount,
                        reasonKind = command.reasonKind,
                        reasonText = validatedReason,
                        linkedSessionID = command.linkedSessionID,
                        linkedAppointmentID = appointmentID,
                        sourceEventKey = command.sourceEventKey,
                        createdAtUTC = now,
                    )

                    s1Dao.insert(adjustment.toEntity())

                    val newBalance = CreditLedger.balance(
                        coursePackage.totalCredits,
                        existingAdjustments + adjustment,
                    )
                    val cachedPackage = coursePackage.cachingRemaining(newBalance, now)
                    packageDao.updateCoursePackage(cachedPackage.toEntity())

                    ApplicationResult.Success(adjustment.toRecord())
                },
            )
        }
    }

    override suspend fun ledger(
        studentID: StudentID,
    ): ApplicationResult<List<CreditAdjustmentRecord>> = runStorage {
        val studentUUID = UUID.fromString(studentID.value)
        val entries = database.runInTransaction(
            Callable {
                packageDao.listStudentCreditAdjustments(studentUUID)
                    .map { it.toDomain() }
                    .sortedWith(
                        compareBy<CreditAdjustment> { it.createdAtUTC }
                            .thenBy { it.creditAdjustmentID.value },
                    )
                    .map { it.toRecord() }
            },
        )
        ApplicationResult.Success(entries)
    }

    override suspend fun refundOnSessionReopen(
        command: RefundOnSessionReopenCommand,
    ): ApplicationResult<CreditAdjustmentRecord?> = runStorage {
        val completeKey = keyBuilder.sessionComplete(command.sessionID)
        val reopenKey = keyBuilder.sessionReopen(command.sessionID)

        synchronized(writeLock) {
            database.runInTransaction(
                Callable {
                    val existingReopen = packageDao.findCreditAdjustmentBySourceEventKey(reopenKey.value)
                    if (existingReopen != null) {
                        return@Callable ApplicationResult.Success(existingReopen.toDomain().toRecord())
                    }

                    val priorDebitEntity = packageDao.findCreditAdjustmentBySourceEventKey(completeKey.value)
                        ?: return@Callable ApplicationResult.Success(null)
                    val priorDebit = priorDebitEntity.toDomain()

                    val packageUUID = priorDebitEntity.packageID
                    val packageEntity = s1Dao.findCoursePackage(packageUUID)
                        ?: throw DomainAbortException(
                            ApplicationError(ApplicationErrorCode.notFound, field = "coursePackageID"),
                        )
                    val coursePackage = packageEntity.toDomain()
                    val existingAdjustments = loadAdjustmentsForPackage(packageUUID)

                    val adjustmentID = ids.newCreditAdjustmentID()
                    val adjustmentUUID = UUID.fromString(adjustmentID.value)
                    if (s1Dao.findCreditAdjustment(adjustmentUUID) != null) {
                        throw DomainAbortException(
                            ApplicationError(ApplicationErrorCode.conflict, field = "creditAdjustmentID"),
                        )
                    }

                    val refund = CreditAdjustment(
                        creditAdjustmentID = adjustmentID,
                        coursePackageID = priorDebit.coursePackageID,
                        direction = CreditDirection.credit,
                        amount = 1L,
                        reasonKind = CreditReasonKind.sessionReopen,
                        reasonText = null,
                        linkedSessionID = command.sessionID,
                        linkedAppointmentID = null,
                        sourceEventKey = reopenKey,
                        createdAtUTC = command.requestedAtUTC,
                    )

                    s1Dao.insert(refund.toEntity())

                    val newBalance = CreditLedger.balance(
                        coursePackage.totalCredits,
                        existingAdjustments + refund,
                    )
                    val cachedPackage = coursePackage.cachingRemaining(newBalance, command.requestedAtUTC)
                    packageDao.updateCoursePackage(cachedPackage.toEntity())

                    ApplicationResult.Success(refund.toRecord())
                },
            )
        }
    }

    private fun loadCurrentActivePackageInTransaction(studentUUID: UUID): Pair<CoursePackage, Long>? {
        val claim = s1Dao.findActivePackageClaim(studentUUID) ?: return null
        val packageEntity = s1Dao.findCoursePackage(claim.packageID)
            ?: throw DomainAbortException(
                ApplicationError(ApplicationErrorCode.incompatibleInput, field = "activePackageClaim"),
            )
        val domain = packageEntity.toDomain()
        if (domain.studentID.value != studentUUID.toString() || domain.status != CoursePackageStatus.active) {
            throw DomainAbortException(
                ApplicationError(ApplicationErrorCode.incompatibleInput, field = "activePackageClaim"),
            )
        }
        val adjustments = loadAdjustmentsForPackage(claim.packageID)
        val balance = CreditLedger.balance(domain.totalCredits, adjustments)
        return domain.copy(remainingCreditsCache = balance) to balance
    }

    private fun loadAdjustmentsForPackage(packageUUID: UUID): List<CreditAdjustment> =
        packageDao.listCreditAdjustments(packageUUID)
            .map { it.toDomain() }
            .sortedWith(
                compareBy<CreditAdjustment> { it.createdAtUTC }
                    .thenBy { it.creditAdjustmentID.value },
            )

    private suspend fun <T> runStorage(block: () -> ApplicationResult<T>): ApplicationResult<T> =
        withContext(ioContext) {
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: DomainAbortException) {
                ApplicationResult.Failure(e.error)
            } catch (_: ArithmeticException) {
                ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidNumber))
            } catch (_: SQLiteConstraintException) {
                ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed))
            } catch (_: SQLiteException) {
                ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed))
            } catch (_: IllegalStateException) {
                ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed))
            } catch (_: IllegalArgumentException) {
                ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.incompatibleInput))
            } catch (_: Exception) {
                ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed))
            }
        }

    private class DomainAbortException(val error: ApplicationError) : RuntimeException(null, null, false, false)

    private object DefaultSourceEventKeyBuilder : CreditLedgerSourceEventKeyBuilder {
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

    companion object {
        private val locks = java.util.WeakHashMap<FineCoachDatabase, Any>()

        @Synchronized
        private fun defaultLockFor(database: FineCoachDatabase): Any =
            locks.getOrPut(database) { Any() }
    }
}

private fun CoursePackageEntity.toDomain(): CoursePackage = CoursePackage(
    coursePackageID = CoursePackageID.fromUUID(id),
    studentID = StudentID.fromUUID(studentID),
    name = name?.let { ValidatedText.parse(it, allowEmpty = true) },
    totalCredits = totalCredits,
    remainingCreditsCache = remainingCreditsCache,
    startDate = startDate,
    endDate = endDate,
    status = status,
    createdAtUTC = createdAtUTC,
    updatedAtUTC = updatedAtUTC,
)

private fun CoursePackage.toEntity(): CoursePackageEntity = CoursePackageEntity(
    id = UUID.fromString(coursePackageID.value),
    studentID = UUID.fromString(studentID.value),
    name = name?.value,
    totalCredits = totalCredits,
    remainingCreditsCache = remainingCreditsCache,
    startDate = startDate,
    endDate = endDate,
    status = status,
    createdAtUTC = createdAtUTC,
    updatedAtUTC = updatedAtUTC,
)

private fun CoursePackage.toRecord(): CoursePackageRecord = CoursePackageRecord(
    coursePackageID = coursePackageID,
    studentID = studentID,
    name = name?.value,
    totalCredits = totalCredits,
    remainingCreditsCache = remainingCreditsCache,
    startDate = startDate,
    endDate = endDate,
    status = status,
    createdAtUTC = createdAtUTC,
    updatedAtUTC = updatedAtUTC,
)

private fun CreditAdjustmentEntity.toDomain(): CreditAdjustment = CreditAdjustment(
    creditAdjustmentID = CreditAdjustmentID.fromUUID(id),
    coursePackageID = CoursePackageID.fromUUID(packageID),
    direction = direction,
    amount = amount,
    reasonKind = reasonKind,
    reasonText = reasonText?.let { ValidatedText.parse(it, allowEmpty = true) },
    linkedSessionID = linkedSessionID?.let { SessionID.fromUUID(it) },
    linkedAppointmentID = linkedAppointmentID?.let { AppointmentID.fromUUID(it) },
    sourceEventKey = SourceEventKey.parse(sourceEventKey),
    createdAtUTC = createdAtUTC,
)

private fun CreditAdjustment.toEntity(): CreditAdjustmentEntity = CreditAdjustmentEntity(
    id = UUID.fromString(creditAdjustmentID.value),
    packageID = UUID.fromString(coursePackageID.value),
    direction = direction,
    amount = amount,
    reasonKind = reasonKind,
    reasonText = reasonText?.value,
    linkedSessionID = linkedSessionID?.let { UUID.fromString(it.value) },
    linkedAppointmentID = linkedAppointmentID?.let { UUID.fromString(it.value) },
    sourceEventKey = sourceEventKey.value,
    createdAtUTC = createdAtUTC,
)

private fun CreditAdjustment.toRecord(): CreditAdjustmentRecord = CreditAdjustmentRecord(
    creditAdjustmentID = creditAdjustmentID,
    coursePackageID = coursePackageID,
    direction = direction,
    amount = amount,
    reasonKind = reasonKind,
    reasonText = reasonText?.value,
    linkedSessionID = linkedSessionID,
    linkedAppointmentID = linkedAppointmentID?.value,
    sourceEventKey = sourceEventKey,
    createdAtUTC = createdAtUTC,
)
