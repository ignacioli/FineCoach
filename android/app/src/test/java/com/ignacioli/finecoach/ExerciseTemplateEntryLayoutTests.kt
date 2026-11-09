// fictional-data: all names, plans and students are invented; Room uses a temporary file database.
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.width
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.graphics.Insets
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.template.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.exercises.*
import com.ignacioli.finecoach.features.templates.*
import com.ignacioli.finecoach.navigation.S1Routes
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w320dp-h640dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ExerciseTemplateEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private lateinit var f: T008Fixture
    private lateinit var exerciseState: ExerciseUiState
    private lateinit var templateState: TemplateUiState
    private lateinit var exerciseUseCases: ExerciseUseCases
    private lateinit var sessionUseCases: ActiveSessionUseCases
    private var back = 0
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun click(tag: String) {
        val control = node(tag)
        if (control.onAncestors().filter(hasScrollAction()).fetchSemanticsNodes().isNotEmpty()) control.performScrollTo()
        try { control.assertIsDisplayed() } catch (failure: AssertionError) {
            throw AssertionError("Entry geometry: control=" + control.getUnclippedBoundsInRoot() +
                "; root=" + compose.onAllNodes(isRoot(), useUnmergedTree = true).fetchSemanticsNodes().map { it.boundsInRoot }, failure)
        }
        control.assertHasClickAction().performClick()
        compose.waitForIdle()
    }
    private fun text(tag: String, value: String) { node(tag).performScrollTo().assertIsDisplayed().performTextReplacement(value) }
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    private fun await(tag: String) { compose.waitUntil(15_000) { exists(tag) } }
    private fun gone(tag: String) { compose.waitUntil(15_000) { !exists(tag) } }
    private fun quiesceThenReopen() {
        compose.runOnUiThread { compose.activity.setContent { } }
        compose.waitForIdle()
        // Disposing Compose cancels queries, but an executing SQLite transaction must finish.
        f.test { f.db.runInTransaction { } }
        f.test { f.reopen() }
    }
    private fun full(tag: String, parent: String) { assertEquals(node(parent).getUnclippedBoundsInRoot().width, node(tag).getUnclippedBoundsInRoot().width) }
    @Before fun prepare() {
        f = T008Fixture()
        val repository = f.exercises
        exerciseUseCases = ExerciseUseCases(repository, f.clock, f.ids)
        exerciseState = ExerciseUiState(exerciseUseCases, repository)
        f.test {
            templateState = TemplateUiState(f.templateUseCases, f.clock, f.ids)
            sessionUseCases = f.useCases
        }
    }
    @After fun close() { f.close() }
    private fun library() { compose.setContent { FineCoachTheme { ExerciseLibraryScreen(exerciseState) { back++ } } } }
    private fun editor(content: TemplateContentRecord) {
        compose.setContent { FineCoachTheme { TemplateEditorScreen(templateState, content.template.templateID, exerciseState) { back++ } } }
        await("template-add-exercise")
    }
    private fun custom(name: String = "虚构动作甲", mode: RecordMode = RecordMode.weightReps): ExerciseRecord {
        lateinit var item: ExerciseRecord
        f.test { item = ok(exerciseUseCases.createCustom(name, mode)) }
        return item
    }
    private fun <T> ok(result: ApplicationResult<T>): T {
        assertTrue("ApplicationResult must succeed: $result", result is ApplicationResult.Success)
        return (result as ApplicationResult.Success).value
    }
    private fun template(): TemplateContentRecord {
        lateinit var result: TemplateContentRecord
        f.test {
            val created = ok(f.templateUseCases.save(SaveTemplateCommand(null, "虚构模板甲", emptySet(), null)))
            val domain = TrainingTemplate.blank(created.templateID, created.name, emptySet(), f.now)
            val a = f.ids.newSectionID(); val b = f.ids.newSectionID()
            val set = TemplatePlannedSet(RecordMode.weightReps, DecimalValue.parse("12.5"), DecimalValue.parse("8"), unit = MeasurementUnit.kilograms)
            val content = domain.addingSection(a, "虚构分段甲", f.now)
                .addingExercise(f.ids.newTemplateExerciseID(), "虚构动作甲", RecordMode.weightReps, listOf(set), a, nowUTC = f.now)
                .addingSection(b, "虚构分段乙", f.now)
                .addingExercise(f.ids.newTemplateExerciseID(), "虚构动作乙", RecordMode.weightReps, listOf(set), b, nowUTC = f.now)
            result = ok(f.templates.saveContent(SaveTemplateContentCommand(created.templateID, created.revision,
                content.sections.map { it.toRecord() }, content.exercises.map { it.toRecord() })))
        }
        return result
    }
    private fun read(id: TemplateID): TemplateContentRecord {
        lateinit var result: TemplateContentRecord
        f.test { result = ok(f.templateUseCases.load(id))!! }
        return result
    }
    private fun sectionDelete(content: TemplateContentRecord) {
        click("template-section-${content.sections.first().sectionID.value}")
        click("template-section-delete")
    }

    @Test fun customCreateEditArchiveRestoreAndBackUseVisibleControlsAndRealRoom() {
        library(); click("exercise-library-trailing")
        text("exercise-name", "虚构新动作"); click("exercise-mode-reps")
        full("exercise-name", "exercise-editor-content"); full("exercise-save", "exercise-editor-content")
        click("exercise-save"); await("exercise-library-search")
        lateinit var item: ExerciseRecord
        f.test { item = ok(exerciseUseCases.search("虚构新动作")).single(); assertEquals(RecordMode.reps, item.recordMode) }
        await("exercise-options-${item.exerciseID.value}"); click("exercise-options-${item.exerciseID.value}"); click("exercise-edit")
        text("exercise-name", "虚构更名动作"); click("exercise-save"); await("exercise-library-search")
        click("exercise-options-${item.exerciseID.value}"); click("exercise-edit"); click("exercise-archive")
        compose.waitUntil(15_000) { !exerciseState.busy && node("exercise-save").fetchSemanticsNode().config.contains(androidx.compose.ui.semantics.SemanticsProperties.Disabled) }
        f.test { assertTrue(ok(exerciseUseCases.search("虚构更名动作")).isEmpty()) }
        click("exercise-archive")
        compose.waitUntil(15_000) { !exerciseState.busy && !node("exercise-save").fetchSemanticsNode().config.contains(androidx.compose.ui.semantics.SemanticsProperties.Disabled) }
        click("exercise-editor-cancel"); await("exercise-library-search")
        click("exercise-library-back"); assertEquals(1, back)
        quiesceThenReopen()
        f.test { assertEquals("虚构更名动作", ok(f.exercises.search("虚构更名动作")).single().canonicalName) }
    }

    @Test fun libraryHideRestoreAliasAndRecordingPreferencesRetainEachOther() {
        val item = custom(); library(); await("exercise-options-${item.exerciseID.value}")
        fun options() { await("exercise-options-${item.exerciseID.value}"); click("exercise-options-${item.exerciseID.value}") }
        options(); text("exercise-alias", "虚构显示名"); full("exercise-alias", "exercise-options-content"); click("exercise-alias-save"); gone("exercise-alias")
        options(); click("exercise-favorite"); gone("exercise-alias")
        options(); click("exercise-assisted"); gone("exercise-alias")
        options(); click("exercise-unilateral"); gone("exercise-alias")
        options(); click("exercise-hide"); gone("exercise-alias")
        f.test { assertTrue(ok(exerciseUseCases.search("")).isEmpty()) }
        click("exercise-show-hidden"); options(); click("exercise-hide"); gone("exercise-alias")
        f.test {
            val p = ok(f.exercises.preference(item.exerciseID))!!
            assertEquals("虚构显示名", p.alias); assertTrue(p.isFavorite); assertTrue(p.isAssisted); assertEquals(true, p.isUnilateral); assertFalse(p.isHidden)
        }
    }

    @Test fun invalidAndConflictingExerciseNamesKeepInputAndDoNotWrite() {
        custom()
        compose.setContent { FineCoachTheme { CustomExerciseEditor(exerciseState, null) { back++ } } }
        click("exercise-save"); await("exercise-error"); assertEquals(0, back)
        text("exercise-name", "虚构动作甲"); click("exercise-save"); await("exercise-error")
        node("exercise-name").assertTextEquals("虚构动作甲"); assertEquals(0, back)
        click("exercise-editor-cancel"); f.test { assertEquals(1, ok(exerciseUseCases.search("")).size) }
    }

    @Test fun editorHeaderAndSystemBackCancelWithoutCreatingExercise() {
        compose.setContent { FineCoachTheme { CustomExerciseEditor(exerciseState, null) { back++ } } }
        text("exercise-name", "虚构未保存动作"); click("exercise-editor-back")
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        assertEquals(2, back); f.test { assertTrue(ok(exerciseUseCases.search("")).isEmpty()) }
    }

    private fun picker(target: SessionRecord) {
        var visible by mutableStateOf(true)
        compose.setContent { FineCoachTheme { if (visible) ExercisePicker(exerciseState, { selection ->
            val current = ok(sessionUseCases.load(target.sessionID))!!
            val id = f.ids.newSessionExerciseID()
            val claimed = if (selection.sourceKind == ExerciseSourceKind.sessionOnly)
                exerciseUseCases.claimSessionOnly(StableExerciseID.parse(id.value), selection.name) else ApplicationResult.Success(Unit)
            when (claimed) {
                is ApplicationResult.Failure -> claimed
                is ApplicationResult.Success -> when (val saved = sessionUseCases.saveContent(SaveSessionContentCommand(target.sessionID,
                    current.session.revision, current.sections, current.exercises + SessionExerciseRecord(id, target.sessionID,
                        current.exercises.size.toUInt(), selection.sourceKind, selection.sourceID, selection.name, selection.mode, null, null, emptyList())))) {
                    is ApplicationResult.Failure -> saved
                    is ApplicationResult.Success -> ApplicationResult.Success(Unit)
                }
            }
        }, { visible = false }) } }
    }
    private fun session(): SessionRecord {
        lateinit var result: SessionRecord
        f.test { f.student(1); result = f.start() }
        return result
    }

    @Test fun reusablePickerPinyinSelectionPersistsStableCatalogSnapshot() {
        val item = custom("虚构深蹲"); val session = session(); picker(session)
        text("exercise-search", "shen dun"); await("exercise-select-${item.exerciseID.value}")
        full("exercise-search", "exercise-picker-content"); click("exercise-select-${item.exerciseID.value}"); gone("exercise-picker")
        f.test {
            val snapshot = ok(f.useCases.load(session.sessionID))!!.exercises.single()
            assertEquals(item.exerciseID, snapshot.sourceID); assertEquals(ExerciseSourceKind.custom, snapshot.sourceKind)
            ok(exerciseUseCases.updateCustom(item.exerciseID, "虚构改名深蹲", RecordMode.reps))
            assertEquals(snapshot, ok(f.useCases.load(session.sessionID))!!.exercises.single())
        }
    }

    @Test fun quickSessionOnlyDoesNotCreateGlobalCatalogItem() {
        val session = session(); picker(session); text("exercise-search", "虚构仅本节动作"); click("quick-mode-duration")
        click("exercise-session-only"); gone("exercise-picker")
        f.test {
            val row = ok(f.useCases.load(session.sessionID))!!.exercises.single()
            assertEquals(ExerciseSourceKind.sessionOnly, row.sourceKind); assertEquals(RecordMode.duration, row.recordModeSnapshot)
            assertNull(row.sourceID); assertTrue(ok(exerciseUseCases.search("")).isEmpty())
        }
    }

    @Test fun explicitLibraryQuickCreateAndSelectAreDistinctDurableActions() {
        val session = session(); picker(session); text("exercise-search", "虚构库动作"); click("exercise-create-library")
        compose.waitUntil(15_000) { exerciseState.entries.size == 1 && !exerciseState.busy }
        val item = exerciseState.entries.single()
        f.test { assertTrue(ok(f.useCases.load(session.sessionID))!!.exercises.isEmpty()) }
        click("exercise-select-${item.exerciseID.value}"); gone("exercise-picker")
        f.test { assertEquals(item.exerciseID, ok(f.useCases.load(session.sessionID))!!.exercises.single().sourceID) }
    }

    @Test fun pickerCancelAndSystemBackWriteNeitherCatalogNorSession() {
        val session = session(); picker(session); text("exercise-search", "虚构取消动作"); click("exercise-picker-cancel"); gone("exercise-picker")
        f.test { assertTrue(ok(f.useCases.load(session.sessionID))!!.exercises.isEmpty()); assertTrue(ok(exerciseUseCases.search("")).isEmpty()) }
    }

    @Test fun templateCreateRoutesToExistingContractAndCancelDoesNotWrite() {
        var route = ""
        compose.setContent { FineCoachTheme { TemplateListScreen(templateState, { route = it }) { back++ } } }
        click("template-new"); text("template-create-name", "虚构取消模板"); click("template-create-cancel")
        f.test { assertTrue(ok(f.templateUseCases.list()).isEmpty()) }
        click("template-new"); text("template-create-name", "虚构新模板")
        full("template-create-name", "template-create-content"); full("template-create-save", "template-create-content")
        click("template-create-save"); gone("template-create-name")
        f.test { assertEquals(S1Routes.templateDetail(ok(f.templateUseCases.list()).single().templateID), route) }
        click("templates-back"); assertEquals(1, back)
    }

    @Test fun templateMetadataAndSectionCreateRenameCancelPersistWithCAS() {
        val original = template(); editor(original)
        click("template-editor-trailing"); text("template-name", "虚构模板改名"); click("template-focus-0")
        full("template-name", "template-metadata-content"); full("template-save", "template-metadata-content")
        click("template-save"); gone("template-name")
        assertEquals("虚构模板改名", read(original.template.templateID).template.name)
        assertEquals(setOf(BodyPart.chest), read(original.template.templateID).template.trainingFocus)
        click("template-add-section"); text("template-section-name", "虚构新分段"); click("template-section-save"); gone("template-section-name")
        val section = read(original.template.templateID).sections.last()
        click("template-section-${section.sectionID.value}"); click("template-section-rename"); text("template-section-name", "虚构分段改名")
        click("template-section-save"); gone("template-section-name")
        assertEquals("虚构分段改名", read(original.template.templateID).sections.last().name)
        val beforeCancel = read(original.template.templateID)
        click("template-add-section"); text("template-section-name", "虚构取消分段"); click("template-section-cancel")
        assertEquals(beforeCancel, read(original.template.templateID))
    }

    @Test fun templateAddPickerMoveExerciseToSectionAndUnsectionedAndRemove() {
        val original = template(); val item = custom("虚构模板新增动作"); editor(original)
        click("template-add-exercise"); text("exercise-search", item.canonicalName); await("exercise-select-${item.exerciseID.value}")
        click("exercise-select-${item.exerciseID.value}"); gone("exercise-picker")
        val added = read(original.template.templateID).exercises.last()
        assertEquals(item.exerciseID, added.sourceID)
        click("template-exercise-${added.templateExerciseID.value}"); click("template-exercise-move")
        click("template-move-${original.sections.first().sectionID.value}"); gone("template-move-content")
        assertEquals(original.sections.first().sectionID, read(original.template.templateID).exercises.last().sectionID)
        click("template-exercise-${added.templateExerciseID.value}"); click("template-exercise-move"); click("template-move-unsectioned"); gone("template-move-content")
        assertNull(read(original.template.templateID).exercises.last().sectionID)
        click("template-exercise-${added.templateExerciseID.value}"); click("template-exercise-remove"); click("template-remove-confirm-cancel")
        assertEquals(3, read(original.template.templateID).exercises.size)
        click("template-exercise-${added.templateExerciseID.value}"); click("template-exercise-remove"); click("template-remove-confirm-accept")
        gone("template-remove-confirm-card"); assertEquals(2, read(original.template.templateID).exercises.size)
    }

    @Test fun independentMoveToTargetKeepsIDsAndPlannedSetsAfterReopen() {
        val original = template(); editor(original)
        val row = original.exercises.first()
        click("template-exercise-${row.templateExerciseID.value}"); click("template-exercise-move")
        click("template-move-cancel"); assertEquals(original, read(original.template.templateID))
        click("template-exercise-${row.templateExerciseID.value}"); click("template-exercise-move")
        click("template-move-${original.sections.last().sectionID.value}"); gone("template-move-content")
        val result = read(original.template.templateID)
        assertEquals(original.sections, result.sections)
        assertEquals(original.exercises.map { it.templateExerciseID }, result.exercises.map { it.templateExerciseID })
        assertEquals(original.exercises.flatMap { it.plannedSets }, result.exercises.flatMap { it.plannedSets })
        assertTrue(result.exercises.all { it.sectionID == original.sections.last().sectionID })
        quiesceThenReopen()
        f.test { assertEquals(result, ok(f.templateUseCases.load(original.template.templateID))) }
    }

    @Test fun emptySectionDeletesDirectlyAndPersistsAfterReopen() {
        val original = template()
        f.test { ok(f.templateUseCases.mutate(original.template.templateID, original.template.revision) {
            it.addingSection(f.ids.newSectionID(), "虚构空分段", f.now)
        }) }
        val before = read(original.template.templateID)
        val empty = before.sections.last()
        editor(before)
        click("template-section-${empty.sectionID.value}"); click("template-section-delete")
        gone("template-section-${empty.sectionID.value}")
        node("template-delete-section-confirm-card").assertDoesNotExist()
        val result = read(original.template.templateID)
        assertEquals(before.sections.filterNot { it.sectionID == empty.sectionID }, result.sections)
        assertEquals(before.exercises, result.exercises)
        quiesceThenReopen()
        f.test { assertEquals(result, ok(f.templateUseCases.load(original.template.templateID))) }
    }

    @Test fun nonemptySectionConfirmationMovesToUnsectionedAndPersistsAfterReopen() {
        val original = template(); val other = template(); editor(original); sectionDelete(original)
        node("template-delete-section-confirm-card").assertIsDisplayed()
        node("template-section-delete-members").assertDoesNotExist()
        node("template-delete-move-content").assertDoesNotExist()
        click("template-delete-section-confirm-accept"); gone("template-delete-section-confirm-card")
        val result = read(original.template.templateID)
        assertEquals(listOf(original.sections.last().sectionID), result.sections.map { it.sectionID })
        assertEquals(original.exercises.map { it.templateExerciseID }, result.exercises.map { it.templateExerciseID })
        assertNull(result.exercises.first().sectionID)
        assertEquals(original.exercises.last().sectionID, result.exercises.last().sectionID)
        assertEquals(original.exercises.map { it.plannedSets }, result.exercises.map { it.plannedSets })
        assertEquals(other, read(other.template.templateID))
        quiesceThenReopen()
        f.test {
            assertEquals(result, ok(f.templateUseCases.load(original.template.templateID)))
            assertEquals(other, ok(f.templateUseCases.load(other.template.templateID)))
        }
    }

    @Test fun nonemptySectionCancelWritesNothingAfterReopen() {
        val original = template(); editor(original)
        f.test { f.blockAllWrites(listOf("training_templates", "template_training_focus", "template_exercises", "template_planned_sets", "session_sections")) }
        sectionDelete(original)
        node("template-delete-section-confirm-accept").assertIsDisplayed()
        click("template-delete-section-confirm-cancel"); gone("template-delete-section-confirm-card")
        assertEquals(original, read(original.template.templateID))
        click("template-editor-back"); assertEquals(1, back)
        quiesceThenReopen()
        f.test { assertEquals(original, ok(f.templateUseCases.load(original.template.templateID))) }
    }

    @Test fun sectionAndExerciseReorderingHasVisibleUpDownAndPersistsUnifiedOrder() {
        val original = template(); editor(original)
        click("template-section-${original.sections.last().sectionID.value}"); click("template-section-up"); gone("template-section-up")
        assertEquals(original.sections.last().sectionID, read(original.template.templateID).sections.minBy { it.orderIndex }.sectionID)
        click("template-section-${original.sections.last().sectionID.value}"); click("template-section-down"); gone("template-section-down")
        click("template-exercise-${original.exercises.first().templateExerciseID.value}"); click("template-exercise-move"); click("template-move-unsectioned"); gone("template-move-content")
        val before = read(original.template.templateID)
        val row = before.exercises.first { it.templateExerciseID == original.exercises.first().templateExerciseID }
        click("template-exercise-${row.templateExerciseID.value}"); click("template-exercise-up"); gone("template-exercise-up")
        val after = read(original.template.templateID)
        assertTrue(after.exercises.first { it.templateExerciseID == row.templateExerciseID }.orderIndex < row.orderIndex)
        click("template-exercise-${row.templateExerciseID.value}"); click("template-exercise-down"); gone("template-exercise-down")
        assertEquals(before.exercises, read(original.template.templateID).exercises)
    }

    @Test fun plannedSetAddEditRemoveSaveAndCancelUseRealTemplateMutation() {
        val original = template(); editor(original)
        val row = original.exercises.first()
        fun open() { click("template-exercise-${row.templateExerciseID.value}"); click("template-planned-sets") }
        open(); text("planned-weight", "20"); text("planned-reps", "6"); click("planned-stage")
        full("planned-save", "planned-content"); click("planned-save"); gone("planned-content")
        assertEquals(2, read(original.template.templateID).exercises.first().plannedSets.size)
        open(); click("planned-edit-1"); text("planned-weight", "22.5"); click("planned-stage"); click("planned-save"); gone("planned-content")
        assertEquals("22.5", read(original.template.templateID).exercises.first().plannedSets.last().weightValue!!.toPlainString())
        val before = read(original.template.templateID)
        open(); click("planned-delete-0"); click("planned-cancel"); assertEquals(before, read(original.template.templateID))
        open(); click("planned-delete-0"); click("planned-save"); gone("planned-content")
        assertEquals(1, read(original.template.templateID).exercises.first().plannedSets.size)
    }

    @Test fun templateDeleteCancelAndAcceptDoNotTouchAppliedSession() {
        val original = template(); val session = session()
        lateinit var applied: SessionContentRecord
        f.test { applied = ok(f.templateUseCases.apply(ApplyTemplateSnapshotCommand(original.template.templateID, session.sessionID,
            original.template.revision, session.revision, f.now))) }
        editor(original); click("template-delete"); click("template-delete-confirm-cancel"); assertEquals(original, read(original.template.templateID))
        click("template-delete"); click("template-delete-confirm-accept"); gone("template-delete-confirm-card"); assertEquals(1, back)
        f.test { assertNull(ok(f.templateUseCases.load(original.template.templateID))); assertEquals(applied, ok(f.useCases.load(session.sessionID))) }
    }

    @Test fun applySheetCancelThenApplyMakesIndependentPendingSnapshot() {
        val original = template(); val session = session()
        var show by mutableStateOf(true)
        var applied: SessionContentRecord? = null
        compose.setContent { FineCoachTheme {
            FcButton("应用模板", Modifier.testTag("open-apply")) { show = true }
            if (show) ApplyTemplateSheet(templateState, session, { applied = it }) { show = false }
        } }
        await("template-apply-${original.template.templateID.value}"); click("template-apply-cancel"); gone("template-apply-content")
        f.test { assertEquals(session, ok(f.useCases.load(session.sessionID))!!.session); assertTrue(ok(f.useCases.load(session.sessionID))!!.exercises.isEmpty()) }
        click("open-apply"); await("template-apply-${original.template.templateID.value}"); click("template-apply-${original.template.templateID.value}"); gone("template-apply-content")
        val result = applied!!
        assertTrue(result.exercises.all { it.sets.all { set -> set.state == SetRecordingState.pending && set.completedAtUTC == null } })
        assertTrue(result.exercises.none { copy -> original.exercises.any { it.templateExerciseID.value == copy.sessionExerciseID.value } })
        f.test { ok(f.templateUseCases.save(SaveTemplateCommand(original.template.templateID, "虚构应用后改名", emptySet(), original.template.revision)))
            assertEquals(result, ok(f.useCases.load(session.sessionID))) }
    }

    @Test fun staleApplyAndTemplateSaveFailureRetainInputsAndReportNoSuccess() {
        val original = template(); editor(original)
        f.test { f.failWrites("training_templates", "UPDATE") }
        click("template-editor-trailing"); text("template-name", "虚构失败输入"); click("template-save"); await("template-metadata-error")
        node("template-name").assertTextEquals("虚构失败输入"); assertEquals(original, read(original.template.templateID))
        f.test { f.clearFailure() }
        click("template-save"); gone("template-name"); assertEquals("虚构失败输入", read(original.template.templateID).template.name)
    }

    @Test fun keyboardInsetsKeepFullWidthEditorSaveReachable() {
        compose.setContent { FineCoachTheme { CustomExerciseEditor(exerciseState, null) { back++ } } }
        text("exercise-name", "虚构键盘动作")
        compose.runOnIdle {
            val insets = WindowInsetsCompat.Builder().setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, 280))
                .setVisible(WindowInsetsCompat.Type.ime(), true).build()
            ViewCompat.dispatchApplyWindowInsets(compose.activity.window.decorView, insets)
        }
        full("exercise-save", "exercise-editor-content")
        click("exercise-save"); compose.waitUntil(15_000) { back == 1 }
        f.test { assertEquals(1, ok(exerciseUseCases.search("虚构键盘动作")).size) }
    }
}
