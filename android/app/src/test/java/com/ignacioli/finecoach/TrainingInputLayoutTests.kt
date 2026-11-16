// fictional-data: numeric layout samples only, no student records.
package com.ignacioli.finecoach

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.material3.Text
import androidx.compose.ui.unit.Density
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
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class TrainingInputLayoutTests {
    @get:Rule val compose = createComposeRule()
    @Test fun numericStepperTextFitsVisibleFieldAtFixtureDensity() {
        compose.setContent { FineCoachTheme { CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) {
            Column(Modifier.width(358.dp)) {
                listOf("weight" to "122.5", "reps" to "8", "left" to "40.25", "right" to "37.5").forEach { (tag, initial) ->
                    var value by remember { mutableStateOf(initial) }
                    FcLabelValueRow(tag) { FcStepperField(tag, value, { value = it }, true,
                        painterResource(R.drawable.ic_ms_remove), painterResource(R.drawable.ic_ms_add), {}, {}, tag = tag) }
                }
                listOf("distance" to "0.125", "speed" to "3.25", "resistance" to "10", "duration" to "1:30").forEach { (tag, value) ->
                    FcTextField(tag, value, {}, Modifier.testTag(tag))
                }
                Text("120 kg × 8", Modifier.testTag("reference"), style = FcTypography.body)
                FcSetRow(1, "120 kg × 8", true, false, {}, {}, tag = "row")
                Box(Modifier.width(260.dp)) { FcSetRow(1, "120 kg × 8", true, false, {}, {}, tag = "compact") }
            }
        } } }
        listOf("weight-input", "reps-input", "left-input", "right-input", "distance", "speed", "resistance", "duration", "reference", "row-values", "compact-values").forEach { tag ->
            val node = compose.onNodeWithTag(tag, useUnmergedTree = true)
            val results = mutableListOf<TextLayoutResult>()
            node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { assertTrue(it(results)) }
            assertEquals(1, results.size)
            val layout = results.single()
            val visible = node.fetchSemanticsNode().boundsInRoot
            val boxes = layout.layoutInput.text.indices.map { layout.getBoundingBox(it) }
            println("INPUT_LAYOUT $tag visible=$visible size=${layout.size} constraints=${layout.layoutInput.constraints} font=${layout.layoutInput.style.fontSize} intrinsic=${layout.multiParagraph.maxIntrinsicWidth} lines=${layout.lineCount} boxes=$boxes")
            assertTrue("$tag text width exceeds visible field", boxes.maxOf { it.right } <= visible.width)
            if (tag == "row-values" || tag == "compact-values") {
                // S1-D40 R1: the natural text box may overflow symmetrically without clipping (1dp at xhdpi).
                val overflow = layout.size.height - visible.height
                assertTrue("$tag natural text box overflow exceeds 2px", overflow <= 2f)
            } else {
                assertTrue("$tag text height exceeds visible field", boxes.maxOf { it.bottom } <= visible.height)
            }
            assertTrue("$tag starts outside field", boxes.minOf { it.left } >= 0f && boxes.minOf { it.top } >= 0f)
            if (tag == "compact-values") assertTrue(layout.multiParagraph.maxIntrinsicWidth < 172f)
        }
    }
}
