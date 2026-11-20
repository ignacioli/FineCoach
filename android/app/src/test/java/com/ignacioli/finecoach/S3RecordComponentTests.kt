// fictional-data: invented exercise values; no personal or device data.
package com.ignacioli.finecoach

import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.history.SessionGainsSection
import com.ignacioli.finecoach.core.domain.progress.SessionGains
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class S3RecordComponentTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    @Test fun decorationFloatsOnceWithoutMovingOriginalValueBadgeOrRow() {
        var sequence by mutableStateOf<Int?>(null)
        compose.setContent { FineCoachTheme { FcSetRow(2, "122.5 kg × 6", true, false, {}, {},
            Modifier.padding(FcSpacing.space4).testTag("row"), tag = "sample", isNewRecord = true, recordFloatSequence = sequence) } }
        val row = node("row").getUnclippedBoundsInRoot()
        val value = node("sample-values").getUnclippedBoundsInRoot()
        val badge = node("sample-record").getUnclippedBoundsInRoot()
        node("sample-record-float").assertDoesNotExist()
        compose.mainClock.autoAdvance = false
        compose.runOnUiThread { sequence = 1 }
        // Settle the new effect key, then give snapTo's state change a recomposition frame.
        compose.waitForIdle()
        compose.mainClock.advanceTimeByFrame()
        compose.waitForIdle()
        compose.mainClock.advanceTimeBy(100)
        node("sample-record-float").assertExists()
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.HideFromAccessibility))
        assertEquals(row, node("row").getUnclippedBoundsInRoot())
        assertEquals(value, node("sample-values").getUnclippedBoundsInRoot())
        assertEquals(badge, node("sample-record").getUnclippedBoundsInRoot())
        compose.mainClock.advanceTimeBy(1600)
        node("sample-record-float").assertDoesNotExist()
        compose.mainClock.advanceTimeBy(2000)
        node("sample-record-float").assertDoesNotExist()
    }
    @Test fun narrowLargeTypeWrapsBadgeUnderTitleAndBadgeRequiresCompletedState() {
        compose.setContent { FineCoachTheme { CompositionLocalProvider(LocalDensity provides Density(1f, 1.5f)) {
            Column(Modifier.width(FcSpacing.space8 * 10)) {
                FcSetRow(2, "122.5 kg × 6", true, false, {}, {}, tag = "large", isNewRecord = true)
                FcSetRow(3, "125 kg × 5", false, true, {}, {}, tag = "pending", isNewRecord = true)
            }
        } } }
        val badge = node("large-record").getUnclippedBoundsInRoot()
        val title = compose.onNodeWithText("第 2 组", useUnmergedTree = true).getUnclippedBoundsInRoot()
        assertTrue(badge.top >= title.bottom)
        node("pending-record").assertDoesNotExist()
    }
    @Test fun milestonesAreOrderedAndEmptySectionHasNoNode() {
        compose.setContent { FineCoachTheme { Column {
            SessionGainsSection(SessionGains(milestoneSessionNumber = 50, attendanceStreakWeeks = 8), "gains")
            SessionGainsSection(SessionGains(), "empty")
        } } }
        node("gains-milestone").assertIsDisplayed(); node("gains-streak").assertIsDisplayed()
        assertTrue(node("gains-milestone").getUnclippedBoundsInRoot().bottom <= node("gains-streak").getUnclippedBoundsInRoot().top)
        node("empty").assertDoesNotExist()
    }
}
