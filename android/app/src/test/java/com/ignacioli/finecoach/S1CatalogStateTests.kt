package com.ignacioli.finecoach

import androidx.compose.foundation.layout.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
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
    @get:Rule val compose = createComposeRule()
    @Test fun s1StateRendersRealComponent() {
        compose.setContent { FineCoachTheme { Column(Modifier.fillMaxSize()) { S1ComponentState(id, state) } } }
        val component = compose.onNodeWithTag("$id-$state", useUnmergedTree = true).assertIsDisplayed()
        when (id) {
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
