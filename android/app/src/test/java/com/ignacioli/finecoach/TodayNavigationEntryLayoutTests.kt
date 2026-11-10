// fictional-data: isolated Room and invented students, packages and sessions.
package com.ignacioli.finecoach

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.unit.width
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.students.StudentTestTags
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w320dp-h640dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class TodayNavigationEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private lateinit var f: T008Fixture
    private lateinit var graph: S1AppGraph
    private var notification by mutableStateOf<SessionID?>(null)
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    private fun await(tag: String) { compose.waitUntil(15_000) { exists(tag) } }
    private fun gone(tag: String) { compose.waitUntil(15_000) { !exists(tag) } }
    private fun click(tag: String) {
        val n = node(tag); if (n.onAncestors().filter(hasScrollAction()).fetchSemanticsNodes().isNotEmpty()) n.performScrollTo()
        n.assertIsDisplayed().assertIsEnabled().assertHasClickAction().performClick(); compose.waitForIdle()
    }
    private fun readyActive(id: SessionID) { compose.waitUntil(15_000) {
        val nodes = compose.onAllNodesWithTag("active-destination-${id.value}", useUnmergedTree = true).fetchSemanticsNodes()
        nodes.singleOrNull()?.config?.getOrNull(SemanticsProperties.StateDescription) == "已加载" && exists("session-add-exercise")
    } }
    private fun text(tag: String, value: String) { node(tag).performScrollTo().assertIsDisplayed().performTextReplacement(value) }
    @Before fun prepare() {
        S1Runtime.resetForTest()
        f = T008Fixture()
        f.test { graph = S1AppGraph(f.db, f.clock, f.ids, f.generation, ApplicationProvider.getApplicationContext<Context>(), java.time.ZoneOffset.UTC) }
    }
    @After fun close() {
        try {
            compose.runOnUiThread { compose.activity.setContent { } }; compose.waitForIdle()
            f.test { f.db.runInTransaction { } }; f.close()
        } finally { S1Runtime.resetForTest() }
    }
    private fun show() { compose.setContent { FineCoachTheme { S1App(graph, notification, { notification = null }) } } }
    @Test fun emptyTodaySwitchesToStudentCreateAndReturnsToSameDurableStudent() {
        show(); await("today-empty"); click("root-1"); await(StudentTestTags.STUDENT_LIST_EMPTY_ADD)
        click(StudentTestTags.STUDENT_LIST_EMPTY_ADD); text(StudentTestTags.EDITOR_NAME, "虚构导航学员"); click(StudentTestTags.EDITOR_SEX_UNDISCLOSED); click(StudentTestTags.EDITOR_SAVE)
        await(StudentTestTags.DETAIL_START_TRAINING)
        f.test { assertEquals(1L, f.count("students")); assertEquals(0L, f.count("sessions")) }
        click(StudentTestTags.DETAIL_HEADER_BACK); await(StudentTestTags.STUDENT_LIST_ROOT)
        click("${StudentTestTags.STUDENT_LIST_SEGMENT}-0"); await("today-empty")
    }
    @Test fun singleAndMultipleHeroesOpenExactExistingSessionAndBackNeverStartsAnother() {
        lateinit var first: SessionContentRecord; lateinit var second: SessionRecord
        f.test { f.student(1); first = f.sessionContent(); f.student(2); f.time = f.now.plusSeconds(60); second = f.start(2) }
        show(); await("hero-${first.session.sessionID.value}")
        click("hero-${first.session.sessionID.value}"); await("session-set-${first.exercises.first().sets.first().trainingSetID.value}")
        click("active-session-back"); await("hero-${second.sessionID.value}")
        click("hero-${second.sessionID.value}"); readyActive(second.sessionID)
        node("session-set-${first.exercises.first().sets.first().trainingSetID.value}").assertDoesNotExist()
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }; await("today-content")
        f.test { assertEquals(2L, f.count("sessions")); assertEquals(2L, f.count("active_session_pointers")) }
    }
    @Test fun notificationRoutesBackToOriginalSessionWhileOtherStudentIsOpenWithoutNewClass() {
        lateinit var first: SessionContentRecord; lateinit var second: SessionRecord
        f.test { f.student(1); first = f.sessionContent(); f.student(2); second = f.start(2) }
        show(); await("hero-${second.sessionID.value}"); click("hero-${second.sessionID.value}"); readyActive(second.sessionID)
        compose.runOnIdle { notification = first.session.sessionID }
        await("session-set-${first.exercises.first().sets.first().trainingSetID.value}")
        assertNull(notification)
        f.test { assertEquals(2L, f.count("sessions")); assertEquals(second.sessionID, f.ok(f.sessions.active(f.studentID(2)))!!.sessionID) }
    }
    @Test fun completedOrMissingNotificationDoesNotCreateOrReopenSession() {
        val missing = f.ids.newSessionID()
        show(); await("today-empty"); compose.runOnIdle { notification = missing }
        await("notification-unavailable-card"); click("notification-unavailable-accept")
        f.test { assertEquals(0L, f.count("sessions")) }
    }
    @Test fun coldLaunchSeedsCatalogAndHubCountsAndRepeatedGraphLaunchKeepsStableRows() {
        show(); await("today-empty")
        compose.onNodeWithText("训练资料").assertDoesNotExist()
        node("today-exercises").assertDoesNotExist(); node("today-templates").assertDoesNotExist()
        click("root-1"); await("student-list-resource-hub"); click("student-list-resource-hub")
        await("resource-hub-exercises")
        compose.waitUntil(15_000) { compose.onAllNodesWithText("内置 541 个 · 自定义 0 个", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("0 个模板", useUnmergedTree = true).assertIsDisplayed()
        for (tag in listOf("resource-hub-exercises", "resource-hub-templates")) {
            node(tag).assertIsDisplayed().assertHasClickAction()
            assertEquals(node("resource-hub-content").getUnclippedBoundsInRoot().width, node(tag).getUnclippedBoundsInRoot().width)
        }
        click("resource-hub-exercises"); compose.waitUntil(15_000) { compose.onAllNodesWithText("杠铃平板卧推", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }; compose.onNodeWithText("杠铃平板卧推", useUnmergedTree = true).performScrollTo().assertIsDisplayed()
        f.test {
            val before = f.ok(graph.exerciseRepository.listCatalog())
            val second = S1AppGraph(f.db, f.clock, f.ids, f.generation, graph.context)
            second.prepareExerciseCatalog()
            assertEquals(before, f.ok(second.exerciseRepository.listCatalog()))
        }
    }

    @Test fun resourceRoutesTemplateAndExerciseEditorCancelReturnConsistently() {
        show(); await("today-empty"); click("root-1"); await("student-list-resource-hub"); click("student-list-resource-hub"); await("resource-hub-exercises"); click("resource-hub-exercises"); await("exercise-library-content")
        click("exercise-library-back"); await("resource-hub-content"); click("resource-hub-templates"); await("template-new")
        click("template-new"); text("template-create-name", "虚构导航模板"); click("template-create-save"); await("template-add-exercise")
        click("template-editor-back"); await("template-new"); click("templates-back"); await("resource-hub-content"); click("resource-hub-back"); await(StudentTestTags.STUDENT_LIST_ROOT)
        f.test { assertEquals(1L, f.count("training_templates")); assertEquals(0L, f.count("sessions")) }
        // SQLite cannot trigger on SELECT: preserve rows in a renamed table to fail catalog reads.
        // The template repository uses the existing store-generation guard.
        try {
            f.test {
                f.db.openHelper.writableDatabase.execSQL("ALTER TABLE exercise_catalog RENAME TO fictional_unavailable_catalog")
                f.db.openHelper.writableDatabase.execSQL("UPDATE store_metadata SET value = ? WHERE `key` = 'store_generation'",
                    arrayOf("abcdef00-0000-4000-8000-000000000099"))
                assertTrue(graph.exerciseRepository.listCatalog() is ApplicationResult.Failure)
                assertTrue(graph.templates.list() is ApplicationResult.Failure)
            }
            click("student-list-resource-hub"); await("resource-hub-content")
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("动作数量加载失败", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() &&
                    compose.onAllNodesWithText("模板数量加载失败", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("动作数量加载失败", useUnmergedTree = true).assertIsDisplayed()
            compose.onNodeWithText("模板数量加载失败", useUnmergedTree = true).assertIsDisplayed()
        } finally {
            f.test {
                f.db.openHelper.writableDatabase.execSQL("ALTER TABLE fictional_unavailable_catalog RENAME TO exercise_catalog")
                f.db.openHelper.writableDatabase.execSQL("UPDATE store_metadata SET value = ? WHERE `key` = 'store_generation'",
                    arrayOf(graph.generation.toString()))
            }
        }
    }
    @Test fun existingSessionFinishSaveSummaryRefreshesTodayAndHistoryWithoutLosingSets() {
        lateinit var original: SessionContentRecord
        f.test { f.student(1); original = f.sessionContent(true) }
        show(); await("hero-${original.session.sessionID.value}"); click("hero-${original.session.sessionID.value}"); readyActive(original.session.sessionID); click("session-finish")
        await("summary-public"); text("summary-public", "虚构端到端总结"); click("summary-save"); await("today-empty")
        f.test { val stored = f.ok(f.sessions.loadContent(original.session.sessionID))!!
            assertEquals(SessionState.completed, stored.session.state); assertEquals(original.exercises, stored.exercises)
            assertEquals("虚构端到端总结", stored.session.studentFacingSummary); assertEquals(0L, f.count("active_session_pointers"))
        }
        click("root-1"); await(StudentTestTags.studentRow(f.studentID(1))); click(StudentTestTags.studentRow(f.studentID(1)))
        await(StudentTestTags.DETAIL_HISTORY); click(StudentTestTags.DETAIL_HISTORY); await("history-open-${original.session.sessionID.value}")
        click("history-open-${original.session.sessionID.value}"); await("history-save-template")
    }
    @Test fun coreFlowCreatesStudentPackageExerciseSetDebitsOnceAndAppearsInHistory() {
        show(); await("today-empty"); click("root-1"); await(StudentTestTags.STUDENT_LIST_EMPTY_ADD); click(StudentTestTags.STUDENT_LIST_EMPTY_ADD)
        text(StudentTestTags.EDITOR_NAME, "虚构全流程学员"); click(StudentTestTags.EDITOR_SEX_UNDISCLOSED); click(StudentTestTags.EDITOR_SAVE)
        await(StudentTestTags.DETAIL_COURSE_PACKAGES); click(StudentTestTags.DETAIL_COURSE_PACKAGES); await("package-list-add"); click("package-list-add")
        await("package-editor-name"); text("package-editor-name", "虚构全流程课包"); click("package-editor-save"); gone("package-editor-name")
        click("package-list-back"); await(StudentTestTags.DETAIL_START_TRAINING); click(StudentTestTags.DETAIL_START_TRAINING); await("session-add-exercise")
        var started: SessionID? = null
        f.test { started = f.ok(graph.sessions.listActiveSessions()).single().sessionID }; readyActive(requireNotNull(started))
        click("session-add-exercise"); click("session-add-library"); await("exercise-search"); text("exercise-search", "虚构全流程动作"); click("quick-mode-reps"); click("exercise-session-only"); gone("exercise-picker")
        lateinit var session: SessionContentRecord
        f.test { session = f.ok(graph.sessions.loadContent(f.ok(graph.sessions.listActiveSessions()).single().sessionID))!! }
        click("session-exercise-${session.exercises.single().sessionExerciseID.value}"); text("set-reps-input", "8"); click("set-save"); node("set-add-editor-content").assertExists(); readyActive(session.session.sessionID)
        click("session-finish"); await("finish-credit-accept"); click("finish-credit-accept"); await("summary-public"); text("summary-public", "虚构全流程完成"); click("summary-save"); await("today-empty")
        f.test {
            val saved = f.ok(graph.sessions.loadContent(session.session.sessionID))!!
            assertEquals(SessionState.completed, saved.session.state); assertEquals(SetRecordingState.completed, saved.exercises.single().sets.single().state)
            assertEquals(1L, f.count("credit_adjustments")); assertEquals(1, f.ok(graph.history.list(HistoryQuery())).records.size)
        }
    }

    @Test fun startupLoadRetryReopensDatabaseAfterInvalidGenerationIsRepaired() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val expected = graph.generation
        f.test { f.db.openHelper.writableDatabase.execSQL("UPDATE store_metadata SET value=? WHERE `key`=?",
            arrayOf("fictional-invalid-generation", "store_generation")) }
        // Only the notification bridge is needed; S1Root uses the real host's LocalContext to open Room.
        val bridge = org.robolectric.Robolectric.buildActivity(MainActivity::class.java).get()
        compose.setContent { FineCoachTheme { S1Root(bridge) } }
        await("s1-load-retry")
        node("s1-load-retry").assertIsDisplayed().assertIsEnabled().assertHasClickAction()
        node("s1-navigation").assertDoesNotExist()
        f.test { f.db.openHelper.writableDatabase.execSQL("UPDATE store_metadata SET value=? WHERE `key`=?",
            arrayOf(expected.toString(), "store_generation")) }
        click("s1-load-retry"); await("today-empty")
        f.test {
            val reopened = f.ok(S1Runtime.open(context))
            assertNotSame(f.db, reopened.database)
            assertTrue(reopened.database.isOpen)
            assertEquals(expected, reopened.generation)
        }
        compose.runOnUiThread { compose.activity.setContent { } }; compose.waitForIdle()
        f.test { f.db.runInTransaction { }; f.ok(S1Runtime.open(context)).database.close() }
    }

    @Test fun startupRecoveryRetryRepeatsCheckpointAndLoadsTheSameSession() {
        lateinit var original: SessionRecord
        f.test { f.student(1); original = f.start(); f.failWrites("sessions", "UPDATE") }
        show(); await("s1-recovery-retry")
        node("s1-recovery-retry").assertIsDisplayed().assertIsEnabled().assertHasClickAction()
        f.test {
            assertEquals(original, f.ok(graph.sessions.find(original.sessionID)))
            f.clearFailure(); f.time = f.now.plusSeconds(60)
        }
        click("s1-recovery-retry"); await("hero-${original.sessionID.value}")
        f.test {
            val saved = f.ok(graph.sessions.find(original.sessionID))!!
            assertTrue(saved.revision.value > original.revision.value)
            assertEquals(f.time, saved.lastCheckpointUTC)
            assertEquals(1L, f.count("sessions")); assertEquals(1L, f.count("active_session_pointers"))
        }
    }

    @Test fun todayRetryReadsRealRepositoryAgainAfterGenerationFailure() {
        lateinit var session: SessionRecord
        f.test {
            f.student(1); session = f.start()
            f.db.openHelper.writableDatabase.execSQL("UPDATE store_metadata SET value=? WHERE `key`=?",
                arrayOf("abcdef00-0000-4000-8000-000000000099", "store_generation"))
        }
        val today = com.ignacioli.finecoach.features.today.TodayUiState(graph.sessions, graph.students, graph.clock)
        compose.setContent { FineCoachTheme { com.ignacioli.finecoach.features.today.TodayScreen(today, {}) } }
        await("today-retry")
        node("today-retry").assertIsDisplayed().assertIsEnabled().assertHasClickAction()
        assertNotNull(today.error); assertTrue(today.items.isEmpty())
        f.test { f.db.openHelper.writableDatabase.execSQL("UPDATE store_metadata SET value=? WHERE `key`=?",
            arrayOf(graph.generation.toString(), "store_generation")) }
        click("today-retry"); await("hero-${session.sessionID.value}")
        assertNull(today.error); assertEquals(session.sessionID.value, today.items.single().id)
        f.test { assertEquals(session, f.ok(graph.sessions.find(session.sessionID))) }
    }

    @Test fun templateRowOpensItsOwnEditorWithoutWritingOrOpeningAnotherTemplate() {
        lateinit var first: TemplateRecord; lateinit var second: TemplateRecord
        f.test {
            first = f.ok(graph.templates.save(SaveTemplateCommand(null, "虚构模板甲", emptySet(), null)))
            second = f.ok(graph.templates.save(SaveTemplateCommand(null, "虚构模板乙", emptySet(), null)))
        }
        show(); await("today-empty"); click("root-1"); await("student-list-resource-hub"); click("student-list-resource-hub"); await("resource-hub-templates"); compose.waitUntil(15_000) { compose.onAllNodesWithText("2 个模板", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }; compose.waitForIdle(); compose.onNodeWithText("2 个模板", useUnmergedTree = true).assertIsDisplayed(); click("resource-hub-templates"); await("template-open-${first.templateID.value}")
        click("template-open-${first.templateID.value}"); await("template-add-exercise")
        compose.onNodeWithText(first.name, useUnmergedTree = true).assertIsDisplayed()
        click("template-editor-back"); await("template-open-${second.templateID.value}")
        click("template-open-${second.templateID.value}"); await("template-add-exercise")
        compose.onNodeWithText(second.name, useUnmergedTree = true).assertIsDisplayed()
        f.test { assertEquals(setOf(first, second), f.ok(graph.templates.list()).toSet()) }
    }

}
