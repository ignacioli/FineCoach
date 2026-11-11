package com.ignacioli.finecoach

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.layout.AlignmentLine
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import com.ignacioli.finecoach.designsystem.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.roundToInt

/** S1-D40 R1: single-line FcText occupies the token line box; the natural font box is centered in it. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class FcTextLineBoxTests {
    @get:Rule val compose = createComposeRule()

    @Test fun differentStylesAlignTheirFirstBaselinesInRoot() {
        val baselines = mutableMapOf<String, Float>()
        compose.setContent { FineCoachTheme { Row {
            listOf("headline" to FcTypography.headline, "callout" to FcTypography.callout).forEach { (name, style) ->
                FcText("训练中 gjpqy", Modifier.alignByBaseline().onGloballyPositioned {
                    val baseline = it[FirstBaseline]
                    assertTrue("$name must expose FirstBaseline", baseline != AlignmentLine.Unspecified)
                    baselines[name] = it.positionInRoot().y + baseline
                }, style = style)
            }
        } } }
        compose.runOnIdle {
            assertEquals(2, baselines.size)
            assertTrue("root baselines: $baselines", abs(baselines.getValue("headline") - baselines.getValue("callout")) <= 1f)
        }
    }

    @Test
    @Config(sdk = [36], qualifiers = "zh-rCN-w1600dp-h2000dp-notnight-xhdpi")
    fun everyTypographyStyleKeepsInkInsideItsNaturalLineBox() {
        val lineCounts = mutableMapOf<String, Int>()
        val naturalHeights = mutableMapOf<String, Int>()
        compose.setContent { FineCoachTheme { Column {
            FcTypography.styles.forEach { (name, style) ->
                // Capture the padded parent: capturing FcText alone would hide overflow at its bounds.
                Box(Modifier.fillMaxWidth().background(Color.White).testTag("ink-$name").padding(vertical = 12.dp)) {
                    FcText("训练中 深蹲 王小明 120 kg gjpqy", Modifier.testTag("text-$name"),
                        color = Color.Black, style = style, softWrap = false, maxLines = 1,
                        onTextLayout = {
                            lineCounts[name] = it.lineCount
                            naturalHeights[name] = it.size.height
                        })
                }
            }
        } } }
        val failures = mutableListOf<String>()
        FcTypography.styles.forEach { (name, _) ->
            assertEquals("$name is a single line", 1, lineCounts[name])
            val parent = compose.onNodeWithTag("ink-$name", useUnmergedTree = true)
            val parentBounds = parent.fetchSemanticsNode().boundsInRoot
            val textBounds = compose.onNodeWithTag("text-$name", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
            val top = (textBounds.top - parentBounds.top).roundToInt()
            val bottom = (textBounds.bottom - parentBounds.top).roundToInt()
            val pixels = parent.captureToImage().toPixelMap()
            val inkRows = (0 until pixels.height).filter { y ->
                (0 until pixels.width).any { x -> pixels[x, y] != Color.White }
            }
            assertTrue("$name must render ink", inkRows.isNotEmpty())
            val above = (top - inkRows.first()).coerceAtLeast(0)
            val below = (inkRows.last() + 1 - bottom).coerceAtLeast(0)
            val token = bottom - top
            val natural = naturalHeights.getValue(name)
            // S1-D42: the natural box is centered in the token box, as in the CSS line-height model.
            val allowedOverflow = ceil((natural - token) / 2.0).toInt() + 1
            println("LINEBOX_INK $name topOverflow=${above}px bottomOverflow=${below}px tokenHeight=${token}px naturalHeight=${natural}px allowedOverflow=${allowedOverflow}px")
            if (above > allowedOverflow || below > allowedOverflow) {
                failures += "$name: top=${above}px bottom=${below}px allowed=${allowedOverflow}px"
            }
        }
        assertTrue("Ink outside natural line box: ${failures.joinToString()}", failures.isEmpty())
    }

    @Test fun singleLineTextOccupiesTokenLineHeightWithAndWithoutTag() {
        compose.setContent { FineCoachTheme { Column(Modifier.fillMaxWidth().testTag("column")) {
            FcText("深蹲", Modifier.testTag("tagged"), style = FcTypography.exerciseTitle)
            FcText("下一行", style = FcTypography.body)
            FcText("末行", Modifier.testTag("after"), style = FcTypography.caption)
        } } }
        val tagged = compose.onNodeWithTag("tagged", useUnmergedTree = true).getUnclippedBoundsInRoot()
        val untagged = compose.onNodeWithText("下一行", useUnmergedTree = true).getUnclippedBoundsInRoot()
        val after = compose.onNodeWithTag("after", useUnmergedTree = true).getUnclippedBoundsInRoot()
        assertEquals(26f, tagged.height.value, 0.5f)    // 20 × 1.3
        assertEquals(23.8f, untagged.height.value, 0.5f) // 17 × 1.4, no outer tag
        assertEquals(tagged.bottom.value, untagged.top.value, 0.01f)
        assertEquals(untagged.bottom.value, after.top.value, 0.01f) // siblings stack on line boxes
    }

    @Test fun multiLineTextKeepsItsNaturalHeight() {
        compose.setContent { FineCoachTheme { Column {
            FcText("一二三四五六七八九十一二三四五六七八九十", Modifier.width(60.dp).testTag("wrap"), style = FcTypography.body)
        } } }
        val wrap = compose.onNodeWithTag("wrap", useUnmergedTree = true).getUnclippedBoundsInRoot()
        assertTrue("multi-line text is taller than two token lines' worth of natural boxes", wrap.height.value > 23.8f * 1.6f)
    }
}
