// fictional-data: invented students, exercises and isolated temporary Room database.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.width
import androidx.compose.ui.unit.height
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.graphics.Insets
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.session.*
import com.ignacioli.finecoach.features.exercises.*
import com.ignacioli.finecoach.features.templates.*
import com.ignacioli.finecoach.storage.repository.HistoryRepository
import java.time.ZoneOffset
import kotlinx.coroutines.*
import java.util.concurrent.atomic.AtomicInteger
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w320dp-h640dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SessionRecoveryEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private lateinit var f: T008Fixture
    private lateinit var state: ActiveSessionUiState
    private lateinit var exercises: ExerciseUiState
    private lateinit var templates: TemplateUiState
    private var back = 0
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    private fun await(tag: String) { compose.waitUntil(15_000) { exists(tag) } }
    private fun gone(tag: String) { compose.waitUntil(15_000) { !exists(tag) } }
    private fun click(tag: String) {
        val n = node(tag)
        if (n.onAncestors().filter(hasScrollAction()).fetchSemanticsNodes().isNotEmpty()) n.performScrollTo()
        n.assertIsDisplayed().assertHasClickAction().performClick(); compose.waitForIdle()
    }
    private fun text(tag: String, value: String) { node(tag).performScrollTo().assertIsDisplayed().performTextReplacement(value) }
    private fun full(tag: String, parent: String) = assertEquals(node(parent).getUnclippedBoundsInRoot().width, node(tag).getUnclippedBoundsInRoot().width)
    @Before fun prepare() {
        f = T008Fixture()
        f.test {
            f.student(1)
            val useCases = ExerciseUseCases(f.exercises, f.clock, f.ids)
            exercises = ExerciseUiState(useCases, f.exercises)
            templates = TemplateUiState(f.templateUseCases, f.clock, f.ids)
            state = ActiveSessionUiState(f.useCases, f.clock, f.ids, f.sessions,
                HistoryRepository(f.db, f.clock, f.generation, ZoneOffset.UTC), useCases)
        }
    }
    @After fun close() {
        compose.runOnUiThread { compose.activity.setContent { } }; compose.waitForIdle()
        f.test { f.db.runInTransaction { } }; f.close()
    }
    private fun <T> ok(result: ApplicationResult<T>) = f.ok(result)
    private fun content(completed: Boolean = false): SessionContentRecord {
        lateinit var result: SessionContentRecord
        f.test { result = f.sessionContent(completed) }
        return result
    }
    private fun show(original: SessionContentRecord) {
        compose.setContent { FineCoachTheme { ActiveSessionScreen(state, original.session.sessionID, exercises, templates, { back++ }, {}) } }
        await("session-add-exercise")
        compose.waitUntil(15_000) { !state.busy }
    }
    private fun read(id: SessionID): SessionContentRecord {
        compose.waitUntil(15_000) { !state.busy }
        lateinit var result: SessionContentRecord
        f.test { result = ok(f.sessions.loadContent(id))!! }; return result
    }
    private fun reopen() {
        compose.runOnUiThread { compose.activity.setContent { } }; compose.waitForIdle()
        f.test { f.db.runInTransaction { }; f.reopen() }
    }
    @Test fun failedSetSaveBlocksFinishAndVisibleRetryCommitsOriginalCommand() {
        val original = content(); show(original)
        f.test { f.failWrites("training_sets", "INSERT") }
        click("session-set-${original.exercises.first().sets.first().trainingSetID.value}-confirm")
        compose.waitUntil(15_000) { !state.busy }
        assertEquals("confirm failure: ${state.error?.code}", FcSaveState.Failed, state.saveState)
        await("save-retry"); node("session-finish").assertIsNotEnabled()
        node("save-status-failed").assertIsDisplayed().assertContentDescriptionEquals("保存失败")
        node("save-finish-blocked").assertIsDisplayed()
        node("save-status-saved").assertDoesNotExist()
        full("save-retry", "save-status-content")
        assertEquals(original, read(original.session.sessionID))
        f.test { f.clearFailure() }; click("save-retry")
        gone("save-status-content"); gone("save-retry"); node("save-status-saved").assertDoesNotExist()
        assertEquals(SetRecordingState.completed, read(original.session.sessionID).exercises.first().sets.first().state)
        assertNotNull(state.rests.end(original.session.sessionID))
        node("session-finish").assertIsEnabled()
    }
    @Test fun savingRemainsAccessibleAndSavedRemovesTheWholePageStatusSlot() {
        val original = content()
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        f.test {
            val delegate = f.sessions
            val suspended = object : SessionRepositoryPort by delegate {
                override suspend fun saveContent(command: SaveSessionContentCommand): ApplicationResult<SessionContentRecord> {
                    entered.complete(Unit)
                    release.await()
                    return delegate.saveContent(command)
                }
            }
            state = ActiveSessionUiState(ActiveSessionUseCases(suspended, f.clock, f.ids), f.clock, f.ids,
                suspended, HistoryRepository(f.db, f.clock, f.generation, ZoneOffset.UTC),
                ExerciseUseCases(f.exercises, f.clock, f.ids))
        }
        show(original)
        node("save-status-content").assertDoesNotExist()
        click("session-set-${original.exercises.first().sets.first().trainingSetID.value}-confirm")
        try {
            compose.waitUntil(15_000) { entered.isCompleted }
            await("save-status-saving")
            node("save-status-saving").assertIsDisplayed().assertContentDescriptionEquals("保存中")
            node("save-status-saved").assertDoesNotExist()
            node("session-finish").assertIsNotEnabled()
        } finally { release.complete(Unit) }
        gone("save-status-content")
        node("save-status-saved").assertDoesNotExist()
        assertEquals(FcSaveState.Saved, state.saveState)
        assertEquals(SetRecordingState.completed, read(original.session.sessionID).exercises.first().sets.first().state)
    }
    @Test fun confirmedSetStartsRestAndVisibleAdjustSkipCloseAreIsolatedAndFullWidth() {
        val original = content(); show(original)
        val other = SessionID.parse("abcdef00-0000-4000-8000-000000000099")
        compose.runOnIdle { state.rests.start(other) }
        click("session-set-${original.exercises.first().sets.first().trainingSetID.value}-confirm"); await("rest-content")
        full("rest-content", "platform-content")
        val bar = node("rest-content").getUnclippedBoundsInRoot()
        val finish = node("session-finish").getUnclippedBoundsInRoot()
        assertTrue(bar.bottom <= finish.top)
        listOf("rest-plus", "rest-minus", "rest-skip").forEach { tag ->
            node(tag).assertIsDisplayed().assertHasClickAction()
                .assertTouchWidthIsEqualTo(FcSpacing.space8 + FcSpacing.space4)
                .assertTouchHeightIsEqualTo(FcSpacing.space8 + FcSpacing.space4)
            val button = node(tag).getUnclippedBoundsInRoot()
            assertTrue(button.left >= bar.left && button.right <= bar.right)
            assertTrue(button.top >= bar.top && button.bottom <= bar.bottom)
        }
        assertEquals(FcSpacing.space3, node("rest-plus").getUnclippedBoundsInRoot().left - node("rest-minus").getUnclippedBoundsInRoot().right)
        assertEquals(FcSpacing.space3, node("rest-skip").getUnclippedBoundsInRoot().left - node("rest-plus").getUnclippedBoundsInRoot().right)
        node("rest-remaining").assertTextEquals("2:00")
        val plus = node("rest-plus").getUnclippedBoundsInRoot()
        // Inject outside the visible text box, within its expanded touch target.
        node("rest-content").performTouchInput {
            click(androidx.compose.ui.geometry.Offset((plus.left + plus.width / 2 - bar.left).toPx(),
                (plus.top - 3.dp - bar.top).toPx()))
        }
        assertEquals(135L, state.rests.remaining(original.session.sessionID))
        click("rest-minus"); assertEquals(120L, state.rests.remaining(original.session.sessionID))
        click("rest-plus"); assertEquals(135L, state.rests.remaining(original.session.sessionID))
        click("rest-minus"); assertEquals(120L, state.rests.remaining(original.session.sessionID))
        compose.runOnIdle {
            ViewCompat.dispatchApplyWindowInsets(compose.activity.window.decorView,
                WindowInsetsCompat.Builder().setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, 280)).setVisible(WindowInsetsCompat.Type.ime(), true).build())
        }
        gone("rest-content"); assertNotNull(state.rests.end(original.session.sessionID))
        compose.runOnIdle {
            ViewCompat.dispatchApplyWindowInsets(compose.activity.window.decorView,
                WindowInsetsCompat.Builder().setInsets(WindowInsetsCompat.Type.ime(), Insets.NONE).setVisible(WindowInsetsCompat.Type.ime(), false).build())
        }
        await("rest-skip")
        click("rest-skip"); gone("rest-content"); assertNotNull(state.rests.end(other))
        compose.runOnIdle { state.rests.start(original.session.sessionID); f.time = f.now.plusSeconds(120) }
        await("rest-close"); full("rest-content", "platform-content")
        node("rest-close").assertIsDisplayed().assertWidthIsAtLeast(FcComponentMetrics.touch)
        node("rest-ended").assertTextEquals("休息结束，可以开始下一组")
        compose.runOnIdle { f.time = f.now.plusSeconds(125) }
        compose.mainClock.advanceTimeBy(1100); await("rest-overdue")
        node("rest-overdue").assertTextEquals("已超时 0:05")
        click("rest-close"); gone("rest-content")
    }
    @Test fun checkpointAndLaunchRecoveryRestoreMultipleSessionsAcrossDatabaseReopen() {
        val original = content(true)
        lateinit var other: SessionRecord
        f.test { f.student(2); other = f.start(2) }
        show(original)
        f.test { state.checkpoint(true) }
        val saved = read(original.session.sessionID)
        reopen()
        lateinit var recovery: SessionRecoveryState
        f.test { f.time = f.now.plusSeconds(1801); recovery = SessionRecoveryState(RecoveryCoordinator(f.sessions, f.clock)) }
        var opened: SessionID? = null
        compose.runOnUiThread { compose.activity.setContent { FineCoachTheme { SessionRecoveryEntry(recovery, { opened = it }) } } }
        await("recovery-open-${original.session.sessionID.value}"); full("recovery-open-${original.session.sessionID.value}", "recovery-content")
        click("recovery-open-${original.session.sessionID.value}"); assertEquals(original.session.sessionID, opened)
        assertEquals(saved.exercises, read(original.session.sessionID).exercises)
        assertTrue(read(original.session.sessionID).session.durationNeedsReview)
        click("recovery-open-${other.sessionID.value}"); assertEquals(other.sessionID, opened)
    }
    @Test fun durationReviewCancelInvalidAndConfirmAreDurableAndKeyboardSafe() {
        var original = content(true)
        f.test { original = original.copy(session = ok(f.useCases.saveDraft(SaveSessionDraftCommand(original.session.sessionID,
            original.session.revision, original.session.draftPayload().copy(durationNeedsReview = true))))) }
        show(original); click("session-review-duration"); text("duration-review-input", "-1"); click("duration-review-confirm")
        await("duration-review-error"); assertEquals(original, read(original.session.sessionID))
        click("duration-review-cancel"); assertEquals(original, read(original.session.sessionID))
        click("session-review-duration"); text("duration-review-input", "20分钟")
        compose.runOnIdle { ViewCompat.dispatchApplyWindowInsets(compose.activity.window.decorView,
            WindowInsetsCompat.Builder().setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, 280)).setVisible(WindowInsetsCompat.Type.ime(), true).build()) }
        full("duration-review-input", "duration-review-content"); full("duration-review-confirm", "duration-review-content")
        click("duration-review-confirm"); gone("duration-review-input")
        val saved = read(original.session.sessionID)
        assertFalse(saved.session.durationNeedsReview); assertEquals("1200", saved.session.coachAdjustedDurationSeconds!!.toPlainString())
        reopen(); assertEquals(saved, read(original.session.sessionID))
    }
    @Test fun recoveryFailureOffersVisibleRetryWithoutClaimingSuccess() {
        val original = content()
        lateinit var recovery: SessionRecoveryState
        f.test { f.failWrites("sessions", "UPDATE"); recovery = SessionRecoveryState(RecoveryCoordinator(f.sessions, f.clock)) }
        compose.setContent { FineCoachTheme { SessionRecoveryEntry(recovery, {}) } }
        await("recovery-error"); assertTrue(recovery.sessions.isEmpty())
        f.test { f.clearFailure() }; click("recovery-retry"); await("recovery-open-${original.session.sessionID.value}")
        assertEquals(1, recovery.sessions.size)
    }
    @Test fun backgroundDuringRecoveryQueuesCheckpointAndStaleRetryRefreshesRevisionDurably() {
        val original = content(true)
        val enteredRecoveryWrite = CompletableDeferred<Unit>()
        val releaseRecoveryWrite = CompletableDeferred<Unit>()
        val attempts = AtomicInteger()
        f.test {
            ok(f.sessions.saveDraft(SaveSessionDraftCommand(original.session.sessionID, original.session.revision,
                original.session.draftPayload().copy(interruptionStartedAtUTC = f.now))))
            val delegate = f.sessions
            val interleaved = object : SessionRepositoryPort by delegate {
                override suspend fun saveDraft(command: SaveSessionDraftCommand): ApplicationResult<SessionRecord> {
                    when (attempts.incrementAndGet()) {
                        1 -> {
                            enteredRecoveryWrite.complete(Unit)
                            releaseRecoveryWrite.await()
                        }
                        2 -> {
                            // A real independent Room write invalidates the checkpoint's CAS revision.
                            val latest = ok(delegate.loadContent(command.sessionID))!!.session
                            ok(delegate.saveDraft(SaveSessionDraftCommand(command.sessionID, latest.revision,
                                latest.draftPayload().copy(trainingFocus = setOf(BodyPart.back)))))
                        }
                    }
                    return delegate.saveDraft(command)
                }
            }
            state = ActiveSessionUiState(ActiveSessionUseCases(interleaved, f.clock, f.ids), f.clock, f.ids,
                interleaved, HistoryRepository(f.db, f.clock, f.generation, ZoneOffset.UTC),
                ExerciseUseCases(f.exercises, f.clock, f.ids))
        }
        show(original)
        compose.waitUntil(15_000) { !state.busy }
        f.test {
            f.time = f.now.plusSeconds(1801)
            withTimeout(15_000) {
                coroutineScope {
                    val recovery = async(start = CoroutineStart.UNDISPATCHED) { state.resume(original.session.sessionID) }
                    enteredRecoveryWrite.await()
                    val refresh = async(start = CoroutineStart.UNDISPATCHED) { state.load(original.session.sessionID) }
                    // This is the same callback used by ON_STOP while recovery is still suspended.
                    val stoppedAgain = async(start = CoroutineStart.UNDISPATCHED) { state.checkpoint(interruption = true) }
                    assertTrue(state.busy)
                    assertFalse(refresh.isCompleted)
                    assertFalse(stoppedAgain.isCompleted)
                    assertEquals(1, attempts.get())
                    releaseRecoveryWrite.complete(Unit)
                    recovery.await()
                    assertTrue(refresh.await() is ApplicationResult.Success)
                    stoppedAgain.await()
                }
            }
            assertEquals(2, attempts.get())
            assertEquals(ApplicationErrorCode.staleRevision, state.error?.code)
            assertEquals(FcSaveState.Failed, state.saveState)
        }
        await("save-retry")
        node("session-finish").assertIsNotEnabled()
        click("save-retry")
        gone("save-status-content"); gone("save-retry"); node("save-status-saved").assertDoesNotExist()
        node("session-finish").assertIsEnabled()
        val saved = read(original.session.sessionID)
        assertEquals(3, attempts.get())
        assertEquals(FcSaveState.Saved, state.saveState)
        assertTrue(state.useCases.saveStatus(original.session.sessionID) is SessionSaveStatus.Saved)
        assertEquals(setOf(BodyPart.back), saved.session.trainingFocus)
        assertEquals(f.time, saved.session.interruptionStartedAtUTC)
        assertTrue(saved.session.durationNeedsReview)
        assertEquals(original.exercises, saved.exercises)
        assertEquals(saved, state.content)
        reopen()
        assertEquals(saved, read(original.session.sessionID))
    }
}
