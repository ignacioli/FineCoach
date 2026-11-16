package com.ignacioli.finecoach.core.application

import com.ignacioli.finecoach.core.domain.training.SessionTimingCoordinator

/** Room is the durable checkpoint; no second file projection can outrank a committed row. */
class RecoveryCoordinator(
    private val repository: SessionRepositoryPort,
    private val clock: AppClock,
) {
    suspend fun reconcileOnLaunch(): ApplicationResult<List<SessionContentRecord>> = trainingValidation {
        val listed = repository.listActiveSessions()
        if (listed is ApplicationResult.Failure) return@trainingValidation listed
        val restored = mutableListOf<SessionContentRecord>()
        for (snapshot in (listed as ApplicationResult.Success).value) {
            val loaded = repository.loadContent(snapshot.sessionID)
            if (loaded is ApplicationResult.Failure) return@trainingValidation loaded
            val content = (loaded as ApplicationResult.Success).value ?: trainingFailure(ApplicationErrorCode.notFound)
            if (content.session.studentID != snapshot.studentID || content.session.revision.value < 1uL) {
                trainingFailure(ApplicationErrorCode.invalidState)
            }
            val session = content.toDomain().session
            val now = clock.now()
            val timing = SessionTimingCoordinator()
            val resumed = session.interruptionStartedAtUTC?.let { timing.resumeAfterInterruption(session, now, it) }
                ?: timing.checkpoint(session, now)
            val saved = repository.saveDraft(SaveSessionDraftCommand(session.sessionID, session.revision,
                resumed.toRecord().draftPayload()))
            if (saved is ApplicationResult.Failure) return@trainingValidation saved
            restored += content.copy(session = (saved as ApplicationResult.Success).value)
        }
        ApplicationResult.Success(restored)
    }
}
