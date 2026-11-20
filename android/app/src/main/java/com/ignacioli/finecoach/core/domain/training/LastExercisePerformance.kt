package com.ignacioli.finecoach.core.domain.training

import com.ignacioli.finecoach.core.domain.common.RecordMode
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.SessionState
import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import java.time.Instant

data class LastExercisePerformance(
    val sessionID: SessionID,
    val completedAtUTC: Instant,
    val sets: List<TrainingSet>,
) {
    init {
        if (sets.isEmpty()) {
            fail(DomainError.invalidState, "sets")
        }
    }

    val firstSet: TrainingSet
        get() = sets.first()

    /**
     * iOS `session.lastReferenceFormat` = "上次 %@ · %d 组"
     * (`LastExercisePerformance.swift:18-24`, `Localizable.xcstrings` key `session.lastReferenceFormat`).
     */
    val referenceText: String
        get() = "上次 ${firstSet.displaySummary()} · ${sets.size} 组"
}

class LastExercisePerformanceLookup(
    sessions: List<Session>,
) {
    private data class LookupKey(
        val sourceID: StableExerciseID?,
        val name: String?,
        val recordMode: RecordMode,
    )

    private val performances: Map<LookupKey, LastExercisePerformance>

    init {
        val newestFirst = sessions
            .asSequence()
            .filter { it.state == SessionState.completed && it.completedAtUTC != null }
            .sortedWith(compareByDescending<Session> { it.completedAtUTC }.thenByDescending { it.sessionID.value })
            .toList()

        val map = linkedMapOf<LookupKey, LastExercisePerformance>()
        for (session in newestFirst) {
            val completedAt = session.completedAtUTC ?: continue
            for (exercise in session.exercises) {
                val key = keyFor(exercise)
                if (map.containsKey(key)) {
                    continue
                }
                val completedSets = exercise.sets.filter { it.contributesToStatistics }
                if (completedSets.isEmpty()) {
                    continue
                }
                map[key] = LastExercisePerformance(
                    sessionID = session.sessionID,
                    completedAtUTC = completedAt,
                    sets = completedSets,
                )
            }
        }
        performances = map
    }

    fun performanceFor(exercise: SessionExercise): LastExercisePerformance? = performances[keyFor(exercise)]

    companion object {
        val empty = LastExercisePerformanceLookup(emptyList())

        private fun keyFor(exercise: SessionExercise): LookupKey {
            if (exercise.sourceID != null) {
                return LookupKey(
                    sourceID = exercise.sourceID,
                    name = null,
                    recordMode = exercise.recordModeSnapshot,
                )
            }
            return LookupKey(
                sourceID = null,
                name = exercise.displayNameSnapshot.value,
                recordMode = exercise.recordModeSnapshot,
            )
        }
    }
}
