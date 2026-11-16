package com.ignacioli.finecoach.storage.repository

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory
import com.ignacioli.finecoach.storage.entity.*
import java.util.UUID
import java.util.concurrent.Callable
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** A repository is bound to one store generation, including after a restore/replacement. */
class SessionRepository(
    private val database: FineCoachDatabase,
    private val clock: AppClock,
    private val ids: StableIDGenerator,
    private val expectedGeneration: UUID,
    private val exerciseRepository: ExerciseRepository,
) : SessionRepositoryPort {
    private val dao get() = database.s1Dao()
    private val writes get() = database.t008SessionDao()

    override suspend fun startOrOpen(command: StartOrOpenSessionCommand): ApplicationResult<SessionRecord> = transaction {
        val student = dao.findStudent(command.studentID.t008UUID()) ?: trainingFailure(ApplicationErrorCode.notFound)
        activeRow(command.studentID)?.let { return@transaction record(it) }
        if (student.lifecycle != StudentLifecycle.active) trainingFailure(ApplicationErrorCode.invalidState)
        val started = Session.start(ids.newSessionID(), command.studentID, command.initialTrainingFocus, command.nowUTC).toRecord()
        dao.insert(started.toEntity())
        started.trainingFocus.forEach { dao.insert(SessionTrainingFocusEntity(started.sessionID.t008UUID(), it)) }
        // Only the stale scalar pointer is replaced; its terminal Session and children are preserved.
        writes.deletePointer(command.studentID.value)
        dao.insert(ActiveSessionPointerEntity(command.studentID.value, started.sessionID.t008UUID()))
        record(requireNotNull(dao.findSession(started.sessionID.t008UUID())))
    }

    override suspend fun active(studentID: StudentID): ApplicationResult<SessionRecord?> = transaction {
        activeRow(studentID)?.let(::record)
    }
    override suspend fun listActiveSessions(): ApplicationResult<List<ActiveSessionSnapshot>> = transaction {
        validatePointers()
        val rows = writes.activeSessions()
        if (rows.groupBy { it.studentID }.any { it.value.size > 1 }) trainingFailure(ApplicationErrorCode.conflict)
        rows.map(::record).sortedWith(compareBy<SessionRecord> { it.startedAtUTC }.thenBy { it.sessionID.value }).map {
            ActiveSessionSnapshot(it.sessionID, it.studentID, it.startedAtUTC, it.lastCheckpointUTC, it.durationNeedsReview)
        }
    }
    override suspend fun find(sessionID: SessionID): ApplicationResult<SessionRecord?> = transaction {
        dao.findSession(sessionID.t008UUID())?.let(::record)
    }
    override suspend fun loadContent(sessionID: SessionID): ApplicationResult<SessionContentRecord?> = transaction {
        loadSessionContent(database, sessionID)
    }
    override suspend fun saveDraft(command: SaveSessionDraftCommand): ApplicationResult<SessionRecord> = transaction {
        val row = requireSession(command.sessionID, command.expectedRevision, SessionState.inProgress)
        val p = command.payload
        if (p.elapsedSeconds.signum() < 0 || p.coachAdjustedDurationSeconds?.let { it.signum() < 0 || it.stripTrailingZeros().scale() > 0 } == true) {
            trainingFailure(ApplicationErrorCode.invalidNumber)
        }
        val changed = record(row).copy(elapsedSeconds = p.elapsedSeconds, interruptionStartedAtUTC = p.interruptionStartedAtUTC,
            durationNeedsReview = p.durationNeedsReview, coachAdjustedDurationSeconds = p.coachAdjustedDurationSeconds,
            trainingFocus = p.trainingFocus, studentFacingSummary = p.studentFacingSummary, privateCoachNote = p.privateCoachNote,
            lastCheckpointUTC = p.lastCheckpointUTC, updatedAtUTC = clock.now(), revision = nextRevision(command.expectedRevision))
            .toDomain().toRecord()
        updateSession(database, changed)
        record(requireNotNull(dao.findSession(row.id)))
    }
    override suspend fun saveCompletedSummary(command: SaveCompletedSessionSummaryCommand): ApplicationResult<SessionRecord> = transaction {
        val row = requireSession(command.sessionID, command.expectedRevision, SessionState.completed)
        val changed = record(row).toDomain().updatingCompletedSummary(command.trainingFocus,
            ValidatedText.optional(command.privateCoachNote), ValidatedText.optional(command.studentFacingSummary), command.savedAtUTC)
        updateSession(database, changed.toRecord())
        record(requireNotNull(dao.findSession(row.id)))
    }
    override suspend fun saveContent(command: SaveSessionContentCommand): ApplicationResult<SessionContentRecord> = transaction {
        val row = requireSession(command.sessionID, command.expectedRevision, SessionState.inProgress)
        val content = SessionContentRecord(record(row).copy(revision = nextRevision(command.expectedRevision),
            updatedAtUTC = clock.now()), command.sections, command.exercises).toDomain().toRecord()
        val removedClaims = sessionClaimOwners(row.id) - content.exercises
            .filter { it.sourceKind == ExerciseSourceKind.sessionOnly }
            .map { StableExerciseID.parse(it.sessionExerciseID.value) }.toSet()
        replaceSessionContent(database, content)
        updateSession(database, content.session)
        exerciseRepository.releaseSessionClaimsInTransaction(removedClaims)
        requireNotNull(loadSessionContent(database, command.sessionID))
    }
    override suspend fun complete(command: CompleteSessionCommand): ApplicationResult<SessionRecord> = transaction {
        // Credit settlement belongs to T009 and cannot be silently reported as performed here.
        if (command.settleCredits) trainingFailure(ApplicationErrorCode.incompatibleInput)
        requireSession(command.sessionID, command.expectedRevision, SessionState.inProgress)
        val finished = requireNotNull(loadSessionContent(database, command.sessionID)).toDomain().session.finished(command.completedAtUTC)
        updateSession(database, finished.toRecord())
        writes.deletePointer(finished.studentID.value)
        exerciseRepository.releaseSessionClaimsInTransaction(sessionClaimOwners(command.sessionID.t008UUID()))
        finished.toRecord()
    }
    override suspend fun abandon(command: AbandonEmptySessionCommand): ApplicationResult<SessionRecord> = transaction {
        requireSession(command.sessionID, command.expectedRevision, SessionState.inProgress)
        val abandoned = requireNotNull(loadSessionContent(database, command.sessionID)).toDomain().session.abandoned(command.abandonedAtUTC)
        updateSession(database, abandoned.toRecord())
        writes.deletePointer(abandoned.studentID.value)
        exerciseRepository.releaseSessionClaimsInTransaction(sessionClaimOwners(command.sessionID.t008UUID()))
        abandoned.toRecord()
    }

    private fun record(row: SessionEntity) = sessionRecord(database, row).toDomain().toRecord()
    private fun sessionClaimOwners(id: UUID): Set<StableExerciseID> = dao.sessionExercises(id)
        .filter { it.sourceKind == ExerciseSourceKind.sessionOnly }.map { StableExerciseID.parse(it.id.toString()) }.toSet()
    private fun requireSession(id: SessionID, revision: Revision, state: SessionState): SessionEntity {
        val row = dao.findSession(id.t008UUID()) ?: trainingFailure(ApplicationErrorCode.notFound)
        if (row.revision != revision.value.toString()) trainingFailure(ApplicationErrorCode.staleRevision)
        if (row.state != state) trainingFailure(ApplicationErrorCode.invalidState)
        validatePointers()
        return row
    }
    private fun validatePointers() = validateSessionPointers(database)
    private fun activeRow(id: StudentID): SessionEntity? {
        validatePointers()
        val active = writes.activeSessions().filter { it.studentID == id.t008UUID() }
        if (active.size > 1) trainingFailure(ApplicationErrorCode.conflict)
        val row = active.singleOrNull() ?: return null
        val pointer = dao.findActiveSessionPointer(id.value)
        if (pointer == null) dao.insert(ActiveSessionPointerEntity(id.value, row.id))
        else if (pointer.sessionID != row.id) {
            val pointed = dao.findSession(pointer.sessionID)
            if (pointed?.state == SessionState.inProgress) trainingFailure(ApplicationErrorCode.invalidState)
            writes.deletePointer(id.value)
            dao.insert(ActiveSessionPointerEntity(id.value, row.id))
        }
        return row
    }
    private suspend fun <T> transaction(action: () -> T) = trainingTransaction(database, expectedGeneration, action)
}

