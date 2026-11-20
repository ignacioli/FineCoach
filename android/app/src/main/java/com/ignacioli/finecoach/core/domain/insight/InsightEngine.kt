package com.ignacioli.finecoach.core.domain.insight

import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.student.Student
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.core.domain.progress.*
import java.time.*
import java.time.temporal.ChronoUnit

data class Insight(
    val kind: Kind, val studentID: StudentID, val exerciseID: StableExerciseID? = null,
    val balance: Long? = null, val packageEndDate: LocalDate? = null, val daysUntilExpiry: Long? = null,
    val daysInactive: Long? = null, val hasNeverTrained: Boolean = false, val stagnantSessionCount: Int? = null,
    val baselineBest: DecimalValue? = null, val baselineMetric: Metric? = null,
) {
    enum class Kind { packageExhausted, packageExpired, packageLow, inactive, stagnant }
    enum class Metric { estimatedOneRepMax, highestWeight, lowestAssistance, mostReps, longestDuration }
    val snoozeKey: String get() = when (kind) {
        Kind.packageExhausted, Kind.packageExpired, Kind.packageLow -> "package:${studentID.value}"
        Kind.inactive -> "inactive:${studentID.value}"
        Kind.stagnant -> "stagnant:${studentID.value}:${exerciseID?.value}"
    }
}

object InsightEngine {
    data class PackageBalance(val balance: Long, val endDate: LocalDate?)
    data class Input(val students: List<Student>, val packages: Map<StudentID, PackageBalance> = emptyMap(),
        val appointments: List<Appointment> = emptyList(), val history: List<CompletedSession> = emptyList(),
        val snoozedKeys: Set<String> = emptySet(), val assistedExerciseIDs: Set<StableExerciseID> = emptySet())

    fun evaluate(input: Input, now: Instant, zone: ZoneId): List<Insight> {
        val today = now.atZone(zone).toLocalDate()
        val history = input.history.groupBy { it.studentID }
        val booked = input.appointments.filter { it.status == AppointmentStatus.scheduled && it.startInstant(zone) > now }.map { it.studentID }.toSet()
        val result = mutableListOf<Insight>()
        for (student in input.students.filter { it.lifecycle == StudentLifecycle.active }) {
            val id = student.studentID
            input.packages[id]?.let { p ->
                val days = p.endDate?.let { ChronoUnit.DAYS.between(today, it) }
                val kind = when {
                    p.balance <= 0 -> Insight.Kind.packageExhausted
                    days != null && days < 0 -> Insight.Kind.packageExpired
                    p.balance <= 2 || (days != null && days <= 7) -> Insight.Kind.packageLow
                    else -> null
                }
                if (kind != null) result += Insight(kind, id, balance = p.balance, packageEndDate = p.endDate, daysUntilExpiry = days)
            }
            val sessions = history[id].orEmpty()
            val last = sessions.maxOfOrNull { it.completedAtUTC }
            val days = ChronoUnit.DAYS.between((last ?: student.createdAtUTC).atZone(zone).toLocalDate(), today)
            if (days >= 14 && id !in booked) result += Insight(Insight.Kind.inactive, id, daysInactive = days, hasNeverTrained = last == null)
            result += stagnant(id, sessions, today, zone, input.assistedExerciseIDs)
        }
        return result.filterNot { it.snoozeKey in input.snoozedKeys }.sortedWith { a, b ->
            val rank = rank(a.kind).compareTo(rank(b.kind))
            if (rank != 0) rank else {
                val secondary = when (a.kind) {
                    Insight.Kind.packageExhausted, Insight.Kind.packageExpired, Insight.Kind.packageLow -> (a.balance ?: 0).compareTo(b.balance ?: 0)
                    Insight.Kind.inactive -> (b.daysInactive ?: 0).compareTo(a.daysInactive ?: 0)
                    else -> 0
                }
                if (secondary != 0) secondary else compareValuesBy(a, b, { it.studentID.value }, { it.exerciseID?.value.orEmpty() })
            }
        }
    }
    private fun rank(kind: Insight.Kind) = when(kind) {
        Insight.Kind.packageExhausted, Insight.Kind.packageExpired -> 0
        Insight.Kind.packageLow -> 1; Insight.Kind.inactive -> 2; Insight.Kind.stagnant -> 3
    }
    private data class Action(val id: StableExerciseID, val mode: RecordMode)
    private data class Point(val session: CompletedSession, val value: DecimalValue)
    private fun stagnant(student: StudentID, sessions: List<CompletedSession>, today: LocalDate, zone: ZoneId, assisted: Set<StableExerciseID>): List<Insight> {
        val ordered = sessions.sortedWith(SessionGains.completedOrder)
        val modes = linkedMapOf<StableExerciseID, RecordMode>()
        for (s in ordered) for (e in s.exercises) e.sourceID?.let { modes[it] = e.recordModeSnapshot }
        val points = mutableMapOf<Action, MutableList<Point>>()
        for (s in ordered) {
            val grouped = s.exercises.filter { it.sourceID != null && modes[it.sourceID] == it.recordModeSnapshot }.groupBy { Action(it.sourceID!!, it.recordModeSnapshot) }
            for ((a, exercises) in grouped) {
                val sets = exercises.flatMap { it.sets }.filter { it.contributesToStatistics }
                val value = if (a.id in EstimatedOneRepMax.exerciseIDs) {
                    sets.filter { it.recordMode == RecordMode.weightReps }.mapNotNull { set ->
                        val w = set.weightValue; val r = set.repetitionCount
                        if (w != null && r != null) EstimatedOneRepMax.value(w, r, a.id) else null
                    }.maxOrNull()
                } else SessionGains.bestMetricValue(sets, SessionGains.mainMetric(a.mode), a.id in assisted)
                if (value != null) points.getOrPut(a) { mutableListOf() } += Point(s, value)
            }
        }
        return points.mapNotNull { (action, values) ->
            if (values.size < 4) return@mapNotNull null
            val recent = values.takeLast(3)
            if (recent.any { ChronoUnit.DAYS.between(it.session.completedAtUTC.atZone(zone).toLocalDate(), today) !in 0L..28L }) return@mapNotNull null
            val estimated = action.id in EstimatedOneRepMax.exerciseIDs
            val kind = SessionGains.mainMetric(action.mode)
            val reverse = !estimated && action.id in assisted
            val baseline = values.dropLast(3).map { it.value }.reduce { best, v -> if (SessionGains.isBetter(v, best, kind, reverse)) v else best }
            if (recent.any { SessionGains.isBetter(it.value, baseline, kind, reverse) }) return@mapNotNull null
            val metric = if (estimated) Insight.Metric.estimatedOneRepMax else when (kind) {
                SessionGains.RecordKind.highestWeight -> if (reverse) Insight.Metric.lowestAssistance else Insight.Metric.highestWeight
                SessionGains.RecordKind.mostReps -> Insight.Metric.mostReps
                SessionGains.RecordKind.longestDuration -> Insight.Metric.longestDuration
            }
            Insight(Insight.Kind.stagnant, student, action.id, stagnantSessionCount = 3, baselineBest = baseline, baselineMetric = metric)
        }
    }
}
