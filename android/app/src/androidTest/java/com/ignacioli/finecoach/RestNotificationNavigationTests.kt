// fictional-data: two randomly identified fictional students on a dedicated test install only.
package com.ignacioli.finecoach

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.navigation.RestNotificationRoute
import com.ignacioli.finecoach.notifications.RestNotifications
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RestNotificationNavigationTests {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private fun <T> ok(result: ApplicationResult<T>): T {
        assertTrue("Application operation must succeed", result is ApplicationResult.Success)
        return (result as ApplicationResult.Success).value
    }
    private fun hasID(node: AccessibilityNodeInfo?, id: String): Boolean {
        if (node == null) return false
        if (node.viewIdResourceName == id) return true
        return (0 until node.childCount).any { hasID(node.getChild(it), id) }
    }
    private fun openAndAwait(id: SessionID, action: () -> Unit) {
        instrumentation.uiAutomation.executeAndWaitForEvent(action, { event ->
            event.eventType in setOf(AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED, AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) &&
                hasID(instrumentation.uiAutomation.rootInActiveWindow, "active-destination-${id.value}")
        }, 15_000).recycle()
        assertTrue(hasID(instrumentation.uiAutomation.rootInActiveWindow, "active-destination-${id.value}"))
    }
    @Test fun actualNotificationPendingIntentReturnsToOriginalSessionWhileAnotherIsOpen() = runBlocking {
        // Host must use the dedicated fictional simulator; this never resets or deletes its database.
        val graph = withContext(Dispatchers.IO) { ok(S1Runtime.open(context)) }
        val first = ok(graph.students.create(StudentDraft(displayName = "虚构通知甲", sex = StudentSex.undisclosed)))
        val second = ok(graph.students.create(StudentDraft(displayName = "虚构通知乙", sex = StudentSex.undisclosed)))
        val a = ok(graph.active.startOrOpen(first.studentID))
        val b = ok(graph.active.startOrOpen(second.studentID))
        val adapter = RestNotifications(context)
        try {
            if (Build.VERSION.SDK_INT >= 33) instrumentation.uiAutomation.executeShellCommand(
                "pm grant ${context.packageName} android.permission.POST_NOTIFICATIONS"
            ).use { java.io.FileInputStream(it.fileDescriptor).use { stream -> stream.readBytes() } }
            openAndAwait(b.sessionID) { context.startActivity(adapter.clickIntent(b.sessionID).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
            val deadline = System.currentTimeMillis() - 1
            assertTrue(context.getSharedPreferences("rest-notification-deadlines", Context.MODE_PRIVATE).edit().putLong(a.sessionID.value, deadline).commit())
            adapter.receive(Intent().setAction(RestNotificationRoute.ACTION).putExtra(RestNotificationRoute.SESSION, a.sessionID.value).putExtra("restDeadline", deadline))
            val posted = context.getSystemService(NotificationManager::class.java).activeNotifications.single { it.tag == a.sessionID.value }
            openAndAwait(a.sessionID) { posted.notification.contentIntent.send() }
            assertEquals(a.sessionID, ok(graph.sessions.active(first.studentID))!!.sessionID)
            assertEquals(b.sessionID, ok(graph.sessions.active(second.studentID))!!.sessionID)
            assertEquals(1, ok(graph.sessions.listActiveSessions()).count { it.studentID == first.studentID })
            assertEquals(1, ok(graph.sessions.listActiveSessions()).count { it.studentID == second.studentID })
        } finally {
            adapter.cancel(a.sessionID); adapter.cancel(b.sessionID)
            // Only release this test's empty sessions; unrelated records are untouched.
            for (id in listOf(a.sessionID, b.sessionID)) {
                val record = (graph.sessions.find(id) as? ApplicationResult.Success)?.value
                if (record?.state == SessionState.inProgress) graph.finisher.abandonEmpty(id, record.revision, true)
            }
        }
    }
}