internal fun validateSessionPointers(database: FineCoachDatabase) {
    for (pointer in database.t008SessionDao().pointers()) {
        val pointed = database.s1Dao().findSession(pointer.sessionID) ?: continue
        if (pointed.studentID.toString() != pointer.key) trainingFailure(ApplicationErrorCode.invalidState)
        // Like iOS inProgressSession, terminal scalar remnants are not active business data.
    }
}

internal suspend fun <T> trainingTransaction(db: FineCoachDatabase, generation: UUID, action: () -> T): ApplicationResult<T> =
    trainingValidation {
        withContext(Dispatchers.IO) {
            try {
                ApplicationResult.Success(db.runInTransaction(Callable {
                    val current = db.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)?.value
                    if (current != generation.toString()) trainingFailure(ApplicationErrorCode.incompatibleInput)
                    action()
                }))
            } catch (error: CancellationException) { throw error
            } catch (error: DomainException) { throw error
            } catch (error: TrainingApplicationException) { throw error
            } catch (error: IllegalArgumentException) { throw error
            } catch (_: Exception) {
                ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed))
            }
        }
    }
internal fun nextRevision(revision: Revision): Revision {
    if (revision.value == ULong.MAX_VALUE) trainingFailure(ApplicationErrorCode.invalidState)
    return Revision(revision.value + 1u)
}
internal fun StudentID.t008UUID(): UUID = UUID.fromString(value)
internal fun SessionID.t008UUID(): UUID = UUID.fromString(value)
internal fun TemplateID.t008UUID(): UUID = UUID.fromString(value)
internal fun SectionID.t008UUID(): UUID = UUID.fromString(value)
internal fun SessionExerciseID.t008UUID(): UUID = UUID.fromString(value)
internal fun TemplateExerciseID.t008UUID(): UUID = UUID.fromString(value)
internal fun TrainingSetID.t008UUID(): UUID = UUID.fromString(value)
internal fun sessionRecord(db: FineCoachDatabase, row: SessionEntity) = SessionRecord(
    SessionID.fromUUID(row.id), StudentID.fromUUID(row.studentID), row.state, row.startedAtUTC, row.lastCheckpointUTC,
    row.elapsedSeconds, row.interruptionStartedAtUTC, row.durationNeedsReview, row.coachAdjustedDurationSeconds,
    db.s1Dao().sessionFocus(row.id).map { it.bodyPart }.toSet(), row.studentFacingSummary, row.privateCoachNote,
    Revision(row.revision.toULong()), row.createdAtUTC, row.updatedAtUTC, row.completedAtUTC,
)
internal fun SessionRecord.toEntity(previous: SessionEntity? = null) = SessionEntity(sessionID.t008UUID(), studentID.t008UUID(),
    state, startedAtUTC, lastCheckpointUTC, elapsedSeconds, interruptionStartedAtUTC, durationNeedsReview,
    coachAdjustedDurationSeconds, studentFacingSummary, privateCoachNote, revision.value.toString(), createdAtUTC,
    updatedAtUTC, completedAtUTC, previous?.appointmentID, previous?.creditSettlementNote)
