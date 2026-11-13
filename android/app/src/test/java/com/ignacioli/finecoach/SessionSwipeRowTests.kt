// fictional-data: component labels reproduce approved synthetic design examples.
package com.ignacioli.finecoach

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.width
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.Density
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.session.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SessionSwipeRowTests {
    @get:Rule val compose = createComposeRule()
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)

    @Test fun exerciseTilesFollowDesignOrderWidthAndKeepLeadingContent() {
        var open by mutableStateOf(false)
        var moves = 0
        compose.setContent {
            FineCoachTheme {
                SessionSwipeRow("row", open, true, { open = it }, listOf(
                    SessionSwipeAction("删除", "session-exercise-delete", true) {},
                    SessionSwipeAction("移入分区", "session-exercise-move") { moves++ })) {
                    FcText("深蹲", Modifier.testTag("leading"), style = FcTypography.headline)
                }
            }
        }
        val before = node("leading").getUnclippedBoundsInRoot()
        compose.runOnIdle { open = true }
        compose.waitForIdle()
        val move = node("session-exercise-move").assertIsDisplayed().getUnclippedBoundsInRoot()
        val delete = node("session-exercise-delete").assertIsDisplayed().getUnclippedBoundsInRoot()
        assertEquals(before.left, node("leading").getUnclippedBoundsInRoot().left)
        node("leading").assertIsDisplayed()
        assertEquals(move.right, delete.left)
        assertEquals(FcComponentMetrics.hub + FcSpacing.space4 + FcSpacing.space1, move.width)
        assertEquals(FcComponentMetrics.hub + FcSpacing.space3, delete.width)
        listOf("移入分区", "删除").forEach { title ->
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(title, useUnmergedTree = true)
                .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertFalse("$title must fit horizontally", layouts.single().didOverflowWidth)
            assertFalse("$title must fit vertically", layouts.single().didOverflowHeight)
        }
        node("session-exercise-move").performClick()
        compose.runOnIdle { assertEquals(1, moves); assertFalse(open) }
    }

    @Test fun sectionPillLeavesTitleVisibleAndCannotFullSwipeDelete() {
        var open by mutableStateOf(false)
        var deletes = 0
        compose.setContent {
            FineCoachTheme {
                SessionSwipeRow("row", open, true, { open = it }, listOf(
                    SessionSwipeAction("删除分区", "session-section-delete", true) { deletes++ })) {
                    FcText("辅助训练", Modifier.testTag("leading"), style = FcTypography.sectionLabel)
                }
            }
        }
        val before = node("leading").getUnclippedBoundsInRoot()
        node("row").performTouchInput { swipeLeft() }
        compose.waitForIdle()
        node("leading").assertIsDisplayed()
        assertEquals(before.left, node("leading").getUnclippedBoundsInRoot().left)
        val pill = node("session-section-delete").assertIsDisplayed().getUnclippedBoundsInRoot()
        assertEquals(FcComponentMetrics.label + FcSpacing.space4, pill.width)
        assertTrue(pill.height >= FcComponentMetrics.touch)
        assertEquals(FcSpacing.space8 + FcSpacing.space1,
            node("session-section-delete-visual").getUnclippedBoundsInRoot().height)
        assertEquals(0, deletes)
        node("session-section-delete").performTouchInput {
            click(Offset(center.x, FcSpacing.space1.toPx() / 2))
        }
        compose.runOnIdle { assertEquals(1, deletes); assertFalse(open) }
    }

    @Test fun allTileLabelsFitAtFontScaleOnePointThree() {
        compose.setContent {
            val density = LocalDensity.current.density
            CompositionLocalProvider(LocalDensity provides Density(density, fontScale = 1.3f)) {
                FineCoachTheme {
                    Column {
                        SessionSwipeRow("exercise-row", true, true, {}, listOf(
                            SessionSwipeAction("移入分区", "session-exercise-move") {},
                            SessionSwipeAction("删除", "session-exercise-delete", true) {})) {
                            FcText("深蹲", style = FcTypography.headline)
                        }
                        SessionSwipeRow("section-row", true, true, {}, listOf(
                            SessionSwipeAction("删除分区", "session-section-delete", true) {})) {
                            FcText("辅助训练", style = FcTypography.sectionLabel)
                        }
                    }
                }
            }
        }
        compose.waitForIdle()
        listOf("移入分区" to "session-exercise-move", "删除" to "session-exercise-delete",
            "删除分区" to "session-section-delete").forEach { (title, tag) ->
            val label = compose.onNodeWithText(title, useUnmergedTree = true).assertIsDisplayed()
            val layouts = mutableListOf<TextLayoutResult>()
            label.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertFalse("$title must fit at fontScale 1.3", layouts.single().didOverflowWidth)
            val tile = node(tag).assertIsDisplayed().getUnclippedBoundsInRoot()
            val text = label.getUnclippedBoundsInRoot()
            assertTrue("$title must stay inside its tile", text.left >= tile.left && text.right <= tile.right)
        }
        assertTrue(node("session-section-delete").getUnclippedBoundsInRoot().height >= FcComponentMetrics.touch)
    }
}
