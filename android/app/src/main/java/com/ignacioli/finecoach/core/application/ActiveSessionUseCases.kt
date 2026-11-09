package com.ignacioli.finecoach.core.application

import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import java.math.BigDecimal
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

sealed interface SessionSaveStatus {
    data object Saving : SessionSaveStatus
    data class Saved(val revision: Revision) : SessionSaveStatus
    data class Failed(val error: ApplicationError) : SessionSaveStatus
}

/** Commands retain their expected revision on retry; a conflict must be reloaded, never overwritten. */
class ActiveSessionUseCases(
    private val repository: SessionRepositoryPort,
    private val clock: AppClock,
    private val ids: StableIDGenerator,
) {
    private val gate = Mutex()
    private val statuses = ConcurrentHashMap<SessionID, SessionSaveStatus>()
    private val pending = ConcurrentHashMap<SessionID, suspend () -> ApplicationResult<Revision>>()
    fun saveStatus(id: SessionID): SessionSaveStatus? = statuses[id]
    suspend fun startOrOpen(studentID: StudentID, focus: Set<BodyPart> = emptySet()) =
        repository.startOrOpen(StartOrOpenSessionCommand(studentID, focus, clock.now()))
    suspend fun load(sessionID: SessionID) = repository.loadContent(sessionID)
    suspend fun saveDraft(command: SaveSessionDraftCommand): ApplicationResult<SessionRecord> = gate.withLock {
        persist(command.sessionID, { retryRevision(repository.saveDraft(command)) { it.revision } },
            { it.revision }) { repository.saveDraft(command) }
    }
    suspend fun saveContent(command: SaveSessionContentCommand): ApplicationResult<SessionContentRecord> = gate.withLock {
        persist(command.sessionID, { retryRevision(repository.saveContent(command)) { it.session.revision } },
            { it.session.revision }) { repository.saveContent(command) }
    }
    suspend fun retry(command: SaveSessionDraftCommand) = saveDraft(command)
    suspend fun retry(command: SaveSessionContentCommand) = saveContent(command)
    suspend fun retry(id: SessionID): ApplicationResult<Revision> = gate.withLock {
        val attempt = pending[id] ?: return@withLock ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.notFound))
        persist(id, attempt, { it }, attempt)
    }
    suspend fun complete(command: CompleteSessionCommand): ApplicationResult<SessionRecord> = gate.withLock {
        if (pending.containsKey(command.sessionID)) return@withLock ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidState))
        repository.complete(command)
    }
    private fun <T> retryRevision(result: ApplicationResult<T>, revision: (T) -> Revision): ApplicationResult<Revision> = when (result) {
        is ApplicationResult.Failure -> result
        is ApplicationResult.Success -> ApplicationResult.Success(revision(result.value))
    }
    private suspend fun <T> persist(id: SessionID, retry: suspend () -> ApplicationResult<Revision>,
        revision: (T) -> Revision, action: suspend () -> ApplicationResult<T>): ApplicationResult<T> {
        pending[id] = retry
        statuses[id] = SessionSaveStatus.Saving
        val result = action()
        when (result) {
            is ApplicationResult.Failure -> statuses[id] = SessionSaveStatus.Failed(result.error)
            is ApplicationResult.Success -> {
                pending.remove(id)
                statuses[id] = SessionSaveStatus.Saved(revision(result.value))
            }
        }
        return result
    }

    suspend fun mutate(
        sessionID: SessionID, expectedRevision: Revision,
        change: (SectionedSession) -> SectionedSession,
    ): ApplicationResult<SessionContentRecord> = trainingValidation {
        when (val loaded = repository.loadContent(sessionID)) {
            is ApplicationResult.Failure -> loaded
            is ApplicationResult.Success -> {
                val content = loaded.value ?: trainingFailure(ApplicationErrorCode.notFound)
                if (content.session.revision != expectedRevision) trainingFailure(ApplicationErrorCode.staleRevision)
                val original = content.toDomain()
                val changed = change(original)
                if (changed == original) ApplicationResult.Success(content) else {
                    if (changed.session.copy(exercises = original.session.exercises, revision = original.session.revision,
                            updatedAtUTC = original.session.updatedAtUTC, lastCheckpointUTC = original.session.lastCheckpointUTC)
                        != original.session) trainingFailure(ApplicationErrorCode.incompatibleInput)
                    val records = changed.toRecord()
                    saveContent(SaveSessionContentCommand(sessionID, expectedRevision, records.sections, records.exercises))
                }
            }
        }
    }

    suspend fun deleteSection(id: SessionID, revision: Revision, section: SectionID,
        disposition: SessionSectionDeletionDisposition?) = mutate(id, revision) {
        it.deletingSection(section, disposition, clock.now())
    }
    suspend fun addSection(id: SessionID, revision: Revision, name: String) = mutate(id, revision) {
        it.addingSection(ids.newSectionID(), name, clock.now())
    }
    suspend fun confirmSet(id: SessionID, revision: Revision, set: TrainingSetID) = mutate(id, revision) {
        it.copy(session = it.session.confirmingSet(set, clock.now()))
    }
    suspend fun checkpoint(id: SessionID, interruption: Boolean = false): ApplicationResult<SessionRecord> = trainingValidation {
        when (val loaded = repository.loadContent(id)) {
            is ApplicationResult.Failure -> loaded
            is ApplicationResult.Success -> {
                val original = loaded.value ?: trainingFailure(ApplicationErrorCode.notFound)
                val now = clock.now()
                val changed = SessionTimingCoordinator().checkpoint(original.toDomain().session, now)
                saveDraft(SaveSessionDraftCommand(id, original.session.revision,
                    changed.toRecord().draftPayload().copy(interruptionStartedAtUTC = if (interruption) now else null)))
            }
        }
    }
}

