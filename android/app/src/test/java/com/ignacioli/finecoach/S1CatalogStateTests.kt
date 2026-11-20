// fictional-data: synthetic catalog states only.
package com.ignacioli.finecoach

import androidx.compose.foundation.layout.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.*
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.unit.width
import com.ignacioli.finecoach.designsystem.FcComponentMetrics
import com.ignacioli.finecoach.designsystem.FcSpacing
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.ParameterizedRobolectricTestRunner
import org.robolectric.ParameterizedRobolectricTestRunner.Parameters
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(ParameterizedRobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w320dp-h640dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class S1CatalogStateTests(private val id: String, private val state: String) {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @Test fun s1StateRendersRealComponent() {
        compose.setContent { FineCoachTheme { Column(Modifier.fillMaxSize().testTag("catalog-state-container")) { S1ComponentState(id, state) } } }
        val component = compose.onNodeWithTag("$id-$state", useUnmergedTree = true).assertIsDisplayed()
        when (id) {
            "DS-CALENDAR-DAY" -> {
                val width = compose.onNodeWithTag("catalog-state-container").getUnclippedBoundsInRoot().width
                component.assertWidthIsEqualTo(width).assertHeightIsAtLeast(FcComponentMetrics.touch).assertHasClickAction()
                val circle = compose.onNodeWithTag("conformance:DS-CALENDAR-DAY · selected", useUnmergedTree = true)
                val dot = compose.onNodeWithTag("conformance:Has-appointment dot", useUnmergedTree = true)
                if (state == "selected") {
                    val side = FcSpacing.space6 + FcSpacing.space1
                    circle.assertExists().assertWidthIsEqualTo(side).assertHeightIsEqualTo(side)
                    component.assertIsSelected(); dot.assertDoesNotExist()
                } else {
                    circle.assertDoesNotExist(); component.assertIsNotSelected()
                    if (state == "scheduled") {
                        dot.assertExists().assertWidthIsEqualTo(FcSpacing.space1).assertHeightIsEqualTo(FcSpacing.space1)
                        component.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "有课程安排"))
                    } else dot.assertDoesNotExist()
                }
            }
            "DS-AMBIENT-SCENE" -> {
                val side = if (state == "calendar") 160.dp else 220.dp
                component.assertWidthIsEqualTo(side).assertHeightIsEqualTo(side)
            }
            "DS-EQUIPMENT-ICON" -> component.assertWidthIsEqualTo(24.dp).assertHeightIsEqualTo(24.dp)
            "DS-SET-ROW" -> {
                component.assertWidthIsEqualTo(320.dp).assertHeightIsEqualTo(38.dp)
                compose.onNodeWithTag("$id-$state-confirm", useUnmergedTree = true)
                    .assertIsDisplayed().assertWidthIsAtLeast(44.dp).assertHeightIsAtLeast(44.dp)
            }
            "DS-PAGE-PRIMARY" -> component.assertWidthIsEqualTo(320.dp).assertHeightIsAtLeast(44.dp)
            "DS-PAGE-SECONDARY" -> component.assertWidthIsEqualTo(320.dp).assertHeightIsEqualTo(312.dp)
            "DS-EMPTY-STATE" -> component.assertWidthIsEqualTo(320.dp).assertHeightIsEqualTo(468.dp)
            "DS-LAUNCH" -> component.assertWidthIsEqualTo(320.dp).assertHeightIsEqualTo(208.dp).assertHasNoClickAction()
            else -> error("Missing catalog geometry contract: $id")
        }
    }
    companion object {
        @JvmStatic @Parameters(name = "{0}/{1}")
        fun cases(): List<Array<String>> = S1CatalogEntries.flatMap { row -> row.states.map { arrayOf(row.id, it) } }
    }
}
