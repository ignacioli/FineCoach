// fictional-data: invented stable Session IDs; no people or training values.
package com.ignacioli.finecoach

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.notifications.*
import com.ignacioli.finecoach.navigation.RestNotificationRoute
import java.time.Instant
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [32])
class RestNotificationTests {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val a = SessionID.parse("abcdef00-0000-4000-8000-000000000001")
    private val b = SessionID.parse("abcdef00-0000-4000-8000-000000000002")
    @Test fun replaceCancelAndProcessAdapterRecreationPreserveSessionIsolation() {
        val adapter = RestNotifications(context)
        val alarms = shadowOf(context.getSystemService(AlarmManager::class.java))
        val now = Instant.now()
        adapter.replace(a, now.plusSeconds(120)); adapter.replace(b, now.plusSeconds(120))
        assertEquals(2, alarms.scheduledAlarms.size)
        adapter.replace(a, now.plusSeconds(135)); assertEquals(2, alarms.scheduledAlarms.size)
        assertTrue(alarms.scheduledAlarms.any { it.triggerAtTime == now.plusSeconds(135).toEpochMilli() })
        RestNotifications(context).cancel(a); assertEquals(1, alarms.scheduledAlarms.size)
        adapter.cancel(b); assertEquals(0, alarms.scheduledAlarms.size)
    }
    @Test fun clickIntentAndBridgeDeliverOnlyValidatedStableSessionID() {
        val adapter = RestNotifications(context)
        var delivered: SessionID? = null
        assertTrue(RestNotificationRoute.deliver(adapter.clickIntent(a)) { delivered = it }); assertEquals(a, delivered)
        assertFalse(RestNotificationRoute.deliver(Intent().setAction(RestNotificationRoute.ACTION).putExtra(RestNotificationRoute.SESSION, "invalid")) { fail() })
        assertFalse(RestNotificationRoute.deliver(Intent()) { fail() })
        assertEquals(setOf(RestNotificationRoute.SESSION), adapter.clickIntent(a).extras!!.keySet())
    }
    @Test fun cancelledOrReplacedLateBroadcastCannotPublishNotification() {
        val adapter = RestNotifications(context)
        val intent = Intent().setAction(RestNotificationRoute.ACTION).putExtra(RestNotificationRoute.SESSION, a.value).putExtra("restDeadline", 1L)
        adapter.cancel(a); adapter.receive(intent)
        assertEquals(0, shadowOf(context.getSystemService(NotificationManager::class.java)).allNotifications.size)
        assertEquals("休息结束", RestNotifications.TITLE); assertEquals("可以继续训练了", RestNotifications.BODY)
    }
    @Test @Config(sdk = [33]) fun api33DeniedPermissionDoesNotScheduleAndNeedsExplicitRequest() {
        shadowOf(context as android.app.Application).denyPermissions(android.Manifest.permission.POST_NOTIFICATIONS)
        val adapter = RestNotifications(context)
        assertTrue(adapter.needsRuntimePermission()); assertFalse(adapter.enabled())
        adapter.replace(a, Instant.now().plusSeconds(120))
        assertEquals(0, shadowOf(context.getSystemService(AlarmManager::class.java)).scheduledAlarms.size)
    }
}
