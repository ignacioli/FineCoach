import Foundation

public struct SessionTimingCoordinator: Sendable {
    public static let reviewThreshold: TimeInterval = 30 * 60

    public init() {}

    public func checkpoint(session: Session, nowUTC: Date) throws -> Session {
        try ensureInProgress(session)
        let delta = nowUTC.timeIntervalSince(session.lastCheckpointUTC)
        if delta < 0 {
            return session.updatingTiming(
                elapsedSeconds: session.elapsedSeconds,
                lastCheckpointUTC: nowUTC,
                interruptionStartedAtUTC: session.interruptionStartedAtUTC,
                durationNeedsReview: true,
                now: nowUTC
            )
        }
        let elapsed = try session.elapsedSeconds.adding(DecimalValue.seconds(delta))
        return session.updatingTiming(
            elapsedSeconds: elapsed,
            lastCheckpointUTC: nowUTC,
            interruptionStartedAtUTC: nil,
            durationNeedsReview: session.durationNeedsReview,
            now: nowUTC
        )
    }

    public func resumeAfterInterruption(
        session: Session,
        nowUTC: Date,
        interruptionStartedAtUTC: Date
    ) throws -> Session {
        try ensureInProgress(session)
        let interruptionLength = nowUTC.timeIntervalSince(interruptionStartedAtUTC)
        let checkpointDelta = nowUTC.timeIntervalSince(session.lastCheckpointUTC)
        var needsReview = session.durationNeedsReview
        if checkpointDelta < 0 || interruptionLength < 0 {
            needsReview = true
        }
        if interruptionLength >= Self.reviewThreshold {
            needsReview = true
        }
        if checkpointDelta >= 24 * 60 * 60 {
            needsReview = true
        }

        let mergedElapsed: DecimalValue
        if checkpointDelta > 0 {
            mergedElapsed = try session.elapsedSeconds.adding(DecimalValue.seconds(checkpointDelta))
        } else {
            mergedElapsed = session.elapsedSeconds
        }

        return session.updatingTiming(
            elapsedSeconds: mergedElapsed,
            lastCheckpointUTC: nowUTC,
            interruptionStartedAtUTC: nil,
            durationNeedsReview: needsReview,
            now: nowUTC
        )
    }

    private func ensureInProgress(_ session: Session) throws {
        guard session.state == .inProgress else {
            throw DomainError.invalidState
        }
    }
}
