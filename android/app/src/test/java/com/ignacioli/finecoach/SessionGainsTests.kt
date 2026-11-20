// fictional-data: synthetic sessions and fixed ISO weeks, no real student records.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.core.domain.progress.*
import java.time.*
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

internal object S3Fixtures {
    val now: Instant = Instant.parse("2026-03-09T07:00:00Z")
    val zone: ZoneId = ZoneId.of("America/Los_Angeles")
    val student = StudentID.fromUUID(UUID(0, 1))
    val exercise = StableExerciseID.parse(UUID(0, 2).toString())
    fun set(n: Long = 1, weight: String = "50", reps: String = "5", mode: RecordMode = RecordMode.weightReps, order: UInt = 0u): TrainingSet = TrainingSet.makeDraft(
        TrainingSetID.fromUUID(UUID(0, n)), SessionExerciseID.fromUUID(UUID(0, 20)), order,
        TrainingSetInput(mode, weightValue = weight.takeIf { mode == RecordMode.weightReps }, repetitionCount = reps.takeIf { mode == RecordMode.weightReps || mode == RecordMode.reps },
            durationSeconds = weight.takeIf { mode == RecordMode.duration || mode == RecordMode.cardio },
            distanceValue = "1".takeIf { mode == RecordMode.cardio }, unit = when(mode) { RecordMode.weightReps -> MeasurementUnit.kilograms; RecordMode.reps -> MeasurementUnit.repetitions; else -> MeasurementUnit.seconds }), now).confirmed(now)
    fun session(n: Long = 100, at: Instant = now, sets: List<TrainingSet> = listOf(set()), mode: RecordMode = sets.firstOrNull()?.recordMode ?: RecordMode.weightReps, source: StableExerciseID = exercise): CompletedSession {
        val sid = SessionID.fromUUID(UUID(0, n))
        val e = SessionExercise(SessionExerciseID.fromUUID(UUID(0, 20)), sid, 0u, ExerciseSourceKind.builtIn, source, NormalizedName.parse("虚构动作"), mode, null, sets = sets)
        return CompletedSession(sid, student, NormalizedName.parse("虚构学员"), at.minusSeconds(600), at, emptySet(), SessionNotes(null, null, emptyMap()), listOf(e), SessionStatistics(sets.size, DecimalValue.parse("600"), null), 0uL)
    }
    fun history(weeks: Int, current: Instant = now): List<CompletedSession> {
        val monday = current.atZone(zone).toLocalDate().with(java.time.temporal.TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        return (1 until weeks).flatMap { week -> listOf(1L, 3L).map { day -> session(1000L + week * 2 + day, monday.minusWeeks(week.toLong()).plusDays(day).atTime(12, 0).atZone(zone).toInstant(), emptyList()) } } +
            session(50, monday.atStartOfDay(zone).toInstant(), emptyList())
    }
}

class SessionGainsTests {
    private fun gains(sets: List<TrainingSet>, old: List<CompletedSession> = listOf(S3Fixtures.session(90, S3Fixtures.now.minusSeconds(3600)))) = SessionGains.evaluate(S3Fixtures.session(sets = sets), old, S3Fixtures.zone)
    @Test fun firstAndTieAreNotRecords() {
        assertTrue(gains(listOf(S3Fixtures.set()), emptyList()).isEmpty)
        assertTrue(gains(listOf(S3Fixtures.set())).isEmpty)
        assertTrue(gains(listOf(S3Fixtures.set(weight = "50.0"))).isEmpty)
    }
    @Test fun holderTransfersOnMoreRepsButNotStrictly() {
        val first = S3Fixtures.set(1, "55", "5"); val second = S3Fixtures.set(2, "55", "6", order = 1u)
        val result = gains(listOf(first, second))
        assertEquals(setOf(second.trainingSetID), result.recordHolderSetIDs)
        assertTrue(result.strictRecordHolderSetIDs.isEmpty())
        assertEquals(setOf(first.trainingSetID), gains(listOf(first)).strictRecordHolderSetIDs)
    }
    @Test fun deletingOrUndoingHolderRecomputes() {
        val a = S3Fixtures.set(1, "55"); val b = S3Fixtures.set(2, "60", order = 1u)
        assertEquals(setOf(b.trainingSetID), gains(listOf(a, b)).recordHolderSetIDs)
        assertEquals(setOf(a.trainingSetID), gains(listOf(a, b.undone(S3Fixtures.now))).recordHolderSetIDs)
        assertEquals(setOf(a.trainingSetID), gains(listOf(a)).recordHolderSetIDs)
        assertTrue(gains(listOf(a.copy(weightValue = DecimalValue.parse("49")))).isEmpty)
    }
    @Test fun progressIsParetoAndIndependentOfAllTimeRecord() {
        val old = listOf(S3Fixtures.session(80, S3Fixtures.now.minusSeconds(7200), listOf(S3Fixtures.set(weight = "80"))), S3Fixtures.session(90, S3Fixtures.now.minusSeconds(3600)))
        assertTrue(gains(listOf(S3Fixtures.set(weight = "55", reps = "4")), old).rows.isEmpty())
        assertEquals(1, gains(listOf(S3Fixtures.set(weight = "55", reps = "6")), old).progress.size)
        assertEquals(1, gains(listOf(S3Fixtures.set(weight = "50", reps = "6")), old).progress.size)
    }
    @Test fun assistedDurationAndRepsUseCorrectDirection() {
        val old = S3Fixtures.session(90, S3Fixtures.now.minusSeconds(1))
        assertEquals(1, SessionGains.evaluate(S3Fixtures.session(sets = listOf(S3Fixtures.set(weight = "45"))), listOf(old), S3Fixtures.zone, setOf(S3Fixtures.exercise)).records.size)
        for (mode in listOf(RecordMode.duration, RecordMode.cardio, RecordMode.reps)) {
            val before = S3Fixtures.session(90, S3Fixtures.now.minusSeconds(1), listOf(S3Fixtures.set(weight = "50", reps = "5", mode = mode)))
            val current = S3Fixtures.session(sets = listOf(S3Fixtures.set(weight = "55", reps = "6", mode = mode)))
            assertEquals(1, SessionGains.evaluate(current, listOf(before), S3Fixtures.zone).records.size)
        }
    }
    @Test fun futureAndOtherStudentsCannotRewriteHistory() {
        val before = S3Fixtures.session(90, S3Fixtures.now.minusSeconds(1))
        val later = S3Fixtures.session(101, sets = listOf(S3Fixtures.set(weight = "100")))
        val current = S3Fixtures.session(sets = listOf(S3Fixtures.set(weight = "55")))
        val foreign = before.copy(studentID = StudentID.fromUUID(UUID(0, 8)))
        assertEquals(SessionGains.evaluate(current, listOf(before), S3Fixtures.zone), SessionGains.evaluate(current, listOf(before, later, foreign), S3Fixtures.zone))
    }
    @Test fun sessionNumberBoundaries() {
        for (number in listOf(9, 10, 11, 149, 150)) {
            val history = (1 until number).map { S3Fixtures.session(it.toLong() + 1000, S3Fixtures.now.minusSeconds(it.toLong()), emptyList()) }
            assertEquals(number.takeIf { it == 10 || it == 150 }, SessionGains.evaluate(S3Fixtures.session(sets = emptyList()), history, S3Fixtures.zone).milestoneSessionNumber)
        }
    }
    @Test fun streakThresholdsAndSecondOnlyAcrossDst() {
        val at = Instant.parse("2026-03-15T20:00:00Z")
        for (weeks in listOf(3, 4, 5, 26, 52, 78)) {
            val history = S3Fixtures.history(weeks, at)
            val current = S3Fixtures.session(at = at, sets = emptyList())
            val expected = weeks.takeIf { it in listOf(4, 26, 52, 78) }
            assertEquals(expected, SessionGains.evaluate(current, history, S3Fixtures.zone).attendanceStreakWeeks)
            assertNull(SessionGains.evaluate(current, history.dropLast(1), S3Fixtures.zone).attendanceStreakWeeks)
            assertNull(SessionGains.evaluate(current.copy(sessionID = SessionID.fromUUID(UUID(0, 200))), history + current.copy(completedAtUTC = at.minusSeconds(1)), S3Fixtures.zone).attendanceStreakWeeks)
        }
    }
    @Test fun sundayMondayBoundaryAndGap() {
        val sunday = Instant.parse("2026-03-16T06:59:00Z")
        val history = S3Fixtures.history(4, sunday)
        assertEquals(4, SessionGains.evaluate(S3Fixtures.session(at = sunday, sets = emptyList()), history, S3Fixtures.zone).attendanceStreakWeeks)
        assertNull(SessionGains.evaluate(S3Fixtures.session(at = sunday.plusSeconds(60), sets = emptyList()), history, S3Fixtures.zone).attendanceStreakWeeks)
        assertNull(SessionGains.evaluate(S3Fixtures.session(at = sunday, sets = emptyList()), history.drop(2), S3Fixtures.zone).attendanceStreakWeeks)
    }
}
