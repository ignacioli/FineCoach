// fictional-data: catalog exercises and a synthetic student's completed sessions only.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.width
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.session.ActiveSessionScreen
import com.ignacioli.finecoach.storage.repository.StudentRepository
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class P4AddExerciseTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    @Test fun libraryPanelUsesTokensAndVisibleSelectionPersists() {
        val fixture = AddExerciseConformanceFixture()
        val f = fixture.training
        try {
            compose.setContent { FineCoachTheme {
                ActiveSessionScreen(f.state, f.content.session.sessionID, fixture.state, f.templates, {}, {},
                    students = StudentRepository(f.room.db, f.room.clock))
            } }
            compose.waitUntil(15_000) { exists("session-add-exercise") }
            node("session-add-exercise").assertIsDisplayed().assertHasClickAction().performClick()
            node("session-add-library").assertIsDisplayed().assertHasClickAction().performClick()
            compose.waitUntil(15_000) { exists("exercise-picker-recent") }
            node("exercise-picker-content").assertWidthIsEqualTo(390.dp)
            node("exercise-picker-muscles").assertWidthIsEqualTo(390.dp)
            node("conformance:Search").assertWidthIsEqualTo(306.dp).assertHeightIsEqualTo(40.dp)
            node("conformance:Tab · 动作库").assertWidthIsEqualTo(66.dp).assertHeightIsEqualTo(30.dp)
            val tabs = node("session-add-tabs").getUnclippedBoundsInRoot()
            val search = node("exercise-picker-search-row").getUnclippedBoundsInRoot()
            assertEquals(12.dp, search.top - tabs.bottom)
            val chips = node("exercise-picker-muscles").getUnclippedBoundsInRoot()
            assertEquals(8.dp, chips.top - search.bottom)
            val recent = node("exercise-picker-recent").getUnclippedBoundsInRoot()
            assertEquals(8.dp, recent.top - chips.bottom)
            assertEquals(fixture.names, fixture.state.recentEntries.map { fixture.state.selection(it).name })
            val items = fixture.state.recentEntries
            val firstTag = "exercise-picker-recent-${items.first().exerciseID.value}"
            val first = node(firstTag).getUnclippedBoundsInRoot()
            val second = node("exercise-picker-recent-${items[1].exerciseID.value}").getUnclippedBoundsInRoot()
            assertEquals(358.dp, first.width)
            assertEquals(70f, (second.top - first.top).value, 0.5f)
            node("exercise-picker-muscle-胸").assertIsDisplayed().performClick()
            node("exercise-picker-recent").assertDoesNotExist()
            node("exercise-picker-muscle-all").performClick()
            compose.waitUntil(15_000) { exists(firstTag) }
            val before = f.state.content!!.exercises.size
            node(firstTag).assertIsDisplayed().assertHasClickAction().performClick()
            compose.waitUntil(15_000) { !exists("exercise-picker") }
            f.room.test {
                val saved = f.room.ok(f.room.sessions.loadContent(f.content.session.sessionID))!!
                assertEquals(before + 1, saved.exercises.size)
                assertEquals(items.first().exerciseID, saved.exercises.last().sourceID)
            }
        } finally { fixture.close() }
    }
}
