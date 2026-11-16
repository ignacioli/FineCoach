// fictional-data: regression contracts requested by the S0 step3 review.
package com.ignacioli.finecoach

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import com.ignacioli.finecoach.designsystem.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w320dp-h640dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class S1ComponentReviewTests {
    @get:Rule val compose = createComposeRule()
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)

    @Test fun todaySceneDefaultsTo220AndIsDecorative() {
        compose.setContent { FineCoachTheme { FcAmbientScene() } }
        node("today-empty-scene").assertIsDisplayed().assertWidthIsEqualTo(220.dp).assertHeightIsEqualTo(220.dp)
        node("today-empty-scene").assertHasNoClickAction()
        assertFalse(node("today-empty-scene").fetchSemanticsNode().config.contains(SemanticsProperties.ContentDescription))
    }

    @Test fun setRowMergesReadableValuesAndExposesStateAppropriateCustomActions() {
        var confirms = 0; var edits = 0; var undos = 0
        compose.setContent { FineCoachTheme { Column {
            FcSetRow(1, "20 kg × 8", false, true, { confirms++ }, { edits++ }, Modifier.testTag("pending"), tag = "pending")
            FcSetRow(2, "20 kg × 8", true, false, {}, { edits++ }, Modifier.testTag("complete"), tag = "complete", onUndo = { undos++ })
        } } }
        val pending = compose.onNodeWithTag("pending").fetchSemanticsNode()
        assertTrue(pending.config.isMergingSemanticsOfDescendants)
        assertEquals("待完成", pending.config[SemanticsProperties.StateDescription])
        val pendingText = pending.config[SemanticsProperties.Text].map { it.text }
        assertTrue(pendingText.containsAll(listOf("第 1 组", "20 kg × 8", "待完成")))
        val actions = pending.config[SemanticsActions.CustomActions]
        assertEquals(listOf("确认", "编辑"), actions.map { it.label })
        compose.runOnIdle { actions.forEach { assertTrue(it.action()) } }
        val completed = compose.onNodeWithTag("complete").fetchSemanticsNode()
        assertEquals("已完成", completed.config[SemanticsProperties.StateDescription])
        assertTrue(completed.config[SemanticsProperties.Text].map { it.text }.containsAll(listOf("第 2 组", "20 kg × 8")))
        val completedActions = completed.config[SemanticsActions.CustomActions]
        assertEquals(listOf("编辑", "撤销"), completedActions.map { it.label })
        compose.runOnIdle { completedActions.forEach { assertTrue(it.action()) } }
        assertEquals(1, confirms); assertEquals(2, edits); assertEquals(1, undos)
    }

    @Test fun setValuesStaySingleLineAndShrinkOnlyToEightyPercent() {
        val value = mutableStateOf("1")
        compose.setContent { FineCoachTheme {
            Column {
                Box(Modifier.width(300.dp)) { FcSetRow(1, value.value, false, true, {}, {}, tag = "sized") }
                androidx.compose.material3.Text("1", Modifier.testTag("minimum-reference"),
                    style = FcTypography.body.copy(fontSize = FcTypography.body.fontSize * 0.8f))
            }
        } }
        fun layout(tag: String = "sized-values"): TextLayoutResult {
            val results = mutableListOf<TextLayoutResult>()
            node(tag).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { assertTrue(it(results)) }
            return results.single()
        }
        val normal = layout()
        assertEquals(1, normal.lineCount)
        assertEquals(FcTypography.body.fontSize.value, normal.layoutInput.style.fontSize.value, 0.001f)
        compose.runOnIdle { value.value = "1234567890".repeat(8) + " kg × 123" }
        val long = layout()
        assertEquals(1, long.lineCount); assertEquals(1, long.layoutInput.maxLines); assertFalse(long.layoutInput.softWrap)
        assertEquals(value.value, long.layoutInput.text.text)
        // Compose semantics copies the requested style into layoutInput, even after auto-size.
        // Compare the rendered digit bounds against the same bundled font at the exact 0.8 floor.
        val minimumDigitWidth = layout("minimum-reference").getBoundingBox(0).width
        assertEquals(minimumDigitWidth, long.getBoundingBox(0).width, 0.001f)
        assertTrue(long.getBoundingBox(0).width < normal.getBoundingBox(0).width)
    }

    @Test fun emptyStateFooterKeepsSpace8ForStaticAndAmbientVariants() {
        val ambient = mutableStateOf(false)
        compose.setContent { FineCoachTheme {
            Box(Modifier.fillMaxSize().testTag("container")) {
                FcEmptyState("虚构空态", "虚构说明", Modifier.fillMaxSize(), ambient = ambient.value,
                    actionTitle = "虚构创建", actionTag = "create")
            }
        } }
        fun checkFooter() {
            node("create").assertIsDisplayed().assertHeightIsAtLeast(52.dp).assertHasClickAction()
            val parent = node("container").getUnclippedBoundsInRoot()
            val button = node("create").getUnclippedBoundsInRoot()
            assertEquals(FcSpacing.space8, parent.bottom - button.bottom)
            assertEquals(parent.right - parent.left, button.right - button.left)
        }
        checkFooter()
        node("empty-mascot").assertWidthIsEqualTo(220.dp).assertHeightIsEqualTo(220.dp)
        compose.runOnIdle { ambient.value = true }
        checkFooter()
        node("empty-mascot").assertDoesNotExist()
        node("today-empty-scene").assertIsDisplayed().assertWidthIsEqualTo(220.dp).assertHeightIsEqualTo(220.dp)
    }
}