internal class TrainingApplicationException(val code: ApplicationErrorCode) : RuntimeException()
internal fun trainingFailure(code: ApplicationErrorCode): Nothing = throw TrainingApplicationException(code)
internal suspend fun <T> trainingValidation(action: suspend () -> ApplicationResult<T>): ApplicationResult<T> = try {
    action()
} catch (error: DomainException) {
    ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.valueOf(error.error.name), error.field))
} catch (error: TrainingApplicationException) {
    ApplicationResult.Failure(ApplicationError(error.code))
} catch (_: IllegalArgumentException) {
    ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.incompatibleInput))
}

internal fun BigDecimal.domainDecimal(): DecimalValue = DecimalValue.fromBigDecimal(this)
internal fun BigDecimal?.optionalDecimal(): DecimalValue? = this?.domainDecimal()
internal fun SessionRecord.draftPayload() = SessionDraftPayload(elapsedSeconds, interruptionStartedAtUTC,
    durationNeedsReview, coachAdjustedDurationSeconds, trainingFocus, studentFacingSummary, privateCoachNote, lastCheckpointUTC)
internal fun SessionRecord.toDomain(exercises: List<SessionExercise> = emptyList()) = Session(
    sessionID, studentID, state, startedAtUTC, lastCheckpointUTC, elapsedSeconds.domainDecimal(),
    interruptionStartedAtUTC, durationNeedsReview, coachAdjustedDurationSeconds.optionalDecimal(), trainingFocus.toSet(),
    ValidatedText.optional(studentFacingSummary), ValidatedText.optional(privateCoachNote), revision,
    createdAtUTC, updatedAtUTC, completedAtUTC, exercises,
)
internal fun Session.toRecord() = SessionRecord(sessionID, studentID, state, startedAtUTC, lastCheckpointUTC,
    elapsedSeconds.decimal, interruptionStartedAtUTC, durationNeedsReview, coachAdjustedDurationSeconds?.decimal,
    trainingFocus.toSet(), studentFacingSummary?.value, privateCoachNote?.value, revision, createdAtUTC, updatedAtUTC, completedAtUTC)
internal fun SectionRecord.toDomain(): SessionSection = SessionSection.create(sectionID,
    when (ownerKind) {
        SessionSectionOwnerKind.session -> SectionOwner.Session(requireNotNull(ownerSessionID))
        SessionSectionOwnerKind.template -> SectionOwner.Template(requireNotNull(ownerTemplateID))
    }, name, orderIndex)
internal fun SessionSection.toRecord() = SectionRecord(sectionID,
    if (owner is SectionOwner.Session) SessionSectionOwnerKind.session else SessionSectionOwnerKind.template,
    (owner as? SectionOwner.Session)?.id, (owner as? SectionOwner.Template)?.id, name.value, orderIndex)
internal fun TrainingSetRecord.toDomain(): TrainingSet = TrainingSet(trainingSetID, sessionExerciseID, orderIndex,
    state, recordMode, weightValue.optionalDecimal(), repetitionCount.optionalDecimal(), durationSeconds.optionalDecimal(),
    unit, side, leftValue.optionalDecimal(), rightValue.optionalDecimal(), distanceValue.optionalDecimal(),
    speedValue.optionalDecimal(), resistanceValue.optionalDecimal(), createdAtUTC, updatedAtUTC, completedAtUTC).also {
    if (state == SetRecordingState.completed) {
        if (completedAtUTC == null) trainingFailure(ApplicationErrorCode.invalidState)
        it.confirmed(updatedAtUTC, completedAtUTC)
    } else if (completedAtUTC != null) trainingFailure(ApplicationErrorCode.invalidState)
}
internal fun TrainingSet.toRecord() = TrainingSetRecord(trainingSetID, sessionExerciseID, orderIndex, state, recordMode,
    weightValue?.decimal, repetitionCount?.decimal, durationSeconds?.decimal, unit, side, leftValue?.decimal,
    rightValue?.decimal, distanceValue?.decimal, speedValue?.decimal, resistanceValue?.decimal,
    createdAtUTC, updatedAtUTC, completedAtUTC)
internal fun SessionExerciseRecord.toDomain() = SessionExercise(sessionExerciseID, sessionID, orderIndex, sourceKind,
    sourceID, NormalizedName.parse(displayNameSnapshot), recordModeSnapshot, ValidatedText.optional(actionPrivateNote),
    sectionID, sets.map { row ->
        if (row.sessionExerciseID != sessionExerciseID || row.recordMode != recordModeSnapshot) {
            trainingFailure(ApplicationErrorCode.invalidState)
        }
        row.toDomain()
    }.also { rows ->
        if (rows.map { it.trainingSetID }.distinct().size != rows.size || rows.map { it.orderIndex }.distinct().size != rows.size) {
            trainingFailure(ApplicationErrorCode.conflict)
        }
    })
internal fun SessionExercise.toRecord() = SessionExerciseRecord(sessionExerciseID, sessionID, orderIndex, sourceKind,
    sourceID, displayNameSnapshot.value, recordModeSnapshot, actionPrivateNote?.value, sectionID, sets.map { it.toRecord() })
internal fun SessionContentRecord.toDomain(): SectionedSession = SectionedSession(
    session.toDomain(exercises.map { it.toDomain() }), sections.map { it.toDomain() },
).also { it.layout() }
internal fun SectionedSession.toRecord() = SessionContentRecord(session.toRecord(), sections.map { it.toRecord() },
    session.exercises.map { it.toRecord() })
