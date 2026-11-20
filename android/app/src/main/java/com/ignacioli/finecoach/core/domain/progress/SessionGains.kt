package com.ignacioli.finecoach.core.domain.progress

import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import java.time.*
import java.time.temporal.TemporalAdjusters

data class SessionGains(
    val recordHolderSetIDs: Set<TrainingSetID> = emptySet(),
    val strictRecordHolderSetIDs: Set<TrainingSetID> = emptySet(),
    val records: List<Record> = emptyList(),
    val rows: List<GainRow> = emptyList(),
    val milestoneSessionNumber: Int? = null,
    val attendanceStreakWeeks: Int? = null,
) {
    enum class RecordKind { highestWeight, longestDuration, mostReps }
    data class Record(val exerciseID: StableExerciseID, val displayName: String, val kind: RecordKind, val set: TrainingSet)
    data class GainRow(val exerciseID: StableExerciseID, val displayName: String, val isNewRecord: Boolean, val previous: TrainingSet, val current: TrainingSet)
    val progress get() = rows.filterNot { it.isNewRecord }
    val isEmpty get() = rows.isEmpty() && milestoneSessionNumber == null && attendanceStreakWeeks == null

    companion object {
        val completedOrder = compareBy<CompletedSession> { it.completedAtUTC }.thenBy { it.sessionID.value }
        fun mainMetric(mode: RecordMode) = when (mode) {
            RecordMode.weightReps -> RecordKind.highestWeight
            RecordMode.reps -> RecordKind.mostReps
            RecordMode.duration, RecordMode.cardio -> RecordKind.longestDuration
        }
        fun metricValue(set: TrainingSet, kind: RecordKind): DecimalValue? = when (kind) {
            RecordKind.highestWeight -> set.weightValue
            RecordKind.mostReps -> set.repetitionCount
            RecordKind.longestDuration -> set.durationSeconds
        }
        fun isBetter(candidate: DecimalValue, current: DecimalValue, kind: RecordKind, assisted: Boolean = false): Boolean =
            if (kind == RecordKind.highestWeight && assisted) candidate < current else candidate > current

        fun bestMetricValue(sets: List<TrainingSet>, kind: RecordKind, assisted: Boolean = false): DecimalValue? =
            sets.mapNotNull { metricValue(it, kind) }.reduceOrNull { best, value -> if (isBetter(value, best, kind, assisted)) value else best }

        fun bestSet(sets: List<TrainingSet>, kind: RecordKind, assisted: Boolean = false): TrainingSet? =
            sets.filter { metricValue(it, kind) != null }.reduceOrNull { best, candidate ->
                val a = metricValue(candidate, kind)!!; val b = metricValue(best, kind)!!
                if (isBetter(a, b, kind, assisted) || (kind == RecordKind.highestWeight && a.compareTo(b) == 0 &&
                    (candidate.repetitionCount ?: DecimalValue.ZERO) > (best.repetitionCount ?: DecimalValue.ZERO))) candidate else best
            }

        fun improved(previous: TrainingSet, current: TrainingSet, kind: RecordKind, assisted: Boolean = false): Boolean {
            val p = metricValue(previous, kind) ?: return false
            val c = metricValue(current, kind) ?: return false
            if (kind != RecordKind.highestWeight) return c > p
            val pr = previous.repetitionCount ?: DecimalValue.ZERO; val cr = current.repetitionCount ?: DecimalValue.ZERO
            return (isBetter(c, p, kind, assisted) && cr >= pr) || (cr > pr && !isBetter(p, c, kind, assisted))
        }

        fun evaluate(current: CompletedSession, history: List<CompletedSession>, zone: ZoneId, assistedExerciseIDs: Set<StableExerciseID> = emptySet()): SessionGains =
            evaluate(current.sessionID, current.studentID, current.completedAtUTC, current.exercises, history, zone, assistedExerciseIDs, current.completedAtUTC)

        fun evaluate(current: Session, history: List<CompletedSession>, zone: ZoneId, assistedExerciseIDs: Set<StableExerciseID> = emptySet()): SessionGains =
            evaluate(current.sessionID, current.studentID, current.completedAtUTC ?: Instant.MAX, current.exercises, history, zone, assistedExerciseIDs, current.completedAtUTC)

        private fun evaluate(id: SessionID, studentID: StudentID, at: Instant, exercises: List<SessionExercise>, history: List<CompletedSession>, zone: ZoneId, assisted: Set<StableExerciseID>, attendanceDate: Instant?): SessionGains {
            val baseline = history.filter { it.studentID == studentID && it.sessionID != id &&
                (it.completedAtUTC < at || (it.completedAtUTC == at && it.sessionID.value < id.value)) }.sortedWith(completedOrder)
            val holders = linkedSetOf<TrainingSetID>(); val strict = linkedSetOf<TrainingSetID>()
            val records = mutableListOf<Record>(); val rows = mutableListOf<GainRow>()
            val ordered = exercises.sortedBy { it.orderIndex }
            val seen = mutableSetOf<Pair<StableExerciseID, RecordMode>>()
            for (exercise in ordered) {
                val source = exercise.sourceID ?: continue
                val key = source to exercise.recordModeSnapshot
                if (!seen.add(key)) continue
                fun matching(e: SessionExercise) = e.sourceID == source && e.recordModeSnapshot == key.second
                val historical = baseline.flatMap { it.exercises }.filter(::matching).flatMap { it.sets }.filter { it.contributesToStatistics }
                if (historical.isEmpty()) continue
                val kind = mainMetric(key.second); val reverse = source in assisted
                val sets = ordered.filter(::matching).flatMap { it.sets }.sortedBy { it.orderIndex }.filter { it.contributesToStatistics }
                val best = bestSet(sets, kind, reverse) ?: continue
                val metric = metricValue(best, kind)!!
                val old = bestMetricValue(historical, kind, reverse)
                val record = old != null && isBetter(metric, old, kind, reverse)
                if (record) {
                    holders += best.trainingSetID
                    if (sets.all { it.trainingSetID == best.trainingSetID || metricValue(it, kind)?.let { v -> isBetter(metric, v, kind, reverse) } != false }) strict += best.trainingSetID
                    records += Record(source, exercise.displayNameSnapshot.value, kind, best)
                }
                val previousSets = baseline.asReversed().firstNotNullOfOrNull { s ->
                    s.exercises.filter(::matching).flatMap { it.sets }.filter { it.contributesToStatistics }.takeIf { it.isNotEmpty() }
                } ?: continue
                val previous = bestSet(previousSets, kind, reverse) ?: continue
                if (record || improved(previous, best, kind, reverse)) rows += GainRow(source, exercise.displayNameSnapshot.value, record, previous, best)
            }
            val number = baseline.size + 1
            return SessionGains(holders, strict, records, rows,
                number.takeIf { it in setOf(10, 25, 50, 100) || (it > 100 && it % 50 == 0) },
                attendanceDate?.let { attendanceMilestone(it, baseline, zone) })
        }
        private fun attendanceMilestone(at: Instant, baseline: List<CompletedSession>, zone: ZoneId): Int? {
            fun week(date: Instant) = date.atZone(zone).toLocalDate().with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
            val current = week(at); val counts = baseline.groupingBy { week(it.completedAtUTC) }.eachCount()
            if (counts[current] != 1) return null
            var weeks = 1; var cursor = current.minusWeeks(1)
            while ((counts[cursor] ?: 0) >= 2) { weeks++; cursor = cursor.minusWeeks(1) }
            return weeks.takeIf { it in setOf(4, 8, 12, 26, 52) || (it > 52 && (it - 52) % 26 == 0) }
        }
    }
}
