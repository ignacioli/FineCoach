package com.ignacioli.finecoach.core.domain.training

import com.ignacioli.finecoach.core.domain.common.BodyPart
import com.ignacioli.finecoach.core.domain.common.ExerciseLifecycle
import com.ignacioli.finecoach.core.domain.common.ExerciseSourceKind
import com.ignacioli.finecoach.core.domain.common.SessionExerciseID
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.SessionState
import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.exercise.ExerciseLibraryEntry
import java.time.Instant

data class SessionNotes(
    val privateCoachNote: String?,
    val studentFacingSummary: String?,
    val actionPrivateNotes: Map<SessionExerciseID, String>,
)

data class SessionStatistics(
    val completedSetCount: Int,
    val displayedDurationSeconds: DecimalValue,
    val ordinaryTrainingVolume: DecimalValue?,
) {
    companion object {
        fun make(from: Session): SessionStatistics {
            var volume: DecimalValue? = null
            for (trainingSet in from.statisticsSets) {
                val contribution = trainingSet.ordinaryVolumeContribution() ?: continue
                volume = if (volume == null) {
                    contribution
                } else {
                    volume.adding(contribution)
                }
            }
            return SessionStatistics(
                completedSetCount = from.completedSetCount,
                displayedDurationSeconds = from.displayedDurationSeconds,
                ordinaryTrainingVolume = volume,
            )
        }
    }
}

data class CompletedSession(
    val sessionID: SessionID,
    val studentID: StudentID,
    val studentDisplayName: String,
    val startedAtUTC: Instant,
    val completedAtUTC: Instant,
    val trainingFocus: Set<BodyPart>,
    val notes: SessionNotes,
    val exercises: List<SessionExercise>,
    val statistics: SessionStatistics,
    val revision: ULong,
) {
    companion object {
        fun make(from: Session, studentDisplayName: String): CompletedSession {
            if (from.state != SessionState.completed || from.completedAtUTC == null) {
                fail(DomainError.invalidState)
            }
            return CompletedSession(
                sessionID = from.sessionID,
                studentID = from.studentID,
                studentDisplayName = requiredText(studentDisplayName, "studentDisplayName"),
                startedAtUTC = from.startedAtUTC,
                completedAtUTC = from.completedAtUTC,
                trainingFocus = from.trainingFocus,
                notes = from.sessionNotes,
                exercises = from.exercises,
                statistics = from.statistics,
                revision = from.revision.value,
            )
        }

        fun mostRecent(sessions: List<CompletedSession>): CompletedSession? =
            sessions.maxByOrNull { it.completedAtUTC }
    }
}

object RecentExerciseSelection {
    fun entries(
        sessions: List<CompletedSession>,
        studentID: StudentID? = null,
        availableEntries: List<ExerciseLibraryEntry>,
        limit: Int = 5,
    ): List<ExerciseLibraryEntry> {
        if (limit <= 0) {
            return emptyList()
        }

        val availableByID = availableEntries
            .filter { entry ->
                entry.item.lifecycle == ExerciseLifecycle.active &&
                    !entry.item.isRetired &&
                    entry.preference?.isHidden != true
            }
            .associateBy { it.exerciseID }

        if (availableByID.isEmpty()) {
            return emptyList()
        }

        val scoped = sessions
            .asSequence()
            .filter { studentID == null || it.studentID == studentID }
            .sortedByDescending { it.completedAtUTC }
            .toList()

        val seen = mutableSetOf<StableExerciseID>()
        val result = ArrayList<ExerciseLibraryEntry>(minOf(limit, availableByID.size))
        for (session in scoped) {
            for (exercise in session.exercises) {
                if (exercise.sourceKind == ExerciseSourceKind.sessionOnly) {
                    continue
                }
                val sourceID = exercise.sourceID ?: continue
                if (!seen.add(sourceID)) {
                    continue
                }
                val entry = availableByID[sourceID] ?: continue
                result += entry
                if (result.size == limit) {
                    return result
                }
            }
        }
        return result
    }
}
