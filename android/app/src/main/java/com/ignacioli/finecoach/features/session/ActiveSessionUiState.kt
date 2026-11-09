package com.ignacioli.finecoach.features.session

import androidx.compose.runtime.*
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.features.exercises.*

class ActiveSessionUiState(
    val useCases: ActiveSessionUseCases, val clock: AppClock, val ids: StableIDGenerator,
    private val sessions: SessionRepositoryPort, private val history: HistoryRepositoryPort,
    private val exerciseUseCases: ExerciseUseCases,
) {
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
    suspend fun <T> perform(action: suspend () -> ApplicationResult<T>, success: suspend (T) -> Unit = {}) {
        if (busy) return
        busy = true
        try { when (val result = action()) {
            is ApplicationResult.Failure -> error = result.error
            is ApplicationResult.Success -> { error = null; success(result.value) }
        } } finally { busy = false }
    }
    suspend fun mutate(change: (SectionedSession) -> SectionedSession): ApplicationResult<Unit> {
        val current = content ?: return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.notFound))
        if (busy) return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidState))
        var outcome: ApplicationResult<Unit> = ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidState))
        perform({ useCases.mutate(current.session.sessionID, current.session.revision, change) }) {
            content = it; outcome = ApplicationResult.Success(Unit)
        }
        return error?.let { ApplicationResult.Failure(it) } ?: outcome
    }
    suspend fun addExercise(selection: ExerciseSelection): ApplicationResult<Unit> {
        val current = content ?: return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.notFound))
        val id = ids.newSessionExerciseID()
        var result: ApplicationResult<Unit> = ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidState))
        perform({
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
        return error?.let { ApplicationResult.Failure(it) } ?: result
    }
    fun accept(value: SessionContentRecord) { content = value }
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
