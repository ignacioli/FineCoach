package com.ignacioli.finecoach

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.onNodeWithTag
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.ParameterizedRobolectricTestRunner.Parameters
import org.robolectric.ParameterizedRobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(ParameterizedRobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w320dp-h640dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ComponentCatalogStateTests(private val id: String, private val state: String) {
    @get:Rule val compose = createComposeRule()
    @Test fun representativeStateRendersARealTaggedComponent() {
        compose.setContent { FineCoachTheme { Column(Modifier.fillMaxWidth()) { S0ComponentState(id, state) } } }
        compose.onNodeWithTag("$id-$state", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("$id-$state-parent", useUnmergedTree = true).assertExists()
        if (id == "DS-TITLE-ACTION" && state == "icon") {
            listOf("calendar", "library", "filter").forEach {
                compose.onNodeWithTag("$id-$state-$it").assertIsDisplayed().performClick()
            }
            compose.onNodeWithTag("$id-$state-count").assertTextEquals("样例交互计数：3")
        }
    }
    companion object {
        @JvmStatic @Parameters(name = "{0}/{1}")
        fun cases(): List<Array<String>> = S0CatalogEntries.flatMap { row -> row.states.map { arrayOf(row.id, it) } }
    }
}
