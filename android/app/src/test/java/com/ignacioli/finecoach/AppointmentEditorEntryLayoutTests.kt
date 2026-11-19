// fictional-data: isolated Room, synthetic students/appointments, fixed Asia/Shanghai time.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.unit.width
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.appointments.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.*
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-xhdpi")
class AppointmentEditorEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private var fixture: S2ScreenFixture? = null
    private fun fixture() = S2ScreenFixture(LocalDate.of(2026, 9, 1), false).also { fixture = it }
    private fun node(tag: String) = compose.onNodeWithTag(tag)
    private fun await(condition: () -> Boolean) = compose.waitUntil(15_000) { compose.waitForIdle(); condition() }
    @After fun close() { compose.runOnUiThread { compose.activity.setContent {} }; compose.waitForIdle(); fixture?.close() }
    @Test fun visibleFieldsPersistSelectedStudentFocusDurationAndReminderTier() {
        val f = fixture(); val state = AppointmentEditorState(f.appointments, f.students, f.room.clock, f.zone, f.date.plusDays(1))
        var saved = false
        compose.setContent { FineCoachTheme { AppointmentEditorScreen(state, {}, { saved = true }) } }
        await { state.loaded }
        node("appointment-student").performClick()
        node("appointment-student-${f.room.studentID(2).value}").performClick()
        node("appointment-duration").performClick(); node("appointment-duration-45").performClick()
        node("appointment-focus-3").performScrollTo().performClick()
        node("appointment-reminder-lead").performScrollTo().performClick(); node("appointment-lead-120").performScrollTo().performClick()
        node("appointment-reminder").performScrollTo().performClick(); assertFalse(state.reminderEnabled)
        node("appointment-reminder").performClick(); assertTrue(state.reminderEnabled)
        assertEquals(compose.onNodeWithTag("platform-content").getUnclippedBoundsInRoot().width, node("appointment-save").getUnclippedBoundsInRoot().width)
        node("appointment-save").assertIsDisplayed().performClick(); await { saved }
        f.room.test {
            val row = f.room.ok(f.appointments.all()).single { it.date == f.date.plusDays(1) }
            assertEquals(f.room.studentID(2), row.studentID); assertEquals(45, row.durationMinutes)
            assertEquals(setOf(BodyPart.thighs), row.trainingFocus); assertEquals(ReminderLeadMinutes.oneTwenty, row.reminderLeadMinutes)
            assertTrue(row.reminderEnabled)
        }
    }
    @Test fun timePickerSupportsClockAndInputAndCancelPreservesDraft() {
        val f = fixture(); val state = AppointmentEditorState(f.appointments, f.students, f.room.clock, f.zone, f.date)
        compose.setContent { FineCoachTheme { AppointmentEditorScreen(state, {}, {}) } }; await { state.loaded }
        val before = state.time
        node("appointment-time").performClick(); node("appointment-time-clock").assertIsDisplayed()
        node("appointment-time-mode").assertHasClickAction()
            .assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.Role,androidx.compose.ui.semantics.Role.Button))
            .assert(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.ContentDescription))
            .performClick(); node("appointment-time-input").assertIsDisplayed()
        node("appointment-time-cancel").performClick(); assertEquals(before, state.time)
        node("appointment-time").performClick(); node("appointment-time-mode").performClick()
        node("appointment-time-mode").performClick(); node("appointment-time-clock").assertIsDisplayed()
        node("appointment-time-accept").performClick(); assertEquals(before,state.time)
        node("appointment-date").performClick(); node("appointment-date-picker").assertExists()
        node("appointment-date").performScrollTo().performClick(); node("appointment-date-picker").assertDoesNotExist()
    }
    @Test fun conflictRequiresVisibleConfirmationAndOverrideKeepsExistingAppointments() {
        val f = fixture(); val state = AppointmentEditorState(f.appointments, f.students, f.room.clock, f.zone, f.date)
        state.studentID = f.room.studentID(2); state.time = LocalTime.of(15, 0)
        var saved = false
        compose.setContent { FineCoachTheme { AppointmentEditorScreen(state, {}, { saved = true }) } }; await { state.loaded }
        val old = f.list.run { var rows: List<Appointment> = emptyList(); f.room.test { rows = f.room.ok(f.appointments.all()) }; rows }
        node("appointment-save").performClick(); await { state.conflict != null }
        assertFalse(saved); assertTrue(state.conflict!!.contains("张伟 15:00"))
        f.room.test { assertEquals(old.size.toLong(), f.room.count("appointments")) }
        node("appointment-conflict-accept").assertIsDisplayed().performClick(); await { saved }
        f.room.test {
            val after = f.room.ok(f.appointments.all())
            assertEquals(old.size + 1, after.size); assertTrue(after.containsAll(old))
        }
    }
    @Test fun recurrenceBoundIsBlockedWithoutWritesAndPreviewUsesLastMaterializedDate() {
        val f = fixture(); val state = AppointmentEditorState(f.appointments, f.students, f.room.clock, f.zone, LocalDate.of(2025, 9, 27))
        f.room.test {
            state.load(); state.interval = RecurrenceInterval.everyTwoDays; state.endDate = LocalDate.of(2025, 10, 31)
            assertEquals("将创建 12 节课（9月27日 – 10月30日，每 3 天一次）", state.preview)
            val before = f.room.count("appointments")
            state.endByCount = true; state.count = 367; state.save()
            assertFalse(state.saved); assertNotNull(state.error); assertEquals(before, f.room.count("appointments"))
            state.count = 2; state.duration = 0; state.save()
            assertFalse(state.saved); assertEquals(before, f.room.count("appointments"))
        }
    }
    @Test fun seriesEditingRequiresScopeAndFutureKeepsPriorInstance() {
        val f = fixture(); var rows: List<Appointment> = emptyList()
        f.room.test {
            rows = f.room.ok(f.appointments.createRecurring(RecurrenceSeries(UUID.randomUUID(), f.room.studentID(2), RecurrenceInterval.everyWeek,
                RecurrenceTermination.RepeatCount(3), LocalTime.of(19, 0), defaultReminderEnabled = false,
                createdAtUTC = f.room.time, updatedAtUTC = f.room.time), f.date.plusDays(1)))
        }
        val state = AppointmentEditorState(f.appointments, f.students, f.room.clock, f.zone, f.date, rows[1].id)
        var saved = false
        compose.setContent { FineCoachTheme { AppointmentEditorScreen(state,{}, { saved = true }) } }; await { state.loaded }
        compose.runOnIdle { state.time = LocalTime.of(20,0) }
        node("appointment-save").performClick(); await { state.scopeRequested }
        assertFalse(state.saved)
        node("appointment-scope-future").assertIsDisplayed().performClick(); await { saved }
        f.room.test {
            assertEquals(rows.first(), f.room.ok(f.appointments.find(rows.first().id)))
            val future = f.room.ok(f.appointments.all()).filter { it.studentID == f.room.studentID(2) && it.date >= rows[1].date && it.seriesID != null }
            assertTrue(future.isNotEmpty()); assertTrue(future.all { it.startTime == LocalTime.of(20, 0) })
        }
    }
    @Test fun invalidRecurrenceErrorsAppearInPreviewAndNeverPersist() {
        val f = fixture(); val state = AppointmentEditorState(f.appointments,f.students,f.room.clock,f.zone,f.date)
        compose.setContent { FineCoachTheme { AppointmentEditorScreen(state,{}, {}) } }; await { state.loaded }
        node("appointment-repeat-2").performScrollTo().performClick()
        compose.runOnIdle { state.endDate = state.date.minusDays(1) }
        node("appointment-preview").performScrollTo().assertTextEquals("当前状态不允许此操作。")
        node("appointment-save").performClick(); await { state.error != null }
        assertEquals("当前状态不允许此操作。",state.error)
        compose.runOnIdle { state.endDate = state.date.plusDays(367) }
        node("appointment-preview").performScrollTo().assertTextEquals("周期安排超过可物化上限（最多 366 次）。")
        node("appointment-save").performClick(); await { state.error == "周期安排超过可物化上限（最多 366 次）。" }
        node("appointment-end-count-mode").performScrollTo().performClick()
        node("appointment-count").performScrollTo().performTextReplacement("1")
        node("appointment-preview").performScrollTo().assertTextEquals("不是有效数字。")
        node("appointment-save").performClick(); await { state.error == "不是有效数字。" }
        assertFalse(state.saved)
        node("appointment-count").performScrollTo().performTextReplacement("2")
        assertTrue(state.validBound); assertTrue(state.preview!!.startsWith("将创建 2 节课"))
        f.room.test { assertEquals(9L,f.room.count("appointments")) }
    }
    @Test fun endDatePickerDisablesDayBeforeStart() {
        val f = fixture(); val state = AppointmentEditorState(f.appointments,f.students,f.room.clock,f.zone,f.date.withDayOfMonth(15))
        compose.setContent { FineCoachTheme { AppointmentEditorScreen(state,{}, {}) } }; await { state.loaded }
        node("appointment-repeat-1").performScrollTo().performClick()
        compose.runOnIdle { state.endDate = state.date }
        node("appointment-end-date").performScrollTo().performClick()
        val previousDay = state.date.minusDays(1)
        val inPicker = hasAnyAncestor(hasTestTag("appointment-date-picker"))
        val disabled = compose.onAllNodes(inPicker and hasText("${previousDay.monthValue}月${previousDay.dayOfMonth}日", substring = true) and hasClickAction(), useUnmergedTree = true)
        if (disabled.fetchSemanticsNodes().isEmpty()) {
            println(compose.onNodeWithTag("appointment-date-picker", useUnmergedTree = true).printToString())
        }
        disabled.assertCountEquals(1); disabled[0].assertIsNotEnabled()
        val enabled = compose.onAllNodes(inPicker and hasText("${state.date.monthValue}月${state.date.dayOfMonth}日", substring = true) and hasClickAction(), useUnmergedTree = true)
        enabled.assertCountEquals(1); enabled[0].assertIsEnabled()
    }
    @Test fun thisOnlyScopeButtonChangesJustTheSelectedOccurrence() {
        val f = fixture(); var rows: List<Appointment> = emptyList()
        f.room.test { rows = f.room.ok(f.appointments.createRecurring(RecurrenceSeries(UUID.randomUUID(),f.room.studentID(2),
            RecurrenceInterval.everyWeek,RecurrenceTermination.RepeatCount(3),LocalTime.of(19,0),defaultReminderEnabled=false,
            createdAtUTC=f.room.time,updatedAtUTC=f.room.time),f.date.plusDays(1))) }
        val state = AppointmentEditorState(f.appointments,f.students,f.room.clock,f.zone,f.date,rows[1].id)
        var saved = false
        compose.setContent { FineCoachTheme { AppointmentEditorScreen(state,{}, { saved=true }) } }; await { state.loaded }
        compose.runOnIdle { state.time=LocalTime.of(20,0) }
        node("appointment-save").performClick(); await { state.scopeRequested }
        node("appointment-scope-single").assertIsDisplayed().performClick(); await { saved }
        f.room.test {
            val changed = f.room.ok(f.appointments.find(rows[1].id))!!
            assertTrue(changed.isDetachedException); assertEquals(LocalTime.of(20,0),changed.startTime)
            assertEquals(rows.first(),f.room.ok(f.appointments.find(rows.first().id)))
            assertEquals(rows.last(),f.room.ok(f.appointments.find(rows.last().id)))
        }
    }
    @Test fun retryLoadsStudentChoicesAfterVisibleFailure() {
        val f=fixture(); var attempts=0
        val real=com.ignacioli.finecoach.storage.repository.StudentRepository(f.room.db,f.room.clock)
        val students=StudentUseCases(object : StudentRepositoryPort by real {
            override suspend fun list(query: StudentQuery): ApplicationResult<List<StudentRecord>> {
                attempts++
                return if (attempts==1) ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed)) else real.list(query)
            }
        },f.room.clock,f.room.ids)
        val state=AppointmentEditorState(f.appointments,students,f.room.clock,f.zone,f.date)
        compose.setContent { FineCoachTheme { AppointmentEditorScreen(state,{}, {}) } }
        await { state.error!=null }
        node("appointment-retry").performScrollTo().assertIsDisplayed().performClick(); await { state.loaded }
        assertNull(state.error); assertEquals(2,attempts)
    }
}
