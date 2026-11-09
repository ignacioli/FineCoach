// fictional-data: isolated test-install Session ID, no real students or training content.
package com.ignacioli.finecoach

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.navigation.RestNotificationRoute
import com.ignacioli.finecoach.notifications.RestNotifications
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RestNotificationPermissionTests {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val id = SessionID.parse("abcdef00-0000-4000-8000-000000000091")
    private fun permission(grant: Boolean) {
        if (Build.VERSION.SDK_INT >= 33) instrumentation.uiAutomation.executeShellCommand(
            "pm ${if (grant) "grant" else "revoke"} ${context.packageName} ${Manifest.permission.POST_NOTIFICATIONS}"
        ).use { descriptor -> java.io.FileInputStream(descriptor.fileDescriptor).use { it.readBytes() } }
    }
    @Test fun actualPermissionGrantAndRevokeAreReflectedWithoutBlockingTimer() {
        try {
            permission(false)
            val adapter = RestNotifications(context)
            assertEquals(Build.VERSION.SDK_INT >= 33, adapter.needsRuntimePermission())
            permission(true)
            if (Build.VERSION.SDK_INT >= 33) assertEquals(PackageManager.PERMISSION_GRANTED, context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS))
            assertFalse(adapter.needsRuntimePermission())
            permission(false)
            if (Build.VERSION.SDK_INT >= 33) assertFalse(adapter.enabled())
        } finally { permission(true); RestNotifications(context).cancel(id) }
    }
    @Test fun actualGenericNotificationDisplaysAndCancelsForOnlyItsSession() {
        permission(true)
        val adapter = RestNotifications(context)
        val deadline = System.currentTimeMillis() - 1
        val preferences = context.getSharedPreferences("rest-notification-deadlines", Context.MODE_PRIVATE)
        try {
            assertTrue("Dedicated test install must have system notifications enabled", adapter.enabled())
            assertTrue(preferences.edit().putLong(id.value, deadline).commit())
            adapter.receive(Intent().setAction(RestNotificationRoute.ACTION).putExtra(RestNotificationRoute.SESSION, id.value).putExtra("restDeadline", deadline))
            val manager = context.getSystemService(NotificationManager::class.java)
            val notification = manager.activeNotifications.single { it.tag == id.value }.notification
            assertEquals(RestNotifications.TITLE, notification.extras.getString("android.title"))
            assertEquals(RestNotifications.BODY, notification.extras.getString("android.text"))
            adapter.cancel(id); assertFalse(manager.activeNotifications.any { it.tag == id.value })
        } finally { adapter.cancel(id) }
    }
}