internal fun updateSession(db: FineCoachDatabase, record: SessionRecord) {
    val previous = db.s1Dao().findSession(record.sessionID.t008UUID()) ?: trainingFailure(ApplicationErrorCode.notFound)
    check(db.t008SessionDao().update(record.toEntity(previous)) == 1)
    db.t008SessionDao().deleteSessionFocus(previous.id)
    record.trainingFocus.forEach { db.s1Dao().insert(SessionTrainingFocusEntity(previous.id, it)) }
}
internal fun loadSessionContent(db: FineCoachDatabase, id: SessionID): SessionContentRecord? {
    val dao = db.s1Dao()
    val row = dao.findSession(id.t008UUID()) ?: return null
    return SessionContentRecord(sessionRecord(db, row), dao.sections(SessionSectionOwnerKind.session, row.id).map { it.toRecord() },
        dao.sessionExercises(row.id).map { exercise ->
            SessionExerciseRecord(SessionExerciseID.fromUUID(exercise.id), id, exercise.orderIndex.toUInt(), exercise.sourceKind,
                exercise.sourceID?.let(StableExerciseID::parse), exercise.displayNameSnapshot, exercise.recordModeSnapshot,
                exercise.actionPrivateNote, exercise.sectionID?.let(SectionID::fromUUID), dao.trainingSets(exercise.id).map {
                    TrainingSetRecord(TrainingSetID.fromUUID(it.id), SessionExerciseID.fromUUID(exercise.id), it.orderIndex.toUInt(),
                        it.state, it.recordMode, it.weightValue, it.repetitionCount, it.durationSeconds, it.unit, it.side,
                        it.leftValue, it.rightValue, it.distanceValue, it.speedValue, it.resistanceValue,
                        it.createdAtUTC, it.updatedAtUTC, it.completedAtUTC)
                })
        }).toDomain().toRecord()
}
internal fun SessionSectionEntity.toRecord() = SectionRecord(SectionID.fromUUID(id), ownerKind,
    if (ownerKind == SessionSectionOwnerKind.session) SessionID.fromUUID(ownerID) else null,
    if (ownerKind == SessionSectionOwnerKind.template) TemplateID.fromUUID(ownerID) else null, name, orderIndex.toUInt())
