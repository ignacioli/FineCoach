// fictional-data: synthetic dates and quantities only; assertion messages contain no sample content.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.trends.*
import java.math.BigDecimal
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-mdpi")
class TrendChartInteractionTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private lateinit var scroll: ScrollState
    private fun samples(count: Int) = List(count) { index -> TrendChartSample("1月${index + 1}日", BigDecimal(10 + index), "kg") }
    private fun show(points: List<TrendChartSample>, scrolling: Boolean = false) {
        compose.setContent { FineCoachTheme {
            scroll = rememberScrollState()
            var inspecting by remember { mutableStateOf(false) }
            Column(Modifier.fillMaxSize().then(if (scrolling) Modifier.verticalScroll(scroll) else Modifier)
                .padding(horizontal = FcSpacing.space4)) {
                Spacer(Modifier.height(FcSpacing.space8))
                Box(Modifier.height(FcSpacing.space6)) { if (!inspecting) FcText("最大值", Modifier.testTag("max-label")) }
                FcTrendChart(points.map { it.value.toFloat() }, false,
                    Modifier.fillMaxWidth().height(FcSpacing.space8 * 6).testTag("chart"), samples = points) { inspecting = it }
                Spacer(Modifier.height(FcSpacing.space8 * 40))
            }
        } }
    }
    @After fun close() { compose.runOnUiThread { compose.activity.setContent {} } }

    @Test fun sparseAndDenseDrawingBranchesKeepOnlyLatestMarkerAfterThreshold() {
        show(samples(8))
        check(compose.onAllNodesWithTag("conformance:svg-circle", true).fetchSemanticsNodes().size == 8) { "Sparse marker branch mismatch" }
        check(TrendChartDrawing.markerIndices(9) == listOf(8)) { "Dense marker model mismatch" }
        check(TrendChartDrawing.markerIndices(7).size == 7) { "Core marker branch changed" }
        check(TrendChartDrawing.nearest(listOf(0f, .1f, 1f), .2f) == 1) { "Snap ignored sample spacing" }
    }

    @Test fun denseChartRendersLatestMarkerAndSummary() {
        val points = samples(9).dropLast(1) + TrendChartSample("1月9日", BigDecimal("12.34"), "kg")
        show(points)
        check(compose.onAllNodesWithTag("conformance:svg-circle", true).fetchSemanticsNodes().size == 1) { "Dense marker branch mismatch" }
        val summary = node("chart").fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
        check(summary == "1月1日至1月9日；最小值 10 kg；最大值 17 kg；最新值 12.3 kg") { "Chart summary mismatch" }
        check(listOf(points.first().date, points.last().date, "最小值", "最大值", "最新值").all { it in summary }) { "Chart summary omitted required fields" }
    }

    @Test fun holdShowsSnappedBubbleHidesMaximumAndReleaseClearsIt() {
        val points = samples(3)
        show(points)
        node("chart").performTouchInput { down(center) }
        compose.mainClock.advanceTimeBy(700)
        compose.waitUntil(5_000) { exists("trend-bubble") }
        node("trend-bubble").assertIsDisplayed()
        val bubble = node("trend-bubble").getUnclippedBoundsInRoot()
        val plot = node("chart").getUnclippedBoundsInRoot()
        check(bubble.left >= plot.left && bubble.right <= plot.right) { "Inspection bubble escaped plot" }
        val text = compose.onAllNodesWithText(points[1].label, useUnmergedTree = true).fetchSemanticsNodes()
        check(text.size == 1) { "Inspection label mismatch" }
        node("max-label").assertDoesNotExist()
        node("chart").performTouchInput { moveTo(Offset(right - 1f, centerY)); up() }
        compose.waitUntil(5_000) { !exists("trend-bubble") }
        node("max-label").assertExists()
    }

    @Test fun horizontalDragSnapsWithoutWaitingForHoldAndCancelClearsIt() {
        val points = samples(3)
        show(points)
        node("chart").performTouchInput { down(Offset(left + 1f, centerY)); moveTo(Offset(right - 1f, centerY), 100) }
        compose.waitUntil(5_000) { exists("trend-bubble") }
        node("trend-bubble").assertIsDisplayed()
        val bubble = node("trend-bubble").getUnclippedBoundsInRoot()
        val plot = node("chart").getUnclippedBoundsInRoot()
        check(bubble.left >= plot.left && bubble.right <= plot.right) { "Inspection bubble escaped plot" }
        check(compose.onAllNodesWithText(points.last().label, useUnmergedTree = true).fetchSemanticsNodes().size == 1) { "Horizontal snap label mismatch" }
        node("chart").performTouchInput { cancel() }
        compose.waitUntil(5_000) { !exists("trend-bubble") }
    }

    @Test fun verticalGestureScrollsPageWithoutStartingInspection() {
        show(samples(9), scrolling = true)
        node("chart").performTouchInput { swipeUp(durationMillis = 200) }
        compose.waitForIdle()
        check(scroll.value > 0) { "Chart intercepted vertical scrolling" }
        node("trend-bubble").assertDoesNotExist()
    }
}
