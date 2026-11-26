// fictional-data: isolated Room, invented navigation student and completed training only.
package com.ignacioli.finecoach

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.progress.EstimatedOneRepMax
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.students.StudentTestTags
import java.time.ZoneOffset
import org.junit.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class S3NavigationEntryLayoutTests {
    @get:Rule(order = 0) val privacy: org.junit.rules.TestRule = InsightTestPrivacyRule()
    @get:Rule(order = 1) val compose = createAndroidComposeRule<ComponentActivity>()
    private lateinit var f: T008Fixture
    private lateinit var graph: S1AppGraph
    private var exerciseID = EstimatedOneRepMax.exerciseIDs.first()
    private val history = mutableListOf<SessionID>()
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    private fun await(tag: String) = compose.waitUntil(15_000) { exists(tag) }
    private fun click(tag: String) {
        val target = node(tag)
        if (target.onAncestors().filter(hasScrollAction()).fetchSemanticsNodes().isNotEmpty()) target.performScrollTo()
        target.assertIsDisplayed().assertIsEnabled().assertHasClickAction().performClick()
    }
    private fun <T> value(result: ApplicationResult<T>): T = when (result) {
        is ApplicationResult.Success -> result.value
        is ApplicationResult.Failure -> error("Navigation setup failed")
    }
    @Before fun prepare() {
        S1Runtime.resetForTest()
        f = T008Fixture()
        f.test {
            f.student(1)
            graph = S1AppGraph(f.db, f.clock, f.ids, f.generation, ApplicationProvider.getApplicationContext<Context>(), ZoneOffset.UTC)
            graph.prepareExerciseCatalog()
            val exercise = value(graph.exerciseRepository.listCatalog()).first { it.exerciseID in EstimatedOneRepMax.exerciseIDs }
            exerciseID = exercise.exerciseID
            repeat(4) { index ->
                f.time = f.now.minusSeconds((4L - index) * 86400)
                val session = value(graph.active.startOrOpen(f.studentID(1), setOf(BodyPart.chest)))
                val id = f.ids.newSessionExerciseID()
                val set = TrainingSet.makeDraft(f.ids.newTrainingSetID(), id, 0u,
                    TrainingSetInput(RecordMode.weightReps, weightValue = "20", repetitionCount = "8", unit = MeasurementUnit.kilograms), f.time).confirmed(f.time)
                val row = SessionExerciseRecord(id, session.sessionID, 0u, ExerciseSourceKind.builtIn, exerciseID,
                    exercise.canonicalName, RecordMode.weightReps, null, null, listOf(set.toRecord()))
                val saved = value(graph.active.saveContent(SaveSessionContentCommand(session.sessionID, session.revision, emptyList(), listOf(row))))
                value(graph.active.complete(CompleteSessionCommand(session.sessionID, saved.session.revision, f.time.plusSeconds(1800), false)))
                history += session.sessionID
            }
            f.time = f.now
        }
        compose.setContent { FineCoachTheme { S1App(graph) } }
        await("today-content")
    }
    @After fun close() {
        compose.runOnUiThread { compose.activity.setContent {} }; compose.waitForIdle()
        f.close(); S1Runtime.resetForTest()
    }
    private fun detail() {
        click("root-1"); await(StudentTestTags.studentRow(f.studentID(1)))
        click(StudentTestTags.studentRow(f.studentID(1))); await("studentDetail.trends")
    }
    @Test fun realStudentDetailOpensLoadedTrendsDestination() {
        detail(); click("studentDetail.trends"); await("trends-metric-0")
        node("trends-metric-0").assertIsDisplayed()
        node("studentDetail.trends").assertDoesNotExist()
    }
    @Test fun realStudentDetailOpensBodyAndMetricUnits() {
        detail(); click("studentDetail.body"); await("body-custom")
        val metric = com.ignacioli.finecoach.core.domain.body.BuiltInBodyMetric.weight.id
        await("body-open-$metric"); click("body-open-$metric"); await("body-unit-kg")
        node("body-unit-kg").assertIsDisplayed()
        node("studentDetail.body").assertDoesNotExist()
    }
    @Test fun todayStagnantInsightOpensTheExerciseTrendsDestination() {
        val tag = "insights.row.stagnant:${f.studentID(1).value}:${exerciseID.value}"
        await(tag)
        click(tag)
        await("trends-metric-3")
        node("trends-metric-3").assertIsDisplayed()
        node("today-content").assertDoesNotExist()
    }
    @Test fun realStudentHistoryOpensComparisonFromVisibleSelection() {
        detail(); click(StudentTestTags.DETAIL_HISTORY); await("history-list-trailing")
        compose.waitUntil(15_000) { node("history-list-trailing").fetchSemanticsNode().config.getOrNull(SemanticsProperties.Disabled) == null }
        click("history-list-trailing")
        val first = "history-compare-pick-${history[0].value}"; val second = "history-compare-pick-${history[1].value}"
        await(first); click(first); click(second); await("history-compare-panel")
        node("history-compare-panel").performScrollTo().assertIsDisplayed()
        node("history-compare-incompatible").assertDoesNotExist()
    }

    @Test fun todayFullListOpensPackageAndPrefilledAppointmentWithoutCreatingOne() {
        val inactive = mutableListOf<StudentID>()
        f.test {
            f.time = f.now.minusSeconds(30L * 86400)
            repeat(2) { index ->
                inactive += value(graph.students.create(com.ignacioli.finecoach.core.domain.student.StudentDraft(
                    "虚构导航候课${if (index == 0) "甲" else "乙"}", StudentSex.undisclosed))).studentID
            }
            f.time = f.now
            value(graph.credits.createActivePackage(f.studentID(1), "虚构导航课包", 1))
        }
        // Re-enter Today through its visible tab to obtain the next authoritative snapshot.
        click("root-1"); await(StudentTestTags.STUDENT_LIST_ROOT)
        click("${StudentTestTags.STUDENT_LIST_SEGMENT}-0"); await("today.insights.all")
        click("today.insights.all")
        val packageRow = "insights.row.package:${f.studentID(1).value}"
        await(packageRow); click(packageRow); await("package-list-add")
        node("package-list-root").assertIsDisplayed()
        click("package-list-back")
        val inactiveRow = "insights.row.inactive:${inactive.first().value}"
        await(inactiveRow); click(inactiveRow); await("appointment-editor-content")
        click("appointment-student")
        await("appointment-student-${inactive.first().value}")
        node("appointment-student-${inactive.first().value}").assertIsSelected()
        f.test { check(value(graph.appointments.all()).isEmpty()) { "Navigation created an appointment" } }
    }
}
