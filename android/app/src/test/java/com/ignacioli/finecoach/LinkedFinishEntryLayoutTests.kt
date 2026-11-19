// fictional-data: isolated Room; invented coach/student/package and appointment.
package com.ignacioli.finecoach

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.test.core.app.ApplicationProvider
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.unit.width
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.session.*
import com.ignacioli.finecoach.storage.*
import com.ignacioli.finecoach.storage.repository.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.UUID
import java.time.LocalTime

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[36],qualifiers="zh-rCN-w390dp-h844dp-notnight-xhdpi")
class LinkedFinishEntryLayoutTests {
    @get:Rule val compose=createAndroidComposeRule<ComponentActivity>()
    private lateinit var f:T009Fixture
    private lateinit var active:ActiveSessionUiState
    private lateinit var finish:FinishSessionUiState
    private lateinit var cases:AppointmentUseCases
    private lateinit var row:Appointment
    private lateinit var content:SessionContentRecord
    private var summary:SessionID?=null
    private fun node(tag:String)=compose.onNodeWithTag(tag)
    private fun await(test:()->Boolean)=compose.waitUntil(15_000) { compose.waitForIdle(); test() }
    @Before fun setup() {
        f=T009Fixture()
        f.test {
            f.coursePackage(); content=f.content(pending=true)
            val sessions=f.sessions
            val generation=UUID.fromString(f.db.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)!!.value)
            cases=AppointmentUseCases(AppointmentRepository(f.db,f.clock,f.ids,generation,sessions,f.zone))
            row=f.ok(cases.createSingle(Appointment(UUID.randomUUID(),f.studentID,date=f.today,startTime=LocalTime.of(9,0),
                reminderEnabled=false,createdAtUTC=f.now,updatedAtUTC=f.now))).single()
            f.ok(cases.startTraining(row.id))
            val exercises=ExerciseUseCases(ExerciseRepository(f.db,ExerciseCatalogLoader(ApplicationProvider.getApplicationContext<Context>().assets),f.clock),f.clock,f.ids)
            active=ActiveSessionUiState(f.active,f.clock,f.ids,sessions,f.history,exercises)
            active.load(content.session.sessionID)
            finish=FinishSessionUiState(active,f.finisher(active.useCases),sessions)
        }
    }
    @After fun close() { compose.runOnUiThread { compose.activity.setContent {} }; compose.waitForIdle(); f.close() }
    private fun show() { compose.setContent { FineCoachTheme { FinishSessionScreen(finish,{},{},{summary=it},{}) } }; await { finish.gate!=null } }
    @Test fun linkedCompletionUsesVisibleDiscardAndDeductsOnceWithoutAdhocChoice() {
        show(); node("finish-credit-accept").assertDoesNotExist()
        assertEquals(node("finish-content").getUnclippedBoundsInRoot().width,node("finish-discard").getUnclippedBoundsInRoot().width)
        node("finish-discard").assertIsDisplayed().performClick(); await { summary!=null }
        node("finish-credit-accept").assertDoesNotExist(); node("finish-skip").assertDoesNotExist()
        f.test {
            assertEquals(AppointmentStatus.completed,f.ok(cases.find(row.id))!!.status)
            f.ok(f.finisher.settlement(content.session.sessionID))
            assertEquals(1L,f.count("credit_adjustments"))
            assertEquals(CreditLedgerSourceEventKeyFactory.sessionComplete(content.session.sessionID),f.ok(f.credits.ledger(f.studentID)).single().sourceEventKey)
        }
    }
    @Test fun linkedDebitFailureHasExplicitRetryAndNoInvalidSkip() {
        show(); f.test { f.failWrites("credit_adjustments","INSERT") }
        node("finish-discard").performClick(); await { finish.error!=null && finish.completed }
        node("finish-skip").assertDoesNotExist(); node("finish-credit-accept").assertDoesNotExist(); assertNull(summary)
        f.test { assertEquals(0L,f.count("credit_adjustments")); assertEquals(AppointmentStatus.completed,f.ok(cases.find(row.id))!!.status); f.clearFailure() }
        node("finish-retry").assertIsDisplayed().performClick(); await { summary!=null }
        f.test { assertEquals(1L,f.count("credit_adjustments")) }
    }
    @Test fun linkedReturnKeepsTrainingAndAppointmentWithoutDebit() {
        show(); node("finish-return").assertIsDisplayed().performClick()
        f.test { assertEquals(AppointmentStatus.inProgress,f.ok(cases.find(row.id))!!.status); assertEquals(0L,f.count("credit_adjustments")) }
        assertFalse(finish.completed)
    }
}
