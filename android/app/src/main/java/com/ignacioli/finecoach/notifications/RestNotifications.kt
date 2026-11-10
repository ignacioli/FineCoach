package com.ignacioli.finecoach.notifications

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import com.ignacioli.finecoach.MainActivity
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.features.session.RestNotificationScheduler
import com.ignacioli.finecoach.navigation.RestNotificationRoute
import java.time.Instant

class RestNotifications(private val context: Context) : RestNotificationScheduler {
    companion object {
        const val CHANNEL = "rest-ended"
        const val TITLE = "休息结束"
        const val BODY = "可以继续训练了"
        private const val DEADLINE = "restDeadline"
    }
    private val alarms = context.getSystemService(AlarmManager::class.java)
    private val manager = context.getSystemService(NotificationManager::class.java)
    private val pending = context.getSharedPreferences("rest-notification-deadlines", Context.MODE_PRIVATE)
    init { manager.createNotificationChannel(NotificationChannel(CHANNEL, "休息提醒", NotificationManager.IMPORTANCE_DEFAULT)) }
    fun enabled(): Boolean = (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
        manager.areNotificationsEnabled() && manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
    fun needsRuntimePermission(): Boolean = Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
    fun clickIntent(id: SessionID): Intent = Intent(context, MainActivity::class.java).setAction(RestNotificationRoute.ACTION)
        .setIdentifier(id.value).putExtra(RestNotificationRoute.SESSION, id.value)
        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    private fun alarm(id: SessionID, end: Instant? = null): PendingIntent = PendingIntent.getBroadcast(context, 0,
        Intent(context, RestNotificationReceiver::class.java).setAction(RestNotificationRoute.ACTION).setIdentifier(id.value)
            .putExtra(RestNotificationRoute.SESSION, id.value).apply { if (end != null) putExtra(DEADLINE, end.toEpochMilli()) },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    override fun replace(sessionID: SessionID, endsAt: Instant) {
        cancel(sessionID)
        if (!enabled() || endsAt <= Instant.now()) return
        if (!pending.edit().putLong(sessionID.value, endsAt.toEpochMilli()).commit()) return
        // Inexact by design: no exact-alarm permission, OS delivery can be delayed.
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endsAt.toEpochMilli(), alarm(sessionID, endsAt))
    }
    override fun cancel(sessionID: SessionID) {
        pending.edit().remove(sessionID.value).commit()
        alarms.cancel(alarm(sessionID)); manager.cancel(sessionID.value, 0)
    }
    fun receive(intent: Intent) {
        val id = RestNotificationRoute.parse(intent) ?: return
        val deadline = intent.getLongExtra(DEADLINE, -1)
        if (deadline < 0 || pending.getLong(id.value, -2) != deadline || Instant.now().toEpochMilli() < deadline) return
        if (!pending.edit().remove(id.value).commit() || !enabled()) return
        val click = PendingIntent.getActivity(context, 0, clickIntent(id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        try {
            manager.notify(id.value, 0, Notification.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_ms_check_circle)
                .setContentTitle(TITLE).setContentText(BODY).setVisibility(Notification.VISIBILITY_PRIVATE)
                .setContentIntent(click).setAutoCancel(true).build())
        } catch (_: SecurityException) { /* Revocation between permission check and notify leaves training unaffected. */ }
    }
}

class RestNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { RestNotifications(context).receive(intent) }
}
