// fictional-data: isolated Room and invented students, packages and sessions.
package com.ignacioli.finecoach

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
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
        f = T008Fixture()
        f.test { graph = S1AppGraph(f.db, f.clock, f.ids, f.generation, ApplicationProvider.getApplicationContext<Context>(), java.time.ZoneOffset.UTC) }
    }
    @After fun close() { compose.runOnUiThread { compose.activity.setContent { } }; compose.waitForIdle(); f.test { f.db.runInTransaction { } }; f.close() }
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
    @Test fun resourceRoutesTemplateAndExerciseEditorCancelReturnConsistently() {
        show(); await("today-empty"); click("today-exercises"); await("exercise-library-content")
        click("exercise-library-back"); await("today-content"); click("today-templates"); await("template-new")
        click("template-new"); text("template-create-name", "虚构导航模板"); click("template-create-save"); await("template-add-exercise")
        click("template-editor-back"); await("template-new"); click("templates-back"); await("today-content")
        f.test { assertEquals(1L, f.count("training_templates")); assertEquals(0L, f.count("sessions")) }
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
        click("session-add-exercise"); await("exercise-search"); text("exercise-search", "虚构全流程动作"); click("quick-mode-reps"); click("exercise-session-only"); gone("exercise-picker")
        lateinit var session: SessionContentRecord
        f.test { session = f.ok(graph.sessions.loadContent(f.ok(graph.sessions.listActiveSessions()).single().sessionID))!! }
        click("session-exercise-${session.exercises.single().sessionExerciseID.value}"); text("set-reps-input", "8"); click("set-save"); gone("set-editor-content")
        click("session-finish"); await("finish-credit-accept"); click("finish-credit-accept"); await("summary-public"); text("summary-public", "虚构全流程完成"); click("summary-save"); await("today-empty")
        f.test {
            val saved = f.ok(graph.sessions.loadContent(session.session.sessionID))!!
            assertEquals(SessionState.completed, saved.session.state); assertEquals(SetRecordingState.completed, saved.exercises.single().sets.single().state)
            assertEquals(1L, f.count("credit_adjustments")); assertEquals(1, f.ok(graph.history.list(HistoryQuery())).records.size)
        }
    }

}