internal fun SectionRecord.toEntity() = SessionSectionEntity(sectionID.t008UUID(), ownerKind,
    ownerSessionID?.t008UUID() ?: requireNotNull(ownerTemplateID).t008UUID(), name, orderIndex.toLong())
internal fun replaceSessionContent(db: FineCoachDatabase, content: SessionContentRecord) {
    // Validate the entire candidate before deleting any stored row. Foreign/global IDs still collide on INSERT ABORT.
    val canonical = content.toDomain().toRecord()
    val id = content.session.sessionID.t008UUID()
    val writes = db.t008SessionDao()
    writes.deleteSessionSets(id)
    writes.deleteSessionExercises(id)
    writes.deleteSections(SessionSectionOwnerKind.session, id)
    canonical.sections.forEach { db.s1Dao().insert(it.toEntity()) }
    canonical.exercises.forEach { e ->
        db.s1Dao().insert(SessionExerciseEntity(e.sessionExerciseID.t008UUID(), id, e.orderIndex.toLong(), e.sourceKind,
            e.sourceID?.value, e.displayNameSnapshot, e.recordModeSnapshot, e.actionPrivateNote, e.sectionID?.t008UUID()))
        e.sets.forEach { s -> db.s1Dao().insert(TrainingSetEntity(s.trainingSetID.t008UUID(), e.sessionExerciseID.t008UUID(),
            s.orderIndex.toLong(), s.state, s.recordMode, s.weightValue, s.repetitionCount, s.durationSeconds, s.leftValue,
            s.rightValue, s.distanceValue, s.speedValue, s.resistanceValue, s.unit, s.side, s.createdAtUTC,
            s.updatedAtUTC, s.completedAtUTC)) }
    }
}
