// fictional-data: invented students, exercises and isolated temporary Room database.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.compose.runtime.*
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.platform.ComposeView
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
import com.ignacioli.finecoach.storage.repository.StudentRepository
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
        n.assertIsDisplayed().assertIsEnabled().assertHasClickAction().performClick(); compose.waitForIdle()
    }
    private fun text(tag: String, value: String) { node(tag).performScrollTo().assertIsDisplayed().performTextReplacement(value) }
    private fun full(tag: String, parent: String) = assertEquals(node(parent).getUnclippedBoundsInRoot().width, node(tag).getUnclippedBoundsInRoot().width)
    private fun editorActionsFillWidth() {
        full("set-editor-actions", if (exists("set-editor-content")) "set-editor-content" else "set-add-editor-content")
        val actions = node("set-editor-actions").getUnclippedBoundsInRoot()
        val save = node("set-save").getUnclippedBoundsInRoot()
        assertEquals(actions.left, save.left)
        if (exists("set-editor-content")) {
            val cancel = node("set-cancel").getUnclippedBoundsInRoot()
            assertEquals(actions.right, cancel.right)
            assertTrue(save.right < cancel.left)
        } else {
            assertEquals(actions.right, save.right)
            compose.onNodeWithTag("set-save").assertTextEquals("确认")
            node("set-cancel").assertDoesNotExist()
        }
    }
    private fun swipe(tag: String) {
        node(tag).performScrollTo().assertIsDisplayed().performTouchInput { swipeLeft(startX = width * 0.9f, endX = width * 0.5f) }
        compose.waitForIdle()
    }
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
    private fun disposeContent() {
        // disposeComposition() retains the content lambda and requests layout. An attached
        // ComposeView then recreates that content on measure, restarting effects during teardown.
        // Replace the subtree instead; the rule retains ownership of the root composition.
        // Activity.setContent also replaces the parent context supplied by the test rule,
        // recreating the old content before installing the new lambda. Keep that context.
        compose.runOnIdle {
            val root = compose.activity.findViewById<android.view.ViewGroup>(android.R.id.content)
            (root.getChildAt(0) as ComposeView).setContent { }
        }
        compose.waitForIdle()
    }
    @After fun close() {
        disposeContent()
        f.test { f.db.runInTransaction { } }; f.close()
    }
    private fun <T> ok(result: ApplicationResult<T>) = f.ok(result)
    private fun content(completed: Boolean = false): SessionContentRecord {
        lateinit var result: SessionContentRecord
        f.test { result = f.sessionContent(completed) }
        return result
    }
    private fun show(original: SessionContentRecord) {
        compose.setContent { FineCoachTheme { ActiveSessionScreen(state, original.session.sessionID, exercises, templates, { back++ }, {}, students = StudentRepository(f.db, f.clock)) } }
        await("session-add-exercise")
        compose.waitUntil(15_000) { !state.busy }
    }
    private fun read(id: SessionID): SessionContentRecord {
        compose.waitUntil(15_000) { !state.busy }
        lateinit var result: SessionContentRecord
        f.test { result = ok(f.sessions.loadContent(id))!! }; return result
    }
    private fun reopen() {
        disposeContent()
        f.test { f.db.runInTransaction { }; f.reopen() }
    }
    private fun options(set: TrainingSetRecord) = swipe("session-set-${set.trainingSetID.value}-swipe")
    private fun change(action: (SectionedSession) -> SectionedSession) { f.test { ok(state.mutate(action)) }; compose.waitForIdle() }
    @Test fun scrollEndKeepsAddControlsFullyAbovePinnedFinish() {
        show(content())
        val body = node("active-session-content")
        assertTrue("Fixture must overflow before scrolling", body.fetchSemanticsNode().config[SemanticsProperties.VerticalScrollAxisRange].maxValue() > 0)
        body.performScrollToNode(hasTestTag("session-add-section"))
        repeat(10) {
            val range = body.fetchSemanticsNode().config[SemanticsProperties.VerticalScrollAxisRange]
            if (range.value() < range.maxValue()) body.performTouchInput { swipeUp() }
        }
        val range = body.fetchSemanticsNode().config[SemanticsProperties.VerticalScrollAxisRange]
        assertEquals(range.maxValue(), range.value())
        val cta = node("session-finish").assertIsDisplayed().fetchSemanticsNode()
        listOf("session-add-exercise", "session-add-section").forEach { tag ->
            val last = node(tag).assertIsDisplayed().fetchSemanticsNode()
            assertEquals(last.size.height.toFloat(), last.boundsInRoot.height, 0.01f)
            assertTrue("$tag must be fully above finish", last.boundsInRoot.bottom <= cta.boundsInRoot.top)
        }
    }

    @Test fun confirmCopyPendingEditKeepsCompletionTimeAndUndoRoundtrip() {
        val original = content(); show(original)
        val set = original.exercises.first().sets.first()
        click("session-set-${set.trainingSetID.value}-confirm")
        val confirmed = read(original.session.sessionID).exercises.first().sets.first()
        assertEquals(SetRecordingState.completed, confirmed.state)
        change { it.copy(session = it.session.copyingSet(confirmed.trainingSetID, f.ids.newTrainingSetID(), f.now)) }; gone("session-set-copy")
        val copied = read(original.session.sessionID).exercises.first().sets.last()
        assertNotEquals(confirmed.trainingSetID, copied.trainingSetID); assertEquals(SetRecordingState.pending, copied.state); assertNull(copied.completedAtUTC)
        click("session-set-${confirmed.trainingSetID.value}-edit"); text("set-weight-input", "15")
        click("set-save"); gone("set-editor-content")
        val edited = read(original.session.sessionID).exercises.first().sets.first()
        assertEquals(confirmed.completedAtUTC, edited.completedAtUTC); assertEquals(SetRecordingState.completed, edited.state)
        change { it.copy(session = it.session.undoingSet(edited.trainingSetID, f.now)) }; gone("session-set-unconfirm")
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
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }; gone("set-add-editor-content")
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
                RecordMode.cardio -> {
                    listOf("set-duration", "set-distance", "set-speed", "set-resistance").forEach { tag ->
                        node(tag).performScrollTo().assertIsDisplayed().assertIsEnabled()
                            .assert(hasSetTextAction())
                        full("$tag-row", "set-add-editor-content")
                        val row = node("$tag-row").getUnclippedBoundsInRoot()
                        val slot = node("$tag-value-slot").getUnclippedBoundsInRoot()
                        val field = node(tag).getUnclippedBoundsInRoot()
                        assertEquals(row.right, slot.right)
                        assertEquals(slot.left, field.left)
                        assertTrue(field.width.value > 0f)
                        assertTrue(field.right < slot.right)
                    }
                    listOf("set-duration", "set-distance", "set-speed", "set-resistance").zipWithNext().forEach { (tag, next) ->
                        val row = node("$tag-row").getUnclippedBoundsInRoot()
                        val divider = node("$tag-divider").getUnclippedBoundsInRoot()
                        val nextRow = node("$next-row").getUnclippedBoundsInRoot()
                        assertEquals(row.bottom.value, divider.top.value, 0.5f)
                        assertEquals(FcComponentMetrics.hairline.value, (divider.bottom - divider.top).value, 0.5f)
                        assertEquals(divider.bottom.value, nextRow.top.value, 0.5f)
                    }
                    listOf("时长", "距离", "速度", "阻力", "km", "km/h").forEach { label ->
                        compose.onNode(hasText(label).and(hasAnyAncestor(hasTestTag("set-add-editor-content"))), useUnmergedTree = true).assertExists()
                    }
                    compose.onAllNodesWithText("必填", useUnmergedTree = true).assertCountEquals(2)
                    compose.onAllNodesWithText("选填", useUnmergedTree = true).assertCountEquals(2)
                    node("set-cardio-validation-hint").performScrollTo().assertIsDisplayed()
                        .assertContentDescriptionEquals("时长与距离均大于 0，才可标记完成")
                    text("set-duration", "2分"); text("set-distance", "0.125"); text("set-speed", "3.25"); text("set-resistance", "2")
                }
            }
            editorActionsFillWidth(); click("set-save"); node("set-add-editor-content").assertExists()
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
        fun request() { swipe("session-section-${section.sectionID.value}-swipe"); click("session-section-delete") }
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
        change { it.renamingSection(section.sectionID, "虚构改名", f.now) }; gone("session-section-name")
        node("session-section-${section.sectionID.value}").performScrollTo().assertTextEquals("虚构改名")
        assertEquals("虚构改名", read(original.session.sessionID).sections.last().name)
        val row = original.exercises.first()
        val beforeMove = read(original.session.sessionID)
        swipe("session-exercise-${row.sessionExerciseID.value}-swipe"); click("session-exercise-move"); click("session-move-cancel")
        gone("session-move-cancel"); assertEquals(beforeMove, read(original.session.sessionID))
        swipe("session-exercise-${row.sessionExerciseID.value}-swipe"); click("session-exercise-move"); click("session-move-${section.sectionID.value}"); gone("session-move-cancel")
        assertEquals(section.sectionID, read(original.session.sessionID).exercises.first().sectionID)
        swipe("session-exercise-${row.sessionExerciseID.value}-swipe"); click("session-exercise-move"); click("session-move-unsectioned"); gone("session-move-cancel")
        swipe("session-section-${section.sectionID.value}-swipe"); click("session-section-delete"); gone("session-section-${section.sectionID.value}")
        node("session-delete-section-confirm-card").assertDoesNotExist()
        assertNull(read(original.session.sessionID).exercises.first().sectionID)
    }
    @Test fun completedExerciseDeleteRequiresExplicitFullScreenConfirmCancelHasNoWrites() {
        val original = content(true); show(original); val row = original.exercises.first()
        fun request() { swipe("session-exercise-${row.sessionExerciseID.value}-swipe"); click("session-exercise-delete") }
        request(); node("session-delete-exercise-title").assertIsDisplayed()
        node("session-delete-exercise-back").assertDoesNotExist()
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        gone("session-delete-exercise-title"); assertEquals(original, read(original.session.sessionID))
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
        compose.onNodeWithTag("set-save").performScrollTo().assertIsDisplayed().assertIsEnabled().assertTextEquals("确认")
        node("set-weight-input").performImeAction()
        editorActionsFillWidth(); click("set-save"); node("set-add-editor-content").assertExists()
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
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }; gone("set-add-editor-content"); assertEquals(next, read(next.session.sessionID))
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
        change { it.reordering(sessionShiftAxis(original, section.sectionID.value, -1), f.now) }; gone("session-section-up")
        assertEquals(section.sectionID, read(original.session.sessionID).sections.minBy { it.orderIndex }.sectionID)
        val reordered = read(original.session.sessionID)
        change { it.reordering(sessionShiftAxis(reordered, section.sectionID.value, 1), f.now) }; gone("session-section-down")
        val row = original.exercises.last()
        swipe("session-exercise-${row.sessionExerciseID.value}-swipe"); click("session-exercise-move"); click("session-move-unsectioned"); gone("session-move-cancel")
        val before = read(original.session.sessionID)
        change { it.reordering(sessionShiftAxis(before, row.sessionExerciseID.value, -1), f.now) }; gone("session-exercise-up")
        assertTrue(read(original.session.sessionID).exercises.last().orderIndex < before.exercises.last().orderIndex)
        val shifted = read(original.session.sessionID)
        change { it.reordering(sessionShiftAxis(shifted, row.sessionExerciseID.value, 1), f.now) }; gone("session-exercise-down")
        assertEquals(before.exercises, read(original.session.sessionID).exercises)
    }
    @Test fun quickAddAndPendingExerciseDirectDeleteAreDurableAndCancelIsZeroWrite() {
        val original = content(); show(original)
        click("session-add-exercise"); click("session-add-library"); text("exercise-search", "虚构取消动作"); click("exercise-picker-cancel"); gone("exercise-picker")
        assertEquals(original, read(original.session.sessionID))
        click("session-add-exercise"); click("session-add-library"); text("exercise-search", "虚构临时动作"); click("quick-mode-reps"); click("exercise-session-only"); gone("exercise-picker")
        val row = read(original.session.sessionID).exercises.last()
        assertEquals(RecordMode.reps, row.recordModeSnapshot); assertEquals(ExerciseSourceKind.sessionOnly, row.sourceKind)
        swipe("session-exercise-${row.sessionExerciseID.value}-swipe"); click("session-exercise-delete"); gone("session-exercise-delete")
        node("session-delete-exercise-confirm").assertDoesNotExist()
        assertEquals(original.exercises, read(original.session.sessionID).exercises)
    }

    @Test fun applyTemplateEntryOpensRealSheetAndCancelDoesNotWrite() {
        val original = content()
        val requested = kotlinx.coroutines.CompletableDeferred<Unit>()
        val release = kotlinx.coroutines.CompletableDeferred<Unit>()
        val completed = kotlinx.coroutines.CompletableDeferred<Unit>()
        lateinit var delegate: TemplateRepositoryPort
        f.test { delegate = f.templates }
        val pendingList = object : TemplateRepositoryPort by delegate {
            override suspend fun list(): ApplicationResult<List<TemplateRecord>> {
                requested.complete(Unit)
                try {
                    release.await()
                    return delegate.list()
                } finally { completed.complete(Unit) }
            }
        }
        templates = TemplateUiState(TemplateUseCases(pendingList, f.clock), f.clock, f.ids)
        show(original)
        click("session-add-exercise"); click("session-apply-template"); await("template-apply-content")
        node("template-apply-content").assertIsDisplayed()
        try {
            compose.waitUntil(15_000) { requested.isCompleted && templates.busy }
            compose.waitForIdle()
            assertFalse(release.isCompleted)
            assertFalse(completed.isCompleted)
            assertTrue(templates.busy)
            // Assert before releasing the read; waiting for enabled would also pass the old implementation.
            node("template-apply-cancel").assertIsDisplayed().assertIsEnabled().assertHasClickAction()
        } finally { release.complete(Unit) }
        compose.waitUntil(15_000) { completed.isCompleted && !templates.busy }
        click("template-apply-cancel"); gone("template-apply-content")
        assertEquals(original, read(original.session.sessionID))
    }

    @Test fun inlineEditSteppersSaveExactValuesCancelWritesNothingAndHeaderCountsReadBack() {
        val original = content(true); show(original)
        val row = original.exercises.first(); val set = row.sets.first()
        node("session-student").assertTextEquals("虚构学员1")
        node("session-stats").assertDoesNotExist()
        node("save-status-saved").assertDoesNotExist()
        node("save-status-content").assertDoesNotExist()
        val glyph = node("active-session-back-glyph")
        glyph.assertTextEquals("‹")
        node("active-session-back").assertContentDescriptionEquals("返回").assertHasClickAction()
        assertTrue(glyph.getUnclippedBoundsInRoot().width < node("active-session-back").getUnclippedBoundsInRoot().width)
        val glyphLayouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        val titleLayouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        val title = compose.onNodeWithText("训练中", useUnmergedTree = true)
        glyph.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { assertTrue(it(glyphLayouts)) }
        title.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { assertTrue(it(titleLayouts)) }
        assertEquals(title.fetchSemanticsNode().boundsInRoot.top + titleLayouts.single().firstBaseline,
            glyph.fetchSemanticsNode().boundsInRoot.top + glyphLayouts.single().firstBaseline, 0.001f)
        val header = "session-exercise-${row.sessionExerciseID.value}"
        val headerParts = node(header).onChildren().fetchSemanticsNodes().size
        click(header)
        node(header).assertIsSelected()
        node(header).onChildren().assertCountEquals(headerParts)
        node(header).onChildren().filter(hasText("已完成")).assertCountEquals(0)
        node(header).onChildren().filter(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.StateDescription, "动作已完成")).assertCountEquals(0)
        click("session-set-${set.trainingSetID.value}-edit")
        node("session-set-${set.trainingSetID.value}").assertExists()
        full("session-set-${set.trainingSetID.value}", "active-session-content")
        full("set-editor-content", "active-session-content")
        val setBounds = node("session-set-${set.trainingSetID.value}").getUnclippedBoundsInRoot()
        val editorBounds = node("set-editor-content").getUnclippedBoundsInRoot()
        assertTrue(editorBounds.top >= setBounds.bottom)
        text("set-weight-input", "20"); text("set-reps-input", "8")
        click("set-weight-plus"); node("set-weight-input").assertTextEquals("22.5")
        click("set-weight-minus"); node("set-weight-input").assertTextEquals("20")
        click("set-reps-plus"); node("set-reps-input").assertTextEquals("9")
        click("set-save"); gone("set-editor-content")
        val saved = read(original.session.sessionID).exercises.first().sets.first()
        assertEquals("20", saved.weightValue!!.toPlainString()); assertEquals("9", saved.repetitionCount!!.toPlainString())
        assertEquals(set.completedAtUTC, saved.completedAtUTC)
        click("session-set-${set.trainingSetID.value}-edit"); click("set-weight-plus"); click("set-cancel")
        assertEquals(saved, read(original.session.sessionID).exercises.first().sets.first())
    }

    @Test fun swipeDeleteShowsExplicitControlAndUndoRestoresCompletedSetAtOriginalPosition() {
        val original = content(true); show(original)
        val row = original.exercises.first(); val set = row.sets.first()
        node("session-set-delete").assertDoesNotExist()
        swipe("session-set-${set.trainingSetID.value}-swipe")
        node("session-set-delete").assertIsDisplayed().assertHasClickAction()
        assertEquals(original, read(original.session.sessionID))
        click("session-set-delete")
        assertTrue(read(original.session.sessionID).exercises.first().sets.isEmpty())
        click("session-deleted-action")
        assertEquals(row.sets, read(original.session.sessionID).exercises.first().sets)
        node("session-set-${set.trainingSetID.value}-undo").assertDoesNotExist()
    }

    @Test fun emptySessionHasVisibleRecordingPrompt() {
        lateinit var empty: SessionContentRecord
        f.test { val session = f.start(); empty = ok(f.sessions.loadContent(session.sessionID))!! }
        show(empty)
        node("session-empty-hint").assertIsDisplayed().assertTextEquals("先添加动作，再记录组数。")
        node("session-add-exercise").assertIsDisplayed().assertHasClickAction()
        node("session-stats").assertDoesNotExist()
    }

    @Test fun unfinishedSetFullSwipeDeletesButCompletedSetOnlyRevealsAction() {
        val original = content(); show(original)
        val row = original.exercises.first(); val set = row.sets.first()
        node("session-set-${set.trainingSetID.value}-swipe").performScrollTo().performTouchInput { swipeLeft() }
        compose.waitUntil(15_000) { !state.busy && state.content?.exercises?.first()?.sets?.isEmpty() == true }
        assertTrue(read(original.session.sessionID).exercises.first().sets.isEmpty())
        node("session-set-${set.trainingSetID.value}").assertDoesNotExist()
        val other = original.exercises.last().sets.first()
        click("session-set-${other.trainingSetID.value}-confirm")
        val confirmed = read(original.session.sessionID).exercises.last().sets.single()
        node("session-set-${other.trainingSetID.value}-swipe").performScrollTo().performTouchInput { swipeLeft() }
        node("session-set-delete").assertIsDisplayed()
        assertEquals(confirmed, read(original.session.sessionID).exercises.last().sets.single())
    }

    @Test fun addPanelCancelWritesNothing() {
        val original = content(); show(original)
        click("session-add-exercise"); node("session-add-library").assertIsDisplayed()
        node("session-apply-template").assertIsDisplayed(); click("session-add-cancel")
        gone("session-add-tabs"); assertEquals(original, read(original.session.sessionID))
    }

    @Test fun recentConfirmUndoUsesRowStatus() {
        val original = content(); show(original)
        val row = original.exercises.first()
        click("session-exercise-${row.sessionExerciseID.value}")
        text("set-weight-input", "20"); text("set-reps-input", "8"); click("set-save")
        node("set-add-editor-content").assertExists()
        node("set-weight-input").assertTextEquals("20"); node("set-reps-input").assertTextEquals("8")
        val saved = read(original.session.sessionID).exercises.first().sets.last()
        text("set-weight-input", "99"); text("set-reps-input", "3")
        click("session-set-${saved.trainingSetID.value}-undo")
        val remaining = read(original.session.sessionID).exercises.first().sets
        assertFalse(remaining.any { it.trainingSetID == saved.trainingSetID })
        assertEquals(row.sets, remaining)
        gone("rest-content"); assertNull(state.rests.end(original.session.sessionID))
        node("set-weight-input").performScrollTo().assertTextEquals(saved.weightValue!!.toPlainString())
        node("set-reps-input").performScrollTo().assertTextEquals(saved.repetitionCount!!.toPlainString())
    }

    @Test fun operationMenusAndSetEditCancelHaveVisibleZeroWriteEntries() {
        val original = content(true); show(original)
        val row = original.exercises.first(); val set = row.sets.first()
        f.test { f.blockAllWrites(listOf("sessions", "session_exercises", "training_sets", "session_sections")) }
        val sectionSwipe = "session-section-${original.sections.first().sectionID.value}-swipe"
        swipe(sectionSwipe); node("session-section-delete").assertIsDisplayed()
        node(sectionSwipe).performTouchInput { swipeRight() }; gone("session-section-delete")
        assertEquals(original, read(original.session.sessionID))
        val exerciseSwipe = "session-exercise-${row.sessionExerciseID.value}-swipe"
        swipe(exerciseSwipe); node("session-exercise-delete").assertIsDisplayed()
        node(exerciseSwipe).performTouchInput { swipeRight() }; gone("session-exercise-delete")
        assertEquals(original, read(original.session.sessionID))
        options(set); node("session-set-delete").assertIsDisplayed()
        node("session-set-${set.trainingSetID.value}-swipe").performTouchInput { swipeRight() }; gone("session-set-delete")
        assertEquals(original, read(original.session.sessionID))
        click("session-set-${set.trainingSetID.value}-edit"); await("set-editor-content")
        node("set-editor-content").assertIsDisplayed()
        assertEquals(original, read(original.session.sessionID))
        text("set-weight-input", "88"); click("set-cancel"); gone("set-editor-content")
        assertEquals(original, read(original.session.sessionID))
    }

    @Test fun clearingContentDoesNotReenterHostedCompositionOnMeasure() {
        var entered = 0
        var disposed = 0
        compose.setContent {
            DisposableEffect(Unit) {
                entered++
                onDispose { disposed++ }
            }
        }
        disposeContent()
        compose.runOnUiThread {
            val root = compose.activity.findViewById<android.view.ViewGroup>(android.R.id.content)
            root.measure(
                android.view.View.MeasureSpec.makeMeasureSpec(root.width, android.view.View.MeasureSpec.EXACTLY),
                android.view.View.MeasureSpec.makeMeasureSpec(root.height, android.view.View.MeasureSpec.EXACTLY))
        }
        compose.runOnIdle {
            assertEquals("Cleared content must not be composed again by a layout pass", 1, entered)
            assertEquals("The hosted subtree must be disposed before closing Room", 1, disposed)
        }
    }
}
