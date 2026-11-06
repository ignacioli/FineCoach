package com.ignacioli.finecoach.core.domain.training

import com.ignacioli.finecoach.core.domain.common.BodyPart
import com.ignacioli.finecoach.core.domain.common.ExerciseKind
import com.ignacioli.finecoach.core.domain.common.ExerciseLifecycle
import com.ignacioli.finecoach.core.domain.common.ExerciseSourceKind
import com.ignacioli.finecoach.core.domain.common.NormalizedName
import com.ignacioli.finecoach.core.domain.common.RecordMode
import com.ignacioli.finecoach.core.domain.common.Revision
import com.ignacioli.finecoach.core.domain.common.SectionID
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.SessionState
import com.ignacioli.finecoach.core.domain.common.SetRecordingState
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.TrainingSetID
import com.ignacioli.finecoach.core.domain.common.ValidatedText
import com.ignacioli.finecoach.core.domain.exercise.ExerciseCatalogItem
import java.time.Instant
import java.util.Locale

enum class SessionFinishGate {
    canComplete,
    abandonEmpty,
    unresolvedDrafts,
}

object ActiveSessionPointerKey {
    const val singleton: String = "active"

    fun student(studentID: StudentID): String = studentID.value.uppercase(Locale.ROOT)
}

data class Session(
    val sessionID: SessionID,
    val studentID: StudentID,
    val state: SessionState,
    val startedAtUTC: Instant,
    val lastCheckpointUTC: Instant,
    val elapsedSeconds: DecimalValue,
    val interruptionStartedAtUTC: Instant?,
    val durationNeedsReview: Boolean,
    val coachAdjustedDurationSeconds: DecimalValue?,
    val trainingFocus: Set<BodyPart>,
    val studentFacingSummary: ValidatedText?,
    val privateCoachNote: ValidatedText?,
    val revision: Revision,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
    val completedAtUTC: Instant?,
    val exercises: List<SessionExercise>,
) {
    val finishGate: SessionFinishGate
        get() = when {
            completedSetCount == 0 -> SessionFinishGate.abandonEmpty
            hasUnresolvedSets -> SessionFinishGate.unresolvedDrafts
            else -> SessionFinishGate.canComplete
        }

    val completedSetCount: Int
        get() = statisticsSets.size

    val displayedDurationSeconds: DecimalValue
        get() = coachAdjustedDurationSeconds ?: elapsedSeconds

    val statisticsSets: List<TrainingSet>
        get() = exercises.flatMap { it.sets }.filter { it.contributesToStatistics }

    val hasUnresolvedSets: Boolean
        get() = exercises.any { exercise -> exercise.sets.any { it.state != SetRecordingState.completed } }

    val sessionNotes: SessionNotes
        get() {
            val actionPrivateNotes = buildMap {
                for (exercise in exercises) {
                    val note = exercise.actionPrivateNote ?: continue
                    put(exercise.sessionExerciseID, note)
                }
            }
            return SessionNotes(
                privateCoachNote = privateCoachNote,
                studentFacingSummary = studentFacingSummary,
                actionPrivateNotes = actionPrivateNotes,
            )
        }

    val statistics: SessionStatistics
        get() = runCatching { SessionStatistics.make(this) }.getOrElse {
            SessionStatistics(
                completedSetCount = completedSetCount,
                displayedDurationSeconds = displayedDurationSeconds,
                ordinaryTrainingVolume = null,
            )
        }

    fun mergingTrainingFocus(additional: Set<BodyPart>, nowUTC: Instant): Session {
        ensureInProgress()
        if (additional.isEmpty()) {
            return this
        }
        return next(
            revision = revision.next(),
            updatedAtUTC = nowUTC,
            trainingFocus = trainingFocus + additional,
        )
    }

    fun addingSessionOnlyExercise(
        id: com.ignacioli.finecoach.core.domain.common.SessionExerciseID,
        displayName: String,
        recordMode: RecordMode,
        nowUTC: Instant,
    ): Session {
        ensureInProgress()
        val exercise = SessionExercise(
            sessionExerciseID = id,
            sessionID = sessionID,
            orderIndex = exercises.size.toUInt(),
            sourceKind = ExerciseSourceKind.sessionOnly,
            sourceID = null,
            displayNameSnapshot = parseDisplayName(displayName),
            recordModeSnapshot = recordMode,
            actionPrivateNote = null,
            sets = emptyList(),
        )
        return next(
            revision = revision.next(),
            updatedAtUTC = nowUTC,
            exercises = exercises + exercise,
        )
    }

    fun addingCatalogExercise(
        id: com.ignacioli.finecoach.core.domain.common.SessionExerciseID,
        item: ExerciseCatalogItem,
        nowUTC: Instant,
    ): Session {
        ensureInProgress()
        if (item.lifecycle != ExerciseLifecycle.active) {
            fail(DomainError.invalidState)
        }
        val sourceKind = if (item.kind == ExerciseKind.builtIn) {
            ExerciseSourceKind.builtIn
        } else {
            ExerciseSourceKind.custom
        }
        val exercise = SessionExercise(
            sessionExerciseID = id,
            sessionID = sessionID,
            orderIndex = exercises.size.toUInt(),
            sourceKind = sourceKind,
            sourceID = item.exerciseID,
            displayNameSnapshot = item.canonicalName,
            recordModeSnapshot = item.recordMode,
            actionPrivateNote = null,
            sets = emptyList(),
        )
        return next(
            revision = revision.next(),
            updatedAtUTC = nowUTC,
            exercises = exercises + exercise,
        )
    }

    fun appendingTemplateExercises(newExercises: List<SessionExercise>, nowUTC: Instant): Session {
        ensureInProgress()
        if (newExercises.any { it.sessionID != sessionID }) {
            fail(DomainError.invalidState)
        }
        return next(
            revision = revision.next(),
            updatedAtUTC = nowUTC,
            exercises = exercises + newExercises,
        )
    }

    fun reorderingExercises(ids: List<com.ignacioli.finecoach.core.domain.common.SessionExerciseID>, nowUTC: Instant): Session {
        ensureInProgress()
        if (ids.size != exercises.size || ids.toSet().size != ids.size) {
            fail(DomainError.invalidState)
        }
        val byID = exercises.associateBy { it.sessionExerciseID }
        val reordered = ids.map { id -> byID[id] ?: fail(DomainError.invalidState) }
        val relinked = reordered.mapIndexed { index, exercise -> exercise.relocating(orderIndex = index.toUInt()) }
        return next(
            revision = revision.next(),
            updatedAtUTC = nowUTC,
            exercises = relinked,
        )
    }

    fun updatingExerciseSection(
        exerciseID: com.ignacioli.finecoach.core.domain.common.SessionExerciseID,
        sectionID: SectionID?,
        nowUTC: Instant,
    ): Session {
        ensureInProgress()
        val (index, exercise) = requireExercise(exerciseID)
        val relocated = exercise.relocating(orderIndex = exercise.orderIndex, sectionID = sectionID)
        return replacingExercise(index = index, updated = relocated, nowUTC = nowUTC)
    }

    fun removingExercise(
        exerciseID: com.ignacioli.finecoach.core.domain.common.SessionExerciseID,
        confirmedIfCompleted: Boolean,
        nowUTC: Instant,
    ): Session {
        ensureInProgress()
        val exercise = exercises.firstOrNull { it.sessionExerciseID == exerciseID } ?: fail(DomainError.notFound)
        if (exercise.hasCompletedSet && !confirmedIfCompleted) {
            fail(DomainError.invalidState)
        }
        val remaining = exercises
            .filter { it.sessionExerciseID != exerciseID }
            .mapIndexed { index, item -> item.relocating(orderIndex = index.toUInt()) }
        return next(
            revision = revision.next(),
            updatedAtUTC = nowUTC,
            exercises = remaining,
        )
    }

    fun addingSet(
        exerciseID: com.ignacioli.finecoach.core.domain.common.SessionExerciseID,
        setID: TrainingSetID,
        input: TrainingSetInput,
        nowUTC: Instant,
    ): Session {
        ensureInProgress()
        val (index, exercise) = requireExercise(exerciseID)
        if (input.recordMode != exercise.recordModeSnapshot) {
            fail(DomainError.invalidMode)
        }
        val trainingSet = TrainingSet.makeDraft(
            id = setID,
            sessionExerciseID = exercise.sessionExerciseID,
            orderIndex = exercise.sets.size.toUInt(),
            input = input,
            nowUTC = nowUTC,
        )
        return replacingExercise(
            index = index,
            updated = exercise.replacingSets(exercise.sets + trainingSet),
            nowUTC = nowUTC,
        )
    }

    fun editingSet(
        setID: TrainingSetID,
        input: TrainingSetInput,
        nowUTC: Instant,
    ): Session {
        return mutateSet(setID = setID, nowUTC = nowUTC) { trainingSet ->
            if (input.recordMode != trainingSet.recordMode) {
                fail(DomainError.invalidMode)
            }
            val updated = trainingSet.updating(input = input, nowUTC = nowUTC)
            if (trainingSet.state != SetRecordingState.completed) {
                updated
            } else {
                updated.confirmed(nowUTC = nowUTC, completedAtUTC = trainingSet.completedAtUTC ?: nowUTC)
            }
        }
    }

    fun confirmingSet(setID: TrainingSetID, nowUTC: Instant): Session =
        mutateSet(setID = setID, nowUTC = nowUTC) { it.confirmed(nowUTC = nowUTC) }

    fun copyingSet(
        sourceSetID: TrainingSetID,
        newSetID: TrainingSetID,
        nowUTC: Instant,
    ): Session {
        ensureInProgress()
        val (index, exercise, source) = requireSet(sourceSetID)
        val copy = source.copiedAsPending(id = newSetID, orderIndex = exercise.sets.size.toUInt(), nowUTC = nowUTC)
        return replacingExercise(index = index, updated = exercise.replacingSets(exercise.sets + copy), nowUTC = nowUTC)
    }

    fun undoingSet(setID: TrainingSetID, nowUTC: Instant): Session =
        mutateSet(setID = setID, nowUTC = nowUTC) { it.undone(nowUTC = nowUTC) }

    fun deletingSet(setID: TrainingSetID, nowUTC: Instant): Session {
        ensureInProgress()
        val (index, exercise, _) = requireSet(setID)
        val remaining = exercise.sets.filter { it.trainingSetID != setID }
        return replacingExercise(index = index, updated = exercise.replacingSets(remaining), nowUTC = nowUTC)
    }

    fun restoringSet(set: TrainingSet, originalIndex: Int, nowUTC: Instant): Session {
        ensureInProgress()
        val (index, exercise) = requireExercise(set.sessionExerciseID)
        if (exercise.sets.any { it.trainingSetID == set.trainingSetID }) {
            return this
        }
        val insertionIndex = originalIndex.coerceIn(0, exercise.sets.size)
        val mutable = exercise.sets.toMutableList()
        mutable.add(insertionIndex, set)
        return replacingExercise(index = index, updated = exercise.replacingSets(mutable), nowUTC = nowUTC)
    }

    fun discardingUnresolvedSets(nowUTC: Instant): Session {
        ensureInProgress()
        val cleaned = exercises.map { exercise ->
            exercise.replacingSets(exercise.sets.filter { it.contributesToStatistics })
        }
        return next(revision = revision.next(), updatedAtUTC = nowUTC, exercises = cleaned)
    }

    fun applyingCoachAdjustedDuration(seconds: DecimalValue, nowUTC: Instant): Session {
        ensureInProgress()
        if (!seconds.isInteger || seconds.decimal < java.math.BigDecimal.ZERO) {
            fail(DomainError.invalidNumber)
        }
        return next(
            revision = revision.next(),
            updatedAtUTC = nowUTC,
            durationNeedsReview = false,
            coachAdjustedDurationSeconds = seconds,
        )
    }

    fun finished(nowUTC: Instant): Session {
        ensureInProgress()
        if (finishGate != SessionFinishGate.canComplete) {
            fail(DomainError.invalidState)
        }
        if (durationNeedsReview && coachAdjustedDurationSeconds == null) {
            fail(DomainError.invalidState)
        }
        return next(
            state = SessionState.completed,
            revision = revision.next(),
            updatedAtUTC = nowUTC,
            completedAtUTC = nowUTC,
        )
    }

    fun abandoned(nowUTC: Instant): Session {
        ensureInProgress()
        if (finishGate != SessionFinishGate.abandonEmpty) {
            fail(DomainError.invalidState)
        }
        return next(
            state = SessionState.abandonedEmpty,
            revision = revision.next(),
            updatedAtUTC = nowUTC,
            completedAtUTC = null,
        )
    }

    fun updatingTiming(
        elapsedSeconds: DecimalValue,
        lastCheckpointUTC: Instant,
        interruptionStartedAtUTC: Instant?,
        durationNeedsReview: Boolean,
        nowUTC: Instant,
    ): Session {
        return next(
            revision = revision.next(),
            updatedAtUTC = nowUTC,
            elapsedSeconds = elapsedSeconds,
            lastCheckpointUTC = lastCheckpointUTC,
            interruptionStartedAtUTC = interruptionStartedAtUTC,
            durationNeedsReview = durationNeedsReview,
        )
    }

    fun updatingTrainingFocus(value: Set<BodyPart>, nowUTC: Instant): Session {
        ensureCompleted()
        return next(revision = revision.next(), updatedAtUTC = nowUTC, trainingFocus = value)
    }

    fun updatingStudentFacingSummary(value: ValidatedText?, nowUTC: Instant): Session {
        ensureCompleted()
        return next(revision = revision.next(), updatedAtUTC = nowUTC, studentFacingSummary = value)
    }

    fun updatingPrivateCoachNote(value: ValidatedText?, nowUTC: Instant): Session {
        ensureCompleted()
        return next(revision = revision.next(), updatedAtUTC = nowUTC, privateCoachNote = value)
    }

    fun updatingActionPrivateNote(
        exerciseID: com.ignacioli.finecoach.core.domain.common.SessionExerciseID,
        note: ValidatedText?,
        nowUTC: Instant,
    ): Session {
        ensureCompleted()
        val (index, exercise) = requireExercise(exerciseID)
        return replacingExercise(index = index, updated = exercise.replacingActionPrivateNote(note), nowUTC = nowUTC)
    }

    fun updatingCompletedSummary(
        trainingFocus: Set<BodyPart>,
        privateCoachNote: ValidatedText?,
        studentFacingSummary: ValidatedText?,
        nowUTC: Instant,
    ): Session {
        ensureCompleted()
        return next(
            revision = revision.next(),
            updatedAtUTC = nowUTC,
            trainingFocus = trainingFocus,
            privateCoachNote = privateCoachNote,
            studentFacingSummary = studentFacingSummary,
        )
    }

    fun editingCompletedSet(setID: TrainingSetID, input: TrainingSetInput, nowUTC: Instant): Session {
        ensureCompleted()
        val (index, exercise, source) = requireSet(setID)
        val updated = source.updating(input = input, nowUTC = nowUTC).confirmed(nowUTC = nowUTC)
        val sets = exercise.sets.map { if (it.trainingSetID == setID) updated else it }
        return replacingExercise(index = index, updated = exercise.replacingSets(sets), nowUTC = nowUTC)
    }

    private fun ensureInProgress() {
        if (state != SessionState.inProgress) {
            fail(DomainError.invalidState)
        }
    }

    private fun ensureCompleted() {
        if (state != SessionState.completed) {
            fail(DomainError.invalidState)
        }
    }

    private fun requireExercise(
        exerciseID: com.ignacioli.finecoach.core.domain.common.SessionExerciseID,
    ): Pair<Int, SessionExercise> {
        val index = exercises.indexOfFirst { it.sessionExerciseID == exerciseID }
        if (index < 0) {
            fail(DomainError.notFound)
        }
        return index to exercises[index]
    }

    private fun requireSet(setID: TrainingSetID): Triple<Int, SessionExercise, TrainingSet> {
        exercises.forEachIndexed { index, exercise ->
            val found = exercise.sets.firstOrNull { it.trainingSetID == setID }
            if (found != null) {
                return Triple(index, exercise, found)
            }
        }
        fail(DomainError.notFound)
    }

    private fun mutateSet(
        setID: TrainingSetID,
        nowUTC: Instant,
        transform: (TrainingSet) -> TrainingSet,
    ): Session {
        ensureInProgress()
        val (index, exercise, source) = requireSet(setID)
        val updated = transform(source)
        val sets = exercise.sets.map { if (it.trainingSetID == setID) updated else it }
        return replacingExercise(index = index, updated = exercise.replacingSets(sets), nowUTC = nowUTC)
    }

    private fun replacingExercise(index: Int, updated: SessionExercise, nowUTC: Instant): Session {
        val mutable = exercises.toMutableList()
        mutable[index] = updated
        return next(revision = revision.next(), updatedAtUTC = nowUTC, exercises = mutable)
    }

    private fun next(
        revision: Revision,
        updatedAtUTC: Instant,
        state: SessionState = this.state,
        exercises: List<SessionExercise> = this.exercises,
        elapsedSeconds: DecimalValue = this.elapsedSeconds,
        lastCheckpointUTC: Instant = updatedAtUTC,
        interruptionStartedAtUTC: Instant? = this.interruptionStartedAtUTC,
        durationNeedsReview: Boolean = this.durationNeedsReview,
        coachAdjustedDurationSeconds: DecimalValue? = this.coachAdjustedDurationSeconds,
        trainingFocus: Set<BodyPart> = this.trainingFocus,
        studentFacingSummary: ValidatedText? = this.studentFacingSummary,
        privateCoachNote: ValidatedText? = this.privateCoachNote,
        completedAtUTC: Instant? = this.completedAtUTC,
    ): Session {
        return copy(
            state = state,
            exercises = exercises,
            elapsedSeconds = elapsedSeconds,
            lastCheckpointUTC = lastCheckpointUTC,
            interruptionStartedAtUTC = interruptionStartedAtUTC,
            durationNeedsReview = durationNeedsReview,
            coachAdjustedDurationSeconds = coachAdjustedDurationSeconds,
            trainingFocus = trainingFocus,
            studentFacingSummary = studentFacingSummary,
            privateCoachNote = privateCoachNote,
            revision = revision,
            updatedAtUTC = updatedAtUTC,
            completedAtUTC = completedAtUTC,
        )
    }

    companion object {
        private fun parseDisplayName(raw: String): NormalizedName = parseDomainName(raw, "displayName")

        fun start(
            id: SessionID,
            studentID: StudentID,
            trainingFocus: Set<BodyPart> = emptySet(),
            nowUTC: Instant,
        ): Session {
            return Session(
                sessionID = id,
                studentID = studentID,
                state = SessionState.inProgress,
                startedAtUTC = nowUTC,
                lastCheckpointUTC = nowUTC,
                elapsedSeconds = DecimalValue.ZERO,
                interruptionStartedAtUTC = null,
                durationNeedsReview = false,
                coachAdjustedDurationSeconds = null,
                trainingFocus = trainingFocus,
                studentFacingSummary = null,
                privateCoachNote = null,
                revision = Revision(1uL),
                createdAtUTC = nowUTC,
                updatedAtUTC = nowUTC,
                completedAtUTC = null,
                exercises = emptyList(),
            )
        }
    }
}

private fun Revision.next(): Revision {
    if (value == ULong.MAX_VALUE) {
        fail(DomainError.invalidState, "revision")
    }
    return Revision(value + 1u)
}
