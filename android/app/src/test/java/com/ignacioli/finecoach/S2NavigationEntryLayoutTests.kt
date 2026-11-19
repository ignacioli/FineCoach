// fictional-data: isolated Room, one invented student and a fixed Asia/Shanghai clock.
package com.ignacioli.finecoach

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.core.domain.appointment.Appointment
import java.time.LocalTime
import java.util.UUID
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.ZoneId

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class S2NavigationEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private lateinit var fixture: T008Fixture
    @Before fun setup() { fixture = T008Fixture() }
    @After fun close() {
        compose.runOnUiThread { compose.activity.setContent {} }; compose.waitForIdle()
        fixture.close(); S1Runtime.resetForTest()
    }
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun await(tag: String) = compose.waitUntil(15_000) {
        compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    }
    @Test fun realNavHostOpensEditorAndCalendarAndReturnsToS2Today() {
        lateinit var graph: S1AppGraph
        lateinit var appointment: Appointment
        fixture.test {
            fixture.student(1)
            graph = S1AppGraph(fixture.db, fixture.clock, fixture.ids, fixture.generation,
                ApplicationProvider.getApplicationContext<Context>(), ZoneId.of("Asia/Shanghai"))
            appointment = fixture.ok(graph.appointments.createSingle(Appointment(UUID.randomUUID(), fixture.studentID(1),
                date = graph.clock.today(graph.zone), startTime = LocalTime.of(23, 0), reminderEnabled = false,
                createdAtUTC = fixture.time, updatedAtUTC = fixture.time))).single()
        }
        compose.setContent { FineCoachTheme { S1App(graph) } }
        await("today-add"); node("today-add").assertIsDisplayed().assertHasClickAction().performClick()
        await("appointment-editor-content")
        compose.onNodeWithText("新建课程安排", useUnmergedTree = true).assertIsDisplayed()
        node("today-content").assertDoesNotExist()
        node("appointment-editor-back").assertIsDisplayed().performClick()
        await("today-add"); node("today-content").assertIsDisplayed()
        node("today-settings").assertIsNotEnabled()
        node("today-calendar").assertIsDisplayed().assertHasClickAction().performClick()
        await("calendar-content"); node("calendar-add").assertIsDisplayed()
        node("today-content").assertDoesNotExist()
        await("calendar-appointment-${appointment.id}")
        node("calendar-appointment-${appointment.id}").assertIsDisplayed().performClick()
        await("appointment-editor-content")
        compose.onNodeWithText("编辑课程安排",useUnmergedTree=true).assertIsDisplayed()
        node("appointment-editor-back").performClick(); await("calendar-content")
        node("calendar-back").assertIsDisplayed().performClick()
        await("today-add"); node("today-content").assertIsDisplayed()
        await("today-appointment-${appointment.id}")
        node("today-appointment-${appointment.id}").assertIsDisplayed().assertHasClickAction().performClick()
        await("appointment-editor-content")
        compose.onNodeWithText("编辑课程安排", useUnmergedTree = true).assertIsDisplayed()
        node("appointment-editor-back").performClick(); await("today-add")
        fixture.test {
            assertEquals(appointment, fixture.ok(graph.appointments.find(appointment.id)))
            assertEquals(1L, fixture.count("appointments")); assertEquals(1L, fixture.count("students"))
        }
    }
}
