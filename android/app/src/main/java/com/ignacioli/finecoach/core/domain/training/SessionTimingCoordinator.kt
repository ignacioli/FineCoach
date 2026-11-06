package com.ignacioli.finecoach.core.domain.training

import com.ignacioli.finecoach.core.domain.common.SessionState
import java.time.Instant

class SessionTimingCoordinator {
    companion object {
        const val reviewThresholdSeconds: Long = 30L * 60L
    }

    fun checkpoint(session: Session, nowUTC: Instant): Session {
        ensureInProgress(session)
        val deltaSeconds = secondsBetween(session.lastCheckpointUTC, nowUTC)
        if (deltaSeconds < 0) {
            return session.updatingTiming(
                elapsedSeconds = session.elapsedSeconds,
                lastCheckpointUTC = nowUTC,
                interruptionStartedAtUTC = session.interruptionStartedAtUTC,
                durationNeedsReview = true,
                nowUTC = nowUTC,
            )
        }
        val elapsed = session.elapsedSeconds.adding(DecimalValue.seconds(deltaSeconds))
        return session.updatingTiming(
            elapsedSeconds = elapsed,
            lastCheckpointUTC = nowUTC,
            interruptionStartedAtUTC = null,
            durationNeedsReview = session.durationNeedsReview,
            nowUTC = nowUTC,
        )
    }

    fun resumeAfterInterruption(
        session: Session,
        nowUTC: Instant,
        interruptionStartedAtUTC: Instant,
    ): Session {
        ensureInProgress(session)

        val interruptionLength = secondsBetween(interruptionStartedAtUTC, nowUTC)
        val checkpointDelta = secondsBetween(session.lastCheckpointUTC, nowUTC)

        var needsReview = session.durationNeedsReview
        if (checkpointDelta < 0 || interruptionLength < 0) {
            needsReview = true
        }
        if (interruptionLength >= reviewThresholdSeconds.toDouble()) {
            needsReview = true
        }
        if (checkpointDelta >= (24L * 60L * 60L).toDouble()) {
            needsReview = true
        }

        val mergedElapsed = if (checkpointDelta > 0) {
            session.elapsedSeconds.adding(DecimalValue.seconds(checkpointDelta))
        } else {
            session.elapsedSeconds
        }

        return session.updatingTiming(
            elapsedSeconds = mergedElapsed,
            lastCheckpointUTC = nowUTC,
            interruptionStartedAtUTC = null,
            durationNeedsReview = needsReview,
            nowUTC = nowUTC,
        )
    }

    private fun ensureInProgress(session: Session) {
        if (session.state != SessionState.inProgress) {
            fail(DomainError.invalidState)
        }
    }

    private fun secondsBetween(from: Instant, to: Instant): Double {
        val seconds = to.epochSecond - from.epochSecond
        val nanos = to.nano - from.nano
        return seconds.toDouble() + nanos.toDouble() / 1_000_000_000.0
    }
}
