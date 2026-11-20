package com.ignacioli.finecoach.core.domain.progress

import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import java.time.Instant

object Comparison {
    enum class LoadDirection { increaseIsImprovement, decreaseIsImprovement }
    sealed interface SessionComparisonResult {
        data class Compatible(val detail: SessionComparisonDetail): SessionComparisonResult
        data object IncompatibleTrainingFocus: SessionComparisonResult
        data object DifferentStudent: SessionComparisonResult
    }
    data class SessionComparisonDetail(val sessionA: SessionID, val sessionB: SessionID,
        val exercisesOnlyInA: List<String>, val exercisesOnlyInB: List<String>,
        val totalSetCountA: Int, val totalSetCountB: Int,
        val totalRepCountA: DecimalValue?, val totalRepCountB: DecimalValue?,
        val totalDurationSecondsA: DecimalValue, val totalDurationSecondsB: DecimalValue,
        val trainingVolumeA: DecimalValue?, val trainingVolumeB: DecimalValue?)
    fun compareSessions(a: CompletedSession, b: CompletedSession): SessionComparisonResult {
        if (a.studentID != b.studentID) return SessionComparisonResult.DifferentStudent
        if (a.trainingFocus != b.trainingFocus) return SessionComparisonResult.IncompatibleTrainingFocus
        val namesA = a.exercises.map { it.displayNameSnapshot.value }.toSet(); val namesB = b.exercises.map { it.displayNameSnapshot.value }.toSet()
        fun sets(s: CompletedSession) = s.exercises.flatMap { it.sets }.filter { it.contributesToStatistics }
        val sa = sets(a); val sb = sets(b)
        return SessionComparisonResult.Compatible(SessionComparisonDetail(a.sessionID, b.sessionID,
            (namesA - namesB).sorted(), (namesB - namesA).sorted(), sa.size, sb.size,
            sum(sa.mapNotNull { it.repetitionCount }), sum(sb.mapNotNull { it.repetitionCount }),
            a.statistics.displayedDurationSeconds, b.statistics.displayedDurationSeconds,
            a.statistics.ordinaryTrainingVolume, b.statistics.ordinaryTrainingVolume))
    }
    data class SetTrendPoint(val sessionID: SessionID, val completedAtUTC: Instant, val recordMode: RecordMode,
        val maxWeight: DecimalValue?, val bestReps: DecimalValue?, val bestDurationSeconds: DecimalValue?,
        val bestDistance: DecimalValue?, val volume: DecimalValue?, val weightDelta: DecimalValue?, val asymmetry: DecimalValue?)
    enum class TrendSampleDensity { empty, single, sparse, sufficient;
        companion object { fun classify(points: List<SetTrendPoint>) = when(points.size) { 0 -> empty; 1 -> single; 2 -> sparse; else -> sufficient } }
    }
    /** Caller supplies a single student's completed snapshot, as in iOS. */
    fun exerciseTrend(exerciseID: StableExerciseID, recordMode: RecordMode, sessions: List<CompletedSession>, loadDirection: LoadDirection = LoadDirection.increaseIsImprovement): List<SetTrendPoint> {
        var previous: DecimalValue? = null
        return sessions.sortedWith(SessionGains.completedOrder).mapNotNull { s ->
            val sets = matching(s, exerciseID, recordMode)
            if (sets.isEmpty()) return@mapNotNull null
            val weights = sets.mapNotNull { it.weightValue }
            val weight = if (loadDirection == LoadDirection.decreaseIsImprovement) weights.minOrNull() else weights.maxOrNull()
            val delta = if (weight != null && previous != null) DecimalValue.fromBigDecimal(weight.decimal - previous!!.decimal) else null
            if (weight != null) previous = weight
            val sided = sets.firstOrNull { it.leftValue != null && it.rightValue != null }
            SetTrendPoint(s.sessionID, s.completedAtUTC, recordMode, weight, sets.mapNotNull { it.repetitionCount }.maxOrNull(),
                sets.mapNotNull { it.durationSeconds }.maxOrNull(), sets.mapNotNull { it.distanceValue }.maxOrNull(),
                sum(sets.mapNotNull { it.ordinaryVolumeContribution() }), delta,
                sided?.let { DecimalValue.fromBigDecimal(it.leftValue!!.decimal - it.rightValue!!.decimal) })
        }
    }
    data class ValueRecord(val sessionID: SessionID, val value: DecimalValue)
    data class RepsRecord(val sessionID: SessionID, val weight: DecimalValue, val reps: DecimalValue)
    data class PersonalRecordSet(val exerciseID: StableExerciseID, val highestWeight: ValueRecord?, val mostRepsAtWeight: RepsRecord?, val longestDuration: ValueRecord?, val longestDistance: ValueRecord?)
    fun personalRecords(exerciseID: StableExerciseID, recordMode: RecordMode, sessions: List<CompletedSession>, loadDirection: LoadDirection = LoadDirection.increaseIsImprovement): PersonalRecordSet {
        var weight: ValueRecord? = null; var reps: RepsRecord? = null; var duration: ValueRecord? = null; var distance: ValueRecord? = null
        var repsAt: Instant? = null; var durationAt: Instant? = null; var distanceAt: Instant? = null
        for (s in sessions) for (set in matching(s, exerciseID, recordMode)) {
            set.weightValue?.let { w ->
                if (weight == null || better(w, weight!!.value, loadDirection)) weight = ValueRecord(s.sessionID, w)
                set.repetitionCount?.let { r ->
                    val old = reps
                    if (old == null || better(w, old.weight, loadDirection) || (w.compareTo(old.weight) == 0 && (r > old.reps || (r.compareTo(old.reps) == 0 && s.completedAtUTC > (repsAt ?: Instant.MIN))))) {
                        reps = RepsRecord(s.sessionID, w, r); repsAt = s.completedAtUTC
                    }
                }
            }
            set.durationSeconds?.let { value ->
                if (duration == null || value > duration!!.value || (value.compareTo(duration!!.value) == 0 && s.completedAtUTC > (durationAt ?: Instant.MIN))) {
                    duration = ValueRecord(s.sessionID, value); durationAt = s.completedAtUTC
                }
            }
            if (recordMode == RecordMode.cardio) set.distanceValue?.let { value ->
                if (distance == null || value > distance!!.value || (value.compareTo(distance!!.value) == 0 && s.completedAtUTC > (distanceAt ?: Instant.MIN))) {
                    distance = ValueRecord(s.sessionID, value); distanceAt = s.completedAtUTC
                }
            }
        }
        return PersonalRecordSet(exerciseID, weight, reps, duration, distance)
    }
    private fun better(a: DecimalValue, b: DecimalValue, direction: LoadDirection) = if (direction == LoadDirection.decreaseIsImprovement) a < b else a > b
    private fun matching(s: CompletedSession, id: StableExerciseID, mode: RecordMode) = s.exercises.filter { it.sourceID == id && it.recordModeSnapshot == mode }.flatMap { it.sets }.filter { it.contributesToStatistics }
    private fun sum(values: List<DecimalValue>): DecimalValue? = values.reduceOrNull { a, b -> a.adding(b) }
}
