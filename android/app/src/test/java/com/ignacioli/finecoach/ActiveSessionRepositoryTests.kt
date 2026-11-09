// fictional-data: invented students, exercises and temporary file databases only.
package com.ignacioli.finecoach

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.storage.*
import com.ignacioli.finecoach.storage.entity.*
import com.ignacioli.finecoach.storage.repository.*
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class ActiveSessionRepositoryTests {
    private lateinit var f: T008Fixture
    @Before fun prepare() { f = T008Fixture() }
    @After fun close() { f.close() }

    @Test fun concurrentDuplicateStartsReturnOneDurableIdentityAndPointer() = f.test {
        f.student(1)
        val repositories = List(4) { f.sessions }
        val start = CountDownLatch(1)
        val ready = CountDownLatch(4)
        val threads = Executors.newFixedThreadPool(4)
        try {
            val jobs = repositories.map { repository -> threads.submit(Callable {
                ready.countDown()
                check(start.await(10, TimeUnit.SECONDS))
                runBlocking { f.ok(repository.startOrOpen(StartOrOpenSessionCommand(f.studentID(1), nowUTC = f.now))) }
            }) }
            assertTrue(ready.await(10, TimeUnit.SECONDS))
            start.countDown()
            val results = jobs.map { it.get(30, TimeUnit.SECONDS) }
            assertEquals(1, results.map { it.sessionID }.distinct().size)
            assertEquals(results.first().sessionID, f.start().sessionID)
            assertEquals(1L, f.count("sessions"))
            assertEquals(1L, f.count("active_session_pointers"))
            f.reopen()
            assertEquals(results.first(), f.ok(f.sessions.active(f.studentID(1))))
        } finally { threads.shutdownNow() }
    }

    @Test fun differentStudentsStartConcurrentlyWithoutOverwritingPointers() = f.test {
        f.student(1); f.student(2)
        val repositories = List(2) { f.sessions }
        val ready = CountDownLatch(2)
        val start = CountDownLatch(1)
        val threads = Executors.newFixedThreadPool(2)
        try {
            val jobs = repositories.mapIndexed { index, repository -> threads.submit(Callable {
                ready.countDown(); check(start.await(10, TimeUnit.SECONDS))
                runBlocking { f.ok(repository.startOrOpen(StartOrOpenSessionCommand(f.studentID(index + 1), nowUTC = f.now))) }
            }) }
            assertTrue(ready.await(10, TimeUnit.SECONDS)); start.countDown()
            assertEquals(2, jobs.map { it.get(30, TimeUnit.SECONDS).sessionID }.distinct().size)
            assertEquals(2L, f.count("active_session_pointers"))
            assertEquals(2, f.ok(f.sessions.listActiveSessions()).size)
        } finally { threads.shutdownNow() }
    }

    @Test fun sessionInsertFailureRollsBackAndRetryCreatesExactlyOne() = f.test {
        f.student(1)
        f.failWrites("sessions", "INSERT")
        f.error(ApplicationErrorCode.persistenceFailed, f.sessions.startOrOpen(f.startCommand()))
        assertEquals(0L, f.count("sessions")); assertEquals(0L, f.count("active_session_pointers"))
        f.clearFailure()
        f.start()
        assertEquals(1L, f.count("sessions")); assertEquals(1L, f.count("active_session_pointers"))
    }

    @Test fun pointerInsertFailureRollsBackSessionAndFocus() = f.test {
        f.student(1)
        f.failWrites("active_session_pointers", "INSERT")
        f.error(ApplicationErrorCode.persistenceFailed, f.sessions.startOrOpen(f.startCommand().copy(initialTrainingFocus = setOf(BodyPart.entries.first()))))
        assertEquals(0L, f.count("sessions")); assertEquals(0L, f.count("session_training_focus"))
        f.clearFailure()
        assertEquals(f.start().sessionID, f.start().sessionID)
    }

    @Test fun archivedStudentCannotStartButCanReopenTheirExistingSession() = f.test {
        f.student(1); f.student(2)
        val session = f.start()
        f.db.openHelper.writableDatabase.execSQL("UPDATE students SET lifecycle = 'archived'")
        assertEquals(session, f.start())
        f.error(ApplicationErrorCode.invalidState, f.sessions.startOrOpen(f.startCommand(2)))
        assertEquals(1L, f.count("sessions"))
    }

    @Test fun missingStudentReturnsNotFoundWithoutCreatingAnything() = f.test {
        f.error(ApplicationErrorCode.notFound, f.sessions.startOrOpen(f.startCommand()))
        assertEquals(0L, f.count("sessions"))
    }

    @Test fun pointerToOtherStudentIsRejectedWithoutWritesOrDeletion() = f.test {
        f.student(1); f.student(2)
        val other = f.start(2)
        f.db.openHelper.writableDatabase.execSQL("UPDATE active_session_pointers SET `key` = ?", arrayOf(f.studentID(1).value))
        f.error(ApplicationErrorCode.invalidState, f.sessions.startOrOpen(f.startCommand()))
        f.error(ApplicationErrorCode.invalidState, RecoveryCoordinator(f.sessions, f.clock).reconcileOnLaunch())
        assertEquals(1L, f.count("sessions")); assertEquals(1L, f.count("active_session_pointers"))
        assertEquals(other, f.ok(f.sessions.find(other.sessionID)))
    }

    @Test fun pointerPrimitiveRefusesTerminalSessionAndOtherStudent() = f.test {
        f.student(1); f.student(2)
        val session = f.start()
        f.db.t008SessionDao().deletePointer(f.studentID(1).value)
        assertThrows(IllegalArgumentException::class.java) {
            f.db.s1Dao().insert(ActiveSessionPointerEntity(f.studentID(2).value, UUID.fromString(session.sessionID.value)))
        }
        f.db.openHelper.writableDatabase.execSQL("UPDATE sessions SET state = 'abandonedEmpty'")
        assertThrows(IllegalArgumentException::class.java) {
            f.db.s1Dao().insert(ActiveSessionPointerEntity(f.studentID(1).value, UUID.fromString(session.sessionID.value)))
        }
        assertEquals(0L, f.count("active_session_pointers"))
    }

    @Test fun abandonAtomicallyReleasesPointerAndAllowsNewClass() = f.test {
        f.student(1)
        val session = f.start()
        val abandoned = f.ok(f.sessions.abandon(AbandonEmptySessionCommand(session.sessionID, session.revision, f.now)))
        assertEquals(SessionState.abandonedEmpty, abandoned.state)
        assertEquals(0L, f.count("active_session_pointers"))
        val next = f.start()
        assertNotEquals(session.sessionID, next.sessionID)
        f.reopen()
        assertEquals(next, f.ok(f.sessions.active(f.studentID(1))))
        assertEquals(abandoned, f.ok(f.sessions.find(session.sessionID)))
    }

    @Test fun completionReleasesPointerAndPersistsCompletedSetsAndState() = f.test {
        f.student(1)
        val content = f.sessionContent(completed = true)
        val session = content.session
        val completed = f.ok(f.sessions.complete(CompleteSessionCommand(session.sessionID, session.revision, f.now.plusSeconds(1), false)))
        assertEquals(SessionState.completed, completed.state)
        assertEquals(0L, f.count("active_session_pointers"))
        assertNotEquals(session.sessionID, f.start().sessionID)
        f.reopen()
        val loaded = f.ok(f.sessions.loadContent(session.sessionID))!!
        assertEquals(completed, loaded.session)
        assertEquals(content.exercises, loaded.exercises)
    }

    @Test fun pointerReleaseFailureRollsBackTerminalWriteAndCanRetry() = f.test {
        f.student(1)
        val session = f.start()
        f.failWrites("active_session_pointers", "DELETE")
        val command = AbandonEmptySessionCommand(session.sessionID, session.revision, f.now)
        f.error(ApplicationErrorCode.persistenceFailed, f.sessions.abandon(command))
        assertEquals(session, f.ok(f.sessions.find(session.sessionID)))
        assertEquals(session, f.start())
        f.clearFailure()
        f.ok(f.sessions.abandon(command))
    }

    @Test fun completedAndRemovedExerciseClaimsReleaseWithoutTouchingOtherOwners() = f.test {
        f.student(1); f.student(2)
        var content = f.sessionContent(completed = true)
        val ownIDs = content.exercises.map { StableExerciseID.parse(it.sessionExerciseID.value) }
        val unrelated = StableExerciseID.parse(f.ids.newSessionExerciseID().value)
        val other = f.start(2)
        f.ok(f.sessions.saveContent(SaveSessionContentCommand(other.sessionID, other.revision, emptyList(),
            listOf(content.exercises.first().copy(sessionExerciseID = SessionExerciseID.parse(unrelated.value),
                sessionID = other.sessionID, sectionID = null, orderIndex = 0u, sets = emptyList())))))
        ownIDs.forEachIndexed { index, id -> f.ok(f.exercises.renameClaim(id, "虚构本课动作$index", ExerciseClaimScope.currentSession)) }
        f.ok(f.exercises.renameClaim(unrelated, "虚构其他课动作", ExerciseClaimScope.currentSession))
        content = f.ok(f.sessions.saveContent(SaveSessionContentCommand(content.session.sessionID, content.session.revision,
            content.sections, content.exercises.drop(1))))
        assertNull(f.db.s1Dao().findExerciseNameClaim("虚构本课动作0"))
        assertNotNull(f.db.s1Dao().findExerciseNameClaim("虚构本课动作1"))
        f.ok(f.sessions.complete(CompleteSessionCommand(content.session.sessionID, content.session.revision, f.now, false)))
        assertNull(f.db.s1Dao().findExerciseNameClaim("虚构本课动作1"))
        assertNotNull(f.db.s1Dao().findExerciseNameClaim("虚构其他课动作"))
        f.reopen()
        assertNotNull(f.db.s1Dao().findExerciseNameClaim("虚构其他课动作"))
    }

    @Test fun claimReleaseFailureRollsBackAbandonAndPointerAndAllowsRetry() = f.test {
        f.student(1)
        val content = f.sessionContent()
        val owner = StableExerciseID.parse(content.exercises.first().sessionExerciseID.value)
        f.ok(f.exercises.renameClaim(owner, "虚构临时动作", ExerciseClaimScope.currentSession))
        val command = AbandonEmptySessionCommand(content.session.sessionID, content.session.revision, f.now)
        f.failWrites("exercise_name_claims", "DELETE")
        f.error(ApplicationErrorCode.persistenceFailed, f.sessions.abandon(command))
        assertEquals(content, f.ok(f.sessions.loadContent(content.session.sessionID)))
        assertEquals(1L, f.count("active_session_pointers"))
        assertNotNull(f.db.s1Dao().findExerciseNameClaim("虚构临时动作"))
        f.clearFailure()
        f.ok(f.sessions.abandon(command))
        f.reopen()
        assertNull(f.db.s1Dao().findExerciseNameClaim("虚构临时动作"))
        assertEquals(0L, f.count("active_session_pointers"))
    }

    @Test fun completionGateRejectsEmptyUnresolvedAndUnreviewedDuration() = f.test {
        f.student(1)
        val session = f.start()
        f.error(ApplicationErrorCode.invalidState, f.sessions.complete(CompleteSessionCommand(session.sessionID, session.revision, f.now, false)))
        var content = f.sessionContent(completed = true)
        content = f.ok(f.sessions.saveContent(SaveSessionContentCommand(content.session.sessionID, content.session.revision,
            content.sections, content.exercises.map { e -> e.copy(sets = e.sets + e.sets.single().copy(
                trainingSetID = f.ids.newTrainingSetID(), orderIndex = 1u, state = SetRecordingState.pending, completedAtUTC = null)) })))
        f.error(ApplicationErrorCode.invalidState, f.sessions.complete(CompleteSessionCommand(content.session.sessionID, content.session.revision, f.now, false)))
        f.error(ApplicationErrorCode.invalidState, f.sessions.abandon(AbandonEmptySessionCommand(content.session.sessionID, content.session.revision, f.now)))
        content = f.ok(f.sessions.saveContent(SaveSessionContentCommand(content.session.sessionID, content.session.revision,
            content.sections, content.exercises.map { it.copy(sets = it.sets.take(1)) })))
        val review = f.ok(f.sessions.saveDraft(SaveSessionDraftCommand(content.session.sessionID, content.session.revision,
            content.session.draftPayload().copy(durationNeedsReview = true))))
        f.error(ApplicationErrorCode.invalidState, f.sessions.complete(CompleteSessionCommand(review.sessionID, review.revision, f.now, false)))
    }

    @Test fun draftFailureKeepsRevisionAndAllowsSameCommandRetryAfterReopen() = f.test {
        f.student(1)
        val original = f.start()
        val command = SaveSessionDraftCommand(original.sessionID, original.revision,
            original.draftPayload().copy(elapsedSeconds = BigDecimal("12.125"), studentFacingSummary = "虚构总结"))
        f.failWrites("sessions", "UPDATE")
        f.error(ApplicationErrorCode.persistenceFailed, f.useCases.retry(command))
        assertEquals(original, f.ok(f.sessions.find(original.sessionID)))
        f.clearFailure(); f.reopen()
        val saved = f.ok(f.useCases.retry(command))
        assertEquals(BigDecimal("12.125"), saved.elapsedSeconds)
        f.error(ApplicationErrorCode.staleRevision, f.useCases.retry(command))
        f.reopen()
        assertEquals(saved, f.ok(f.sessions.find(original.sessionID)))
    }

    @Test fun staleContentAndDraftRejectWithoutChangingPersistedRows() = f.test {
        f.student(1)
        val initial = f.start()
        val content = f.sessionContent()
        f.error(ApplicationErrorCode.staleRevision, f.sessions.saveContent(SaveSessionContentCommand(initial.sessionID,
            initial.revision, emptyList(), emptyList())))
        f.error(ApplicationErrorCode.staleRevision, f.sessions.saveDraft(SaveSessionDraftCommand(initial.sessionID,
            initial.revision, initial.draftPayload())))
        assertEquals(content, f.ok(f.sessions.loadContent(initial.sessionID)))
    }

    @Test fun failedSaveStatusBlocksCompletionUntilPendingCommandRetriesSuccessfully() = f.test {
        f.student(1)
        val original = f.sessionContent(completed = true)
        val useCases = f.useCases
        val command = SaveSessionDraftCommand(original.session.sessionID, original.session.revision,
            original.session.draftPayload().copy(elapsedSeconds = BigDecimal("60")))
        f.failWrites("sessions", "UPDATE")
        f.error(ApplicationErrorCode.persistenceFailed, useCases.saveDraft(command))
        assertTrue(useCases.saveStatus(command.sessionID) is SessionSaveStatus.Failed)
        f.error(ApplicationErrorCode.invalidState, useCases.complete(CompleteSessionCommand(command.sessionID,
            original.session.revision, f.now, false)))
        f.clearFailure()
        val revision = f.ok(useCases.retry(command.sessionID))
        assertEquals(SessionSaveStatus.Saved(revision), useCases.saveStatus(command.sessionID))
        assertEquals(SessionState.completed, f.ok(useCases.complete(CompleteSessionCommand(command.sessionID, revision, f.now, false))).state)
    }

    @Test fun sectionsMovePreservesMembersSetsAndUnrelatedRowsAcrossReopen() = f.test {
        f.student(1)
        val before = f.sessionContent()
        val target = before.sections.last().sectionID
        val saved = f.ok(f.useCases.deleteSection(before.session.sessionID, before.session.revision, before.sections.first().sectionID,
            SessionSectionDeletionDisposition.MoveExercisesTo(target)))
        assertEquals(before.exercises.map { it.sessionExerciseID }, saved.exercises.map { it.sessionExerciseID })
        assertEquals(before.exercises.flatMap { it.sets }, saved.exercises.flatMap { it.sets })
        assertEquals(target, saved.exercises.first().sectionID)
        assertEquals(before.exercises.last().copy(orderIndex = 2u), saved.exercises.last())
        f.reopen()
        assertEquals(saved, f.ok(f.sessions.loadContent(saved.session.sessionID)))
    }

    @Test fun sectionsDeleteOnlyMembersAndTheirSets() = f.test {
        f.student(1)
        val before = f.sessionContent()
        val saved = f.ok(f.useCases.deleteSection(before.session.sessionID, before.session.revision, before.sections.first().sectionID,
            SessionSectionDeletionDisposition.DeleteWithExercises))
        assertEquals(listOf(before.exercises.last().sessionExerciseID), saved.exercises.map { it.sessionExerciseID })
        assertEquals(before.exercises.last().sets, saved.exercises.single().sets)
        assertEquals(1L, f.count("training_sets"))
        f.reopen()
        assertEquals(saved, f.ok(f.sessions.loadContent(saved.session.sessionID)))
    }

    @Test fun cancelledSectionDeletionPerformsZeroWrites() = f.test {
        f.student(1)
        val before = f.sessionContent()
        f.blockAllWrites(listOf("sessions", "session_sections", "session_exercises", "training_sets", "session_training_focus"))
        val cancelled = f.ok(f.useCases.deleteSection(before.session.sessionID, before.session.revision, before.sections.first().sectionID, null))
        assertEquals(before, cancelled)
        assertEquals(before, f.ok(f.sessions.loadContent(before.session.sessionID)))
    }

    @Test fun invalidSectionTargetsRejectAndMidDeleteFailureRollsBackAllRows() = f.test {
        f.student(1); f.student(2)
        val before = f.sessionContent()
        val other = f.start(2)
        val foreign = f.ids.newSectionID()
        f.db.s1Dao().insert(SessionSectionEntity(UUID.fromString(foreign.value), SessionSectionOwnerKind.session,
            UUID.fromString(other.sessionID.value), "虚构外部分段", 0))
        for (target in listOf(before.sections.first().sectionID, f.ids.newSectionID(), foreign)) {
            f.error(ApplicationErrorCode.invalidState, f.useCases.deleteSection(before.session.sessionID, before.session.revision,
                before.sections.first().sectionID, SessionSectionDeletionDisposition.MoveExercisesTo(target)))
        }
        f.failWrites("session_sections", "DELETE")
        f.error(ApplicationErrorCode.persistenceFailed, f.useCases.deleteSection(before.session.sessionID, before.session.revision,
            before.sections.first().sectionID, SessionSectionDeletionDisposition.DeleteWithExercises))
        assertEquals(before, f.ok(f.sessions.loadContent(before.session.sessionID)))
        f.clearFailure(); f.reopen()
        assertEquals(before, f.ok(f.sessions.loadContent(before.session.sessionID)))
    }

    @Test fun moveSessionMembersToUnsectionedPreservesSetIdentityAndContent() = f.test {
        f.student(1)
        val before = f.sessionContent()
        val saved = f.ok(f.useCases.deleteSection(before.session.sessionID, before.session.revision,
            before.sections.first().sectionID, SessionSectionDeletionDisposition.MoveExercisesTo(null)))
        assertNull(saved.exercises.first().sectionID)
        assertEquals(before.exercises.first().sessionExerciseID, saved.exercises.first().sessionExerciseID)
        assertEquals(before.exercises.first().sets, saved.exercises.first().sets)
        f.reopen()
        assertEquals(saved, f.ok(f.sessions.loadContent(saved.session.sessionID)))
    }

    @Test fun setConfirmEditCopyUndoDeleteAndRestoreKeepIdentityOrderAndCompletionTime() = f.test {
        f.student(1)
        var current = f.sessionContent()
        val sessionID = current.session.sessionID
        val setID = current.exercises.first().sets.single().trainingSetID
        val useCases = f.useCases
        current = f.ok(useCases.confirmSet(sessionID, current.session.revision, setID))
        val completedAt = current.exercises.first().sets.single().completedAtUTC
        current = f.ok(useCases.mutate(sessionID, current.session.revision) {
            it.copy(session = it.session.editingSet(setID, TrainingSetInput(RecordMode.weightReps,
                weightValue = "13.375", repetitionCount = "9", unit = MeasurementUnit.kilograms), f.now.plusSeconds(1)))
        })
        val edited = current.exercises.first().sets.single()
        assertEquals(SetRecordingState.completed, edited.state)
        assertEquals(completedAt, edited.completedAtUTC)
        val copyID = f.ids.newTrainingSetID()
        current = f.ok(useCases.mutate(sessionID, current.session.revision) {
            it.copy(session = it.session.copyingSet(setID, copyID, f.now))
        })
        val copied = current.exercises.first().sets.last()
        assertEquals(SetRecordingState.pending, copied.state)
        assertNull(copied.completedAtUTC)
        val deleted = copied.toDomain()
        current = f.ok(useCases.mutate(sessionID, current.session.revision) {
            it.copy(session = it.session.deletingSet(copyID, f.now))
        })
        current = f.ok(useCases.mutate(sessionID, current.session.revision) {
            it.copy(session = it.session.restoringSet(deleted, 1, f.now))
        })
        assertEquals(copied, current.exercises.first().sets.last())
        val beforeDuplicateRestore = current
        current = f.ok(useCases.mutate(sessionID, current.session.revision) {
            it.copy(session = it.session.restoringSet(deleted, 1, f.now))
        })
        assertEquals(beforeDuplicateRestore, current)
        current = f.ok(useCases.mutate(sessionID, current.session.revision) {
            it.copy(session = it.session.undoingSet(setID, f.now))
        })
        assertEquals(SetRecordingState.pending, current.exercises.first().sets.first().state)
        assertEquals(listOf(0u, 1u), current.exercises.first().sets.map { it.orderIndex })
        f.reopen()
        assertEquals(current, f.ok(f.sessions.loadContent(sessionID)))
    }

    @Test fun allRecordModesRoundtripExactDecimalAndBilateralFields() = f.test {
        f.student(1)
        val session = f.start()
        val inputs = listOf(
            TrainingSetInput(RecordMode.weightReps, weightValue = "0", repetitionCount = "8", unit = MeasurementUnit.pounds,
                side = SetSide.bilateral, leftValue = "0.125", rightValue = "0.375"),
            TrainingSetInput(RecordMode.reps, repetitionCount = "12", unit = MeasurementUnit.repetitions),
            TrainingSetInput(RecordMode.duration, durationSeconds = "61.125", unit = MeasurementUnit.seconds),
            TrainingSetInput(RecordMode.cardio, durationSeconds = "120.25", unit = MeasurementUnit.seconds,
                distanceValue = "1.125", speedValue = "2.375", resistanceValue = "3.625"),
        )
        val exercises = inputs.mapIndexed { index, input ->
            val id = f.ids.newSessionExerciseID()
            SessionExercise(id, session.sessionID, index.toUInt(), ExerciseSourceKind.sessionOnly, null,
                NormalizedName.parse("虚构动作$index"), input.recordMode, null, null,
                listOf(TrainingSet.makeDraft(f.ids.newTrainingSetID(), id, 0u, input, f.now).confirmed(f.now))).toRecord()
        }
        val saved = f.ok(f.sessions.saveContent(SaveSessionContentCommand(session.sessionID, session.revision, emptyList(), exercises)))
        assertEquals(exercises, saved.exercises)
        f.reopen()
        assertEquals(saved, f.ok(f.sessions.loadContent(session.sessionID)))
    }

    @Test fun staleTerminalPointerDoesNotResumeOrDeleteBusinessData() = f.test {
        f.student(1)
        val before = f.sessionContent(completed = true)
        f.db.openHelper.writableDatabase.execSQL("UPDATE sessions SET state = 'completed', completedAtUTC = ? WHERE id = ?",
            arrayOf(f.now.toString(), before.session.sessionID.value))
        f.reopen()
        assertTrue(f.ok(RecoveryCoordinator(f.sessions, f.clock).reconcileOnLaunch()).isEmpty())
        assertEquals(1L, f.count("active_session_pointers"))
        assertEquals(before.exercises, f.ok(f.sessions.loadContent(before.session.sessionID))!!.exercises)
        val next = f.start()
        assertNotEquals(before.session.sessionID, next.sessionID)
        assertEquals(2L, f.count("sessions")); assertEquals(1L, f.count("active_session_pointers"))
    }

    @Test fun launchRecoveryRestoresEachStudentWithTimingAndContentAfterReopen() = f.test {
        f.student(1); f.student(2)
        val before = f.sessionContent()
        f.start(2)
        f.ok(f.useCases.checkpoint(before.session.sessionID, interruption = true))
        f.reopen(); f.time = f.now.plusSeconds(1801)
        val restored = f.ok(RecoveryCoordinator(f.sessions, f.clock).reconcileOnLaunch())
        assertEquals(2, restored.size)
        val resumed = restored.single { it.session.studentID == f.studentID(1) }
        assertEquals(before.exercises, resumed.exercises)
        assertEquals(before.sections, resumed.sections)
        assertTrue(resumed.session.durationNeedsReview)
        assertNull(resumed.session.interruptionStartedAtUTC)
        assertEquals(BigDecimal("1801"), resumed.session.elapsedSeconds)
        f.reopen()
        assertEquals(resumed, f.ok(f.sessions.loadContent(resumed.session.sessionID)))
    }

    @Test fun oldGenerationCannotReadWriteOrRecoverAndFailureIsNotSuccess() = f.test {
        f.student(1)
        val session = f.start()
        val repository = f.sessions
        f.db.openHelper.writableDatabase.execSQL("UPDATE store_metadata SET value = ? WHERE `key` = 'store_generation'",
            arrayOf(UUID.randomUUID().toString()))
        f.error(ApplicationErrorCode.incompatibleInput, repository.find(session.sessionID))
        f.error(ApplicationErrorCode.incompatibleInput, repository.saveDraft(SaveSessionDraftCommand(session.sessionID,
            session.revision, session.draftPayload())))
        f.error(ApplicationErrorCode.incompatibleInput, RecoveryCoordinator(repository, f.clock).reconcileOnLaunch())
        assertEquals(session, f.ok(f.sessions.find(session.sessionID)))
    }

    @Test fun decimalMappingRejectsOversizedValueWithoutThrowingOrWriting() = f.test {
        f.student(1)
        val before = f.start()
        val huge = BigDecimal("1E+65537")
        f.error(ApplicationErrorCode.textTooLong, f.sessions.saveDraft(SaveSessionDraftCommand(before.sessionID, before.revision,
            before.draftPayload().copy(elapsedSeconds = huge))))
        assertEquals(before, f.ok(f.sessions.find(before.sessionID)))
    }
}

