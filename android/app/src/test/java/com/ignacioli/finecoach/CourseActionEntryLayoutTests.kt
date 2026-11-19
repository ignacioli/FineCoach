// fictional-data: isolated Room, synthetic students, appointments and credit packages.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.unit.width
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.appointments.*
import com.ignacioli.finecoach.storage.repository.CoursePackageRepository
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.*
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[36], qualifiers="zh-rCN-w390dp-h844dp-notnight-xhdpi")
class CourseActionEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private lateinit var f: S2ScreenFixture
    private lateinit var credits: CreditUseCases
    private lateinit var row: Appointment
    private lateinit var state: CourseActionState
    private var dismissed = 0; private var changed = 0; private var opened: SessionID? = null; private var edited: UUID? = null
    private fun node(tag: String) = compose.onNodeWithTag(tag)
    private fun await(test: () -> Boolean) = compose.waitUntil(15_000) { compose.waitForIdle(); test() }
    @Before fun setup() {
        f = S2ScreenFixture(todayHero=false)
        credits = CreditUseCases(CoursePackageRepository(f.room.db,f.room.clock,f.room.ids,f.zone),f.room.clock,f.room.ids,f.zone)
        f.room.test { row = f.room.ok(f.appointments.all()).first { it.startTime == LocalTime.of(15,0) }; f.room.ok(credits.createActivePackage(row.studentID,null,5)) }
    }
    @After fun close() { compose.runOnUiThread { compose.activity.setContent {} }; compose.waitForIdle(); f.close() }
    private fun show(cases: AppointmentUseCases = f.appointments) {
        state = CourseActionState(row.id,cases,credits,f.students,f.room.clock,f.zone)
        compose.setContent { FineCoachTheme { CourseActionSheet(state,{dismissed++},{changed++},{edited=it},{opened=it}) } }
        await { state.row != null && state.name.isNotBlank() }
    }
    @Test fun cancelConfirmationAndDismissKeepRecordWithoutDebit() {
        show(); node("course-cancel").assertIsDisplayed().performClick()
        node("course-confirm-cancel").assertIsDisplayed().performClick()
        f.room.test { assertEquals(row,f.room.ok(f.appointments.find(row.id))); assertEquals(0L,f.room.count("credit_adjustments")) }
        node("course-cancel").performClick(); node("course-confirm-accept").performClick(); await { changed==1 }
        f.room.test { assertEquals(AppointmentStatus.cancelled,f.room.ok(f.appointments.find(row.id))!!.status); assertEquals(0L,f.room.count("credit_adjustments")) }
    }
    @Test fun deleteRequiresConfirmationAndHasFullWidthVisibleControl() {
        show(); await { state.deletable }
        assertEquals(node("course-actions").getUnclippedBoundsInRoot().width,node("course-delete").getUnclippedBoundsInRoot().width)
        node("course-delete").assertIsDisplayed().performClick(); node("course-confirm-cancel").performClick()
        f.room.test { assertEquals(row,f.room.ok(f.appointments.find(row.id))) }
        node("course-delete").performClick(); node("course-confirm-accept").performClick(); await { changed==1 }
        f.room.test { assertNull(f.room.ok(f.appointments.find(row.id))); assertEquals(0L,f.room.count("credit_adjustments")) }
    }
    @Test fun overdueNeverOffersPermanentDeleteAndEditDismissDoNotWrite() {
        f.room.test { f.room.time = row.endInstant(f.zone).plusSeconds(1) }
        show(); node("course-delete").assertDoesNotExist()
        node("course-edit").assertIsDisplayed().performClick(); assertEquals(row.id,edited)
        node("course-dismiss").assertIsDisplayed().performClick(); assertEquals(1,dismissed)
        f.room.test { assertEquals(row,f.room.ok(f.appointments.find(row.id))) }
    }
    @Test fun absentBackThenExplicitDebitPersistsOneIdempotentAppointmentEvent() {
        show(); node("course-absent").assertIsDisplayed().performClick()
        node("course-absent-back").assertIsDisplayed().performClick()
        f.room.test { assertEquals(row,f.room.ok(f.appointments.find(row.id))) }
        node("course-absent").performClick(); node("course-absent-debit").assertIsDisplayed().performClick(); await { changed==1 }
        f.room.test {
            assertEquals(AppointmentStatus.absent,f.room.ok(f.appointments.find(row.id))!!.status)
            assertEquals(AbsentCreditChoice.charged,f.room.ok(f.appointments.find(row.id))!!.absentCreditChoice)
            f.room.ok(f.appointments.markAbsent(row.id,AbsentCreditChoice.charged,true))
            val ledger=f.room.ok(credits.ledger(row.studentID)); assertEquals(1,ledger.size)
            assertEquals(CreditLedgerSourceEventKeyFactory.appointmentAbsent(row.id.toString()),ledger.single().sourceEventKey)
        }
    }
    @Test fun absentWithoutDebitNeverWritesLedger() {
        show(); node("course-absent").performClick(); node("course-absent-free").assertIsDisplayed().performClick(); await { changed==1 }
        f.room.test { assertEquals(AbsentCreditChoice.notCharged,f.room.ok(f.appointments.find(row.id))!!.absentCreditChoice); assertEquals(0L,f.room.count("credit_adjustments")) }
    }
    @Test fun startCreatesLinkedTrainingWithFocusAndVisiblePreviousTrainingEntryLeavesNewAppointmentUnchanged() {
        lateinit var previous: SessionRecord
        f.room.test {
            val old=f.add(2,"13:00")
            previous=(f.room.ok(f.appointments.startTraining(old.id)) as AppointmentTrainingStartResult.Started).session
        }
        show(); node("course-start").assertIsDisplayed().performClick(); await { state.previous!=null }
        node("course-previous").assertIsDisplayed().performClick(); assertEquals(previous.sessionID,opened)
        f.room.test { assertEquals(row,f.room.ok(f.appointments.find(row.id))); assertEquals(0L,f.room.count("credit_adjustments")) }
    }
    @Test fun startPersistsAndNavigatesOnlyAfterSuccess() {
        show(); assertEquals(node("course-actions").getUnclippedBoundsInRoot().width,node("course-start").getUnclippedBoundsInRoot().width)
        node("course-start").assertIsDisplayed().performClick(); await { opened!=null }
        f.room.test { val saved=f.room.ok(f.appointments.find(row.id))!!; assertEquals(AppointmentStatus.inProgress,saved.status)
            assertEquals(opened!!.value,saved.linkedSessionID.toString()); assertEquals(row.trainingFocus,f.room.ok(f.room.sessions.find(opened!!))!!.trainingFocus) }
    }
    @Test fun failedStartShowsErrorAndKeepsRoomUnchanged() {
        val port=object : AppointmentRepositoryPort by f.repository {
            override suspend fun start(id: UUID): ApplicationResult<AppointmentTrainingStartResult> = ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed))
        }
        show(AppointmentUseCases(port)); node("course-start").performClick(); await { state.error!=null }
        node("course-error").assertIsDisplayed(); assertNull(opened)
        f.room.test { assertEquals(row,f.room.ok(f.appointments.find(row.id))); assertEquals(0L,f.room.count("credit_adjustments")) }
    }    @Test fun linkedAppointmentHasVisibleContinueAndNeverDelete() {
        lateinit var started: SessionRecord
        f.room.test { started=(f.room.ok(f.appointments.startTraining(row.id)) as AppointmentTrainingStartResult.Started).session }
        show(); node("course-delete").assertDoesNotExist(); node("course-continue").assertIsDisplayed().performClick()
        assertEquals(started.sessionID,opened)
    }
    @Test fun ledgerReferenceHidesDeleteEvenForScheduledFuture() {
        f.room.test { val pack=f.room.ok(credits.activePackage(row.studentID,f.date))!!; f.room.ok(credits.debitOnAppointmentAbsent(pack.coursePackageID,row.id.toString())) }
        show(); node("course-delete").assertDoesNotExist()
        f.room.test { assertEquals(row,f.room.ok(f.appointments.find(row.id))); assertEquals(1L,f.room.count("credit_adjustments")) }
    }
    @Test fun absenceDebitFailureReportsDurableAbsenceAndExplicitRetryWritesOnce() {
        show(); f.room.test { f.room.failWrites("credit_adjustments","INSERT") }
        node("course-absent").performClick(); node("course-absent-debit").performClick(); await { state.error!=null }
        node("course-error").assertIsDisplayed(); assertEquals(0,changed)
        f.room.test { assertEquals(AppointmentStatus.absent,f.room.ok(f.appointments.find(row.id))!!.status); assertEquals(0L,f.room.count("credit_adjustments")); f.room.clearFailure() }
        node("course-absent-debit").assertIsDisplayed().performClick(); await { changed==1 }
        f.room.test { assertEquals(1L,f.room.count("credit_adjustments")) }
    }
    @Test fun studentDeleteConfirmationCountsAppointmentsAndCancelKeepsRoom() {
        lateinit var state: com.ignacioli.finecoach.features.students.DeleteStudentViewModel
        f.room.test { state=com.ignacioli.finecoach.features.students.DeleteStudentViewModel(row.studentID,f.students, f.room.sessions,appointments=f.appointments) }
        compose.setContent { FineCoachTheme { com.ignacioli.finecoach.features.students.DeleteStudentScreen(state,{dismissed++}) } }
        await { state.uiState.impact!=null }
        val expected=state.uiState.impact!!.appointmentCount!!
        assertTrue(expected>0)
        node("delete-student-appointments").performScrollTo().assertTextContains("$expected 个课程安排",substring=true)
        node(com.ignacioli.finecoach.features.students.StudentTestTags.DELETE_CANCEL).assertIsDisplayed().performClick()
        await { dismissed==1 }
        f.room.test { assertEquals(expected,f.room.ok(f.appointments.all()).count { it.studentID==row.studentID }) }
    }

}
