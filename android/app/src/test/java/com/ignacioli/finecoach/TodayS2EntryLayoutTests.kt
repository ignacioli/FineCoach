// fictional-data: isolated Room appointments; fixed Asia/Shanghai clock.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.unit.width
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.today.TodayS2Screen
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.LocalDate
import androidx.compose.runtime.rememberCoroutineScope
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.appointment.Appointment
import com.ignacioli.finecoach.features.appointments.AppointmentListState
import kotlinx.coroutines.*

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-xhdpi")
class TodayS2EntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private var fixture: S2ScreenFixture? = null
    @After fun close() {
        compose.runOnUiThread { compose.activity.setContent {} }; compose.waitForIdle()
        fixture?.close()
    }
    @Test fun visibleEntriesAndCollapsedResolvedRowsUseRealAppointmentData() {
        val f = S2ScreenFixture().also { fixture = it }
        var created: LocalDate? = null; var calendar = false; val selected = mutableListOf<java.util.UUID>()
        compose.setContent { FineCoachTheme { TodayS2Screen(f.training, f.list, {}, { calendar = true }, { created = it }, selected::add) } }
        compose.waitUntil(15_000) { compose.waitForIdle(); f.list.loaded && f.training.hasCompletedInitialLoad }
        compose.onNodeWithTag("conformance:icon / plus", useUnmergedTree = true)
            .assertWidthIsEqualTo(com.ignacioli.finecoach.designsystem.FcComponentMetrics.badge)
            .assertHeightIsEqualTo(com.ignacioli.finecoach.designsystem.FcComponentMetrics.badge)
        compose.onNodeWithTag("today-add").assertIsDisplayed()
            .assertWidthIsAtLeast(com.ignacioli.finecoach.designsystem.FcComponentMetrics.touch).performClick()
        compose.onNodeWithTag("today-calendar").assertIsDisplayed().performClick()
        assertEquals(f.date, created); assertTrue(calendar)
        val first = f.list.rows.single { it.startTime.hour == 15 }
        val control = compose.onNodeWithTag("today-appointment-${first.id}")
        control.assertIsDisplayed().assertHasClickAction()
        assertEquals(compose.onNodeWithTag("platform-content").getUnclippedBoundsInRoot().width, control.getUnclippedBoundsInRoot().width)
        control.performClick(); assertEquals(listOf(first.id), selected)
        compose.onAllNodesWithTag("today-resolved-${f.list.rows.first { it.status == com.ignacioli.finecoach.core.domain.appointment.AppointmentStatus.cancelled }.id}").assertCountEquals(0)
        compose.onNodeWithTag("today-resolved").performScrollTo().assertHasClickAction().performClick()
        compose.onNodeWithText("已处理 · 3").assertExists()
        assertEquals(3, f.list.rows.count { it.status == com.ignacioli.finecoach.core.domain.appointment.AppointmentStatus.cancelled })
    }
    @Test fun overdueAndOtherTodayRowsAreVisibleClickableAndUseSharedStatus() {
        val f = S2ScreenFixture().also { fixture = it }
        lateinit var overdue: com.ignacioli.finecoach.core.domain.appointment.Appointment
        f.room.test { overdue = f.add(2,"10:00") }
        val clicked = mutableListOf<java.util.UUID>()
        compose.setContent { FineCoachTheme { TodayS2Screen(f.training,f.list,{}, {}, {},clicked::add) } }
        compose.waitUntil(15_000) { compose.waitForIdle(); f.list.loaded }
        compose.onNodeWithTag("today-appointment-${overdue.id}").performScrollTo().assertIsDisplayed().performClick()
        compose.onNodeWithTag("appointment-overdue-status",useUnmergedTree=true).assertContentDescriptionEquals("逾期")
        val other = f.list.rows.single { it.startTime.hour == 19 }
        compose.onNodeWithTag("today-appointment-${other.id}").performScrollTo().assertIsDisplayed().performClick()
        assertEquals(listOf(overdue.id,other.id),clicked)
    }
    @Test fun missingStudentKeepsVisibleRowWithEmptyNameAndNoScreenError() {
        val f = S2ScreenFixture().also { fixture = it }
        val real = com.ignacioli.finecoach.storage.repository.StudentRepository(f.room.db,f.room.clock)
        val names = com.ignacioli.finecoach.core.application.StudentUseCases(object : com.ignacioli.finecoach.core.application.StudentRepositoryPort by real {
            override suspend fun displayNames(ids: Set<com.ignacioli.finecoach.core.domain.common.StudentID>): com.ignacioli.finecoach.core.application.ApplicationResult<Map<com.ignacioli.finecoach.core.domain.common.StudentID,String>> = com.ignacioli.finecoach.core.application.ApplicationResult.Success(emptyMap())
        },f.room.clock,f.room.ids)
        val state = com.ignacioli.finecoach.features.appointments.AppointmentListState(f.appointments,names,f.room.clock,f.zone)
        compose.setContent { FineCoachTheme { TodayS2Screen(f.training,state,{}, {}, {},{}) } }
        compose.waitUntil(15_000) { compose.waitForIdle(); state.loaded }
        val row = state.rows.single { it.startTime.hour == 15 }
        compose.onNodeWithTag("today-appointment-${row.id}").assertIsDisplayed().assertHasClickAction().performClick()
        assertEquals("",state.names[row.studentID]); assertNull(state.error)
        compose.onAllNodesWithText("张伟",useUnmergedTree=true).assertCountEquals(0)
    }
    @Test fun retryReadsTodayRangeAfterVisibleFailure() {
        val f = S2ScreenFixture().also { fixture = it }; var attempts = 0
        val repository = object : com.ignacioli.finecoach.core.application.AppointmentRepositoryPort by f.repository {
            override suspend fun inDateRange(first: java.time.LocalDate,last: java.time.LocalDate): com.ignacioli.finecoach.core.application.ApplicationResult<List<com.ignacioli.finecoach.core.domain.appointment.Appointment>> {
                attempts++
                return if (attempts == 1) com.ignacioli.finecoach.core.application.ApplicationResult.Failure(com.ignacioli.finecoach.core.application.ApplicationError(com.ignacioli.finecoach.core.application.ApplicationErrorCode.persistenceFailed)) else f.repository.inDateRange(first,last)
            }
        }
        val state = com.ignacioli.finecoach.features.appointments.AppointmentListState(com.ignacioli.finecoach.core.application.AppointmentUseCases(repository),f.students,f.room.clock,f.zone)
        compose.setContent { FineCoachTheme { TodayS2Screen(f.training,state,{}, {}, {},{}) } }
        compose.waitUntil(15_000) { compose.waitForIdle(); state.error != null }
        compose.onNodeWithTag("today-retry").assertIsDisplayed().performClick()
        compose.waitUntil(15_000) { compose.waitForIdle(); state.loaded }
        assertNull(state.error); assertEquals(2,attempts)
    }
    @Test fun sameRangeReloadKeepsDisplayedRowsUntilReplacementArrives() {
        val f = S2ScreenFixture().also { fixture = it }
        val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        var attempts = 0
        val repository = object : AppointmentRepositoryPort by f.repository {
            override suspend fun inDateRange(first: LocalDate, last: LocalDate): ApplicationResult<List<Appointment>> {
                if (++attempts > 1) { entered.complete(Unit); release.await() }
                val result = f.repository.inDateRange(first, last)
                return if (attempts > 1 && result is ApplicationResult.Success) {
                    ApplicationResult.Success(result.value.map { if (it.startTime.hour == 15) it.copy(durationMinutes = 90) else it })
                } else result
            }
        }
        val state = AppointmentListState(AppointmentUseCases(repository), f.students, f.room.clock, f.zone)
        lateinit var scope: CoroutineScope
        compose.setContent {
            scope = rememberCoroutineScope()
            FineCoachTheme { TodayS2Screen(f.training, state, {}, {}, {}, {}) }
        }
        compose.waitUntil(15_000) { compose.waitForIdle(); state.loaded }
        val rows = state.rows; val names = state.names
        val old = rows.single { it.startTime.hour == 15 }
        compose.runOnIdle { scope.launch { state.load() } }
        compose.waitUntil(15_000) { compose.waitForIdle(); entered.isCompleted }
        assertTrue(state.loaded); assertEquals(rows, state.rows); assertEquals(names, state.names)
        compose.onNodeWithTag("today-appointment-${old.id}").assertIsDisplayed()
        compose.onNodeWithText("60 分钟 · 大腿").assertIsDisplayed()
        release.complete(Unit)
        compose.waitUntil(15_000) { compose.waitForIdle(); state.rows.any { it.id == old.id && it.durationMinutes == 90 } }
        compose.onNodeWithTag("today-appointment-${old.id}").assertIsDisplayed()
        compose.onNodeWithText("90 分钟 · 大腿").assertIsDisplayed()
        assertTrue(state.loaded); assertEquals(names, state.names)
    }
}
