package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.domain.common.ExerciseKind
import com.ignacioli.finecoach.core.domain.common.ExerciseSourceKind
import com.ignacioli.finecoach.core.domain.common.MeasurementUnit
import com.ignacioli.finecoach.core.domain.common.NormalizedName
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
import com.ignacioli.finecoach.core.domain.training.CompletedSession
import com.ignacioli.finecoach.core.domain.training.DecimalValue
import com.ignacioli.finecoach.core.domain.training.DomainError
import com.ignacioli.finecoach.core.domain.training.DomainException
import com.ignacioli.finecoach.core.domain.training.DurationTextParser
import com.ignacioli.finecoach.core.domain.training.LastExercisePerformance
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
    fun sessionOnlyExerciseRejectsBlankNameWithDomainError() {
        val session = Session.start(id = sessionID, studentID = studentID, nowUTC = now)
        listOf("", " \t\r\n ").forEach { name ->
            val error = assertThrows(DomainException::class.java) {
                session.addingSessionOnlyExercise(
                    id = squatExerciseID,
                    displayName = name,
                    recordMode = RecordMode.reps,
                    nowUTC = now,
                )
            }
            assertEquals(DomainError.emptyText, error.error)
            assertEquals("displayName", error.field)
        }
    }

    @Test
    fun sessionOnlyExerciseRejectsNameOverUtf8LimitWithDomainError() {
        val session = Session.start(id = sessionID, studentID = studentID, nowUTC = now)
        val boundaryName = "练".repeat(21845) + "a"
        assertEquals(65536, boundaryName.toByteArray(Charsets.UTF_8).size)
        val accepted = session.addingSessionOnlyExercise(
            id = squatExerciseID,
            displayName = boundaryName,
            recordMode = RecordMode.reps,
            nowUTC = now,
        )
        assertEquals(boundaryName, accepted.exercises.single().displayNameSnapshot.value)
        listOf("a".repeat(65537), boundaryName + "a").forEach { name ->
            val error = assertThrows(DomainException::class.java) {
                session.addingSessionOnlyExercise(
                    id = squatExerciseID,
                    displayName = name,
                    recordMode = RecordMode.reps,
                    nowUTC = now,
                )
            }
            assertEquals(DomainError.textTooLong, error.error)
            assertEquals("displayName", error.field)
        }
    }

    @Test
    fun catalogExerciseRejectsBlankNameWithDomainError() {
        listOf("", " \t\r\n ").forEach { name ->
            val error = assertThrows(DomainException::class.java) {
                ExerciseCatalogItem.make(
                    exerciseID = StableExerciseID.parse("fictional.exercise.name-validation"),
                    kind = ExerciseKind.custom,
                    canonicalName = name,
                    recordMode = RecordMode.reps,
                )
            }
            assertEquals(DomainError.emptyText, error.error)
            assertEquals("canonicalName", error.field)
        }
    }

    @Test
    fun catalogExerciseEnforcesUtf8NameLimitWithDomainError() {
        val exerciseID = StableExerciseID.parse("fictional.exercise.name-validation")
        val boundaryName = "练".repeat(21845) + "a"
        assertEquals(65536, boundaryName.toByteArray(Charsets.UTF_8).size)
        val accepted = ExerciseCatalogItem.make(
            exerciseID = exerciseID,
            kind = ExerciseKind.custom,
            canonicalName = boundaryName,
            recordMode = RecordMode.reps,
        )
        assertEquals(boundaryName, accepted.canonicalName.value)
        assertEquals(boundaryName, accepted.normalizedName)
        listOf("a".repeat(65537), boundaryName + "a").forEach { name ->
            assertEquals(65537, name.toByteArray(Charsets.UTF_8).size)
            val error = assertThrows(DomainException::class.java) {
                ExerciseCatalogItem.make(
                    exerciseID = exerciseID,
                    kind = ExerciseKind.custom,
                    canonicalName = name,
                    recordMode = RecordMode.reps,
                )
            }
            assertEquals(DomainError.textTooLong, error.error)
            assertEquals("canonicalName", error.field)
        }
    }

    @Test
    fun decimalParseRejectsNonFiniteAndMalformedStringsWithDomainError() {
        listOf("NaN", "Infinity", "-Infinity", "abc", "", " \t\r\n ").forEach { input ->
            assertDomainError(DomainError.invalidDecimal) { DecimalValue.parse(input) }
        }
    }

    @Test
    fun decimalSecondsRejectsNonFiniteValuesWithDomainError() {
        listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY).forEach { input ->
            assertDomainError(DomainError.invalidDecimal) { DecimalValue.seconds(input) }
        }
        assertEquals("0", DecimalValue.seconds(-1.5).canonicalString)
        assertEquals("0", DecimalValue.seconds(0.0).canonicalString)
        assertEquals("1", DecimalValue.seconds(1.9).canonicalString)
    }

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
        assertEquals("0", completed.ordinaryVolumeContribution()?.canonicalString)

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

        val left = TrainingSet.makeDraft(
            id = firstSetID,
            sessionExerciseID = squatExerciseID,
            orderIndex = 0u,
            input = TrainingSetInput(
                recordMode = RecordMode.weightReps,
                weightValue = "40",
                repetitionCount = "5",
                unit = MeasurementUnit.kilograms,
                side = SetSide.left,
                leftValue = "20",
            ),
            nowUTC = now,
        ).confirmed(nowUTC = now)
        assertEquals(SetRecordingState.completed, left.state)
        assertEquals(SetSide.left, left.side)
        assertEquals("20", left.leftValue?.canonicalString)
        assertNull(left.rightValue)

        val right = TrainingSet.makeDraft(
            id = secondSetID,
            sessionExerciseID = squatExerciseID,
            orderIndex = 0u,
            input = TrainingSetInput(
                recordMode = RecordMode.weightReps,
                weightValue = "40",
                repetitionCount = "4",
                unit = MeasurementUnit.kilograms,
                side = SetSide.right,
                rightValue = "15",
            ),
            nowUTC = now,
        ).confirmed(nowUTC = now)
        assertEquals(SetRecordingState.completed, right.state)
        assertEquals(SetSide.right, right.side)
        assertEquals("15", right.rightValue?.canonicalString)
        assertNull(right.leftValue)

        assertCannotComplete(
            TrainingSetInput(
                recordMode = RecordMode.weightReps,
                weightValue = "40",
                repetitionCount = "5",
                unit = MeasurementUnit.kilograms,
                side = SetSide.left,
            ),
            DomainError.invalidNumber,
        )
        assertCannotComplete(
            TrainingSetInput(
                recordMode = RecordMode.weightReps,
                weightValue = "40",
                repetitionCount = "4",
                unit = MeasurementUnit.kilograms,
                side = SetSide.right,
            ),
            DomainError.invalidNumber,
        )

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
        val catalogItem = ExerciseCatalogItem.make(
            exerciseID = sourceID,
            kind = ExerciseKind.custom,
            canonicalName = "\u3000深蹲",
            recordMode = RecordMode.weightReps,
        )
        assertEquals("深蹲", catalogItem.canonicalName.value)
        assertEquals(catalogItem.canonicalName.value, catalogItem.normalizedName)

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
        assertEquals("60 kg × 5", newestPerformance?.firstSet?.displaySummary())
        assertEquals("上次 60 kg × 5 · 1 组", newestPerformance?.referenceText)

        val sessionOnlyQuery = SessionExercise(
            sessionExerciseID = sessionExercise("78787878-7878-4787-8787-787878787878"),
            sessionID = session("90909090-9090-4909-8909-909090909090"),
            orderIndex = 0u,
            sourceKind = ExerciseSourceKind.sessionOnly,
            sourceID = null,
            displayNameSnapshot = NormalizedName.parse("平板支撑"),
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

    @Test
    fun displaySummaryAndReferenceTextMatchIos() {
        assertEquals("17.5 kg × 12", draft(weightReps(weight = "17.5", reps = "12")).displaySummary())
        assertEquals("17.5 kg × 12", draft(weightReps(weight = "17.5", reps = "12", unit = MeasurementUnit.pounds)).displaySummary())
        assertEquals("17.5 lb × 12", draft(weightReps(weight = "17.5", reps = "12")).displaySummary(weightUnit = "lb"))
        assertEquals(
            "左 8 kg × 10",
            draft(weightReps(reps = "10", side = SetSide.left, left = "8")).displaySummary(),
        )
        assertEquals(
            "左 8 kg × 10",
            draft(weightReps(weight = "8", reps = "10", side = SetSide.left)).displaySummary(),
        )
        assertEquals(
            "右 9 kg × 10",
            draft(weightReps(reps = "10", side = SetSide.right, right = "9")).displaySummary(),
        )
        assertEquals(
            "右 9 kg × 10",
            draft(weightReps(weight = "9", reps = "10", side = SetSide.right)).displaySummary(),
        )
        assertEquals(
            "左 8 kg / 右 9 kg × 10",
            draft(weightReps(reps = "10", side = SetSide.bilateral, left = "8", right = "9")).displaySummary(),
        )
        assertEquals(
            "每侧 12.5 kg × 10",
            draft(
                weightReps(weight = "12.5", reps = "10", side = SetSide.bilateral, left = "12.5", right = "12.5"),
            ).displaySummary(),
        )
        assertEquals(
            "40 kg（双侧） × 8",
            draft(weightReps(weight = "40", reps = "8", side = SetSide.bilateral)).displaySummary(),
        )
        assertEquals(
            "20 次",
            draft(
                TrainingSetInput(
                    recordMode = RecordMode.reps,
                    repetitionCount = "20",
                    unit = MeasurementUnit.repetitions,
                ),
            ).displaySummary(),
        )
        assertEquals(
            "1 分",
            draft(durationInput("60")).displaySummary(),
        )
        assertEquals(
            "45 秒",
            draft(durationInput("45")).displaySummary(),
        )
        assertEquals(
            "50 分",
            draft(durationInput("3000")).displaySummary(),
        )
        assertEquals(
            "-",
            draft(
                TrainingSetInput(recordMode = RecordMode.duration, unit = MeasurementUnit.seconds),
            ).displaySummary(),
        )
        assertEquals(
            "5 分 · 5 km · 速度 10 · 阻力 3",
            draft(
                TrainingSetInput(
                    recordMode = RecordMode.cardio,
                    durationSeconds = "300",
                    distanceValue = "5",
                    speedValue = "10",
                    resistanceValue = "3",
                    unit = MeasurementUnit.seconds,
                ),
            ).displaySummary(),
        )
        assertEquals(
            "1 分 30 秒 · 1 km",
            draft(
                TrainingSetInput(
                    recordMode = RecordMode.cardio,
                    durationSeconds = "90",
                    distanceValue = "1",
                    unit = MeasurementUnit.seconds,
                ),
            ).displaySummary(),
        )

        val first = draft(weightReps(weight = "120", reps = "8"), id = firstSetID).confirmed(nowUTC = now)
        val second = draft(weightReps(weight = "122.5", reps = "8"), id = secondSetID).confirmed(nowUTC = now)
        val performance = LastExercisePerformance(
            sessionID = sessionID,
            completedAtUTC = now,
            sets = listOf(first, second),
        )
        assertEquals("120 kg × 8", performance.firstSet.displaySummary())
        assertEquals("上次 120 kg × 8 · 2 组", performance.referenceText)
    }

    @Test
    fun mutationsAdvanceLastCheckpointUtc() {
        val started = Session.start(id = sessionID, studentID = studentID, nowUTC = now)
        assertEquals(now, started.lastCheckpointUTC)

        val later = now.plusSeconds(45)
        val moved = started.addingSessionOnlyExercise(
            id = squatExerciseID,
            displayName = "杠铃深蹲",
            recordMode = RecordMode.weightReps,
            nowUTC = later,
        )
        assertEquals(later, moved.lastCheckpointUTC)
        assertEquals(later, moved.updatedAtUTC)

        val checkpoint = later.plusSeconds(10)
        val timedAt = later.plusSeconds(20)
        val timed = moved.updatingTiming(
            elapsedSeconds = DecimalValue.parse("10"),
            lastCheckpointUTC = checkpoint,
            interruptionStartedAtUTC = null,
            durationNeedsReview = false,
            nowUTC = timedAt,
        )
        assertEquals(checkpoint, timed.lastCheckpointUTC)
        assertEquals(timedAt, timed.updatedAtUTC)
    }

    @Test
    fun completionRejectsBadDecimalsIncompatibleFieldsAndUnits() {
        val canonical = draft(weightReps(weight = "1.50", reps = "5")).confirmed(nowUTC = now)
        assertEquals(DecimalValue.parse("1.50").canonicalString, canonical.weightValue?.canonicalString)
        assertEquals(DecimalValue.parse("1.5").canonicalString, canonical.weightValue?.canonicalString)
        val trimmed = draft(weightReps(weight = "  1.50  ", reps = " 5 ")).confirmed(nowUTC = now)
        assertEquals(DecimalValue.parse("1.50").canonicalString, trimmed.weightValue?.canonicalString)
        assertEquals(DecimalValue.parse("5").canonicalString, trimmed.repetitionCount?.canonicalString)
        assertCannotComplete(weightReps(weight = "abc", reps = "5"), DomainError.invalidDecimal)

        assertCannotComplete(
            weightReps(weight = "60", reps = "5").copy(durationSeconds = "30"),
            DomainError.invalidMode,
        )
        assertCannotComplete(
            TrainingSetInput(
                recordMode = RecordMode.reps,
                weightValue = "60",
                repetitionCount = "10",
                unit = MeasurementUnit.repetitions,
            ),
            DomainError.invalidMode,
        )
        assertCannotComplete(
            TrainingSetInput(
                recordMode = RecordMode.duration,
                repetitionCount = "10",
                durationSeconds = "30",
                unit = MeasurementUnit.seconds,
            ),
            DomainError.invalidMode,
        )
        assertCannotComplete(
            weightReps(weight = "60", reps = "5").copy(distanceValue = "1"),
            DomainError.invalidMode,
        )
        assertCannotComplete(
            TrainingSetInput(
                recordMode = RecordMode.cardio,
                weightValue = "60",
                durationSeconds = "60",
                distanceValue = "1",
                unit = MeasurementUnit.seconds,
            ),
            DomainError.invalidMode,
        )
        assertCannotComplete(
            weightReps(weight = "40", reps = "8", side = SetSide.bilateral, left = "10"),
            DomainError.invalidNumber,
        )
        assertCannotComplete(
            weightReps(weight = "40", reps = "8", side = SetSide.none, left = "10"),
            DomainError.invalidState,
        )
        assertCannotComplete(
            TrainingSetInput(
                recordMode = RecordMode.reps,
                repetitionCount = "10",
                unit = MeasurementUnit.kilograms,
            ),
            DomainError.invalidUnit,
        )
        assertCannotComplete(
            weightReps(weight = "60", reps = "5", unit = MeasurementUnit.seconds),
            DomainError.invalidUnit,
        )
        assertCannotComplete(
            TrainingSetInput(
                recordMode = RecordMode.duration,
                durationSeconds = "30",
                unit = MeasurementUnit.kilograms,
            ),
            DomainError.invalidUnit,
        )
        assertCannotComplete(
            TrainingSetInput(
                recordMode = RecordMode.cardio,
                durationSeconds = "60",
                distanceValue = "1",
                unit = MeasurementUnit.repetitions,
            ),
            DomainError.invalidUnit,
        )
        assertCannotComplete(
            TrainingSetInput(
                recordMode = RecordMode.reps,
                repetitionCount = "5.5",
                unit = MeasurementUnit.repetitions,
            ),
            DomainError.invalidNumber,
        )
        assertCannotComplete(weightReps(weight = "60", reps = "-1"), DomainError.invalidNumber)
        assertCannotComplete(
            TrainingSetInput(
                recordMode = RecordMode.cardio,
                durationSeconds = "60",
                distanceValue = "0",
                unit = MeasurementUnit.seconds,
            ),
            DomainError.invalidNumber,
        )
    }

    @Test
    fun editingCompletedSetPreservesCompletedAt() {
        val session = sessionWithOneCompletedWeightSet()
        val later = now.plusSeconds(300)
        val edited = session.editingSet(
            setID = firstSetID,
            input = weightReps(weight = "62.5", reps = "8"),
            nowUTC = later,
        )
        val editedSet = setIn(edited, firstSetID)
        assertEquals(SetRecordingState.completed, editedSet.state)
        assertEquals(now, editedSet.completedAtUTC)
        assertEquals(later, editedSet.updatedAtUTC)
        assertEquals("62.5", editedSet.weightValue?.canonicalString)
        assertEquals(1, edited.completedSetCount)

        assertDomainError(DomainError.invalidNumber) {
            session.editingSet(
                setID = firstSetID,
                input = weightReps(weight = "62.5", reps = "0"),
                nowUTC = later,
            )
        }
        val unchanged = setIn(session, firstSetID)
        assertEquals("60", unchanged.weightValue?.canonicalString)
        assertEquals(now, unchanged.completedAtUTC)
    }

    @Test
    fun undoRestoreDeleteAndRemoveExercise() {
        var session = Session.start(id = sessionID, studentID = studentID, nowUTC = now)
        session = session.addingSessionOnlyExercise(
            id = squatExerciseID,
            displayName = "杠铃深蹲",
            recordMode = RecordMode.weightReps,
            nowUTC = now,
        )
        session = session.addingSessionOnlyExercise(
            id = plankExerciseID,
            displayName = "平板支撑",
            recordMode = RecordMode.duration,
            nowUTC = now,
        )
        session = session.addingSet(
            exerciseID = squatExerciseID,
            setID = firstSetID,
            input = weightReps(weight = "60", reps = "5"),
            nowUTC = now,
        )
        session = session.confirmingSet(setID = firstSetID, nowUTC = now)

        session = session.undoingSet(setID = firstSetID, nowUTC = now)
        val undone = setIn(session, firstSetID)
        assertEquals(SetRecordingState.pending, undone.state)
        assertNull(undone.completedAtUTC)
        assertFalse(undone.contributesToStatistics)
        assertEquals(0, session.completedSetCount)

        val removedSet = undone
        session = session.deletingSet(setID = firstSetID, nowUTC = now)
        assertTrue(session.exercises.flatMap { it.sets }.none { it.trainingSetID == firstSetID })

        val restored = session.restoringSet(set = removedSet, originalIndex = 0, nowUTC = now.plusSeconds(1))
        val squatSets = restored.exercises.first { it.sessionExerciseID == squatExerciseID }.sets
        assertEquals(0, squatSets.indexOfFirst { it.trainingSetID == firstSetID })
        assertEquals(1, squatSets.count { it.trainingSetID == firstSetID })
        val duplicate = restored.restoringSet(set = removedSet, originalIndex = 0, nowUTC = now.plusSeconds(2))
        assertEquals(restored.revision, duplicate.revision)
        assertEquals(1, duplicate.exercises.first { it.sessionExerciseID == squatExerciseID }.sets.size)

        val completedAgain = duplicate.confirmingSet(setID = firstSetID, nowUTC = now.plusSeconds(3))
        assertDomainError(DomainError.invalidState) {
            completedAgain.removingExercise(
                exerciseID = squatExerciseID,
                confirmedIfCompleted = false,
                nowUTC = now.plusSeconds(4),
            )
        }
        val withoutSquat = completedAgain.removingExercise(
            exerciseID = squatExerciseID,
            confirmedIfCompleted = true,
            nowUTC = now.plusSeconds(4),
        )
        assertEquals(listOf(plankExerciseID), withoutSquat.exercises.map { it.sessionExerciseID })
        val cleared = withoutSquat.removingExercise(
            exerciseID = plankExerciseID,
            confirmedIfCompleted = false,
            nowUTC = now.plusSeconds(5),
        )
        assertTrue(cleared.exercises.isEmpty())
        assertEquals(SessionFinishGate.abandonEmpty, cleared.finishGate)
    }

    @Test
    fun abandonEmptySessionCannotFinish() {
        val empty = Session.start(id = sessionID, studentID = studentID, nowUTC = now)
        assertEquals(SessionFinishGate.abandonEmpty, empty.finishGate)
        assertDomainError(DomainError.invalidState) { empty.finished(nowUTC = now) }
        val later = now.plusSeconds(5)
        val abandoned = empty.abandoned(nowUTC = later)
        assertEquals(SessionState.abandonedEmpty, abandoned.state)
        assertNull(abandoned.completedAtUTC)
        assertEquals(later, abandoned.lastCheckpointUTC)

        val active = sessionWithOneCompletedWeightSet()
        assertDomainError(DomainError.invalidState) { active.abandoned(nowUTC = now) }
    }

    @Test
    fun ordinaryVolumeCountsOnlyCompletedWeightSets() {
        var session = sessionWithOneCompletedWeightSet()
        session = session.copyingSet(sourceSetID = firstSetID, newSetID = secondSetID, nowUTC = now)
        val draftSetID = trainingSet("88888888-8888-4888-8888-888888888888")
        session = session.addingSet(
            exerciseID = squatExerciseID,
            setID = draftSetID,
            input = weightReps(weight = "80", reps = "3"),
            nowUTC = now,
        )
        assertEquals(SetRecordingState.pending, setIn(session, secondSetID).state)
        assertEquals(SetRecordingState.draft, setIn(session, draftSetID).state)
        assertEquals(1, session.statistics.completedSetCount)
        assertEquals("300", session.statistics.ordinaryTrainingVolume?.canonicalString)
        assertFalse(setIn(session, secondSetID).contributesToStatistics)
        assertFalse(setIn(session, draftSetID).contributesToStatistics)
        assertDomainError(DomainError.invalidState) {
            session.editingCompletedSet(
                setID = firstSetID,
                input = weightReps(weight = "80", reps = "6"),
                nowUTC = now,
            )
        }

        val pullUpExerciseID = sessionExercise("55555555-5555-4555-8555-555555555555")
        val pullUpSetID = trainingSet("99999999-9999-4999-8999-999999999999")
        session = addConfirmed(
            session = session,
            exerciseID = pullUpExerciseID,
            displayName = "引体向上",
            recordMode = RecordMode.reps,
            setID = pullUpSetID,
            input = TrainingSetInput(
                recordMode = RecordMode.reps,
                repetitionCount = "8",
                unit = MeasurementUnit.repetitions,
            ),
        )
        val plankSetID = trainingSet("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
        session = addConfirmed(
            session = session,
            exerciseID = plankExerciseID,
            displayName = "平板支撑",
            recordMode = RecordMode.duration,
            setID = plankSetID,
            input = durationInput("30"),
        )
        assertEquals(3, session.statistics.completedSetCount)
        assertEquals("300", session.statistics.ordinaryTrainingVolume?.canonicalString)

        session = session.discardingUnresolvedSets(nowUTC = now).finished(nowUTC = now)
        assertEquals(SessionState.completed, session.state)
        assertEquals(3, session.statistics.completedSetCount)
        assertEquals("300", session.statistics.ordinaryTrainingVolume?.canonicalString)
        assertEquals(3, session.exercises.flatMap { it.sets }.size)

        val completedBeforeEdit = CompletedSession.make(
            from = session,
            studentDisplayName = NormalizedName.parse("林青"),
        )
        assertEquals("300", completedBeforeEdit.statistics.ordinaryTrainingVolume?.canonicalString)

        val editedAt = now.plusSeconds(30)
        session = session.editingCompletedSet(
            setID = firstSetID,
            input = weightReps(weight = "80", reps = "6"),
            nowUTC = editedAt,
        )
        assertEquals(SetRecordingState.completed, setIn(session, firstSetID).state)
        assertEquals(3, session.statistics.completedSetCount)
        assertEquals("480", session.statistics.ordinaryTrainingVolume?.canonicalString)
        val completedAfterEdit = CompletedSession.make(
            from = session,
            studentDisplayName = NormalizedName.parse("林青"),
        )
        assertEquals("480", completedAfterEdit.statistics.ordinaryTrainingVolume?.canonicalString)
        assertEquals(session.revision.value, completedAfterEdit.revision)

        val bodyweight = addConfirmed(
            session = Session.start(id = sessionID, studentID = studentID, nowUTC = now),
            exerciseID = pullUpExerciseID,
            displayName = "引体向上",
            recordMode = RecordMode.reps,
            setID = pullUpSetID,
            input = TrainingSetInput(
                recordMode = RecordMode.reps,
                repetitionCount = "8",
                unit = MeasurementUnit.repetitions,
            ),
        ).finished(nowUTC = now)
        assertEquals(1, bodyweight.statistics.completedSetCount)
        assertNull(bodyweight.statistics.ordinaryTrainingVolume)

        val rowExerciseID = sessionExercise("12121212-3434-4343-8343-565656565656")
        val rowSetID = trainingSet("67676767-6767-4676-8676-676767676767")
        val leftExerciseID = sessionExercise("78787878-7878-4787-8787-787878787878")
        val leftSetID = trainingSet("89898989-8989-4898-8898-898989898989")
        val rightExerciseID = sessionExercise("90909090-9090-4909-8909-909090909090")
        val rightSetID = trainingSet("a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1")
        val sided = addConfirmed(
            session = addConfirmed(
                session = addConfirmed(
                    session = addConfirmed(
                        session = Session.start(id = sessionID, studentID = studentID, nowUTC = now),
                        exerciseID = squatExerciseID,
                        displayName = "杠铃深蹲",
                        recordMode = RecordMode.weightReps,
                        setID = firstSetID,
                        input = weightReps(weight = "60", reps = "5"),
                    ),
                    exerciseID = rowExerciseID,
                    displayName = "哑铃划船",
                    recordMode = RecordMode.weightReps,
                    setID = rowSetID,
                    input = weightReps(weight = "40", reps = "8", side = SetSide.bilateral, left = "10", right = "12"),
                ),
                exerciseID = leftExerciseID,
                displayName = "左腿箭步蹲",
                recordMode = RecordMode.weightReps,
                setID = leftSetID,
                input = weightReps(weight = "40", reps = "5", side = SetSide.left, left = "20"),
            ),
            exerciseID = rightExerciseID,
            displayName = "右腿箭步蹲",
            recordMode = RecordMode.weightReps,
            setID = rightSetID,
            input = weightReps(weight = "40", reps = "4", side = SetSide.right, right = "15"),
        ).finished(nowUTC = now)
        assertEquals(4, sided.statistics.completedSetCount)
        assertEquals("636", sided.statistics.ordinaryTrainingVolume?.canonicalString)

        val doubled = TrainingSet(
            trainingSetID = firstSetID,
            sessionExerciseID = squatExerciseID,
            orderIndex = 0u,
            state = SetRecordingState.completed,
            recordMode = RecordMode.weightReps,
            weightValue = DecimalValue.parse("10"),
            repetitionCount = DecimalValue.parse("4"),
            durationSeconds = null,
            unit = MeasurementUnit.kilograms,
            side = SetSide.bilateral,
            leftValue = null,
            rightValue = null,
            distanceValue = null,
            speedValue = null,
            resistanceValue = null,
            createdAtUTC = now,
            updatedAtUTC = now,
            completedAtUTC = now,
        )
        assertEquals("80", doubled.ordinaryVolumeContribution()?.canonicalString)
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

    private fun weightReps(
        weight: String? = null,
        reps: String,
        unit: MeasurementUnit = MeasurementUnit.kilograms,
        side: SetSide = SetSide.none,
        left: String? = null,
        right: String? = null,
    ): TrainingSetInput {
        return TrainingSetInput(
            recordMode = RecordMode.weightReps,
            weightValue = weight,
            repetitionCount = reps,
            unit = unit,
            side = side,
            leftValue = left,
            rightValue = right,
        )
    }

    private fun durationInput(seconds: String): TrainingSetInput {
        return TrainingSetInput(
            recordMode = RecordMode.duration,
            durationSeconds = seconds,
            unit = MeasurementUnit.seconds,
        )
    }

    private fun draft(input: TrainingSetInput, id: TrainingSetID = firstSetID): TrainingSet {
        return TrainingSet.makeDraft(
            id = id,
            sessionExerciseID = squatExerciseID,
            orderIndex = 0u,
            input = input,
            nowUTC = now,
        )
    }

    private fun addConfirmed(
        session: Session,
        exerciseID: SessionExerciseID,
        displayName: String,
        recordMode: RecordMode,
        setID: TrainingSetID,
        input: TrainingSetInput,
        at: Instant = now,
    ): Session {
        return session.addingSessionOnlyExercise(
            id = exerciseID,
            displayName = displayName,
            recordMode = recordMode,
            nowUTC = at,
        ).addingSet(
            exerciseID = exerciseID,
            setID = setID,
            input = input,
            nowUTC = at,
        ).confirmingSet(setID = setID, nowUTC = at)
    }
}
