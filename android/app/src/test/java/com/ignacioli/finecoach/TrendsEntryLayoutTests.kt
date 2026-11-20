// fictional-data: invented training history for trend controls; no real coach or student.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.unit.width
import com.ignacioli.finecoach.core.application.ProgressUseCases
import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.trends.TrendMetric
import com.ignacioli.finecoach.features.trends.TrendsScreen
import com.ignacioli.finecoach.features.trends.TrendsState
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-mdpi")
class TrendsEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val f = T009Fixture()
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    @After fun close() { compose.runOnUiThread { compose.activity.setContent {} }; f.close() }

    @Test fun exercisePickerAndMetricAreVisibleAndDoNotWriteHistory() {
        lateinit var state: TrendsState
        f.test {
            val first = f.content(); f.finish(first)
            f.now = f.now.plusSeconds(86_400)
            val second = f.content(sourceID = StableExerciseID.parse("a2f5b6ef-b780-49c0-8d96-fdaff23e27ce")); f.finish(second)
            state = TrendsState(f.studentID, ProgressUseCases(f.history, f.sessions), f.zone)
            state.load()
        }
        val before = f.count("sessions")
        compose.setContent { FineCoachTheme { TrendsScreen(state) {} } }
        compose.waitForIdle()
        node("trends-exercise").assertIsDisplayed().assertHasClickAction().performClick()
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(1_000)
        compose.waitForIdle()
        compose.mainClock.autoAdvance = true
        node("trends-picker").assertIsDisplayed()
        val option = state.content!!.options.first()
        node("trends-pick-${option.id.value}").assertIsDisplayed().assertHasClickAction().performClick()
        compose.waitForIdle()
        assertTrue(state.content!!.metrics.contains(TrendMetric.weight))
        node("trends-metric-0").assertIsDisplayed().assertHasClickAction().performClick()
        compose.waitForIdle()
        assertEquals(TrendMetric.weight, state.content!!.metric)
        assertEquals(node("platform-content").getUnclippedBoundsInRoot().width, node("trends-exercise").getUnclippedBoundsInRoot().width)
        assertEquals(before, f.count("sessions"))
    }
}
