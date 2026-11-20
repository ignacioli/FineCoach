// fictional-data: synthetic completed sessions and loads.
package com.ignacioli.finecoach
import com.ignacioli.finecoach.core.domain.progress.Comparison
import com.ignacioli.finecoach.core.domain.common.*
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID
class ComparisonTests {
    @Test fun focusIsASetAndStudentMustMatch() {
        val a = S3Fixtures.session().copy(trainingFocus = setOf(BodyPart.chest, BodyPart.back))
        val b = a.copy(trainingFocus = setOf(BodyPart.back, BodyPart.chest))
        assertTrue(Comparison.compareSessions(a, b) is Comparison.SessionComparisonResult.Compatible)
        assertEquals(Comparison.SessionComparisonResult.IncompatibleTrainingFocus, Comparison.compareSessions(a, b.copy(trainingFocus = emptySet())))
        assertEquals(Comparison.SessionComparisonResult.DifferentStudent, Comparison.compareSessions(a, b.copy(studentID = StudentID.fromUUID(UUID(0, 4)))))
    }
    @Test fun compatibleTotalsExcludePending() {
        val a = S3Fixtures.session(sets = listOf(S3Fixtures.set(), S3Fixtures.set(2).undone(S3Fixtures.now)))
        val result = Comparison.compareSessions(a, a) as Comparison.SessionComparisonResult.Compatible
        assertEquals(1, result.detail.totalSetCountA); assertEquals("5", result.detail.totalRepCountA?.canonicalString)
    }
    @Test fun trendsUseModeDirectionAndDensity() {
        val a = S3Fixtures.session(90, S3Fixtures.now.minusSeconds(1), listOf(S3Fixtures.set(weight = "50")))
        val b = S3Fixtures.session(sets = listOf(S3Fixtures.set(weight = "45")))
        val points = Comparison.exerciseTrend(S3Fixtures.exercise, RecordMode.weightReps, listOf(b, a), Comparison.LoadDirection.decreaseIsImprovement)
        assertEquals("-5", points[1].weightDelta?.canonicalString); assertEquals("225", points[1].volume?.canonicalString)
        assertEquals(Comparison.TrendSampleDensity.empty, Comparison.TrendSampleDensity.classify(emptyList()))
        assertEquals(Comparison.TrendSampleDensity.single, Comparison.TrendSampleDensity.classify(points.take(1)))
        assertEquals(Comparison.TrendSampleDensity.sparse, Comparison.TrendSampleDensity.classify(points))
        assertEquals(Comparison.TrendSampleDensity.sufficient, Comparison.TrendSampleDensity.classify(points + points))
        assertTrue(Comparison.exerciseTrend(S3Fixtures.exercise, RecordMode.duration, listOf(a, b)).isEmpty())
    }
    @Test fun personalBestIsLexicographicAndTiesChooseLatest() {
        val a = S3Fixtures.session(90, S3Fixtures.now.minusSeconds(1), listOf(S3Fixtures.set(weight = "60", reps = "3")))
        val b = S3Fixtures.session(sets = listOf(S3Fixtures.set(weight = "60", reps = "3"), S3Fixtures.set(2, "50", "10")))
        val result = Comparison.personalRecords(S3Fixtures.exercise, RecordMode.weightReps, listOf(b, a))
        assertEquals(b.sessionID, result.mostRepsAtWeight?.sessionID); assertEquals("60", result.mostRepsAtWeight?.weight?.canonicalString)
        assertEquals("3", result.mostRepsAtWeight?.reps?.canonicalString)
        val reverse = Comparison.personalRecords(S3Fixtures.exercise, RecordMode.weightReps, listOf(a, b), Comparison.LoadDirection.decreaseIsImprovement)
        assertEquals("50", reverse.highestWeight?.value?.canonicalString)
    }
}
