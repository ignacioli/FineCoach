// fictional-data: isolated file Room and invented training history, students and notes.
package com.ignacioli.finecoach

import android.content.Context
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.unit.width
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.exercises.*
import com.ignacioli.finecoach.features.templates.*
import com.ignacioli.finecoach.features.session.*
import com.ignacioli.finecoach.features.history.*
import com.ignacioli.finecoach.storage.repository.ExerciseRepository
import kotlinx.coroutines.CompletableDeferred
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class S3SessionGainsEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private lateinit var f: T009Fixture
    private lateinit var active: ActiveSessionUiState
    private lateinit var exercises: ExerciseUiState
    private lateinit var templates: TemplateUiState
    private lateinit var progress: ProgressUseCases
    private lateinit var current: SessionContentRecord
    private var reads = 0
    private var haptics = 0
    private var source = StableExerciseID.parse("fictional.pending")
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    private fun await(tag: String) = compose.waitUntil(15_000) { exists(tag) }
    private fun click(tag: String) {
        val n = node(tag)
        if (n.onAncestors().filter(hasScrollAction()).fetchSemanticsNodes().isNotEmpty()) n.performScrollTo()
        n.assertIsDisplayed().assertIsEnabled().assertHasClickAction().performClick()
        compose.waitForIdle()
    }
    private fun waitSaved() = compose.waitUntil(15_000) { !active.busy && active.content!!.session.revision != current.session.revision }
    private fun full(tag: String, parent: String) = assertEquals(node(parent).getUnclippedBoundsInRoot().width, node(tag).getUnclippedBoundsInRoot().width)
    private fun read(): SessionContentRecord { lateinit var value: SessionContentRecord; f.test { value = f.ok(f.sessions.loadContent(current.session.sessionID))!! }; return value }
    @Before fun prepare() {
        f = T009Fixture()
        f.test {
            val repo = ExerciseRepository(f.db, ExerciseCatalogLoader(ApplicationProvider.getApplicationContext<Context>().assets), f.clock)
            repo.prepareCatalog()
            source = f.ok(repo.listCatalog()).single { it.canonicalName == "杠铃深蹲" }.exerciseID
            val prior = f.content(sourceID = source); f.finish(prior)
            f.now = f.now.plusSeconds(3600)
            current = f.content(completed = false, sourceID = source)
            val cases = ExerciseUseCases(repo, f.clock, f.ids)
            exercises = ExerciseUiState(cases, repo)
            templates = TemplateUiState(TemplateUseCases(com.ignacioli.finecoach.storage.repository.TemplateRepository(
                f.db, f.clock, f.ids, java.util.UUID.fromString(f.db.storeMetadataDao().find(com.ignacioli.finecoach.storage.FineCoachDatabaseFactory.GENERATION_KEY)!!.value)), f.clock), f.clock, f.ids)
            val history = object : HistoryRepositoryPort by f.history {
                override suspend fun list(query: HistoryQuery): ApplicationResult<List<SessionHistoryRecord>> { reads++; return f.history.list(query) }
            }
            progress = ProgressUseCases(history, f.sessions)
            active = ActiveSessionUiState(f.active, f.clock, f.ids, f.sessions, history, cases, progress = progress, zone = f.zone)
        }
        Settings.Global.putFloat(compose.activity.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
    }
    @After fun close() {
        compose.mainClock.autoAdvance = true
        compose.runOnUiThread { compose.activity.setContent { } }; compose.waitForIdle()
        f.close()
    }
    private fun show() {
        compose.setContent { FineCoachTheme { ActiveSessionScreen(active, current.session.sessionID, exercises, templates, {}, {}, confirmationHaptic = { haptics++ }) } }
        await("set-save"); compose.waitUntil(15_000) { !active.busy && !exercises.busy }
    }
    private fun add(weight: String): TrainingSetRecord {
        node("set-weight-input").performScrollTo().performTextReplacement(weight)
        click("set-save")
        compose.waitUntil(15_000) { !active.busy && active.content!!.exercises.first().sets.size > current.exercises.first().sets.size }
        current = read()
        return current.exercises.first().sets.last()
    }
    @Test fun entryPublishesRowsOnlyAfterHistorySnapshotSoVisibleBackIsActionable() {
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        var backs = 0
        f.test {
            val repo = ExerciseRepository(f.db, ExerciseCatalogLoader(ApplicationProvider.getApplicationContext<Context>().assets), f.clock)
            val cases = ExerciseUseCases(repo, f.clock, f.ids)
            val delayed = ProgressUseCases(f.history, f.sessions) {
                entered.complete(Unit)
                release.await()
                ApplicationResult.Success(emptySet())
            }
            active = ActiveSessionUiState(f.active, f.clock, f.ids, f.sessions, f.history, cases, progress = delayed, zone = f.zone)
        }
        compose.setContent { FineCoachTheme {
            ActiveSessionScreen(active, current.session.sessionID, exercises, templates, { backs++ }, {})
        } }
        compose.waitUntil(15_000) { entered.isCompleted }
        try {
            assertTrue(active.busy)
            node("session-set-${current.exercises.first().sets.single().trainingSetID.value}").assertDoesNotExist()
        } finally { release.complete(Unit) }
        await("session-set-${current.exercises.first().sets.single().trainingSetID.value}")
        assertFalse(active.busy)
        click("active-session-back")
        assertEquals(1, backs)
        assertEquals(current, read())
    }
    @Test fun confirmEditDeleteRestoreAndUndoRecomputeWithoutExtraFeedbackOrHistoryReads() {
        show()
        val entryReads = reads
        assertEquals(1, entryReads)
        val first = add("12.5")
        val firstTag = "session-set-${first.trainingSetID.value}"
        await("$firstTag-record"); assertEquals(1, haptics)
        assertEquals("10", active.previous.values.single().weightValue!!.toPlainString())
        full(firstTag, "session-exercises")
        val second = add("15")
        val secondTag = "session-set-${second.trainingSetID.value}"
        await("$secondTag-record"); node("$firstTag-record").assertDoesNotExist(); assertEquals(2, haptics)
        click("$secondTag-edit"); await("set-editor-content")
        node("set-weight-input").performScrollTo().performTextReplacement("11")
        click("set-save"); compose.waitUntil(15_000) { !active.busy && active.gains.recordHolderSetIDs == setOf(first.trainingSetID) }
        current = read(); assertEquals("11", current.exercises.first().sets.last().weightValue!!.toPlainString()); assertEquals(2, haptics)
        node("$firstTag-swipe").performScrollTo().performTouchInput { swipeLeft(startX = width * 0.9f, endX = width * 0.5f) }
        click("session-set-delete")
        compose.waitUntil(15_000) { !active.busy && active.deleted != null }
        assertEquals(setOf(second.trainingSetID), active.gains.recordHolderSetIDs)
        assertEquals(2, read().exercises.first().sets.size)
        click("session-deleted-action")
        compose.waitUntil(15_000) { !active.busy && active.deleted == null }
        assertEquals(setOf(first.trainingSetID), active.gains.recordHolderSetIDs)
        assertEquals(3, read().exercises.first().sets.size)
        click("$secondTag-undo")
        compose.waitUntil(15_000) { !active.busy && active.entryPrefill != null }
        assertEquals(2, read().exercises.first().sets.size)
        assertEquals(2, haptics); assertEquals(entryReads, reads)
    }
    @Test fun pendingConfirmationUsesOneHapticAndFailureUsesNone() {
        show()
        val set = current.exercises.first().sets.single()
        click("session-set-${set.trainingSetID.value}-confirm")
        waitSaved()
        assertEquals(SetRecordingState.completed, read().exercises.first().sets.single().state)
        assertEquals(1, haptics)
        // Same weight as history: no record, still one confirmation feedback.
        assertTrue(active.gains.recordHolderSetIDs.isEmpty())
        node("set-weight-input").performScrollTo().performTextReplacement("bad")
        click("set-save"); await("set-error"); assertEquals(1, haptics)
        assertEquals(1, read().exercises.first().sets.size)
    }
    @Test fun disabledAnimationsKeepBadgeAndDoNotFloat() {
        Settings.Global.putFloat(compose.activity.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 0f)
        show(); val set = add("12.5")
        val tag = "session-set-${set.trainingSetID.value}"
        await("$tag-record"); node("$tag-record-float").assertDoesNotExist()
        assertEquals(1, haptics)
        compose.mainClock.advanceTimeBy(2000); node("$tag-record-float").assertDoesNotExist()
    }
    @Test fun processStyleReopenRecomputesSameHoldersWithoutConfirmationEvent() {
        show(); val set = add("12.5")
        val before = active.gains
        compose.runOnUiThread { compose.activity.setContent { } }; compose.waitForIdle()
        f.test {
            f.reopen()
            val repo = ExerciseRepository(f.db, ExerciseCatalogLoader(ApplicationProvider.getApplicationContext<Context>().assets), f.clock)
            val restored = ActiveSessionUiState(f.active, f.clock, f.ids, f.sessions, f.history, ExerciseUseCases(repo, f.clock, f.ids))
            restored.load(current.session.sessionID)
            assertEquals(before, restored.gains); assertTrue(restored.confirmations.isEmpty())
            assertEquals(setOf(set.trainingSetID), restored.gains.recordHolderSetIDs)
        }
    }
    @Test fun summaryHistoryAndReopenAgreeAndDoNotRewriteNotes() {
        lateinit var summary: SessionSummaryUiState
        lateinit var history: HistoryUiState
        f.test {
            active.load(current.session.sessionID)
            f.ok(active.confirmSet(current.exercises.first().sets.single().trainingSetID))
            f.ok(active.saveSet(current.exercises.first().sessionExerciseID, null,
                TrainingSetInput(RecordMode.weightReps, weightValue = "15", repetitionCount = "8", unit = MeasurementUnit.kilograms)))
            f.finish(active.content!!)
            val session = f.ok(f.sessions.loadContent(current.session.sessionID))!!.session
            f.ok(f.historyCases.saveSummary(SaveCompletedSessionSummaryCommand(session.sessionID, session.revision,
                emptySet(), "虚构公开总结", "虚构教练备注", f.now)))
            summary = SessionSummaryUiState(f.historyCases, f.clock, ProgressUseCases(f.history, f.sessions), f.zone)
            summary.load(session.sessionID)
            history = HistoryUiState(f.historyCases, null, progress = ProgressUseCases(f.history, f.sessions), zone = f.zone)
            history.load(session.sessionID)
        }
        assertFalse(summary.gains.isEmpty); assertEquals(summary.gains, history.gains)
        compose.setContent { FineCoachTheme { SessionSummaryScreen(summary, current.session.sessionID, {}, {}) } }
        await("summary-gains-action-0"); full("summary-gains", "summary-content")
        for (tag in listOf("summary-private", "summary-public")) {
            val input = node(tag).performScrollTo().assertIsDisplayed().assertIsEnabled().assertHasClickAction()
            val field = input.fetchSemanticsNode()
            val viewport = node("summary-content").fetchSemanticsNode().boundsInRoot
            assertEquals("$tag must not be horizontally clipped", field.size.width.toFloat(), field.boundsInRoot.width, 0f)
            assertEquals("$tag must not be vertically clipped", field.size.height.toFloat(), field.boundsInRoot.height, 0f)
            assertTrue("$tag must fit inside the scroll viewport", field.boundsInRoot.top >= viewport.top && field.boundsInRoot.bottom <= viewport.bottom)
            input.performClick().assertIsFocused()
        }
        assertEquals("虚构公开总结", summary.publicSummary); assertEquals("虚构教练备注", summary.privateNote)
        val expected = summary.gains
        compose.runOnUiThread { compose.activity.setContent { } }; compose.waitForIdle()
        f.test {
            f.reopen()
            history = HistoryUiState(f.historyCases, null, progress = ProgressUseCases(f.history, f.sessions), zone = f.zone)
            history.load(current.session.sessionID)
            assertEquals(expected, history.gains)
            assertEquals("虚构公开总结", history.detail!!.content.session.studentFacingSummary)
            assertEquals("虚构教练备注", history.detail!!.content.session.privateCoachNote)
        }
        compose.runOnUiThread { compose.activity.setContent { FineCoachTheme { HistoryDetailScreen(history, current.session.sessionID, f.zone, {}) } } }
        await("history-gains-action-0"); node("history-gains").performScrollTo().assertIsDisplayed()
        full("history-gains", "history-record-card")
        assertEquals("虚构公开总结", read().session.studentFacingSummary)
        assertEquals("虚构教练备注", read().session.privateCoachNote)
    }
    @Test fun emptyGainsOmitWholeSectionAndLeaveNotesBlank() {
        lateinit var summary: SessionSummaryUiState
        f.test {
            active.load(current.session.sessionID)
            f.ok(active.confirmSet(current.exercises.first().sets.single().trainingSetID))
            f.finish(active.content!!)
            summary = SessionSummaryUiState(f.historyCases, f.clock, progress, f.zone)
        }
        compose.setContent { FineCoachTheme { SessionSummaryScreen(summary, current.session.sessionID, {}, {}) } }
        await("summary-private"); node("summary-gains").assertDoesNotExist()
        assertEquals("", summary.publicSummary); assertEquals("", summary.privateNote)
        assertNull(read().session.studentFacingSummary); assertNull(read().session.privateCoachNote)
    }
}
