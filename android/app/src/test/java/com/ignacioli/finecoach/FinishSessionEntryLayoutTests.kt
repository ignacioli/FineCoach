// fictional-data: isolated Room, invented students, packages and notes.
package com.ignacioli.finecoach

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.width
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.session.*
import com.ignacioli.finecoach.storage.repository.ExerciseRepository
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.graphics.Insets
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w320dp-h640dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class FinishSessionEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private lateinit var f: T009Fixture
    private lateinit var active: ActiveSessionUiState
    private lateinit var finish: FinishSessionUiState
    private lateinit var summary: SessionSummaryUiState
    private var returned = 0
    private var abandoned = 0
    private var summaryID: SessionID? = null
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    private fun await(tag: String) { compose.waitUntil(15_000) { exists(tag) } }
    private fun gone(tag: String) { compose.waitUntil(15_000) { !exists(tag) } }
    private fun click(tag: String) {
        val n = node(tag); if (n.onAncestors().filter(hasScrollAction()).fetchSemanticsNodes().isNotEmpty()) n.performScrollTo()
        n.assertIsDisplayed().assertHasClickAction().performClick(); compose.waitForIdle()
    }
    private fun text(tag: String, value: String) { node(tag).performScrollTo().assertIsDisplayed().performTextReplacement(value) }
    @Before fun prepare() {
        f = T009Fixture()
        f.test {
            val exercise = ExerciseUseCases(ExerciseRepository(f.db, ExerciseCatalogLoader(ApplicationProvider.getApplicationContext<Context>().assets), f.clock), f.clock, f.ids)
            val useCases = f.active
            active = ActiveSessionUiState(useCases, f.clock, f.ids, f.sessions, f.history, exercise)
            finish = FinishSessionUiState(active, f.finisher(useCases), f.sessions)
            summary = SessionSummaryUiState(f.historyCases, f.clock)
        }
    }
    @After fun close() {
        compose.runOnUiThread { compose.activity.setContent { } }; compose.waitForIdle()
        f.test { f.db.runInTransaction { } }; f.close()
    }
    private fun show(content: SessionContentRecord) {
        f.test { active.load(content.session.sessionID) }
        compose.setContent { FineCoachTheme { FinishSessionScreen(finish, { returned++ }, { abandoned++ }, { summaryID = it }, {}) } }
    }
    private fun read(id: SessionID): SessionContentRecord {
        compose.waitUntil(15_000) { !finish.busy && !active.busy && !summary.busy }
        lateinit var result: SessionContentRecord; f.test { result = f.ok(f.sessions.loadContent(id))!! }; return result
    }
    @Test fun emptyAbandonAndCancelNeverCreateLedgerOrCompletedHistory() {
        lateinit var original: SessionContentRecord
        f.test { original = f.content(completed = false) }; show(original); await("finish-abandon")
        click("finish-return"); assertEquals(1, returned); assertEquals(original, read(original.session.sessionID))
        click("finish-abandon"); compose.waitUntil(15_000) { abandoned == 1 }
        assertEquals(SessionState.abandonedEmpty, read(original.session.sessionID).session.state)
        f.test { assertEquals(0L, f.count("credit_adjustments")); assertTrue(f.ok(f.history.list(HistoryQuery())).isEmpty()) }
    }
    @Test fun unresolvedReturnThenExplicitDiscardCompletesWithoutPackageAndClearsRest() {
        lateinit var original: SessionContentRecord
        f.test { original = f.content(pending = true); active.rests.start(original.session.sessionID) }; show(original)
        await("finish-discard"); click("finish-return"); assertEquals(original, read(original.session.sessionID))
        assertEquals(node("finish-content").getUnclippedBoundsInRoot().width, node("finish-discard").getUnclippedBoundsInRoot().width)
        click("finish-discard"); compose.waitUntil(15_000) { summaryID != null }
        val saved = read(original.session.sessionID); assertEquals(SessionState.completed, saved.session.state)
        assertEquals(1, saved.exercises.single().sets.size); assertNull(active.rests.end(saved.session.sessionID))
        f.test { assertEquals(SessionCreditSettlementNote.noActivePackage, f.ok(f.history.find(saved.session.sessionID))!!.note); assertEquals(0L, f.count("credit_adjustments")) }
    }
    @Test fun explicitDebitIsDurableAndRepeatedConfirmationRemainsOneLedgerEntry() {
        lateinit var original: SessionContentRecord
        f.test { f.coursePackage(); original = f.content() }; show(original); await("finish-credit-accept")
        assertEquals(SessionState.completed, read(original.session.sessionID).session.state)
        f.test { assertEquals(0L, f.count("credit_adjustments")) }
        click("finish-credit-accept"); compose.waitUntil(15_000) { summaryID != null }
        f.test { assertEquals(1L, f.count("credit_adjustments")); f.ok(f.finisher.debitAdhoc(original.session.sessionID, f.ok(f.credits.activePackage(f.studentID, f.today))!!.coursePackageID)); assertEquals(1L, f.count("credit_adjustments")) }
    }
    @Test fun skipAndDialogCancellationWriteNoDebit() {
        lateinit var original: SessionContentRecord
        f.test { f.coursePackage(); original = f.content() }; show(original); await("finish-credit-cancel"); click("finish-credit-cancel")
        compose.waitUntil(15_000) { summaryID != null }
        f.test { assertEquals(0L, f.count("credit_adjustments")); assertEquals(SessionState.completed, f.ok(f.sessions.find(original.session.sessionID))!!.state) }
    }
    @Test fun debitFailurePreservesCompletedTrainingAndRetryNeverAutoDebits() {
        lateinit var original: SessionContentRecord
        f.test { f.coursePackage(); original = f.content() }; show(original); await("finish-credit-accept")
        f.test { f.failWrites("credit_adjustments", "INSERT") }; click("finish-credit-accept"); await("finish-error")
        assertNull(summaryID); assertEquals(SessionState.completed, read(original.session.sessionID).session.state)
        f.test { assertEquals(0L, f.count("credit_adjustments")); f.clearFailure() }
        click("finish-retry"); await("finish-credit-accept"); f.test { assertEquals(0L, f.count("credit_adjustments")) }
        click("finish-credit-accept"); compose.waitUntil(15_000) { summaryID != null }
        f.test { assertEquals(1L, f.count("credit_adjustments")) }
    }
    @Test fun summarySaveFailureRetainsInputsThenDurablySavesWithoutAnotherDebit() {
        lateinit var original: SessionContentRecord
        f.test { original = f.content(); f.finish(original) }
        compose.setContent { FineCoachTheme { SessionSummaryScreen(summary, original.session.sessionID, { returned++ }, { returned++ }) } }
        await("summary-private"); text("summary-private", "虚构私密提示"); text("summary-public", "虚构公开总结"); click("summary-focus-0")
        compose.runOnIdle { ViewCompat.dispatchApplyWindowInsets(compose.activity.window.decorView, WindowInsetsCompat.Builder().setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, 280)).setVisible(WindowInsetsCompat.Type.ime(), true).build()) }
        f.test { f.failWrites("sessions", "UPDATE") }; click("summary-save"); await("summary-error"); assertEquals(0, returned)
        node("summary-private").assertTextEquals("虚构私密提示")
        assertEquals(node("summary-content").getUnclippedBoundsInRoot().width, node("summary-save").getUnclippedBoundsInRoot().width)
        f.test { f.clearFailure() }; click("summary-save"); compose.waitUntil(15_000) { returned == 1 }
        val saved = read(original.session.sessionID); assertEquals("虚构私密提示", saved.session.privateCoachNote); assertEquals("虚构公开总结", saved.session.studentFacingSummary)
        assertEquals(setOf(BodyPart.chest), saved.session.trainingFocus)
        f.test { assertEquals(0L, f.count("credit_adjustments")) }
    }
    @Test fun failedCheckpointCompletionRetryUsesOriginalPendingCommand() {
        lateinit var original: SessionContentRecord
        f.test { original = f.content(); f.failWrites("sessions", "UPDATE") }; show(original); await("finish-error")
        assertEquals(SessionState.inProgress, read(original.session.sessionID).session.state)
        assertNull(summaryID); f.test { f.clearFailure() }; click("finish-retry")
        compose.waitUntil(15_000) { summaryID != null }
        assertEquals(SessionState.completed, read(original.session.sessionID).session.state)
    }
    @Test fun durationReviewBeforeCompletionRequiresExplicitSaveAndCancellationWritesNothing() {
        lateinit var original: SessionContentRecord
        f.test { original = f.content(); original = original.copy(session = f.ok(f.active.saveDraft(SaveSessionDraftCommand(original.session.sessionID,
            original.session.revision, original.session.draftPayload().copy(durationNeedsReview = true))))) }
        show(original); await("duration-review-input"); text("duration-review-input", "12分钟"); click("duration-review-cancel")
        assertEquals(original, read(original.session.sessionID)); assertEquals(1, returned)
        click("duration-review-confirm"); compose.waitUntil(15_000) { summaryID != null }
        assertEquals("720", read(original.session.sessionID).session.coachAdjustedDurationSeconds!!.toPlainString())
    }
    @Test fun expiredPackageOffersVisibleManualAdjustmentWithoutAutomaticDebit() {
        lateinit var original: SessionContentRecord
        f.test { f.coursePackage(endDate = f.today.minusDays(1)); original = f.content() }; show(original)
        await("finish-adjust"); node("finish-skip").assertIsDisplayed()
        f.test { assertEquals(0L, f.count("credit_adjustments")) }; click("finish-skip")
        compose.waitUntil(15_000) { summaryID != null }
        f.test { assertEquals(0L, f.count("credit_adjustments")) }
    }

}
