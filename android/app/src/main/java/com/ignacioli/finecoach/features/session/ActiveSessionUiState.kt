package com.ignacioli.finecoach.features.session

import androidx.compose.runtime.*
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.features.exercises.*
import com.ignacioli.finecoach.designsystem.FcSaveState
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class ActiveSessionUiState(
    val useCases: ActiveSessionUseCases, val clock: AppClock, val ids: StableIDGenerator,
    private val sessions: SessionRepositoryPort, private val history: HistoryRepositoryPort,
    private val exerciseUseCases: ExerciseUseCases,
    val rests: RestTimerStore = RestTimerStore(clock),
) {
    companion object {
        private val operationGates = java.util.WeakHashMap<ActiveSessionUseCases, Mutex>()
        private fun gateFor(useCases: ActiveSessionUseCases): Mutex = synchronized(operationGates) {
            operationGates.getOrPut(useCases) { Mutex() }
        }
    }
    // Recovery bypasses the frozen use-case gate, so serialize its entire read/write/refresh here.
    private val operationGate = gateFor(useCases)
    private var timingFailure = false
    var saveState by mutableStateOf(FcSaveState.Saved); private set
    private var retryAction: (suspend () -> Unit)? = null
    var content by mutableStateOf<SessionContentRecord?>(null); private set
    var error by mutableStateOf<ApplicationError?>(null); private set
    var busy by mutableStateOf(false); private set
    var deleted by mutableStateOf<TrainingSet?>(null); private set
    private var deletedIndex = 0
    val previous = mutableStateMapOf<SessionExerciseID, TrainingSetRecord>()

    suspend fun load(id: SessionID) = perform({ useCases.load(id) }) { loaded ->
        content = loaded
        if (loaded == null) error = ApplicationError(ApplicationErrorCode.notFound)
        else loadPrevious(loaded)
    }
    private suspend fun loadPrevious(current: SessionContentRecord) {
        previous.clear()
        when (val rows = history.list(HistoryQuery(studentID = current.session.studentID))) {
            is ApplicationResult.Failure -> error = rows.error
            is ApplicationResult.Success -> for (row in rows.value.sortedByDescending { it.completedAtUTC }) {
                when (val result = sessions.loadContent(row.sessionID)) {
                    is ApplicationResult.Failure -> { error = result.error; return }
                    is ApplicationResult.Success -> {
                        val old = result.value ?: continue
                        if (old.session.state != SessionState.completed) continue
                        current.exercises.forEach { exercise ->
                            if (exercise.sessionExerciseID !in previous) {
                                old.exercises.lastOrNull { it.recordModeSnapshot == exercise.recordModeSnapshot &&
                                    it.displayNameSnapshot == exercise.displayNameSnapshot && it.sourceID == exercise.sourceID }
                                    ?.sets?.firstOrNull { it.state == SetRecordingState.completed }
                                    ?.let { previous[exercise.sessionExerciseID] = it }
                            }
                        }
                    }
                }
            }
        }
    }
    suspend fun <T> perform(action: suspend () -> ApplicationResult<T>, success: suspend (T) -> Unit = {}): ApplicationResult<T> = operationGate.withLock {
        busy = true
        try {
            val result = action()
            when (result) {
                is ApplicationResult.Failure -> error = result.error
                is ApplicationResult.Success -> { error = null; success(result.value) }
            }
            result
        } finally { busy = false }
    }
    suspend fun mutate(change: (SectionedSession) -> SectionedSession): ApplicationResult<Unit> {
        val current = content ?: return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.notFound))
        if (busy) return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidState))
        var outcome: ApplicationResult<Unit> = ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidState))
        saveState = FcSaveState.Saving
        perform({ timingFailure = false; useCases.mutate(current.session.sessionID, current.session.revision, change) }) {
            acceptMutation(it); outcome = ApplicationResult.Success(Unit)
        }
        saveState = if (error == null) FcSaveState.Saved else FcSaveState.Failed
        retryAction = if (error == null) null else ({
            perform({ useCases.retry(current.session.sessionID) }) { loadAfterRetry(current.session.sessionID) }
        })
        return error?.let { ApplicationResult.Failure(it) } ?: outcome
    }
    suspend fun addExercise(selection: ExerciseSelection): ApplicationResult<Unit> {
        val current = content ?: return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.notFound))
        val id = ids.newSessionExerciseID()
        var result: ApplicationResult<Unit> = ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidState))
        saveState = FcSaveState.Saving
        perform({
            timingFailure = false
            val claim = if (selection.sourceKind == ExerciseSourceKind.sessionOnly)
                exerciseUseCases.claimSessionOnly(StableExerciseID.parse(id.value), selection.name) else ApplicationResult.Success(Unit)
            when (claim) {
                is ApplicationResult.Failure -> claim
                is ApplicationResult.Success -> useCases.saveContent(SaveSessionContentCommand(current.session.sessionID,
                    current.session.revision, current.sections, current.exercises + SessionExerciseRecord(id,
                        current.session.sessionID, (current.sections.map { it.orderIndex } + current.exercises.map { it.orderIndex })
                            .maxOrNull()?.plus(1u) ?: 0u,
                        selection.sourceKind, selection.sourceID, selection.name, selection.mode, null, null, emptyList())))
            }
        }) { content = it; loadPrevious(it); result = ApplicationResult.Success(Unit) }
        saveState = if (error == null) FcSaveState.Saved else FcSaveState.Failed
        retryAction = if (error == null) null else ({ addExercise(selection) })
        return error?.let { ApplicationResult.Failure(it) } ?: result
    }
    fun accept(value: SessionContentRecord) { content = value }
    private fun acceptMutation(value: SessionContentRecord) {
        val completed = content?.exercises?.flatMap { it.sets }?.filter { it.state == SetRecordingState.completed }?.map { it.trainingSetID }?.toSet().orEmpty()
        content = value
        if (value.exercises.flatMap { it.sets }.any { it.state == SetRecordingState.completed && it.trainingSetID !in completed }) rests.start(value.session.sessionID)
    }
    private suspend fun loadAfterRetry(id: SessionID) {
        when (val loaded = useCases.load(id)) {
            is ApplicationResult.Failure -> error = loaded.error
            is ApplicationResult.Success -> loaded.value?.let(::acceptMutation)
        }
    }
    suspend fun retrySave() {
        if (busy) return
        val action = retryAction ?: return
        saveState = FcSaveState.Saving
        action()
        saveState = if (error == null) FcSaveState.Saved else FcSaveState.Failed
        if (error == null) retryAction = null
    }
    suspend fun checkpoint(interruption: Boolean = false) {
        val id = content?.session?.sessionID ?: return
        timingOperation({ checkpoint(interruption) }) {
            val current = requireContent(id)
            when (current) {
                is ApplicationResult.Failure -> current
                is ApplicationResult.Success -> when {
                    current.value.session.state != SessionState.inProgress -> current
                    else -> when (val saved = useCases.checkpoint(id, interruption)) {
                        is ApplicationResult.Failure -> saved
                        is ApplicationResult.Success -> requireContent(id)
                    }
                }
            }
        }
    }
    suspend fun resume(id: SessionID) {
        timingOperation({ resume(id) }) {
            when (val current = requireContent(id)) {
                is ApplicationResult.Failure -> current
                is ApplicationResult.Success -> {
                    val recovered = if (current.value.session.interruptionStartedAtUTC == null) current else {
                        when (val result = RecoveryCoordinator(sessions, clock).reconcileOnLaunch()) {
                            is ApplicationResult.Failure -> result
                            is ApplicationResult.Success -> requireContent(id)
                        }
                    }
                    // Clear a failed lifecycle command via a fresh CAS, never by replaying its old revision.
                    if (recovered is ApplicationResult.Success && recovered.value.session.state == SessionState.inProgress &&
                        timingFailure && useCases.saveStatus(id) is SessionSaveStatus.Failed) {
                        when (val saved = useCases.saveDraft(SaveSessionDraftCommand(id, recovered.value.session.revision,
                            recovered.value.session.draftPayload()))) {
                            is ApplicationResult.Failure -> saved
                            is ApplicationResult.Success -> requireContent(id)
                        }
                    } else recovered
                }
            }
        }
    }
    private suspend fun requireContent(id: SessionID): ApplicationResult<SessionContentRecord> = when (val loaded = useCases.load(id)) {
        is ApplicationResult.Failure -> loaded
        is ApplicationResult.Success -> loaded.value?.let { ApplicationResult.Success(it) }
            ?: ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.notFound))
    }
    private suspend fun timingOperation(retry: suspend () -> Unit, action: suspend () -> ApplicationResult<SessionContentRecord>) {
        perform({
            // Do not erase a failed content edit when a lifecycle callback arrives.
            if (saveState == FcSaveState.Failed && !timingFailure) {
                ApplicationResult.Failure(error ?: ApplicationError(ApplicationErrorCode.invalidState))
            } else {
                saveState = FcSaveState.Saving
                val result = action()
                timingFailure = result is ApplicationResult.Failure
                saveState = if (result is ApplicationResult.Success) FcSaveState.Saved else FcSaveState.Failed
                retryAction = if (result is ApplicationResult.Failure) retry else null
                result
            }
        }) { content = it }
    }
    suspend fun reviewDuration(seconds: String): ApplicationResult<Unit> {
        val current = content ?: return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.notFound))
        val value = seconds.toBigDecimalOrNull()
        if (value == null || value.signum() < 0 || value.stripTrailingZeros().scale() > 0) return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidNumber))
        saveState = FcSaveState.Saving
        perform({ timingFailure = false; useCases.saveDraft(SaveSessionDraftCommand(current.session.sessionID, current.session.revision,
            current.session.draftPayload().copy(coachAdjustedDurationSeconds = value, durationNeedsReview = false))) }) { content = current.copy(session = it) }
        saveState = if (error == null) FcSaveState.Saved else FcSaveState.Failed
        if (error != null) retryAction = ({ perform({ useCases.retry(current.session.sessionID) }) { loadAfterRetry(current.session.sessionID) } })
        return error?.let { ApplicationResult.Failure(it) } ?: ApplicationResult.Success(Unit)
    }
    suspend fun saveSet(exercise: SessionExerciseID, target: TrainingSetID?, input: TrainingSetInput): ApplicationResult<Unit> = mutate {
        val now = clock.now()
        it.copy(session = if (target != null) it.session.editingSet(target, input, now) else {
            val id = ids.newTrainingSetID()
            it.session.addingSet(exercise, id, input, now).confirmingSet(id, now)
        })
    }
    suspend fun removeExercise(id: SessionExerciseID, confirmed: Boolean): ApplicationResult<Unit> = mutate { original ->
        val removed = original.session.removingExercise(id, confirmed, clock.now())
        val order = original.session.exercises.associate { it.sessionExerciseID to it.orderIndex }
        original.copy(session = removed.copy(exercises = removed.exercises.map { it.copy(orderIndex = order.getValue(it.sessionExerciseID)) }))
    }
    suspend fun deleteSet(set: TrainingSet) {
        val result = mutate { it.copy(session = it.session.deletingSet(set.trainingSetID, clock.now())) }
        if (result is ApplicationResult.Success) { deleted = set; deletedIndex = set.orderIndex.toInt() }
    }
    suspend fun restoreSet() {
        val set = deleted ?: return
        if (mutate { it.copy(session = it.session.restoringSet(set, deletedIndex, clock.now())) } is ApplicationResult.Success) deleted = null
    }
}
