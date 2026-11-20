// fictional-data: isolated Room, one invented student and a fixed Asia/Shanghai clock.
package com.ignacioli.finecoach

import android.os.Bundle
import com.ignacioli.finecoach.features.settings.*
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicBoolean
import android.Manifest
import android.app.Application
import android.app.NotificationManager
import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.core.domain.appointment.Appointment
import com.ignacioli.finecoach.notifications.AppointmentReminders
import com.ignacioli.finecoach.storage.StoreMetadata
import java.time.LocalTime
import java.util.UUID
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
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
            fixture.db.storeMetadataDao().insert(StoreMetadata(AppointmentReminders.PERMISSION_REQUESTED, "true"))
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
        shadowOf(ApplicationProvider.getApplicationContext<Application>()).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        node("today-settings").assertIsDisplayed().performClick(); await("settings-content")
        compose.waitUntil(15_000) { compose.onAllNodesWithContentDescription("权限拒绝").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithContentDescription("权限拒绝").assertIsDisplayed()
        compose.onNodeWithText("前往设置").assertIsDisplayed()
        node("settings-notifications").assertIsDisplayed()
        node("settings-back").performClick(); await("today-add")
        node("today-calendar").assertIsDisplayed().assertHasClickAction().performClick()
        await("calendar-content"); node("calendar-add").assertIsDisplayed()
        node("today-content").assertDoesNotExist()
        await("calendar-appointment-${appointment.id}")
        node("calendar-appointment-${appointment.id}").assertIsDisplayed().performClick()
        await("course-edit"); node("course-edit").assertIsDisplayed().performClick()
        await("appointment-editor-content")
        compose.onNodeWithText("编辑课程安排",useUnmergedTree=true).assertIsDisplayed()
        node("appointment-editor-back").performClick(); await("calendar-content")
        node("calendar-back").assertIsDisplayed().performClick()
        await("today-add"); node("today-content").assertIsDisplayed()
        await("today-appointment-${appointment.id}")
        node("today-appointment-${appointment.id}").assertIsDisplayed().assertHasClickAction().performClick()
        await("course-edit"); node("course-edit").assertIsDisplayed().performClick()
        await("appointment-editor-content")
        compose.onNodeWithText("编辑课程安排", useUnmergedTree = true).assertIsDisplayed()
        node("appointment-editor-back").performClick(); await("today-add")
        fixture.test {
            assertEquals(appointment, fixture.ok(graph.appointments.find(appointment.id)))
            assertEquals(1L, fixture.count("appointments")); assertEquals(1L, fixture.count("students"))
        }
    }
    private fun showDeniedReminderSave(): S1AppGraph {
        lateinit var graph: S1AppGraph
        fixture.test {
            fixture.student(1)
            fixture.db.storeMetadataDao().insert(StoreMetadata(AppointmentReminders.PERMISSION_REQUESTED, "true"))
            graph = S1AppGraph(fixture.db, fixture.clock, fixture.ids, fixture.generation,
                ApplicationProvider.getApplicationContext<Context>(), ZoneId.of("Asia/Shanghai"))
        }
        compose.setContent { FineCoachTheme { S1App(graph) } }
        await("today-add"); node("today-add").performClick(); await("appointment-editor-content")
        node("appointment-student").performClick()
        node("appointment-student-${fixture.studentID(1).value}").performClick()
        node("appointment-save").performClick()
        await("saved-reminder-denied-card")
        return graph
    }
    @Test fun deniedReminderSaveKeepsRowAndCompleteDismisses() {
        val graph = showDeniedReminderSave()
        node("saved-reminder-denied-cancel").assertIsDisplayed().assertHasClickAction().performClick()
        await("today-add"); node("saved-reminder-denied-card").assertDoesNotExist()
        fixture.test {
            val saved = fixture.ok(graph.appointments.all()).single()
            assertTrue(saved.reminderEnabled); assertEquals(1L, fixture.count("appointments"))
        }
    }
    @Test fun deniedReminderSaveOpensSettingsFromVisibleAction() {
        val graph = showDeniedReminderSave()
        node("saved-reminder-denied-accept").assertIsDisplayed().assertHasClickAction().performClick()
        await("settings-content")
        fixture.test {
            val saved = fixture.ok(graph.appointments.all()).single()
            assertTrue(saved.reminderEnabled); assertEquals(1L, fixture.count("appointments"))
        }
    }
    private lateinit var permissionGraph: S1AppGraph
    private fun showFirstReminderSave(restoration: androidx.compose.ui.test.junit4.StateRestorationTester? = null, progress: androidx.compose.runtime.MutableState<NotificationPermissionProgress>? = null, initialRevision: Int = 0, readStatus: (suspend () -> ReminderSettingsState.Status)? = null): androidx.compose.runtime.MutableState<Int> {
        lateinit var graph: S1AppGraph
        fixture.test {
            fixture.student(1)
            graph = S1AppGraph(fixture.db, fixture.clock, fixture.ids, fixture.generation,
                ApplicationProvider.getApplicationContext<Context>(), ZoneId.of("Asia/Shanghai"))
        }
        val app = ApplicationProvider.getApplicationContext<Application>()
        shadowOf(app).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        shadowOf(app.getSystemService(NotificationManager::class.java)).setNotificationsEnabled(true)
        permissionGraph = graph
        val revision = mutableStateOf(initialRevision)
        val content: @androidx.compose.runtime.Composable () -> Unit = {
            FineCoachTheme { S1App(graph, permissionRevision = progress?.value?.revision ?: revision.value, permissionInFlight = progress?.value?.inFlight ?: false, readSavedReminderStatus = readStatus) }
        }
        if (restoration == null) compose.setContent(content) else restoration.setContent(content)

        await("today-add"); node("today-add").performClick(); await("appointment-editor-content")
        node("appointment-student").performClick()
        node("appointment-student-${fixture.studentID(1).value}").performClick()
        return revision
    }
    private val statusReads = AtomicInteger()
    private val lastReadStatus = java.util.concurrent.atomic.AtomicReference<ReminderSettingsState.Status?>()
    private suspend fun countedStatus(): ReminderSettingsState.Status {
        statusReads.incrementAndGet()
        val status = readReminderSettingsStatus(permissionGraph.reminders::enabled) {
            permissionGraph.database.storeMetadataDao().find(AppointmentReminders.PERMISSION_REQUESTED) != null
        }
        lastReadStatus.set(status)
        return status
    }
    private fun recreateLaunchedRequest(): Pair<androidx.compose.runtime.MutableState<NotificationPermissionProgress>, Bundle> {
        val restoration = androidx.compose.ui.test.junit4.StateRestorationTester(compose)
        val original = NotificationPermissionProgress("fictional-process").also { repeat(3) { _ -> it.complete() }; it.begin() }
        val progress = mutableStateOf(original)
        showFirstReminderSave(restoration, progress, readStatus = ::countedStatus)
        node("appointment-save").performClick(); await("today-add")
        // Model S1Root's launch handshake: queue consumed, system result still outstanding.
        compose.runOnIdle { permissionGraph.reminders.permissionRequest.value = false }
        val saved = Bundle().also(original::save)
        compose.runOnIdle { progress.value = NotificationPermissionProgress("fictional-process").also { it.restore(saved) } }
        restoration.emulateSavedInstanceStateRestore()
        await("today-add"); compose.waitForIdle()
        compose.runOnIdle { assertFalse(permissionGraph.reminders.permissionRequest.value); assertEquals(0, statusReads.get()) }
        node("saved-reminder-denied-card").assertDoesNotExist()
        return progress to saved
    }
    @Test fun rotationDuringRequestWaitsForLateResultRatherThanShowingDenial() {
        val (progress, _) = recreateLaunchedRequest()
        compose.runOnIdle { progress.value.complete() }
        await("saved-reminder-denied-card")
        assertEquals(1, statusReads.get())
    }
    @Test fun lateGrantAfterRecreationFinishesWaitWithoutDeniedCard() {
        val (progress, _) = recreateLaunchedRequest()
        shadowOf(ApplicationProvider.getApplicationContext<Application>()).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        compose.runOnIdle { progress.value.complete() }
        compose.waitUntil(15_000) {
            // The v2 rule must settle the permission-result recomposition before reading an external atomic.
            compose.waitForIdle()
            lastReadStatus.get() == ReminderSettingsState.Status.enabled
        }
        compose.waitForIdle()
        node("saved-reminder-denied-card").assertDoesNotExist()
        assertEquals(1, statusReads.get())
        // A later revision must not read again once the saved-request wait has ended.
        compose.runOnIdle { progress.value.complete() }
        compose.waitForIdle()
        assertEquals(1, statusReads.get())
        node("saved-reminder-denied-card").assertDoesNotExist()
    }
    @Test fun lostRequestAfterProcessRecreationFallsBackToCurrentPermission() {
        val (progress, saved) = recreateLaunchedRequest()
        // UI wait has survived recreation; a new process cannot keep the old launch in flight.
        compose.runOnIdle { progress.value = NotificationPermissionProgress("fictional-new-process").also { it.restore(saved) } }
        await("saved-reminder-denied-card")
        assertEquals(1, statusReads.get())
    }
    @Test fun saveCallbackReadFailurePreservesAppointmentAndVisibleRetryRecovers() {
        val fail = AtomicBoolean(true)
        showFirstReminderSave(readStatus = {
            if (fail.get()) throw IllegalStateException("fictional post-save read failure")
            countedStatus()
        })
        fixture.test { fixture.db.storeMetadataDao().insert(StoreMetadata(AppointmentReminders.PERMISSION_REQUESTED, "true")) }
        node("appointment-save").performClick()
        await("saved-reminder-error-card")
        compose.onNodeWithText("读取通知设置失败，请重试。", useUnmergedTree = true).assertIsDisplayed()
        fixture.test { assertEquals(1L, fixture.count("appointments")); assertTrue(fixture.ok(permissionGraph.appointments.all()).single().reminderEnabled) }
        fail.set(false)
        node("saved-reminder-error-accept").assertIsDisplayed().performClick()
        await("saved-reminder-denied-card")
        node("saved-reminder-error-card").assertDoesNotExist()
        fixture.test { assertEquals(1L, fixture.count("appointments")) }
    }
    @Test fun firstReminderGrantDoesNotShowDeniedPrompt() {
        val revision = showFirstReminderSave()
        node("appointment-save").performClick(); await("today-add")
        node("saved-reminder-denied-card").assertDoesNotExist()
        shadowOf(ApplicationProvider.getApplicationContext<Application>()).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        compose.runOnIdle { revision.value = 1 }
        compose.waitForIdle()
        node("saved-reminder-denied-card").assertDoesNotExist()
    }
    @Test fun firstReminderDenialShowsPromptAfterGrantResult() {
        val revision = showFirstReminderSave()
        node("appointment-save").performClick(); await("today-add")
        node("saved-reminder-denied-card").assertDoesNotExist()
        compose.runOnIdle { revision.value = 1 }
        await("saved-reminder-denied-card")
        node("saved-reminder-denied-card").assertIsDisplayed()
    }
    @Test fun firstSaveWithoutRuntimeRequestShowsDeniedPromptWhenNotificationsAreOff() {
        showFirstReminderSave()
        val app = ApplicationProvider.getApplicationContext<Application>()
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        shadowOf(app.getSystemService(NotificationManager::class.java)).setNotificationsEnabled(false)
        node("appointment-save").performClick()
        await("saved-reminder-denied-card")
        compose.onNodeWithText("前往设置").assertIsDisplayed()
        node("saved-reminder-denied-accept").assertIsDisplayed().assertHasClickAction()
        assertNull(shadowOf(compose.activity).lastRequestedPermission)
    }
    @Test fun firstSaveWithoutRuntimeRequestShowsNoPromptWhenNotificationsAreAvailable() {
        showFirstReminderSave()
        shadowOf(ApplicationProvider.getApplicationContext<Application>()).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        node("appointment-save").performClick(); await("today-add")
        compose.waitForIdle()
        node("saved-reminder-denied-card").assertDoesNotExist()
        assertNull(shadowOf(compose.activity).lastRequestedPermission)
    }
}
