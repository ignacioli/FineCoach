package com.ignacioli.finecoach.core.domain.training

import com.ignacioli.finecoach.core.domain.common.BodyPart
import com.ignacioli.finecoach.core.domain.common.NormalizedName
import com.ignacioli.finecoach.core.domain.common.SessionExerciseID
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.SessionState
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.ValidatedText
import java.time.Instant

data class SessionNotes(
    val privateCoachNote: ValidatedText?,
    val studentFacingSummary: ValidatedText?,
    val actionPrivateNotes: Map<SessionExerciseID, ValidatedText>,
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
    val studentDisplayName: NormalizedName,
    val startedAtUTC: Instant,
    val completedAtUTC: Instant,
    val trainingFocus: Set<BodyPart>,
    val notes: SessionNotes,
    val exercises: List<SessionExercise>,
    val statistics: SessionStatistics,
    val revision: ULong,
) {
    companion object {
        fun make(from: Session, studentDisplayName: NormalizedName): CompletedSession {
            if (from.state != SessionState.completed || from.completedAtUTC == null) {
                fail(DomainError.invalidState)
            }
            return CompletedSession(
                sessionID = from.sessionID,
                studentID = from.studentID,
                studentDisplayName = studentDisplayName,
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
