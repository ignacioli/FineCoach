// fictional-data: the seeded fixture student only; no measurements or history writes.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.width
import com.ignacioli.finecoach.core.application.StudentUseCases
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.body.BodyDataScreen
import com.ignacioli.finecoach.features.body.BodyDataState
import com.ignacioli.finecoach.features.students.StudentDetailScreen
import com.ignacioli.finecoach.features.students.StudentFeatureFactory
import com.ignacioli.finecoach.features.trends.TrendsScreen
import com.ignacioli.finecoach.features.trends.TrendsState
import com.ignacioli.finecoach.navigation.S1Routes
import com.ignacioli.finecoach.storage.repository.StudentRepository
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-mdpi")
class StudentRecordEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val f = T009Fixture()
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    @After fun close() { compose.runOnUiThread { compose.activity.setContent {} }; f.close() }

    @Test fun trendsEntryOpensTheTrendPageAtFullWidth() = open("studentDetail.trends", S1Routes.studentTrends(f.studentID), "trends", "trends-root")
    @Test fun bodyEntryOpensTheBodyPageAtFullWidth() = open("studentDetail.body", S1Routes.studentBody(f.studentID), "body", "body-list")

    private fun open(tag: String, route: String, pageName: String, destination: String) {
        lateinit var detail: com.ignacioli.finecoach.features.students.StudentDetailViewModel
        lateinit var trends: TrendsState
        lateinit var body: BodyDataState
        f.test {
            val students = StudentUseCases(StudentRepository(f.db, f.clock), f.clock, f.ids)
            detail = StudentFeatureFactory.detailViewModel(f.studentID, students, f.sessions, f.credits, historyRepository = f.history, clock = f.clock, zoneId = f.zone)
            trends = TrendsState(f.studentID, com.ignacioli.finecoach.core.application.ProgressUseCases(f.history, f.sessions), f.zone)
            body = BodyDataState(f.studentID, com.ignacioli.finecoach.core.application.BodyDataUseCases(
                com.ignacioli.finecoach.storage.repository.BodyDataRepository(f.db, f.clock), f.clock, f.zone) { java.util.UUID.randomUUID() })
        }
        var page by mutableStateOf("detail")
        compose.setContent {
            FineCoachTheme {
                when (page) {
                    "trends" -> TrendsScreen(trends) {}
                    "body" -> BodyDataScreen(body) {}
                    else -> StudentDetailScreen(detail, onRoute = { if (it == route) page = pageName }, onBack = {})
                }
            }
        }
        compose.waitUntil(15_000) { exists(tag) }
        node(tag).performScrollTo().assertIsDisplayed().assertHasClickAction()
        check(node("platform-content").getUnclippedBoundsInRoot().width == node(tag).getUnclippedBoundsInRoot().width) { "entry does not fill the page" }
        node(tag).performClick()
        compose.waitUntil(15_000) { exists(destination) }
        node(destination).assertIsDisplayed()
    }
}
