// fictional-data: isolated synthetic catalog and preferences only.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.exercises.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class P4ExerciseLibraryTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    @Test fun exerciseRowUsesAnatomyAndTagsVisibleShapesInsideHitAreas() {
        compose.setContent { FineCoachTheme {
            Column(Modifier.width(358.dp).testTag("parent")) {
                FcListRow("虚构动作", Modifier.testTag("row"), subtitle = "杠铃 · 次要：肩、臂",
                    mode = FcRowMode.Action {}, leading = painterResource(R.drawable.ic_equipment_barbell),
                    exerciseLibrary = true, leadingModifier = Modifier.testTag("icon"), disclosureVisualTag = "disclosure")
                FcFilterChip("胸", true, Modifier.testTag("chip"), visualModifier = Modifier.testTag("chip-shape")) {}
            }
        } }
        val row = node("row").getUnclippedBoundsInRoot()
        assertEquals(node("parent").getUnclippedBoundsInRoot().width, row.width)
        assertEquals(68.7f, row.height.value, 0.6f)
        node("row").assertIsDisplayed().assertHasClickAction()
        val title = compose.onNodeWithText("虚构动作", useUnmergedTree = true).getUnclippedBoundsInRoot()
        assertEquals(40f, (title.left - row.left).value, 0.1f)
        assertEquals(12f, (title.top - row.top).value, 0.1f)
        node("icon").assertWidthIsEqualTo(24.dp).assertHeightIsEqualTo(24.dp)
        node("disclosure").assertIsDisplayed()
        node("chip").assertHeightIsAtLeast(44.dp)
        node("chip-shape").assertHeightIsEqualTo(30.dp)
    }
    @Test fun libraryVisibleControlsPreserveDurablePreferenceAndFullWidthRows() {
        val fixture = ExerciseConformanceFixture()
        try {
            compose.setContent { FineCoachTheme { ExerciseLibraryScreen(fixture.state) {} } }
            compose.waitUntil(15_000) { compose.onAllNodesWithTag("exercise-options-fictional-conformance-0", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
            val row = node("exercise-options-fictional-conformance-0")
            assertEquals(node("exercise-library-content").getUnclippedBoundsInRoot().width, row.getUnclippedBoundsInRoot().width)
            val search = node("exercise-library-search").assertIsDisplayed().assertHeightIsAtLeast(44.dp)
            node("conformance:Search").assertWidthIsEqualTo(310.dp).assertHeightIsEqualTo(40.dp)
            node("exercise-library-section-胸").assertTextEquals("胸 · 21")
            assertTrue(node("exercise-library-section-胸").getUnclippedBoundsInRoot().width < node("exercise-library-content").getUnclippedBoundsInRoot().width)
            val searchRow = node("exercise-library-search-row").getUnclippedBoundsInRoot()
            assertEquals(searchRow.left, search.getUnclippedBoundsInRoot().left)
            assertEquals(searchRow.right, node("exercise-library-filter").getUnclippedBoundsInRoot().right)
            node("exercise-library-trailing").assertIsDisplayed().assertHasClickAction()
            row.assertIsDisplayed().assertIsEnabled().assertHasClickAction().performClick()
            node("exercise-favorite").performScrollTo().assertIsDisplayed().assertHasClickAction().performClick()
            compose.waitUntil(15_000) { fixture.state.preference(com.ignacioli.finecoach.core.domain.common.StableExerciseID.parse("fictional-conformance-0")).isFavorite }
            fixture.room.test {
                assertTrue(requireNotNull(fixture.room.db.s1Dao().findExercisePreference("fictional-conformance-0")).isFavorite)
            }
        } finally { fixture.close() }
    }
}
