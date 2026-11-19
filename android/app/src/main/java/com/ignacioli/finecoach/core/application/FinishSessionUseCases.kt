package com.ignacioli.finecoach.core.application

import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.SessionFinishGate
import com.ignacioli.finecoach.core.domain.training.SessionTimingCoordinator
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.CancellationException

enum class SessionCreditUnusableReason { expired, insufficientBalance }

sealed interface SessionCreditOutcome {
    data class AdhocChoiceRequired(val coursePackage: CoursePackageRecord) : SessionCreditOutcome
    data class PackageUnusable(val coursePackage: CoursePackageRecord, val reason: SessionCreditUnusableReason) : SessionCreditOutcome
    data class Debited(val adjustment: CreditAdjustmentRecord) : SessionCreditOutcome
    data object NoActivePackage : SessionCreditOutcome
    data object Skipped : SessionCreditOutcome
}

/** Completion succeeds independently of settlement. Callers must inspect [settlement] before showing credit success. */
data class FinishedSessionResult(
    val session: SessionRecord,
    val settlement: ApplicationResult<SessionCreditOutcome>,
)

class FinishSessionUseCases(
    private val sessions: SessionRepositoryPort,
    private val activeSessions: ActiveSessionUseCases,
    private val credits: CreditUseCases,
    private val notes: SessionSettlementNotePort,
    private val clock: AppClock,
    private val zoneID: ZoneId,
) {
    suspend fun gate(sessionID: SessionID): ApplicationResult<SessionFinishGate> = settlementValidation {
        when (val result = sessions.loadContent(sessionID)) {
            is ApplicationResult.Failure -> result
            is ApplicationResult.Success -> {
                val content = result.value ?: trainingFailure(ApplicationErrorCode.notFound)
                if (content.session.state != SessionState.inProgress) trainingFailure(ApplicationErrorCode.invalidState)
                ApplicationResult.Success(content.toDomain().session.finishGate)
            }
        }
    }

    /** Discarding unresolved sets requires an explicit coach choice; returning/cancelling calls neither mutation. */
    suspend fun finish(sessionID: SessionID, expectedRevision: Revision, discardUnresolved: Boolean = false): ApplicationResult<FinishedSessionResult> = settlementValidation {
        val content = when (val loaded = sessions.loadContent(sessionID)) {
            is ApplicationResult.Failure -> return@settlementValidation loaded
            is ApplicationResult.Success -> loaded.value ?: trainingFailure(ApplicationErrorCode.notFound)
        }
        if (content.session.state == SessionState.completed) {
            return@settlementValidation ApplicationResult.Success(FinishedSessionResult(content.session, settlement(sessionID)))
        }
        if (content.session.revision != expectedRevision) trainingFailure(ApplicationErrorCode.staleRevision)
        when (activeSessions.saveStatus(sessionID)) {
            is SessionSaveStatus.Failed, SessionSaveStatus.Saving -> trainingFailure(ApplicationErrorCode.invalidState)
            else -> Unit
        }
        val domain = content.toDomain().session
        if (domain.finishGate == SessionFinishGate.abandonEmpty) trainingFailure(ApplicationErrorCode.invalidState)
        if (domain.hasUnresolvedSets && !discardUnresolved) trainingFailure(ApplicationErrorCode.invalidState)
        if (domain.durationNeedsReview && domain.coachAdjustedDurationSeconds == null) trainingFailure(ApplicationErrorCode.invalidState)
        var current = content.session
        if (domain.hasUnresolvedSets) {
            when (val saved = activeSessions.mutate(sessionID, current.revision) {
                it.copy(session = it.session.discardingUnresolvedSets(clock.now()))
            }) {
                is ApplicationResult.Failure -> return@settlementValidation saved
                is ApplicationResult.Success -> current = saved.value.session
            }
        }
        val timed = SessionTimingCoordinator().checkpoint(current.toDomain(), clock.now()).toRecord()
        when (val saved = activeSessions.saveDraft(SaveSessionDraftCommand(sessionID, current.revision,
            timed.draftPayload().copy(interruptionStartedAtUTC = null)))) {
            is ApplicationResult.Failure -> return@settlementValidation saved
            is ApplicationResult.Success -> current = saved.value
        }
        val completed = when (val result = activeSessions.complete(CompleteSessionCommand(sessionID, current.revision, clock.now(), false))) {
            is ApplicationResult.Failure -> return@settlementValidation result
            is ApplicationResult.Success -> result.value
        }
        ApplicationResult.Success(FinishedSessionResult(completed, settlement(sessionID)))
    }

    suspend fun abandonEmpty(sessionID: SessionID, expectedRevision: Revision, confirmed: Boolean): ApplicationResult<SessionRecord> = settlementValidation {
        if (!confirmed) trainingFailure(ApplicationErrorCode.invalidState)
        sessions.abandon(AbandonEmptySessionCommand(sessionID, expectedRevision, clock.now()))
    }

    /** Safe to call after process restart: this reads the choice context, never auto-selects a debit. */
    suspend fun settlement(sessionID: SessionID): ApplicationResult<SessionCreditOutcome> = settlementValidation {
        val session = completed(sessionID)
        if (session is ApplicationResult.Failure) return@settlementValidation session
        val record = (session as ApplicationResult.Success).value
        val ledger = when (val result = credits.ledger(record.studentID)) {
            is ApplicationResult.Failure -> return@settlementValidation result
            is ApplicationResult.Success -> result.value
        }
        val linked = when (val result = sessions.linkedAppointmentID(sessionID)) {
            is ApplicationResult.Failure -> return@settlementValidation result
            is ApplicationResult.Success -> result.value != null
        }
        val key = if (linked) CreditLedgerSourceEventKeyFactory.sessionComplete(sessionID) else CreditLedgerSourceEventKeyFactory.adhocSession(sessionID)
        ledger.firstOrNull { it.sourceEventKey == key }?.let {
            return@settlementValidation ApplicationResult.Success(SessionCreditOutcome.Debited(it))
        }
        val coursePackage = when (val result = credits.activePackage(record.studentID, clock.today(zoneID))) {
            is ApplicationResult.Failure -> return@settlementValidation result
            is ApplicationResult.Success -> result.value
        }
        if (coursePackage == null) {
            when (val saved = notes.save(SaveSessionSettlementNoteCommand(sessionID, record.revision, SessionCreditSettlementNote.noActivePackage))) {
                is ApplicationResult.Failure -> return@settlementValidation saved
                is ApplicationResult.Success -> return@settlementValidation ApplicationResult.Success(SessionCreditOutcome.NoActivePackage)
            }
        }
        val reason = unusableReason(coursePackage, clock.today(zoneID))
        if (linked && reason == null) {
            return@settlementValidation when (val debit = credits.debitOnSessionComplete(coursePackage.coursePackageID, sessionID)) {
                is ApplicationResult.Failure -> debit
                is ApplicationResult.Success -> ApplicationResult.Success(SessionCreditOutcome.Debited(debit.value))
            }
        }
        ApplicationResult.Success(if (reason == null) SessionCreditOutcome.AdhocChoiceRequired(coursePackage)
            else SessionCreditOutcome.PackageUnusable(coursePackage, reason))
    }

    /** The package ID is the one actually shown to the coach. Replacement requires a fresh choice. */
    suspend fun debitAdhoc(sessionID: SessionID, observedPackageID: CoursePackageID): ApplicationResult<SessionCreditOutcome> = settlementValidation {
        when (val context = settlement(sessionID)) {
            is ApplicationResult.Failure -> context
            is ApplicationResult.Success -> when (val outcome = context.value) {
                is SessionCreditOutcome.Debited -> context
                is SessionCreditOutcome.AdhocChoiceRequired -> {
                    if (outcome.coursePackage.coursePackageID != observedPackageID) trainingFailure(ApplicationErrorCode.conflict)
                    when (val debited = credits.debitOnAdhocSession(observedPackageID, sessionID)) {
                        is ApplicationResult.Failure -> debited
                        is ApplicationResult.Success -> ApplicationResult.Success(SessionCreditOutcome.Debited(debited.value))
                    }
                }
                is SessionCreditOutcome.PackageUnusable -> ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidState,
                    if (outcome.reason == SessionCreditUnusableReason.expired) "endDate" else "amount"))
                else -> ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidState))
            }
        }
    }

    suspend fun skipDebit(sessionID: SessionID): ApplicationResult<SessionCreditOutcome> = settlementValidation {
        when (val linked = sessions.linkedAppointmentID(sessionID)) {
            is ApplicationResult.Failure -> return@settlementValidation linked
            is ApplicationResult.Success -> if (linked.value != null) {
                when (val unusable = linkedPackageUnusable(sessionID)) {
                    is ApplicationResult.Failure -> return@settlementValidation unusable
                    is ApplicationResult.Success -> if (!unusable.value) trainingFailure(ApplicationErrorCode.invalidState)
                }
            }
        }
        when (val result = completed(sessionID)) {
            is ApplicationResult.Failure -> result
            is ApplicationResult.Success -> ApplicationResult.Success(SessionCreditOutcome.Skipped)
        }
    }

    /** Read-only PackageUnusable check. Does not call settlement, which debits a usable linked package. */
    private suspend fun linkedPackageUnusable(sessionID: SessionID): ApplicationResult<Boolean> {
        val session = completed(sessionID)
        if (session is ApplicationResult.Failure) return session
        val record = (session as ApplicationResult.Success).value
        val ledger = when (val result = credits.ledger(record.studentID)) {
            is ApplicationResult.Failure -> return result
            is ApplicationResult.Success -> result.value
        }
        if (ledger.any { it.sourceEventKey == CreditLedgerSourceEventKeyFactory.sessionComplete(sessionID) }) {
            return ApplicationResult.Success(false)
        }
        val coursePackage = when (val result = credits.activePackage(record.studentID, clock.today(zoneID))) {
            is ApplicationResult.Failure -> return result
            is ApplicationResult.Success -> result.value
        } ?: return ApplicationResult.Success(false)
        return ApplicationResult.Success(unusableReason(coursePackage, clock.today(zoneID)) != null)
    }

    private suspend fun completed(id: SessionID): ApplicationResult<SessionRecord> = when (val loaded = sessions.find(id)) {
        is ApplicationResult.Failure -> loaded
        is ApplicationResult.Success -> {
            val record = loaded.value ?: trainingFailure(ApplicationErrorCode.notFound)
            if (record.state != SessionState.completed) trainingFailure(ApplicationErrorCode.invalidState)
            ApplicationResult.Success(record)
        }
    }
}

internal fun unusableReason(coursePackage: CoursePackageRecord, today: LocalDate): SessionCreditUnusableReason? = when {
    coursePackage.endDate?.let { it < today } == true -> SessionCreditUnusableReason.expired
    coursePackage.remainingCreditsCache <= 0 -> SessionCreditUnusableReason.insufficientBalance
    else -> null
}

internal suspend fun <T> settlementValidation(action: suspend () -> ApplicationResult<T>): ApplicationResult<T> = try {
    trainingValidation(action)
} catch (error: CancellationException) {
    throw error
} catch (_: Exception) {
    ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed))
}
