package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.domain.common.ExerciseKind
import com.ignacioli.finecoach.core.domain.common.ExerciseLifecycle
import com.ignacioli.finecoach.core.domain.common.ExerciseSourceKind
import com.ignacioli.finecoach.core.domain.common.MeasurementUnit
import com.ignacioli.finecoach.core.domain.common.RecordMode
import com.ignacioli.finecoach.core.domain.common.SessionExerciseID
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.SessionState
import com.ignacioli.finecoach.core.domain.common.SetRecordingState
import com.ignacioli.finecoach.core.domain.common.SetSide
import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.TrainingSetID
import com.ignacioli.finecoach.core.domain.exercise.ExerciseCatalogItem
import com.ignacioli.finecoach.core.domain.training.DecimalValue
import com.ignacioli.finecoach.core.domain.training.DomainError
import com.ignacioli.finecoach.core.domain.training.DomainException
import com.ignacioli.finecoach.core.domain.training.DurationTextParser
import com.ignacioli.finecoach.core.domain.training.LastExercisePerformanceLookup
import com.ignacioli.finecoach.core.domain.training.Session
import com.ignacioli.finecoach.core.domain.training.SessionExercise
import com.ignacioli.finecoach.core.domain.training.SessionFinishGate
import com.ignacioli.finecoach.core.domain.training.SessionTimingCoordinator
import com.ignacioli.finecoach.core.domain.training.SetValueStepping
import com.ignacioli.finecoach.core.domain.training.TrainingSet
import com.ignacioli.finecoach.core.domain.training.TrainingSetInput
import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class TrainingDomainTests {
    private val now: Instant = Instant.ofEpochSecond(1_700_000_000)

    private val studentID: StudentID = student("11111111-1111-4111-8111-111111111111")
    private val sessionID: SessionID = session("22222222-2222-4222-8222-222222222222")
    private val squatExerciseID: SessionExerciseID = sessionExercise("33333333-3333-4333-8333-333333333333")
    private val plankExerciseID: SessionExerciseID = sessionExercise("44444444-4444-4444-8444-444444444444")
    private val firstSetID: TrainingSetID = trainingSet("66666666-6666-4666-8666-666666666666")
    private val secondSetID: TrainingSetID = trainingSet("77777777-7777-4777-8777-777777777777")

    @Test
    fun weightZeroIsValidAndInvalidCountsAreRejected() {
        val zeroWeight = TrainingSet.makeDraft(
            id = firstSetID,
            sessionExerciseID = squatExerciseID,
            orderIndex = 0u,
            input = TrainingSetInput(
                recordMode = RecordMode.weightReps,
                weightValue = "0",
                repetitionCount = "5",
                unit = MeasurementUnit.kilograms,
                side = SetSide.none,
            ),
            nowUTC = now,
        )

        val completed = zeroWeight.confirmed(nowUTC = now)
        assertEquals(SetRecordingState.completed, completed.state)
        assertEquals("0", completed.weightValue?.canonicalString)
        assertTrue(completed.contributesToStatistics)

        assertCannotComplete(
            TrainingSetInput(
                recordMode = RecordMode.reps,
                repetitionCount = "0",
                unit = MeasurementUnit.repetitions,
            ),
            DomainError.invalidNumber,
        )
        assertCannotComplete(
            TrainingSetInput(
                recordMode = RecordMode.duration,
                durationSeconds = "0",
                unit = MeasurementUnit.seconds,
            ),
            DomainError.invalidNumber,
        )
        assertCannotComplete(
            TrainingSetInput(
                recordMode = RecordMode.weightReps,
                weightValue = "0",
                unit = MeasurementUnit.kilograms,
            ),
            DomainError.invalidNumber,
        )
    }

    @Test
    fun unilateralAndCardioValidationMatchesRules() {
        assertCannotComplete(
            TrainingSetInput(
                recordMode = RecordMode.weightReps,
                weightValue = "40",
                repetitionCount = "8",
                unit = MeasurementUnit.kilograms,
                side = SetSide.bilateral,
                leftValue = "10",
            ),
            DomainError.invalidNumber,
        )
        assertCannotComplete(
            TrainingSetInput(
                recordMode = RecordMode.cardio,
                durationSeconds = "600",
                unit = MeasurementUnit.seconds,
            ),
            DomainError.invalidNumber,
        )

        val bilateral = TrainingSet.makeDraft(
            id = firstSetID,
            sessionExerciseID = squatExerciseID,
            orderIndex = 0u,
            input = TrainingSetInput(
                recordMode = RecordMode.weightReps,
                weightValue = "40",
                repetitionCount = "8",
                unit = MeasurementUnit.kilograms,
                side = SetSide.bilateral,
                leftValue = "10",
                rightValue = "12",
            ),
            nowUTC = now,
        ).confirmed(nowUTC = now)
        assertEquals(SetSide.bilateral, bilateral.side)
        assertEquals("10", bilateral.leftValue?.canonicalString)
        assertEquals("12", bilateral.rightValue?.canonicalString)

        val cardio = TrainingSet.makeDraft(
            id = secondSetID,
            sessionExerciseID = plankExerciseID,
            orderIndex = 0u,
            input = TrainingSetInput(
                recordMode = RecordMode.cardio,
                durationSeconds = "900",
                distanceValue = "3000",
                speedValue = "3.3",
                unit = MeasurementUnit.seconds,
            ),
            nowUTC = now,
        ).confirmed(nowUTC = now)
        assertEquals(SetRecordingState.completed, cardio.state)
        assertEquals("3000", cardio.distanceValue?.canonicalString)
    }

    @Test
    fun copyPendingUsesNewIdAndIsExcludedFromStatistics() {
        var session = sessionWithOneCompletedWeightSet()
        assertEquals(SessionFinishGate.canComplete, session.finishGate)
        assertEquals(1, session.completedSetCount)

        session = session.copyingSet(sourceSetID = firstSetID, newSetID = secondSetID, nowUTC = now)
        val copied = setIn(session, secondSetID)
        assertEquals(SetRecordingState.pending, copied.state)
        assertNull(copied.completedAtUTC)
        assertFalse(copied.contributesToStatistics)
        assertNotEquals(firstSetID, copied.trainingSetID)
        assertEquals(1, session.statisticsSets.size)
        assertEquals(SessionFinishGate.unresolvedDrafts, session.finishGate)

        val cleaned = session.discardingUnresolvedSets(nowUTC = now)
        assertEquals(SessionFinishGate.canComplete, cleaned.finishGate)
        assertEquals(1, cleaned.statisticsSets.size)
    }

    @Test
    fun finishGateAndDurationReviewRequireExplicitHandling() {
        var session = sessionWithOneCompletedWeightSet()
        session = session.addingSet(
            exerciseID = squatExerciseID,
            setID = secondSetID,
            input = TrainingSetInput(
                recordMode = RecordMode.weightReps,
                weightValue = "65",
                repetitionCount = "3",
                unit = MeasurementUnit.kilograms,
            ),
            nowUTC = now,
        )
        assertEquals(SessionFinishGate.unresolvedDrafts, session.finishGate)
        assertDomainError(DomainError.invalidState) { session.finished(nowUTC = now) }

        val completable = session.discardingUnresolvedSets(nowUTC = now)
        assertEquals(SessionFinishGate.canComplete, completable.finishGate)

        val reviewRequired = completable.updatingTiming(
            elapsedSeconds = DecimalValue.parse("1200"),
            lastCheckpointUTC = now,
            interruptionStartedAtUTC = now,
            durationNeedsReview = true,
            nowUTC = now,
        )
        assertTrue(reviewRequired.durationNeedsReview)
        assertDomainError(DomainError.invalidState) { reviewRequired.finished(nowUTC = now) }

        val adjusted = reviewRequired.applyingCoachAdjustedDuration(seconds = DecimalValue.parse("1200"), nowUTC = now)
        val finished = adjusted.finished(nowUTC = now)
        assertEquals(SessionState.completed, finished.state)
    }

    @Test
    fun timingCoordinatorMarksReviewOnLongOrInvalidClockJumps() {
        val coordinator = SessionTimingCoordinator()
        val session = sessionWithOneCompletedWeightSet()

        val resumed = coordinator.resumeAfterInterruption(
            session = session,
            nowUTC = now.plusSeconds(SessionTimingCoordinator.reviewThresholdSeconds),
            interruptionStartedAtUTC = now,
        )
        assertTrue(resumed.durationNeedsReview)
        assertEquals(SessionState.inProgress, resumed.state)

        val checkpointed = coordinator.checkpoint(session = session, nowUTC = now.minusSeconds(60))
        assertTrue(checkpointed.durationNeedsReview)
        assertEquals(session.elapsedSeconds, checkpointed.elapsedSeconds)
    }

    @Test
    fun lastPerformanceLookupUsesNewestCompletedSessionAndSupportsSessionOnlyMatching() {
        val sourceID = StableExerciseID.parse("fictional.exercise.squat")
        val catalogItem = ExerciseCatalogItem(
            exerciseID = sourceID,
            kind = ExerciseKind.custom,
            canonicalName = "深蹲",
            normalizedName = "深蹲",
            recordMode = RecordMode.weightReps,
            metadataVersion = "custom.1",
            lifecycle = ExerciseLifecycle.active,
            isRetired = false,
            provenanceRef = null,
            createdAtUTC = now.minusSeconds(3000),
            updatedAtUTC = now.minusSeconds(3000),
        )

        var older = Session.start(id = session("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"), studentID = studentID, nowUTC = now.minusSeconds(2000))
        older = older.addingCatalogExercise(id = sessionExercise("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"), item = catalogItem, nowUTC = now.minusSeconds(2000))
        older = older.addingSet(
            exerciseID = older.exercises.first().sessionExerciseID,
            setID = trainingSet("cccccccc-cccc-4ccc-8ccc-cccccccccccc"),
            input = TrainingSetInput(
                recordMode = RecordMode.weightReps,
                weightValue = "50",
                repetitionCount = "8",
                unit = MeasurementUnit.kilograms,
            ),
            nowUTC = now.minusSeconds(2000),
        )
        older = older.confirmingSet(setID = older.exercises.first().sets.first().trainingSetID, nowUTC = now.minusSeconds(2000))
        older = older.finished(nowUTC = now.minusSeconds(1990))

        var newer = Session.start(id = session("dddddddd-dddd-4ddd-8ddd-dddddddddddd"), studentID = studentID, nowUTC = now.minusSeconds(1000))
        newer = newer.addingCatalogExercise(id = sessionExercise("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"), item = catalogItem, nowUTC = now.minusSeconds(1000))
        newer = newer.addingSet(
            exerciseID = newer.exercises.first().sessionExerciseID,
            setID = trainingSet("ffffffff-ffff-4fff-8fff-ffffffffffff"),
            input = TrainingSetInput(
                recordMode = RecordMode.weightReps,
                weightValue = "60",
                repetitionCount = "5",
                unit = MeasurementUnit.kilograms,
            ),
            nowUTC = now.minusSeconds(1000),
        )
        newer = newer.confirmingSet(setID = newer.exercises.first().sets.first().trainingSetID, nowUTC = now.minusSeconds(1000))
        newer = newer.finished(nowUTC = now.minusSeconds(990))

        var sessionOnly = Session.start(id = session("12121212-1212-4212-8212-121212121212"), studentID = studentID, nowUTC = now.minusSeconds(500))
        val sessionOnlyExerciseID = sessionExercise("34343434-3434-4343-8343-343434343434")
        sessionOnly = sessionOnly.addingSessionOnlyExercise(
            id = sessionOnlyExerciseID,
            displayName = "平板支撑",
            recordMode = RecordMode.duration,
            nowUTC = now.minusSeconds(500),
        )
        sessionOnly = sessionOnly.addingSet(
            exerciseID = sessionOnlyExerciseID,
            setID = trainingSet("56565656-5656-4565-8565-565656565656"),
            input = TrainingSetInput(
                recordMode = RecordMode.duration,
                durationSeconds = "120",
                unit = MeasurementUnit.seconds,
            ),
            nowUTC = now.minusSeconds(500),
        )
        sessionOnly = sessionOnly.confirmingSet(
            setID = trainingSet("56565656-5656-4565-8565-565656565656"),
            nowUTC = now.minusSeconds(500),
        )
        sessionOnly = sessionOnly.finished(nowUTC = now.minusSeconds(490))

        val lookup = LastExercisePerformanceLookup(listOf(older, newer, sessionOnly))
        val newestPerformance = lookup.performanceFor(newer.exercises.first())
        assertNotNull(newestPerformance)
        assertEquals(newer.sessionID, newestPerformance?.sessionID)
        assertEquals("60 kg × 5", newestPerformance?.firstSet?.displaySummary)

        val sessionOnlyQuery = SessionExercise(
            sessionExerciseID = sessionExercise("78787878-7878-4787-8787-787878787878"),
            sessionID = session("90909090-9090-4909-8909-909090909090"),
            orderIndex = 0u,
            sourceKind = ExerciseSourceKind.sessionOnly,
            sourceID = null,
            displayNameSnapshot = "平板支撑",
            recordModeSnapshot = RecordMode.duration,
            actionPrivateNote = null,
            sectionID = null,
            sets = emptyList(),
        )
        val sessionOnlyPerformance = lookup.performanceFor(sessionOnlyQuery)
        assertNotNull(sessionOnlyPerformance)
        assertEquals(sessionOnly.sessionID, sessionOnlyPerformance?.sessionID)
    }

    @Test
    fun steppingAndDurationParserCoverCoreInputRules() {
        assertEquals("2.5", SetValueStepping.stepped(text = "", field = SetValueStepping.Field.weight, up = true))
        assertEquals("1", SetValueStepping.stepped(text = "1", field = SetValueStepping.Field.reps, up = false))
        assertTrue(SetValueStepping.canStepDown(text = "2", field = SetValueStepping.Field.reps))
        assertFalse(SetValueStepping.canStepDown(text = "1", field = SetValueStepping.Field.reps))

        assertEquals("330", DurationTextParser.parseSeconds("5分30秒"))
        assertEquals("300", DurationTextParser.parseSeconds("5m"))
        assertEquals("5400", DurationTextParser.parseSessionDurationSeconds("1小时30分"))
        assertEquals("1 小时 30 分", DurationTextParser.formatSessionDurationForEditing("5400"))
        assertEquals("5 分 30 秒", DurationTextParser.formatForEditing("330"))
    }

    private fun sessionWithOneCompletedWeightSet(): Session {
        var session = Session.start(id = sessionID, studentID = studentID, nowUTC = now)
        session = session.addingSessionOnlyExercise(
            id = squatExerciseID,
            displayName = "杠铃深蹲",
            recordMode = RecordMode.weightReps,
            nowUTC = now,
        )
        session = session.addingSet(
            exerciseID = squatExerciseID,
            setID = firstSetID,
            input = TrainingSetInput(
                recordMode = RecordMode.weightReps,
                weightValue = "60",
                repetitionCount = "5",
                unit = MeasurementUnit.kilograms,
            ),
            nowUTC = now,
        )
        return session.confirmingSet(setID = firstSetID, nowUTC = now)
    }

    private fun setIn(session: Session, setID: TrainingSetID): TrainingSet =
        session.exercises.flatMap { it.sets }.first { it.trainingSetID == setID }

    private fun assertCannotComplete(input: TrainingSetInput, expected: DomainError) {
        val error = try {
            val draft = TrainingSet.makeDraft(
                id = firstSetID,
                sessionExerciseID = squatExerciseID,
                orderIndex = 0u,
                input = input,
                nowUTC = now,
            )
            draft.confirmed(nowUTC = now)
            null
        } catch (exception: DomainException) {
            exception
        }
        assertNotNull("Expected domain error: $expected", error)
        assertEquals(expected, error?.error)
    }

    private fun assertDomainError(expected: DomainError, block: () -> Unit) {
        val exception = assertThrows(DomainException::class.java, block)
        assertEquals(expected, exception.error)
    }

    private fun student(raw: String): StudentID = StudentID.fromUUID(UUID.fromString(raw))
    private fun session(raw: String): SessionID = SessionID.fromUUID(UUID.fromString(raw))
    private fun sessionExercise(raw: String): SessionExerciseID = SessionExerciseID.fromUUID(UUID.fromString(raw))
    private fun trainingSet(raw: String): TrainingSetID = TrainingSetID.fromUUID(UUID.fromString(raw))
}
