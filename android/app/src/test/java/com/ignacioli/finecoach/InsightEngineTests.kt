// fictional-data: synthetic students, fixed clock and fictional history.
package com.ignacioli.finecoach
import com.ignacioli.finecoach.core.domain.insight.*
import com.ignacioli.finecoach.core.domain.progress.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.core.domain.appointment.*
import java.time.*
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class InsightEngineTests {
    private val now = Instant.parse("2026-03-15T19:00:00Z")
    private val student = StudentDraft("虚构学员", StudentSex.female).makeStudent(S3Fixtures.student, now.minusSeconds(40 * 86400))
    private fun evaluate(input: InsightEngine.Input) = InsightEngine.evaluate(input, now, S3Fixtures.zone)
    @Test fun packageBoundariesAndPriority() {
        for (balance in listOf(3L, 2L, 0L)) for (days in listOf(8L, 7L, -1L)) {
            val end = now.atZone(S3Fixtures.zone).toLocalDate().plusDays(days)
            val result = evaluate(InsightEngine.Input(listOf(student), mapOf(student.studentID to InsightEngine.PackageBalance(balance, end))))
            val expected = when { balance == 0L -> Insight.Kind.packageExhausted; days < 0 -> Insight.Kind.packageExpired; balance <= 2 || days <= 7 -> Insight.Kind.packageLow; else -> null }
            assertEquals(expected, result.firstOrNull { it.balance != null }?.kind)
        }
    }
    @Test fun inactivityUsesLocalDaysAndOnlyFutureScheduledBookings() {
        for (days in listOf(13L, 14L)) {
            val s = student.copy(createdAtUTC = now.minusSeconds(days * 86400))
            val input = InsightEngine.Input(listOf(s))
            assertEquals(days == 14L, evaluate(input).any { it.kind == Insight.Kind.inactive })
            val appointment = Appointment(UUID(0, 3), s.studentID, date = LocalDate.parse("2026-03-16"), startTime = LocalTime.NOON, createdAtUTC = now, updatedAtUTC = now)
            assertTrue(evaluate(input.copy(appointments = listOf(appointment))).isEmpty())
            assertEquals(days == 14L, evaluate(input.copy(appointments = listOf(appointment.copy(status = AppointmentStatus.cancelled)))) .any { it.kind == Insight.Kind.inactive })
            assertTrue(evaluate(input.copy(students = listOf(s.archived(now)))).isEmpty())
        }
    }
    @Test fun stagnantRequiresBaselineAndThreeRecentSessions() {
        val history = (1L..4L).map { S3Fixtures.session(it + 10, now.minusSeconds(it * 86400)) }
        assertTrue(evaluate(InsightEngine.Input(listOf(student), history = history.take(3))).none { it.kind == Insight.Kind.stagnant })
        val input = InsightEngine.Input(listOf(student), history = history)
        assertEquals(1, evaluate(input).count { it.kind == Insight.Kind.stagnant })
        assertTrue(evaluate(input.copy(history = history.mapIndexed { i, s -> if (i == 0) s.copy(exercises = s.exercises.map { it.copy(sets = listOf(S3Fixtures.set(weight = "55"))) }) else s })).none { it.kind == Insight.Kind.stagnant })
        assertTrue(evaluate(input.copy(snoozedKeys = setOf("stagnant:${student.studentID.value}:${S3Fixtures.exercise.value}"))).isEmpty())
    }
    @Test fun estimatedMetricDetectsMoreRepsAndAssistanceReverses() {
        val source = EstimatedOneRepMax.exerciseIDs.first()
        val history = (1L..4L).map { S3Fixtures.session(it + 10, now.minusSeconds(it * 86400), source = source) }
        val input = InsightEngine.Input(listOf(student), history = history)
        assertEquals(Insight.Metric.estimatedOneRepMax, evaluate(input).single().baselineMetric)
        val improved = history.first().copy(exercises = history.first().exercises.map { it.copy(sets = listOf(S3Fixtures.set(reps = "6"))) })
        assertTrue(evaluate(input.copy(history = listOf(improved) + history.drop(1))).isEmpty())
        val assisted = input.copy(history = history.map { s -> s.copy(exercises = s.exercises.map { it.copy(sourceID = S3Fixtures.exercise) }) }, assistedExerciseIDs = setOf(S3Fixtures.exercise))
        assertEquals(Insight.Metric.lowestAssistance, evaluate(assisted).single().baselineMetric)
    }
    @Test fun rankingAndStudentFiltering() {
        val other = student.copy(studentID = StudentID.fromUUID(UUID(0, 4)))
        val input = InsightEngine.Input(listOf(other, student), packages = mapOf(other.studentID to InsightEngine.PackageBalance(2, null), student.studentID to InsightEngine.PackageBalance(0, null)))
        val result = evaluate(input)
        assertEquals(listOf(Insight.Kind.packageExhausted, Insight.Kind.packageLow, Insight.Kind.inactive, Insight.Kind.inactive), result.map { it.kind })
        assertEquals(student.studentID, result[2].studentID)
    }    @Test fun hundredStudentsWithTwoHundredSessionsObservation() {
        val students = (1L..100L).map { student.copy(studentID = StudentID.fromUUID(UUID(0, 1000 + it))) }
        val prototype = S3Fixtures.session()
        val history = students.flatMapIndexed { index, s -> (1L..200L).map { n ->
            prototype.copy(sessionID = SessionID.fromUUID(UUID(0, 10000 + index * 200 + n)), studentID = s.studentID,
                completedAtUTC = now.minusSeconds(n * 3600))
        } }
        val started = System.nanoTime()
        val result = evaluate(InsightEngine.Input(students, history = history))
        val elapsedMillis = (System.nanoTime() - started) / 1_000_000
        assertEquals(100, result.size)
        assertTrue(result.all { it.kind == Insight.Kind.stagnant })
        println("S3-PERFORMANCE elapsedMillis=$elapsedMillis")
    }

}
