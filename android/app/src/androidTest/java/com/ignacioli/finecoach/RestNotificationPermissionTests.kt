// fictional-data: isolated test-install Session IDs, no real students or training content.
package com.ignacioli.finecoach

import android.Manifest
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.ignacioli.finecoach.core.application.AppClock
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.features.session.RestTimerStore
import com.ignacioli.finecoach.notifications.RestNotifications
import java.time.Instant
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RestNotificationPermissionTests {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val id = SessionID.parse("abcdef00-0000-4000-8000-000000000091")
    private val other = SessionID.parse("abcdef00-0000-4000-8000-000000000092")

    @Test fun configuredPermissionStateIsReflectedWithoutBlockingTimer() {
        val adapter = RestNotifications(context)
        if (Build.VERSION.SDK_INT >= 33) {
            val expected = InstrumentationRegistry.getArguments().getString("restPermissionState")
            assertTrue("Host must explicitly select granted or denied before instrumentation", expected in setOf("granted", "denied"))
            val granted = expected == "granted"
            assertEquals(granted, context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
            assertEquals(!granted, adapter.needsRuntimePermission())
            assertEquals(granted, adapter.enabled())
        } else {
            assertFalse(adapter.needsRuntimePermission())
            assertTrue("Dedicated test install must have system notifications enabled", adapter.enabled())
        }
        // Permission mutation belongs to the host before this process starts, never to this test.
        val now = Instant.parse("2026-11-09T00:00:00Z")
        val timer = RestTimerStore(AppClock { now })
        timer.start(id); assertEquals(120L, timer.remaining(id))
        timer.adjust(id, -15); assertEquals(105L, timer.remaining(id))
        timer.clear(id); assertNull(timer.end(id))
    }

    @Test fun actualGenericNotificationDisplaysAndCancelsForOnlyItsSession() {
        val adapter = RestNotifications(context)
        val manager = context.getSystemService(NotificationManager::class.java)
        try {
            assertTrue("Run this case only in the host's granted phase with system notifications enabled", adapter.enabled())
            adapter.cancel(id); adapter.cancel(other)
            RestNotificationDeviceSupport.awaitRemoved(manager, id)
            RestNotificationDeviceSupport.awaitRemoved(manager, other)
            RestNotificationDeviceSupport.deliverDue(context, adapter, id)
            RestNotificationDeviceSupport.deliverDue(context, adapter, other)
            val notification = RestNotificationDeviceSupport.awaitPosted(manager, id).notification
            RestNotificationDeviceSupport.awaitPosted(manager, other)
            assertEquals(RestNotifications.TITLE, notification.extras.getString("android.title"))
            assertEquals(RestNotifications.BODY, notification.extras.getString("android.text"))
            adapter.cancel(id)
            RestNotificationDeviceSupport.awaitRemoved(manager, id)
            assertTrue(manager.activeNotifications.any { it.tag == other.value && it.id == 0 })
        } finally {
            adapter.cancel(id); adapter.cancel(other)
            RestNotificationDeviceSupport.awaitRemoved(manager, id)
            RestNotificationDeviceSupport.awaitRemoved(manager, other)
        }
    }
}