internal class T008Fixture {
    val now: Instant = Instant.parse("2026-11-08T10:00:00Z")
    var time: Instant = now
    val clock = AppClock { time }
    val ids: StableIDGenerator = T008IDs()
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val worker = Executors.newSingleThreadExecutor()
    var db: FineCoachDatabase
        private set
    init {
        context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        db = FineCoachDatabaseFactory.create(context)
    }
    val generation get() = UUID.fromString(db.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)!!.value)
    val exercises get() = ExerciseRepository(db, ExerciseCatalogLoader(context.assets), clock)
    val sessions get() = SessionRepository(db, clock, ids, generation, exercises)
    val templates get() = TemplateRepository(db, clock, ids, generation)
    val useCases get() = ActiveSessionUseCases(sessions, clock, ids)
    val templateUseCases get() = TemplateUseCases(templates, clock)
    fun studentID(n: Int) = StudentID.parse("abcdef00-0000-4000-8000-${n.toString().padStart(12, '0')}")
    fun student(n: Int) {
        db.s1Dao().insert(StudentEntity(UUID.fromString(studentID(n).value), "虚构学员$n", StudentSex.undisclosed,
            null, null, null, null, null, StudentLifecycle.active, now, now))
    }
    fun startCommand(n: Int = 1) = StartOrOpenSessionCommand(studentID(n), nowUTC = now)
    suspend fun start(n: Int = 1) = ok(sessions.startOrOpen(startCommand(n)))
    fun <T> ok(result: ApplicationResult<T>): T {
        assertTrue("Expected success, got $result", result is ApplicationResult.Success)
        return (result as ApplicationResult.Success).value
    }
    fun error(code: ApplicationErrorCode, result: ApplicationResult<*>) {
        assertTrue("Expected failure, got $result", result is ApplicationResult.Failure)
        assertEquals(code, (result as ApplicationResult.Failure).error.code)
    }
    fun test(action: suspend () -> Unit) { worker.submit(Callable { runBlocking { action() } }).get(60, TimeUnit.SECONDS) }
    fun count(table: String): Long = db.openHelper.writableDatabase.query("SELECT COUNT(*) FROM `$table`").use {
        check(it.moveToFirst()); it.getLong(0)
    }
    fun failWrites(table: String, operation: String) {
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER t008_failure BEFORE $operation ON `$table` BEGIN SELECT RAISE(ABORT, 'injected'); END")
    }
    fun clearFailure() { db.openHelper.writableDatabase.execSQL("DROP TRIGGER t008_failure") }
    fun blockAllWrites(tables: List<String>) {
        for (table in tables) for (operation in listOf("INSERT", "UPDATE", "DELETE")) {
            db.openHelper.writableDatabase.execSQL("CREATE TRIGGER t008_${table}_$operation BEFORE $operation ON `$table` BEGIN SELECT RAISE(ABORT, 'unexpected write'); END")
        }
    }
    fun reopen() { db.close(); db = FineCoachDatabaseFactory.create(context) }
    fun close() {
        try { worker.submit { db.close() }.get(30, TimeUnit.SECONDS) } finally {
            worker.shutdownNow(); context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        }
    }
    suspend fun sessionContent(completed: Boolean = false): SessionContentRecord {
        val session = start()
        val owner = SectionOwner.Session(session.sessionID)
        val a = SessionSection.create(ids.newSectionID(), owner, "虚构分段甲", 0u)
        val b = SessionSection.create(ids.newSectionID(), owner, "虚构分段乙", 2u)
        fun exercise(order: UInt, section: SectionID): SessionExercise {
            val id = ids.newSessionExerciseID()
            val draft = TrainingSet.makeDraft(ids.newTrainingSetID(), id, 0u,
                TrainingSetInput(RecordMode.weightReps, weightValue = "12.125", repetitionCount = "8", unit = MeasurementUnit.kilograms), now)
            val set = if (completed) draft.confirmed(now) else draft
            return SessionExercise(id, session.sessionID, order, ExerciseSourceKind.sessionOnly, null,
                NormalizedName.parse("虚构动作"), RecordMode.weightReps, null, section, listOf(set))
        }
        return ok(sessions.saveContent(SaveSessionContentCommand(session.sessionID, session.revision,
            listOf(a.toRecord(), b.toRecord()), listOf(exercise(1u, a.sectionID).toRecord(), exercise(3u, b.sectionID).toRecord()))))
    }
}

private class T008IDs : StableIDGenerator {
    override fun newStudentID() = StudentID.fromUUID(UUID.randomUUID())
    override fun newCoursePackageID() = CoursePackageID.fromUUID(UUID.randomUUID())
    override fun newCreditAdjustmentID() = CreditAdjustmentID.fromUUID(UUID.randomUUID())
    override fun newSessionID() = SessionID.fromUUID(UUID.randomUUID())
    override fun newTemplateID() = TemplateID.fromUUID(UUID.randomUUID())
    override fun newSectionID() = SectionID.fromUUID(UUID.randomUUID())
    override fun newSessionExerciseID() = SessionExerciseID.fromUUID(UUID.randomUUID())
    override fun newTemplateExerciseID() = TemplateExerciseID.fromUUID(UUID.randomUUID())
    override fun newTrainingSetID() = TrainingSetID.fromUUID(UUID.randomUUID())
    override fun newExerciseID() = StableExerciseID.parse(UUID.randomUUID().toString())
}
