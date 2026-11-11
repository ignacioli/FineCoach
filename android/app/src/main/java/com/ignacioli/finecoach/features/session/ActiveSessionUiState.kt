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
        /** Sections move as blocks; members move only inside their section. */
        internal fun sessionShiftAxis(content: SessionContentRecord, key: String, delta: Int): List<SessionSectionAxisItem> {
            val blocks = (content.sections.map { section -> section.orderIndex to
                (listOf<SessionSectionAxisItem>(SessionSectionAxisItem.Section(section.sectionID)) + content.exercises
                    .filter { it.sectionID == section.sectionID }.sortedBy { it.orderIndex }.map { SessionSectionAxisItem.Exercise(it.sessionExerciseID.value) }) } +
                content.exercises.filter { it.sectionID == null }.map { it.orderIndex to listOf<SessionSectionAxisItem>(SessionSectionAxisItem.Exercise(it.sessionExerciseID.value)) })
                .sortedBy { it.first }.map { it.second.toMutableList() }.toMutableList()
            val row = content.exercises.firstOrNull { it.sessionExerciseID.value == key }
            if (row?.sectionID != null) {
                val block = blocks.first { it.any { item -> item is SessionSectionAxisItem.Exercise && item.id == key } }
                val index = block.indexOfFirst { it is SessionSectionAxisItem.Exercise && it.id == key }
                if (index + delta in 1 until block.size) java.util.Collections.swap(block, index, index + delta)
            } else {
                val index = blocks.indexOfFirst { block -> when (val item = block.first()) {
                    is SessionSectionAxisItem.Section -> item.id.value == key
                    is SessionSectionAxisItem.Exercise -> item.id == key
                } }
                if (index >= 0 && index + delta in blocks.indices) java.util.Collections.swap(blocks, index, index + delta)
            }
            return blocks.flatten()
        }
        internal fun recordedSideWeight(left: String, right: String, assisted: Boolean): String {
            val l = left.trim().toBigDecimalOrNull() ?: return ""
            val r = right.trim().toBigDecimalOrNull() ?: return ""
            return (if (assisted) minOf(l, r) else maxOf(l, r)).stripTrailingZeros().toPlainString()
        }

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
    var undoableSetID by mutableStateOf<TrainingSetID?>(null); private set
    fun expireRecentUndo(id: TrainingSetID?) { if (undoableSetID == id) undoableSetID = null }
    var entryPrefill by mutableStateOf<TrainingSetRecord?>(null); private set
    var entryPrefillVersion by mutableIntStateOf(0); private set
    suspend fun undoRecentSet() {
        val id = undoableSetID ?: return
        val set = content?.exercises?.flatMap { it.sets }?.firstOrNull { it.trainingSetID == id } ?: return
        if (mutate { it.copy(session = it.session.deletingSet(id, clock.now())) } is ApplicationResult.Success) {
            content?.session?.sessionID?.let(rests::clear)
            entryPrefill = set
            entryPrefillVersion++
        }
    }
    val previous = mutableStateMapOf<SessionExerciseID, TrainingSetRecord>()
    val previousCounts = mutableStateMapOf<SessionExerciseID, Int>()

    suspend fun load(id: SessionID) = perform({ useCases.load(id) }) { loaded ->
        content = loaded
        if (loaded == null) error = ApplicationError(ApplicationErrorCode.notFound)
        else loadPrevious(loaded)
    }
    private suspend fun loadPrevious(current: SessionContentRecord) {
        previous.clear()
        previousCounts.clear()
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
                                old.exercises.firstOrNull { it.recordModeSnapshot == exercise.recordModeSnapshot &&
                                    it.sourceID == exercise.sourceID && (exercise.sourceID != null || it.displayNameSnapshot == exercise.displayNameSnapshot) &&
                                    it.sets.any { set -> set.state == SetRecordingState.completed } }
                                    ?.sets?.filter { it.state == SetRecordingState.completed }
                                    ?.let { previous[exercise.sessionExerciseID] = it.first(); previousCounts[exercise.sessionExerciseID] = it.size }
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
        val newlyCompleted = value.exercises.flatMap { it.sets }.lastOrNull { it.state == SetRecordingState.completed && it.trainingSetID !in completed }
        if (newlyCompleted != null) { undoableSetID = newlyCompleted.trainingSetID; rests.start(value.session.sessionID) }
        else if (value.exercises.flatMap { it.sets }.none { it.trainingSetID == undoableSetID && it.state == SetRecordingState.completed }) undoableSetID = null
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

    suspend fun studentDisplayName(students: StudentRepositoryPort?, studentID: StudentID): String? =
        when (val result = students?.find(studentID)) {
            is ApplicationResult.Success -> result.value?.displayName.orEmpty()
            is ApplicationResult.Failure -> "学员信息暂不可用"
            null -> null
        }

    fun keyboardHidden(id: SessionID) {
        if (rests.end(id) != null && rests.remaining(id) == 0L) rests.clear(id)
    }

    suspend fun confirmSet(id: TrainingSetID): ApplicationResult<Unit> = mutate {
        it.copy(session = it.session.confirmingSet(id, clock.now()))
    }

    suspend fun saveSection(id: SectionID?, name: String): ApplicationResult<Unit> = mutate { original ->
        id?.let { original.renamingSection(it, name, clock.now()) }
            ?: original.addingSection(ids.newSectionID(), name, clock.now())
    }

    suspend fun deleteSection(id: SectionID, moveExercises: Boolean): ApplicationResult<Unit> = mutate {
        it.deletingSection(id, if (moveExercises) SessionSectionDeletionDisposition.MoveExercisesTo(null)
            else SessionSectionDeletionDisposition.DeleteWithExercises, clock.now())
    }

    suspend fun moveExercise(id: SessionExerciseID, target: SectionID?): ApplicationResult<Unit> = mutate {
        it.movingExercise(id, target, clock.now())
    }

    suspend fun saveSetEntry(exercise: SessionExerciseRecord, target: TrainingSetRecord?, initial: TrainingSetRecord?,
        sideEntry: Boolean, assisted: Boolean, values: SetEntryValues): ApplicationResult<Unit> {
        val (weight, reps, duration, distance, speed, resistance, left, right, split) = values
        val mode = exercise.recordModeSnapshot
        val input = TrainingSetInput(mode,
            weightValue = if (mode == RecordMode.weightReps) if (sideEntry && split) recordedSideWeight(left, right, assisted) else weight else null,
            repetitionCount = reps.takeIf { mode == RecordMode.weightReps || mode == RecordMode.reps },
            durationSeconds = if (mode == RecordMode.duration || mode == RecordMode.cardio) DurationTextParser.parseSeconds(duration) ?: duration else null,
            unit = initial?.unit ?: when (mode) { RecordMode.weightReps -> MeasurementUnit.kilograms; RecordMode.reps -> MeasurementUnit.repetitions; else -> MeasurementUnit.seconds },
            side = if (sideEntry) SetSide.bilateral else initial?.side ?: SetSide.none,
            leftValue = if (sideEntry) if (split) left else weight else left.takeIf { initial?.side == SetSide.left || initial?.side == SetSide.right },
            rightValue = if (sideEntry) if (split) right else weight else right.takeIf { initial?.side == SetSide.left || initial?.side == SetSide.right },
            distanceValue = distance.takeIf { mode == RecordMode.cardio }, speedValue = speed.takeIf { mode == RecordMode.cardio }, resistanceValue = resistance.takeIf { mode == RecordMode.cardio })
        return saveSet(exercise.sessionExerciseID, target?.trainingSetID, input)
    }

    suspend fun saveSet(exercise: SessionExerciseID, target: TrainingSetID?, input: TrainingSetInput): ApplicationResult<Unit> = mutate {
        val now = clock.now()
        it.copy(session = if (target != null) it.session.editingSet(target, input, now) else {
            val id = ids.newTrainingSetID()
            it.session.addingSet(exercise, id, input, now).confirmingSet(id, now)
        })
    }.also { result ->
        if (result is ApplicationResult.Success && target == null) entryPrefill = null
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
        val previousUndo = undoableSetID
        if (mutate { it.copy(session = it.session.restoringSet(set, deletedIndex, clock.now())) } is ApplicationResult.Success) {
            deleted = null
            // Restoring is not a new confirmation event. Keep any unrelated undo window.
            undoableSetID = previousUndo
        }
    }
}

internal fun sessionShiftAxis(content: SessionContentRecord, key: String, delta: Int): List<SessionSectionAxisItem> =
    ActiveSessionUiState.sessionShiftAxis(content, key, delta)

internal fun recordedSideWeight(left: String, right: String, assisted: Boolean): String =
    ActiveSessionUiState.recordedSideWeight(left, right, assisted)

data class SetEntryValues(
    val weight: String = "", val reps: String = "", val duration: String = "", val distance: String = "",
    val speed: String = "", val resistance: String = "", val left: String = "", val right: String = "",
    val split: Boolean = false,
)
