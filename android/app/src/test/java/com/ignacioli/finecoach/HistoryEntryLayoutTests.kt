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
    @Before fun prepare() { f = T009Fixture(); f.test { state = HistoryUiState(f.historyCases, f.studentID, studentCases()) } }
    @After fun close() { compose.runOnUiThread { compose.activity.setContent { } }; compose.waitForIdle(); f.test { f.db.runInTransaction { } }; f.close() }
    private fun studentCases() = StudentUseCases(com.ignacioli.finecoach.storage.repository.StudentRepository(f.db, f.clock), f.clock, f.ids)
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
        compose.waitUntil(15_000) { !state.busy }
        node("history-student-name").assertIsDisplayed().assertTextEquals("虚构学员")
        node("history-count").assertTextEquals("2 次训练")
        compose.onNodeWithTag("history-open-${first.session.sessionID.value}").assertTextContains("11月8日 周日")
            .assertTextContains("1 组 · 1 分钟\n未扣课 · 无有效课包")
        node("history-filter-clear").assertDoesNotExist()
        click("history-filter-date"); click("history-filter-cancel"); assertNull(state.query.window)
        click("history-filter-focus-open"); click("history-filter-focus-1"); click("history-filter-cancel")
        assertTrue(state.query.trainingFocus.isEmpty())
        click("history-filter-focus-open"); click("history-filter-focus-0"); assertTrue(state.query.trainingFocus.isEmpty()); assertEquals(node("history-filter-content").getUnclippedBoundsInRoot().width, node("history-filter-done").getUnclippedBoundsInRoot().width)
        click("history-filter-done"); await("history-no-matches")
        node("history-no-matches").onChildren().filter(hasText("没有符合条件的训练")).assertCountEquals(1)
        node("history-no-matches").onChildren().filter(hasText("换一个日期范围、部位或动作试试，或清除筛选。")).assertCountEquals(1)
        node("history-filter-summary").assertTextEquals("已筛选：训练重点 胸")
        click("history-filter-clear"); await("history-open-${second.session.sessionID.value}")
        HistoryWindowDays.entries.forEach { click("history-filter-date"); click("history-window-${it.days}"); assertEquals(it, state.query.window) }
        click("history-filter-date"); click("history-window-all"); assertNull(state.query.window)
        click("history-open-${first.session.sessionID.value}"); assertEquals(com.ignacioli.finecoach.navigation.S1Routes.historyDetail(first.session.sessionID), route)
        click("history-list-back"); assertEquals(1, back)
    }
    @Test fun onlyInProgressDoesNotAppearAsCompletedHistory() {
        f.test { f.content() }
        compose.setContent { FineCoachTheme { HistoryListScreen(state, f.zone, {}, {}) } }
        await("history-empty"); assertTrue(state.records.isEmpty())
        node("history-empty").onChildren().filter(hasText("还没有完成的训练")).assertCountEquals(1)
        node("history-empty").onChildren().filter(hasText("完成一次训练后会出现在这里。")).assertCountEquals(1)
    }
    @Test fun focusEditCancelSystemBackAndSavePreserveIdentitySnapshotsAndLedger() {
        val original = completed(); val before = read(original.session.sessionID)
        compose.setContent { FineCoachTheme { HistoryDetailScreen(state, original.session.sessionID, f.zone, { back++ }) } }
        await("history-edit-focus-entry"); compose.waitUntil(15_000) { state.detail != null }
        click("history-edit-focus-entry")
        BodyPart.entries.forEachIndexed { index, _ -> click("history-edit-focus-$index"); click("history-edit-focus-$index") }
        click("history-edit-back"); assertEquals(before, read(original.session.sessionID))
        click("history-edit-focus-entry"); click("history-edit-focus-0"); node("history-edit-cancel").assertDoesNotExist(); click("history-edit-back")
        assertEquals(before, read(original.session.sessionID))
        click("history-edit-focus-entry"); click("history-edit-focus-1")
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }; gone("history-edit-save")
        assertEquals(before, read(original.session.sessionID))
        click("history-edit-focus-entry"); click("history-edit-focus-2")
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
        compose.waitUntil(15_000) { state.detail != null }; click("history-edit-focus-entry"); click("history-edit-focus-0")
        f.test { f.failWrites("sessions", "UPDATE") }; click("history-edit-save"); await("history-edit-error")
        assertEquals(before, read(original.session.sessionID)); assertEquals(setOf(BodyPart.chest), state.focus)
        f.test { f.clearFailure() }; click("history-edit-save"); gone("history-edit-save")
        assertEquals(setOf(BodyPart.chest), read(original.session.sessionID).session.trainingFocus)
    }
    @Test fun detailRendersStoredSnapshotAndCoachOnlyCreditNoteWithoutFutureEntries() {
        lateinit var original: SessionContentRecord
        f.test {
            val content = f.content()
            val row = content.exercises.single()
            val sets = (0..3).map { index -> row.sets.single().copy(trainingSetID = f.ids.newTrainingSetID(), orderIndex = index.toUInt()) }
            val pending = row.sets.single().copy(trainingSetID = f.ids.newTrainingSetID(), orderIndex = 4u, state = SetRecordingState.pending, completedAtUTC = null)
            original = f.ok(f.sessions.saveContent(SaveSessionContentCommand(content.session.sessionID, content.session.revision, emptyList(), listOf(row.copy(sets = sets + pending)))))
            f.now = f.now.plusSeconds(90)
            f.ok(f.finisher.finish(original.session.sessionID, original.session.revision, discardUnresolved = true))
            val finished = f.ok(f.sessions.loadContent(original.session.sessionID))!!
            f.ok(f.historyCases.saveSummary(SaveCompletedSessionSummaryCommand(finished.session.sessionID, finished.session.revision,
                setOf(BodyPart.chest), "虚构课后总结", "虚构私密总结", f.now)))
        }
        f.test { state = HistoryUiState(f.historyCases, null, studentCases()) }
        compose.setContent { FineCoachTheme { HistoryDetailScreen(state, original.session.sessionID, f.zone, {}) } }
        await("history-credit-note")
        val row = original.exercises.single(); node("history-snapshot-${row.sessionExerciseID.value}").assertTextEquals(row.displayNameSnapshot)
        node("history-set-${row.sets.first().trainingSetID.value}").assertExists()
        listOf("history-reopen", "history-share", "history-compare", "history-edit-private", "history-detail-trailing", "history-gains").forEach { node(it).assertDoesNotExist() }
        node("history-record-date").assertTextEquals("11月8日 周日")
        node("history-record-title").assertTextEquals("胸训练")
        node("history-student-name").assertIsDisplayed().assertTextEquals("虚构学员")
        assertTrue(node("history-student-name").getUnclippedBoundsInRoot().top > node("history-record-title").getUnclippedBoundsInRoot().top)
        node("history-stat-总组数").onChildren().filter(hasText("4")).assertCountEquals(1)
        node("history-stat-总次数").onChildren().filter(hasText("32")).assertCountEquals(1)
        node("history-stat-分钟").onChildren().filter(hasText("2")).assertCountEquals(1)
        val cells = row.sets.take(4).map { node("history-set-${it.trainingSetID.value}").getUnclippedBoundsInRoot() }
        assertEquals(cells[0].top, cells[1].top); assertEquals(cells[1].top, cells[2].top)
        assertTrue(cells[3].top > cells[0].top); assertEquals(cells[0].width, cells[3].width)
        assertEquals(cells[0].left, cells[3].left)
        node("history-set-${row.sets.last().trainingSetID.value}").assertDoesNotExist()
        compose.onAllNodesWithText("虚构动作私密备注", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithText("虚构私密总结", useUnmergedTree = true).assertCountEquals(0)
        node("history-record-summary").onChildren().filter(hasText("虚构课后总结")).assertCountEquals(1)
        assertEquals(node("history-detail-content").getUnclippedBoundsInRoot().width, node("history-record-card").getUnclippedBoundsInRoot().width)
        assertEquals(node("history-detail-content").getUnclippedBoundsInRoot().width, node("history-edit-focus-entry").getUnclippedBoundsInRoot().width)
        assertEquals("1 分钟", historyDuration("0")); assertEquals("1 分钟", historyDuration("89"))
        assertEquals("2 分钟", historyDuration("90")); assertEquals("61 分钟", historyDuration("3630"))
        click("history-detail-back")
    }
    @Test fun exerciseFilterUsesCompletedSnapshotIDsAndCancelLeavesQueryUnchanged() {
        val exercise = StableExerciseID.parse("abcdef00-0000-4000-8000-000000000081")
        lateinit var original: SessionContentRecord
        val lastExercise = StableExerciseID.parse("abcdef00-0000-4000-8000-000000000082")
        f.test {
            original = f.content(sourceID = exercise); f.finish(original)
            f.now = f.now.plusSeconds(60)
            val last = f.content(sourceID = lastExercise)
            val renamed = f.ok(f.sessions.saveContent(SaveSessionContentCommand(last.session.sessionID, last.session.revision, emptyList(),
                listOf(last.exercises.single().copy(displayNameSnapshot = "虚构末位动作")))))
            f.finish(renamed)
        }
        compose.setContent { FineCoachTheme { HistoryListScreen(state, f.zone, {}, {}) } }
        await("history-open-${original.session.sessionID.value}")
        // Records are published before list() finishes loading filter options.
        compose.waitUntil(15_000) { !state.busy && exercise in state.exerciseOptions }
        node("history-filter-exercise").assertIsEnabled()
        click("history-filter-exercise")
        assertTrue(node("history-filter-exercise-${exercise.value}").getUnclippedBoundsInRoot().top < node("history-filter-exercise-${lastExercise.value}").getUnclippedBoundsInRoot().top)
        click("history-filter-cancel"); assertTrue(state.query.exerciseIDs.isEmpty())
        click("history-filter-exercise"); click("history-filter-exercise-${exercise.value}")
        assertEquals(setOf(exercise), state.query.exerciseIDs); assertEquals(original.session.sessionID, state.records.single().sessionID)
        click("history-filter-exercise")
        assertEquals(node("history-filter-content").getUnclippedBoundsInRoot().width, node("history-filter-exercise-all").getUnclippedBoundsInRoot().width)
        click("history-filter-exercise-all"); assertTrue(state.query.exerciseIDs.isEmpty())
        click("history-filter-exercise"); click("history-filter-exercise-${exercise.value}")
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
        node("history-template-save").assertIsNotEnabled()
        node("history-template-name").performScrollTo().performTextReplacement("虚构模板")
        click("history-template-cancel"); f.test { assertEquals(0L, f.count("training_templates")) }
        click("history-save-template")
        assertEquals(node("history-template-content").getUnclippedBoundsInRoot().width, node("history-template-save").getUnclippedBoundsInRoot().width)
        click("history-template-save"); gone("history-template-content")
        compose.onNodeWithTag("history-save-template").assertTextContains("已保存为模板")
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

    @Test fun historyRetryReadsCompletedHistoryAgainAfterGenerationFailure() {
        val original = completed()
        var generation = ""
        f.test {
            generation = f.db.storeMetadataDao().find("store_generation")!!.value
            f.db.openHelper.writableDatabase.execSQL("UPDATE store_metadata SET value=? WHERE `key`=?",
                arrayOf("abcdef09-0000-4000-8000-000000000099", "store_generation"))
        }
        compose.setContent { FineCoachTheme { HistoryListScreen(state, f.zone, {}, {}) } }
        await("history-error")
        node("history-error").assertIsDisplayed().assertTextEquals("加载失败，请返回重试")
        node("history-error").assert(hasClickAction().not())
        node("history-retry").assertDoesNotExist()
        assertNotNull(state.error); assertTrue(state.records.isEmpty())
        f.test { f.db.openHelper.writableDatabase.execSQL("UPDATE store_metadata SET value=? WHERE `key`=?",
            arrayOf(generation, "store_generation")) }
        f.test { state.list() }; await("history-open-${original.session.sessionID.value}")
        assertNull(state.error); assertEquals(original.session.sessionID, state.records.single().sessionID)
        assertEquals(SessionState.completed, read(original.session.sessionID).session.state)
    }

}
