// fictional-data: two randomly identified fictional students on a dedicated test install only.
package com.ignacioli.finecoach

import android.app.NotificationManager
import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.notifications.RestNotifications
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RestNotificationNavigationTests {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private fun <T> ok(result: ApplicationResult<T>): T {
        assertTrue("Application operation must succeed", result is ApplicationResult.Success)
        return (result as ApplicationResult.Success).value
    }
    private fun openAndAwait(id: SessionID, phase: String, action: () -> Unit) {
        action()
        RestNotificationDeviceSupport.awaitDestination(context, id, phase)
    }
    @Test fun actualNotificationPendingIntentReturnsToOriginalSessionWhileAnotherIsOpen() =
        RestNotificationDeviceSupport.withReportedViewIds { runBlocking {
            // Host must use the dedicated fictional simulator; this never resets or deletes its database.
            val graph = withContext(Dispatchers.IO) { ok(S1Runtime.open(context)) }
            val first = ok(graph.students.create(StudentDraft(displayName = "虚构通知甲", sex = StudentSex.undisclosed)))
            val second = ok(graph.students.create(StudentDraft(displayName = "虚构通知乙", sex = StudentSex.undisclosed)))
            val a = ok(graph.active.startOrOpen(first.studentID))
            val b = ok(graph.active.startOrOpen(second.studentID))
            val adapter = RestNotifications(context)
            val manager = context.getSystemService(NotificationManager::class.java)
            try {
                assertTrue("Host must grant notification permission and enable system notifications before this case", adapter.enabled())
                openAndAwait(b.sessionID, "first-open-b") { context.startActivity(adapter.clickIntent(b.sessionID).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                // iOS alerts for another Student while b is visible; Android receive has no foreground suppression.
                RestNotificationDeviceSupport.deliverDue(context, adapter, a.sessionID)
                val posted = RestNotificationDeviceSupport.awaitPosted(manager, a.sessionID)
                openAndAwait(a.sessionID, "notification-open-a") { posted.notification.contentIntent.send() }
                assertEquals(a.sessionID, ok(graph.sessions.active(first.studentID))!!.sessionID)
                assertEquals(b.sessionID, ok(graph.sessions.active(second.studentID))!!.sessionID)
                assertEquals(1, ok(graph.sessions.listActiveSessions()).count { it.studentID == first.studentID })
                assertEquals(1, ok(graph.sessions.listActiveSessions()).count { it.studentID == second.studentID })
            } finally {
                adapter.cancel(a.sessionID); adapter.cancel(b.sessionID)
                RestNotificationDeviceSupport.awaitRemoved(manager, a.sessionID)
                RestNotificationDeviceSupport.awaitRemoved(manager, b.sessionID)
                // Only release this test's empty sessions; unrelated records are untouched.
                for (id in listOf(a.sessionID, b.sessionID)) {
                    val record = (graph.sessions.find(id) as? ApplicationResult.Success)?.value
                    if (record?.state == SessionState.inProgress) graph.finisher.abandonEmpty(id, record.revision, true)
                }
            }
        } }
}
