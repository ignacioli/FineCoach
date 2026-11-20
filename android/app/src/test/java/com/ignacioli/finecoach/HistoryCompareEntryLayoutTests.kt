// fictional-data: two invented completed sessions; no real coach or student.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.unit.width
import com.ignacioli.finecoach.core.application.ProgressUseCases
import com.ignacioli.finecoach.core.application.UpdateHistoryTrainingFocusCommand
import com.ignacioli.finecoach.core.domain.common.BodyPart
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.history.HistoryListScreen
import com.ignacioli.finecoach.features.history.HistoryUiState
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class HistoryCompareEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val f = T009Fixture()
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    @After fun close() { compose.runOnUiThread { compose.activity.setContent {} }; f.close() }

    @Test fun visibleSelectionComparesMatchingFocusAndExplainsAMismatch() {
        lateinit var state: HistoryUiState
        lateinit var progress: ProgressUseCases
        lateinit var first: String
        lateinit var second: String
        f.test {
            val a = f.content(); f.finish(a)
            val savedA = f.ok(f.sessions.loadContent(a.session.sessionID))!!
            f.ok(f.historyCases.saveFocusEdit(UpdateHistoryTrainingFocusCommand(savedA.session.sessionID, savedA.session.revision, setOf(BodyPart.chest))))
            f.now = f.now.plusSeconds(86_400)
            val b = f.content(); f.finish(b)
            val savedB = f.ok(f.sessions.loadContent(b.session.sessionID))!!
            f.ok(f.historyCases.saveFocusEdit(UpdateHistoryTrainingFocusCommand(savedB.session.sessionID, savedB.session.revision, setOf(BodyPart.back))))
            first = a.session.sessionID.value
            second = b.session.sessionID.value
            progress = ProgressUseCases(f.history, f.sessions)
            state = HistoryUiState(f.historyCases, f.studentID)
        }
        val before = f.count("sessions")
        compose.setContent { FineCoachTheme { HistoryListScreen(state, f.zone, {}, {}, progress) } }
        compose.waitUntil(15_000) { !state.busy && state.records.size == 2 }
        node("history-list-trailing").assertIsDisplayed().assertHasClickAction().performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithTag("history-compare-pick-$first", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        node("history-compare-pick-$first").performScrollTo().assertIsDisplayed().assertHasClickAction().performClick()
        node("history-compare-pick-$second").performScrollTo().assertIsDisplayed().assertHasClickAction().performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithTag("history-compare-incompatible", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        node("history-compare-incompatible").assertIsDisplayed().assertTextEquals("训练重点不同，无法对比，已分别展示。")
        assertEquals(node("history-results").getUnclippedBoundsInRoot().width, node("history-compare-panel").getUnclippedBoundsInRoot().width)
        assertEquals(before, f.count("sessions"))
    }
}
