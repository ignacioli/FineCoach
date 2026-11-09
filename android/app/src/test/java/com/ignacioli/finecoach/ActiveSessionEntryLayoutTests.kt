// fictional-data: invented students, exercises and isolated temporary Room database.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.width
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
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w320dp-h640dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ActiveSessionEntryLayoutTests {
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
    private fun options(set: TrainingSetRecord) = click("session-set-options-${set.trainingSetID.value}")
    @Test fun confirmCopyPendingEditKeepsCompletionTimeAndUndoRoundtrip() {
        val original = content(); show(original)
        val set = original.exercises.first().sets.first()
        click("session-set-${set.trainingSetID.value}-confirm")
        val confirmed = read(original.session.sessionID).exercises.first().sets.first()
        assertEquals(SetRecordingState.completed, confirmed.state)
        options(confirmed); click("session-set-copy"); gone("session-set-copy")
        val copied = read(original.session.sessionID).exercises.first().sets.last()
        assertNotEquals(confirmed.trainingSetID, copied.trainingSetID); assertEquals(SetRecordingState.pending, copied.state); assertNull(copied.completedAtUTC)
        click("session-set-${confirmed.trainingSetID.value}-edit"); text("set-weight-input", "15")
        click("set-save"); gone("set-editor-content")
        val edited = read(original.session.sessionID).exercises.first().sets.first()
        assertEquals(confirmed.completedAtUTC, edited.completedAtUTC); assertEquals(SetRecordingState.completed, edited.state)
        options(edited); click("session-set-unconfirm"); gone("session-set-unconfirm")
        assertEquals(SetRecordingState.pending, read(original.session.sessionID).exercises.first().sets.first().state)
        options(copied); click("session-set-delete"); gone("session-set-delete")
        assertEquals(1, read(original.session.sessionID).exercises.first().sets.size)
        click("session-deleted-action")
        val restored = read(original.session.sessionID)
        assertEquals(listOf(confirmed.trainingSetID, copied.trainingSetID), restored.exercises.first().sets.map { it.trainingSetID })
        assertEquals(copied, restored.exercises.first().sets.last())
        reopen(); assertEquals(restored, read(original.session.sessionID))
    }
    @Test fun setCancelHeaderAndSystemBackWriteNothing() {
        val original = content(true); show(original)
        val row = original.exercises.first()
        click("session-set-${row.sets.first().trainingSetID.value}-edit"); text("set-weight-input", "99"); click("set-cancel")
        assertEquals(original, read(original.session.sessionID))
        click("session-exercise-${row.sessionExerciseID.value}"); text("set-weight-input", "88")
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }; gone("set-editor-content")
        click("active-session-back"); assertEquals(1, back)
        assertEquals(original, read(original.session.sessionID))
    }
    @Test fun modeInputsValidateThenConfirmDurableExactValuesAndFillWidth() {
        var original = content()
        f.test {
            original = ok(f.useCases.mutate(original.session.sessionID, original.session.revision) { value ->
                var s = value.session
                RecordMode.entries.forEach { mode -> s = s.addingSessionOnlyExercise(f.ids.newSessionExerciseID(), "虚构$mode", mode, f.now) }
                s = s.copy(exercises = s.exercises.mapIndexed { index, row -> if (index >= value.session.exercises.size) row.copy(orderIndex = (index + 10).toUInt()) else row })
                value.copy(session = s)
            })
        }
        show(original)
        original.exercises.takeLast(4).forEach { row ->
            click("session-exercise-${row.sessionExerciseID.value}")
            click("set-save"); await("set-error")
            when (row.recordModeSnapshot) {
                RecordMode.weightReps -> { text("set-weight-input", "0"); text("set-reps-input", "6") }
                RecordMode.reps -> { text("set-reps-input", "7"); click("set-reps-plus"); node("set-reps-input").assertTextEquals("8") }
                RecordMode.duration -> text("set-duration", "1分30秒")
                RecordMode.cardio -> { text("set-duration", "2分"); text("set-distance", "0.125"); text("set-speed", "3.25"); text("set-resistance", "2") }
            }
            full("set-save", "set-editor-content"); click("set-save"); gone("set-editor-content")
            val saved = read(original.session.sessionID).exercises.first { it.sessionExerciseID == row.sessionExerciseID }.sets.single()
            assertEquals(SetRecordingState.completed, saved.state)
            when (row.recordModeSnapshot) {
                RecordMode.weightReps -> assertEquals("0", saved.weightValue!!.toPlainString())
                RecordMode.reps -> assertEquals("8", saved.repetitionCount!!.toPlainString())
                RecordMode.duration -> assertEquals("90", saved.durationSeconds!!.toPlainString())
                RecordMode.cardio -> assertEquals("0.125", saved.distanceValue!!.toPlainString())
            }
        }
    }
    @Test fun nonemptySectionCancelThenMoveOutPreservesSetsAndIDsAcrossReopen() {
        val original = content(true); show(original); val section = original.sections.first()
        fun request() { click("session-section-${section.sectionID.value}"); click("session-section-delete") }
        request(); click("session-delete-section-confirm-cancel"); assertEquals(original, read(original.session.sessionID))
        request(); click("session-delete-section-confirm-accept"); gone("session-delete-section-confirm-card")
        val saved = read(original.session.sessionID)
        assertFalse(saved.sections.any { it.sectionID == section.sectionID }); assertNull(saved.exercises.first().sectionID)
        assertEquals(original.exercises.map { it.sets }, saved.exercises.map { it.sets })
        assertEquals(original.exercises.map { it.sessionExerciseID }, saved.exercises.map { it.sessionExerciseID })
        reopen(); assertEquals(saved, read(original.session.sessionID))
    }
    @Test fun createRenameEmptySectionDirectDeleteAndMoveExerciseHaveVisibleEntries() {
        val original = content(); show(original)
        click("session-add-section"); text("session-section-name", "虚构取消"); click("session-section-cancel"); assertEquals(original, read(original.session.sessionID))
        click("session-add-section"); text("session-section-name", "虚构新段"); full("session-section-save", "session-section-form-content"); click("session-section-save"); gone("session-section-name")
        val section = read(original.session.sessionID).sections.last()
        click("session-section-${section.sectionID.value}"); click("session-section-rename"); text("session-section-name", "虚构改名"); click("session-section-save"); gone("session-section-name")
        assertEquals("虚构改名", read(original.session.sessionID).sections.last().name)
        val row = original.exercises.first()
        click("session-exercise-options-${row.sessionExerciseID.value}"); click("session-exercise-move"); click("session-move-${section.sectionID.value}"); gone("session-move-cancel")
        assertEquals(section.sectionID, read(original.session.sessionID).exercises.first().sectionID)
        click("session-exercise-options-${row.sessionExerciseID.value}"); click("session-exercise-move"); click("session-move-unsectioned"); gone("session-move-cancel")
        click("session-section-${section.sectionID.value}"); click("session-section-delete"); gone("session-section-${section.sectionID.value}")
        node("session-delete-section-confirm-card").assertDoesNotExist()
        assertNull(read(original.session.sessionID).exercises.first().sectionID)
    }
    @Test fun completedExerciseDeleteRequiresExplicitFullScreenConfirmCancelHasNoWrites() {
        val original = content(true); show(original); val row = original.exercises.first()
        fun request() { click("session-exercise-options-${row.sessionExerciseID.value}"); click("session-exercise-delete") }
        request(); click("session-delete-exercise-cancel"); assertEquals(original, read(original.session.sessionID))
        request(); click("session-delete-exercise-confirm"); gone("session-delete-exercise-confirm")
        assertFalse(read(original.session.sessionID).exercises.any { it.sessionExerciseID == row.sessionExerciseID })
    }
    @Test fun failedSaveKeepsEditorAndInputThenExplicitRetryCanPersist() {
        val original = content(true); show(original)
        f.test { f.failWrites("training_sets", "INSERT") }
        click("session-set-${original.exercises.first().sets.first().trainingSetID.value}-edit"); text("set-weight-input", "22.5")
        click("set-save"); await("set-error"); node("set-weight-input").assertTextEquals("22.5")
        assertEquals(original, read(original.session.sessionID))
        f.test { f.clearFailure() }; click("set-save"); gone("set-editor-content")
        assertEquals("22.5", read(original.session.sessionID).exercises.first().sets.first().weightValue!!.toPlainString())
    }
    @Test fun keyboardInsetsLeaveConfirmationReachableAndFullWidth() {
        val original = content(); show(original); val row = original.exercises.first()
        click("session-exercise-${row.sessionExerciseID.value}"); text("set-weight-input", "20")
        compose.runOnIdle {
            ViewCompat.dispatchApplyWindowInsets(compose.activity.window.decorView,
                WindowInsetsCompat.Builder().setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, 280)).setVisible(WindowInsetsCompat.Type.ime(), true).build())
        }
        full("set-save", "set-editor-content"); click("set-save"); gone("set-editor-content")
        assertEquals(2, read(original.session.sessionID).exercises.first().sets.size)
    }
    @Test fun historicalFirstSetPrefillIsStudentAndSnapshotScopedAndNotCompleted() {
        var old = content(true)
        lateinit var next: SessionContentRecord
        f.test {
            ok(f.sessions.complete(CompleteSessionCommand(old.session.sessionID, old.session.revision, f.now, false)))
            val s = f.start()
            val rows = old.exercises.mapIndexed { index, row -> row.copy(sessionID = s.sessionID,
                sessionExerciseID = f.ids.newSessionExerciseID(), sectionID = null, orderIndex = index.toUInt(), sets = emptyList()) }
            next = ok(f.sessions.saveContent(SaveSessionContentCommand(s.sessionID, s.revision, emptyList(), rows)))
        }
        show(next); await("session-previous-${next.exercises.first().sessionExerciseID.value}")
        click("session-exercise-${next.exercises.first().sessionExerciseID.value}")
        node("set-weight-input").assertTextEquals("12.125"); node("set-reps-input").assertTextEquals("8")
        assertTrue(read(next.session.sessionID).exercises.first().sets.isEmpty())
        click("set-cancel"); assertEquals(next, read(next.session.sessionID))
    }
    @Test fun bilateralSplitUsesHeavierAndAssistedLighterWeightAndKeepsExactSides() {
        var original = content()
        f.test {
            val row = original.exercises.first()
            val set = row.sets.first().copy(side = SetSide.bilateral,
                leftValue = "12.125".toBigDecimal(), rightValue = "12.125".toBigDecimal())
            original = ok(f.sessions.saveContent(SaveSessionContentCommand(original.session.sessionID,
                original.session.revision, original.sections, original.exercises.map { if (it == row) it.copy(sets = listOf(set)) else it })))
        }
        show(original); val row = original.exercises.first()
        click("session-set-${row.sets.first().trainingSetID.value}-edit"); click("set-split")
        text("set-left-input", "15.125"); text("set-right-input", "10.25")
        click("set-save"); gone("set-editor-content")
        val set = read(original.session.sessionID).exercises.first().sets.single()
        assertEquals("15.125", set.weightValue!!.toPlainString()); assertEquals("10.25", set.rightValue!!.toPlainString())
        assertEquals(SetSide.bilateral, set.side)
        assertEquals("10.25", recordedSideWeight("15.125", "10.25", true))
    }
    @Test fun sectionReorderAndExerciseMoveUpDownPreserveMembers() {
        val original = content(); show(original); val section = original.sections.last()
        click("session-section-${section.sectionID.value}"); click("session-section-up"); gone("session-section-up")
        assertEquals(section.sectionID, read(original.session.sessionID).sections.minBy { it.orderIndex }.sectionID)
        click("session-section-${section.sectionID.value}"); click("session-section-down"); gone("session-section-down")
        val row = original.exercises.last()
        click("session-exercise-options-${row.sessionExerciseID.value}"); click("session-exercise-move"); click("session-move-unsectioned"); gone("session-move-cancel")
        val before = read(original.session.sessionID)
        click("session-exercise-options-${row.sessionExerciseID.value}"); click("session-exercise-up"); gone("session-exercise-up")
        assertTrue(read(original.session.sessionID).exercises.last().orderIndex < before.exercises.last().orderIndex)
        click("session-exercise-options-${row.sessionExerciseID.value}"); click("session-exercise-down"); gone("session-exercise-down")
        assertEquals(before.exercises, read(original.session.sessionID).exercises)
    }
    @Test fun quickAddAndPendingExerciseDirectDeleteAreDurableAndCancelIsZeroWrite() {
        val original = content(); show(original)
        click("session-add-exercise"); text("exercise-search", "虚构取消动作"); click("exercise-picker-cancel"); gone("exercise-picker")
        assertEquals(original, read(original.session.sessionID))
        click("session-add-exercise"); text("exercise-search", "虚构临时动作"); click("quick-mode-reps"); click("exercise-session-only"); gone("exercise-picker")
        val row = read(original.session.sessionID).exercises.last()
        assertEquals(RecordMode.reps, row.recordModeSnapshot); assertEquals(ExerciseSourceKind.sessionOnly, row.sourceKind)
        click("session-exercise-options-${row.sessionExerciseID.value}"); click("session-exercise-delete"); gone("session-exercise-delete")
        node("session-delete-exercise-confirm").assertDoesNotExist()
        assertEquals(original.exercises, read(original.session.sessionID).exercises)
    }

}
