package com.ignacioli.finecoach.notifications

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import com.ignacioli.finecoach.MainActivity
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.storage.*
import java.time.*
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

class AppointmentReminders(
    private val context: Context,
    private val database: FineCoachDatabase,
    private val repository: AppointmentRepositoryPort,
    private val clock: AppClock,
    private val registerAlarm: ((Long, PendingIntent) -> Unit)? = null,
    private val zone: () -> ZoneId = { ZoneId.systemDefault() },
) : AppointmentReminderPort {
    companion object {
        const val CHANNEL = "appointment-reminders"
        const val ACTION = "com.ignacioli.finecoach.APPOINTMENT_REMINDER"
        const val ID = "appointmentID"
        const val PERMISSION_REQUESTED = "appointment-permission-requested"
        private const val REGISTRY = "appointment-reminders-v1"
        private val gate = Mutex()
        fun parse(intent: Intent?): UUID? = try {
            if (intent?.action == ACTION) UUID.fromString(intent.getStringExtra(ID)) else null
        } catch (_: IllegalArgumentException) { null }
    }
    private val alarms = context.getSystemService(AlarmManager::class.java)
    private val manager = context.getSystemService(NotificationManager::class.java)
    init { manager.createNotificationChannel(NotificationChannel(CHANNEL, "课程提醒", NotificationManager.IMPORTANCE_DEFAULT)) }
    fun enabled() = (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
        manager.areNotificationsEnabled() && manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
    fun clickIntent(id: UUID) = Intent(context, MainActivity::class.java).setAction(ACTION)
        .setIdentifier("appointment-reminder:$id").putExtra(ID, id.toString())
        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    private fun alarm(id: UUID) = PendingIntent.getBroadcast(context, 0,
        Intent(context, ReminderRescheduleReceiver::class.java).setAction(ACTION).setIdentifier("appointment-reminder:$id").putExtra(ID, id.toString()),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun read() = JSONObject(database.storeMetadataDao().find(REGISTRY)?.value ?: "{}")
    private fun write(value: JSONObject) {
        val dao = database.storeMetadataDao()
        val row = StoreMetadata(REGISTRY, value.toString())
        if (dao.find(REGISTRY) == null) dao.insert(row) else check(dao.update(row) == 1)
    }
    val lastFailure = kotlinx.coroutines.flow.MutableStateFlow<ApplicationError?>(null)
    private suspend fun safely(action: suspend () -> Unit) {
        try { action(); lastFailure.value = null }
        catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (_: Exception) { lastFailure.value = ApplicationError(ApplicationErrorCode.persistenceFailed) }
    }
    val permissionRequest = kotlinx.coroutines.flow.MutableStateFlow(false)
    @Volatile var observedPermissionRevision: Int = 0
    private val pendingPermissionBaseline = java.util.concurrent.atomic.AtomicReference<Int?>(null)
    /** Baseline captured before [permissionRequest] is raised, so a fast grant result is not compared with itself. */
    fun takePendingPermissionBaseline(): Int? = pendingPermissionBaseline.getAndSet(null)
    override suspend fun appointmentSaved() = safely {
        withContext(Dispatchers.IO) { gate.withLock {
            val rows = (repository.all() as? ApplicationResult.Success)?.value.orEmpty()
            if (rows.any { it.reminderEnabled } && database.storeMetadataDao().find(PERMISSION_REQUESTED) == null) {
                database.storeMetadataDao().insert(StoreMetadata(PERMISSION_REQUESTED, "true"))
                val issue = Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                if (issue) pendingPermissionBaseline.set(observedPermissionRevision)
                permissionRequest.value = issue
            }
        } }
        reconcile()
    }
    override suspend fun reconcile() { reconcile(force = false) }
    suspend fun reconcile(force: Boolean) = safely { reconcileWork(force) }
    private suspend fun reconcileWork(force: Boolean) = withContext(Dispatchers.IO) { gate.withLock {
        val rows = when (val result = repository.all()) {
            is ApplicationResult.Success -> result.value
            is ApplicationResult.Failure -> error("Reminder repository unavailable")
        }
        val current = read()
        val desired = JSONObject()
        val tz = zone()
        val exact = alarms.canScheduleExactAlarms()
        if (enabled()) rows.forEach { row ->
            val fire = fireTime(row, clock.now(), tz)
            if (fire != null) desired.put(row.id.toString(), "$fire|$tz|$exact")
        }
        current.keys().asSequence().toList().filter { !desired.has(it) }.forEach {
            alarms.cancel(alarm(UUID.fromString(it))); manager.cancel("appointment-reminder:$it", 0)
            current.remove(it)
        }
        write(current)
        desired.keys().forEach { key ->
            if (force || current.optString(key) != desired.getString(key)) {
                val fire = Instant.parse(desired.getString(key).substringBefore('|')).toEpochMilli()
                val pending = alarm(UUID.fromString(key))
                alarms.cancel(pending)
                current.remove(key); write(current)
                if (registerAlarm != null) registerAlarm.invoke(fire, pending) else try {
                    if (alarms.canScheduleExactAlarms()) alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fire, pending)
                    else alarms.setWindow(AlarmManager.RTC_WAKEUP, fire, 600_000, pending)
                } catch (_: SecurityException) {
                    // Exact access can be revoked after the check. Preserve the inexact fallback.
                    alarms.setWindow(AlarmManager.RTC_WAKEUP, fire, 600_000, pending)
                }
                // Only acknowledge a successful OS registration. Failed sets remain retryable.
                current.put(key, desired.getString(key)); write(current)
            }
        }
    } }
    suspend fun receive(intent: Intent) = withContext(Dispatchers.IO) { gate.withLock {
        val id = parse(intent) ?: return@withLock
        val registry = read()
        if (!registry.has(id.toString())) return@withLock
        val row = when (val result = repository.find(id)) {
            is ApplicationResult.Success -> result.value
            is ApplicationResult.Failure -> return@withLock
        } ?: return@withLock
        val fire = row.reminderLeadMinutes?.let { row.startInstant(zone()).minusSeconds(it.minutes * 60L) }
        if (row.status != AppointmentStatus.scheduled || !row.reminderEnabled || fire == null ||
            fire.toString() != registry.getString(id.toString()).substringBefore('|') || clock.now() < fire || clock.now() >= row.startInstant(zone())) return@withLock
        registry.remove(id.toString()); write(registry)
        if (!enabled()) return@withLock
        val click = PendingIntent.getActivity(context, 0, clickIntent(id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        try {
            manager.notify("appointment-reminder:$id", 0, Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_ms_check_circle).setContentTitle(AppointmentNotificationContentBuilder.title())
                .setContentText(AppointmentNotificationContentBuilder.body(row.startInstant(zone()), zone()))
                .setVisibility(Notification.VISIBILITY_PUBLIC).setContentIntent(click).setAutoCancel(true).build())
        } catch (_: SecurityException) { /* Notification access may be revoked; saved data is unaffected. */ }
    } }
}

internal fun fireTime(row: Appointment, now: Instant, zone: ZoneId): Instant? {
    if (row.status != AppointmentStatus.scheduled || !row.reminderEnabled) return null
    val lead = row.reminderLeadMinutes ?: return null
    return row.startInstant(zone).minusSeconds(lead.minutes * 60L).takeIf { it > now }
}
