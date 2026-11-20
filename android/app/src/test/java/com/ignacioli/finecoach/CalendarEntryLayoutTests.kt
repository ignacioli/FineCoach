// fictional-data: fixed September appointments and isolated Room; no real records.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.unit.width
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.calendar.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.LocalDate
import kotlinx.coroutines.CompletableDeferred
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.appointment.Appointment
import com.ignacioli.finecoach.features.appointments.AppointmentListState

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-xhdpi")
class CalendarEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private var fixture: S2ScreenFixture? = null
    @After fun close() { compose.runOnUiThread { compose.activity.setContent {} }; compose.waitForIdle(); fixture?.close() }
    @Test fun monthSwitchSelectionAndCreatePassSelectedDateWithoutMutation() {
        val f = S2ScreenFixture(LocalDate.of(2026, 9, 1), false).also { fixture = it }
        f.room.test { f.add(2,"09:00",day=f.date.plusMonths(1)) }
        val state = CalendarUiState(f.list); var created: LocalDate? = null
        compose.setContent { FineCoachTheme { CalendarScreen(state, {}, { created = it }, {}) } }
        compose.waitUntil(15_000) { compose.waitForIdle(); f.list.loaded }
        val before = f.list.rows
        compose.onNodeWithTag("calendar-next").assertIsDisplayed().performClick()
        assertEquals(java.time.YearMonth.of(2026, 10), state.month)
        compose.waitUntil(15_000) { compose.waitForIdle(); f.list.rows.all { it.date.monthValue == 10 } && f.list.rows.isNotEmpty() }
        assertEquals(1,f.list.rows.size)
        compose.onNodeWithTag("calendar-previous").performClick()
        compose.waitUntil(15_000) { compose.waitForIdle(); f.list.rows.size == before.size }
        compose.onNodeWithTag("calendar-day-8").assertHasClickAction().performClick()
        compose.onNodeWithTag("calendar-day-8").assertIsSelected()
        assertEquals(LocalDate.of(2026, 9, 8), state.selectedDate)
        compose.onNodeWithTag("calendar-add").assertIsDisplayed().performClick()
        assertEquals(state.selectedDate, created)
        assertEquals(compose.onNodeWithTag("platform-content").getUnclippedBoundsInRoot().width,
            compose.onNodeWithTag("calendar-add").getUnclippedBoundsInRoot().width)
        assertEquals(before, f.list.rows)
        f.room.test { assertEquals(before.size.toLong()+1, f.room.count("appointments")) }
    }
    @Test fun februaryUsesRealMonthLengthAndSelectedDayHasNonColorAppointmentState() {
        val f = S2ScreenFixture(LocalDate.of(2026, 9, 1), false).also { fixture = it }
        val state = CalendarUiState(f.list, LocalDate.of(2028, 2, 1))
        compose.setContent { FineCoachTheme { CalendarScreen(state, {}, {}, {}) } }
        compose.waitUntil(15_000) { f.list.loaded }
        compose.onNodeWithTag("calendar-day-29").assertExists()
        compose.onNodeWithTag("calendar-day-30").assertDoesNotExist()
        compose.onNodeWithTag("calendar-day-1").assertIsSelected()
            .assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.StateDescription, "无课程安排"))
    }
    @Test fun calendarDays() {
        val f = S2ScreenFixture(LocalDate.of(2026,9,1),false).also { fixture = it }
        val state = CalendarUiState(f.list)
        compose.setContent { FineCoachTheme { CalendarScreen(state,{}, {},{}) } }
        compose.waitUntil(15_000) { compose.waitForIdle(); f.list.loaded }
        val day = compose.onNodeWithTag("calendar-day-4")
        day.assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.StateDescription,"有课程安排"))
        compose.onNode(hasTestTag("conformance:Has-appointment dot") and hasAnyAncestor(hasTestTag("calendar-day-4")),useUnmergedTree=true).assertExists()
        day.performClick().assertIsSelected()
        compose.onNode(hasTestTag("conformance:Has-appointment dot") and hasAnyAncestor(hasTestTag("calendar-day-4")),useUnmergedTree=true).assertDoesNotExist()
    }
    @Test fun retryReloadsDisplayedMonthAfterVisibleFailure() {
        val f = S2ScreenFixture(LocalDate.of(2026,9,1),false).also { fixture = it }; var attempts = 0
        val repository = object : com.ignacioli.finecoach.core.application.AppointmentRepositoryPort by f.repository {
            override suspend fun inDateRange(first: LocalDate,last: LocalDate): com.ignacioli.finecoach.core.application.ApplicationResult<List<com.ignacioli.finecoach.core.domain.appointment.Appointment>> {
                assertEquals(LocalDate.of(2026,9,1),first); assertEquals(LocalDate.of(2026,9,30),last); attempts++
                return if (attempts==1) com.ignacioli.finecoach.core.application.ApplicationResult.Failure(com.ignacioli.finecoach.core.application.ApplicationError(com.ignacioli.finecoach.core.application.ApplicationErrorCode.persistenceFailed)) else f.repository.inDateRange(first,last)
            }
        }
        val list = com.ignacioli.finecoach.features.appointments.AppointmentListState(com.ignacioli.finecoach.core.application.AppointmentUseCases(repository),f.students,f.room.clock,f.zone)
        val state = CalendarUiState(list)
        compose.setContent { FineCoachTheme { CalendarScreen(state,{}, {},{}) } }
        compose.waitUntil(15_000) { compose.waitForIdle(); list.error!=null }
        compose.onNodeWithTag("calendar-retry").performScrollTo().assertIsDisplayed().performClick()
        compose.waitUntil(15_000) { compose.waitForIdle(); list.loaded }
        assertNull(list.error); assertEquals(2,attempts)
    }
    @Test fun monthChangeClearsOldRowsAndDotsWhileNewRangeIsSuspended() {
        val f = S2ScreenFixture(LocalDate.of(2026, 9, 1), false).also { fixture = it }
        val releaseOctober = CompletableDeferred<Unit>()
        val enteredOctober = CompletableDeferred<Unit>()
        val repository = object : AppointmentRepositoryPort by f.repository {
            override suspend fun inDateRange(first: LocalDate, last: LocalDate): ApplicationResult<List<Appointment>> {
                if (first.monthValue == 10) {
                    enteredOctober.complete(Unit)
                    releaseOctober.await()
                    return ApplicationResult.Success(emptyList())
                }
                return f.repository.inDateRange(first, last)
            }
        }
        val list = AppointmentListState(AppointmentUseCases(repository), f.students, f.room.clock, f.zone)
        val state = CalendarUiState(list)
        compose.setContent { FineCoachTheme { CalendarScreen(state, {}, {}, {}) } }
        compose.waitUntil(15_000) { compose.waitForIdle(); list.loaded }
        val oldRows = list.rows
        assertTrue(oldRows.isNotEmpty())
        compose.onNode(hasTestTag("conformance:Has-appointment dot") and hasAnyAncestor(hasTestTag("calendar-day-4")), useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("calendar-next").performClick()
        compose.waitUntil(15_000) { compose.waitForIdle(); enteredOctober.isCompleted }
        assertFalse(list.loaded); assertTrue(list.rows.isEmpty()); assertTrue(list.names.isEmpty())
        assertEquals(f.date, state.selectedDate)
        compose.onAllNodesWithTag("conformance:Has-appointment dot", useUnmergedTree = true).assertCountEquals(0)
        compose.onNodeWithTag("calendar-empty").assertDoesNotExist()
        oldRows.forEach { compose.onNodeWithTag("calendar-appointment-${it.id}").assertDoesNotExist() }
        releaseOctober.complete(Unit)
        compose.waitUntil(15_000) { compose.waitForIdle(); list.loaded }
        compose.onNodeWithTag("calendar-empty").assertExists()
    }
}
