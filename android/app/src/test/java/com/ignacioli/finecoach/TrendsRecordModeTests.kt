// fictional-data: synthetic sessions for every record mode and sample density.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.domain.common.RecordMode
import com.ignacioli.finecoach.core.domain.progress.Comparison
import com.ignacioli.finecoach.core.domain.training.DurationTextParser
import com.ignacioli.finecoach.features.trends.TrendMetric
import com.ignacioli.finecoach.features.trends.TrendsPresentation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TrendsRecordModeTests {
    private fun page(mode: RecordMode, count: Int, emptyExercise: Boolean = false) = TrendsPresentation.content(
        when {
            emptyExercise -> listOf(S3Fixtures.session(sets = listOf(S3Fixtures.set(mode = mode).undone(S3Fixtures.now)), mode = mode))
            count == 0 -> emptyList()
            else -> (0 until count).map { index ->
                S3Fixtures.session(400L + index, S3Fixtures.now.plusSeconds(index * 86_400L),
                    listOf(S3Fixtures.set(n = 500L + index, mode = mode)), mode)
            }
        },
        emptySet(), S3Fixtures.zone, S3Fixtures.exercise, TrendMetric.weight,
    )

    private fun text(mode: RecordMode) = when (mode) {
        RecordMode.reps -> "5 次"
        RecordMode.duration -> DurationTextParser.formatForEditing("50")
        RecordMode.cardio -> DurationTextParser.formatForEditing("50") + " · 1 km"
        RecordMode.weightReps -> "50 kg"
    }

    private fun assertDensity(mode: RecordMode, count: Int) {
        val shown = page(mode, count, emptyExercise = count == 0)
        assertEquals(Comparison.TrendSampleDensity.classify(List(count) { Comparison.SetTrendPoint(
            S3Fixtures.session().sessionID, S3Fixtures.now, mode, null, null, null, null, null, null, null) }), shown.density)
        if (count == 0) {
            assertEquals(TrendsPresentation.EMPTY, shown.emptyText)
            assertTrue(shown.values.isEmpty()); assertTrue(shown.rows.isEmpty()); assertNull(shown.singleValue)
        } else if (count == 1) {
            assertEquals(text(mode), shown.singleValue)
            assertTrue(shown.rows.isEmpty())
            assertEquals(if (mode == RecordMode.weightReps) 1 else 0, shown.values.size)
        } else {
            assertNull(shown.emptyText); assertNull(shown.singleValue)
            assertEquals(count == 2, shown.dashed)
            if (mode == RecordMode.weightReps) {
                assertEquals(count, shown.values.size); assertTrue(shown.rows.isEmpty()); assertTrue(shown.metrics.isNotEmpty())
            } else {
                assertTrue(shown.values.isEmpty()); assertTrue(shown.metrics.isEmpty())
                assertEquals(count, shown.rows.size)
                assertTrue(shown.rows.all { it.second == text(mode) })
            }
        }
    }

    @Test fun weightRepsEmpty() = assertDensity(RecordMode.weightReps, 0)
    @Test fun weightRepsSingle() = assertDensity(RecordMode.weightReps, 1)
    @Test fun weightRepsSparse() = assertDensity(RecordMode.weightReps, 2)
    @Test fun weightRepsSufficient() = assertDensity(RecordMode.weightReps, 3)
    @Test fun durationEmpty() = assertDensity(RecordMode.duration, 0)
    @Test fun durationSingle() = assertDensity(RecordMode.duration, 1)
    @Test fun durationSparse() = assertDensity(RecordMode.duration, 2)
    @Test fun durationSufficient() = assertDensity(RecordMode.duration, 3)
    @Test fun repsEmpty() = assertDensity(RecordMode.reps, 0)
    @Test fun repsSingle() = assertDensity(RecordMode.reps, 1)
    @Test fun repsSparse() = assertDensity(RecordMode.reps, 2)
    @Test fun repsSufficient() = assertDensity(RecordMode.reps, 3)
    @Test fun cardioEmpty() = assertDensity(RecordMode.cardio, 0)
    @Test fun cardioSingle() = assertDensity(RecordMode.cardio, 1)
    @Test fun cardioSparse() = assertDensity(RecordMode.cardio, 2)
    @Test fun cardioSufficient() = assertDensity(RecordMode.cardio, 3)
}
