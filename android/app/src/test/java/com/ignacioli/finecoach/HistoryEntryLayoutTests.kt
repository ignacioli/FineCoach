// fictional-data: isolated Room with invented students, snapshots and notes.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.width
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.history.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w320dp-h640dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class HistoryEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private lateinit var f: T009Fixture
    private lateinit var state: HistoryUiState
    private var back = 0
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    private fun await(tag: String) { compose.waitUntil(15_000) { exists(tag) } }
    private fun gone(tag: String) { compose.waitUntil(15_000) { !exists(tag) } }
    private fun click(tag: String) {
        val n = node(tag); if (n.onAncestors().filter(hasScrollAction()).fetchSemanticsNodes().isNotEmpty()) n.performScrollTo()
        n.assertIsDisplayed().assertHasClickAction().performClick(); compose.waitForIdle()
        compose.waitUntil(15_000) { !state.busy }
    }
    @Before fun prepare() { f = T009Fixture(); f.test { state = HistoryUiState(f.historyCases, f.studentID) } }
    @After fun close() { compose.runOnUiThread { compose.activity.setContent { } }; compose.waitForIdle(); f.test { f.db.runInTransaction { } }; f.close() }
    private fun completed(): SessionContentRecord {
        lateinit var content: SessionContentRecord
        f.test { content = f.content(); f.finish(content) }; return content
    }
    private fun read(id: SessionID): SessionContentRecord { lateinit var value: SessionContentRecord; f.test { value = f.ok(f.sessions.loadContent(id))!! }; return value }
    @Test fun emptyHistoryAndNoMatchAreDistinctAndClearRestoresResultsInDescendingOrder() {
        val first = completed()
        f.test { f.now = f.now.plusSeconds(24 * 60 * 60) }
        val second = completed()
        var route = ""
        compose.setContent { FineCoachTheme { HistoryListScreen(state, f.zone, { route = it }, { back++ }) } }
        await("history-open-${second.session.sessionID.value}")
        assertEquals(listOf(second.session.sessionID, first.session.sessionID), state.records.map { it.sessionID })
        click("history-filter-focus-0"); await("history-no-matches")
        click("history-filter-clear"); await("history-open-${second.session.sessionID.value}")
        HistoryWindowDays.entries.forEach { click("history-window-${it.days}"); assertEquals(it, state.query.window) }
        click("history-open-${first.session.sessionID.value}"); assertEquals(com.ignacioli.finecoach.navigation.S1Routes.historyDetail(first.session.sessionID), route)
        click("history-list-back"); assertEquals(1, back)
    }
    @Test fun onlyInProgressDoesNotAppearAsCompletedHistory() {
        f.test { f.content() }
        compose.setContent { FineCoachTheme { HistoryListScreen(state, f.zone, {}, {}) } }
        await("history-empty"); assertTrue(state.records.isEmpty())
    }
    @Test fun focusEditCancelSystemBackAndSavePreserveIdentitySnapshotsAndLedger() {
        val original = completed(); val before = read(original.session.sessionID)
        compose.setContent { FineCoachTheme { HistoryDetailScreen(state, original.session.sessionID, f.zone, { back++ }) } }
        await("history-detail-trailing"); compose.waitUntil(15_000) { state.detail != null }
        click("history-detail-trailing"); click("history-edit-focus-0"); click("history-edit-cancel")
        assertEquals(before, read(original.session.sessionID))
        click("history-detail-trailing"); click("history-edit-focus-1")
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }; gone("history-edit-save")
        assertEquals(before, read(original.session.sessionID))
        click("history-detail-trailing"); click("history-edit-focus-2")
        assertEquals(node("history-edit-content").getUnclippedBoundsInRoot().width, node("history-edit-save").getUnclippedBoundsInRoot().width)
        click("history-edit-save"); gone("history-edit-save")
        val saved = read(original.session.sessionID)
        assertEquals(setOf(BodyPart.back), saved.session.trainingFocus); assertEquals(before.exercises, saved.exercises)
        assertEquals(before.session.completedAtUTC, saved.session.completedAtUTC)
        f.test { assertEquals(0L, f.count("credit_adjustments")) }
        compose.runOnUiThread { compose.activity.setContent { } }; compose.waitForIdle(); f.test { f.db.runInTransaction { }; f.reopen() }
        assertEquals(saved, read(original.session.sessionID))
    }
    @Test fun failedFocusSaveDoesNotExitOrChangePersistedRecord() {
        val original = completed(); val before = read(original.session.sessionID)
        compose.setContent { FineCoachTheme { HistoryDetailScreen(state, original.session.sessionID, f.zone, {}) } }
        compose.waitUntil(15_000) { state.detail != null }; click("history-detail-trailing"); click("history-edit-focus-0")
        f.test { f.failWrites("sessions", "UPDATE") }; click("history-edit-save"); await("history-edit-error")
        assertEquals(before, read(original.session.sessionID)); assertEquals(setOf(BodyPart.chest), state.focus)
        f.test { f.clearFailure() }; click("history-edit-save"); gone("history-edit-save")
        assertEquals(setOf(BodyPart.chest), read(original.session.sessionID).session.trainingFocus)
    }
    @Test fun detailRendersStoredSnapshotAndCoachOnlyCreditNoteWithoutFutureEntries() {
        val original = completed()
        compose.setContent { FineCoachTheme { HistoryDetailScreen(state, original.session.sessionID, f.zone, {}) } }
        await("history-credit-note")
        val row = original.exercises.single(); node("history-snapshot-${row.sessionExerciseID.value}").assertTextEquals(row.displayNameSnapshot)
        node("history-set-${row.sets.single().trainingSetID.value}").assertExists()
        listOf("history-reopen", "history-share", "history-compare", "history-edit-private").forEach { node(it).assertDoesNotExist() }
    }
    @Test fun exerciseFilterUsesCompletedSnapshotIDsAndCancelLeavesQueryUnchanged() {
        val exercise = StableExerciseID.parse("abcdef00-0000-4000-8000-000000000081")
        lateinit var original: SessionContentRecord
        f.test { original = f.content(sourceID = exercise); f.finish(original) }
        compose.setContent { FineCoachTheme { HistoryListScreen(state, f.zone, {}, {}) } }
        await("history-open-${original.session.sessionID.value}")
        click("history-filter-exercise"); click("history-filter-cancel"); assertTrue(state.query.exerciseIDs.isEmpty())
        click("history-filter-exercise"); click("history-filter-exercise-${exercise.value}")
        assertEquals(setOf(exercise), state.query.exerciseIDs); assertEquals(original.session.sessionID, state.records.single().sessionID)
        click("history-filter-clear"); assertTrue(state.query.exerciseIDs.isEmpty())
    }

    private fun templateState(): HistoryTemplateState {
        lateinit var result: HistoryTemplateState
        f.test { val generation = java.util.UUID.fromString(f.db.storeMetadataDao().find(com.ignacioli.finecoach.storage.FineCoachDatabaseFactory.GENERATION_KEY)!!.value)
            val repository = com.ignacioli.finecoach.storage.repository.TemplateRepository(f.db, f.clock, f.ids, generation)
            result = HistoryTemplateState(TemplateUseCases(repository, f.clock), f.clock, f.ids)
        }; return result
    }
    @Test fun templateCancelIsZeroWriteAndSaveCreatesIndependentSnapshotWithoutPrivateData() {
        val original = completed(); val templates = templateState()
        compose.setContent { FineCoachTheme { HistoryDetailScreen(state, original.session.sessionID, f.zone, {}, templates) } }
        await("history-save-template"); click("history-save-template")
        node("history-template-name").performScrollTo().performTextReplacement("虚构模板")
        click("history-template-cancel"); f.test { assertEquals(0L, f.count("training_templates")) }
        click("history-save-template")
        assertEquals(node("history-template-content").getUnclippedBoundsInRoot().width, node("history-template-save").getUnclippedBoundsInRoot().width)
        click("history-template-save"); gone("history-template-content")
        val saved = templates.saved!!
        assertEquals(original.exercises.single().displayNameSnapshot, saved.exercises.single().displayNameSnapshot)
        assertNotEquals(original.exercises.single().sessionExerciseID.value, saved.exercises.single().templateExerciseID.value)
        assertTrue(saved.template.trainingFocus.isEmpty())
        assertFalse(saved.toString().contains("虚构动作私密备注"))
        f.test { assertEquals(1L, f.count("training_templates")); assertEquals(0L, f.count("credit_adjustments")) }
    }
    @Test fun templateContentFailureKeepsSameCreatedIDAndExplicitRetryDoesNotDuplicate() {
        val original = completed(); val templates = templateState()
        compose.setContent { FineCoachTheme { HistoryDetailScreen(state, original.session.sessionID, f.zone, {}, templates) } }
        await("history-save-template"); click("history-save-template")
        node("history-template-name").performScrollTo().performTextReplacement("虚构重试模板")
        f.test { f.failWrites("template_exercises", "INSERT") }; click("history-template-save"); await("history-template-error")
        assertNull(templates.saved); val id = templates.created!!.templateID
        f.test { assertEquals(1L, f.count("training_templates")); f.clearFailure() }
        click("history-template-save"); gone("history-template-content")
        assertEquals(id, templates.saved!!.template.templateID)
        f.test { assertEquals(1L, f.count("training_templates")); assertEquals(1L, f.count("template_exercises")) }
    }

}
