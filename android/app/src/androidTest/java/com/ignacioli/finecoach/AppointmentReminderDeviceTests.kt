// fictional-data: dedicated test-install appointments and synthetic students only; never run on owner data.
package com.ignacioli.finecoach

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.common.StudentSex
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.notifications.AppointmentReminders
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.testing.AppointmentAlarmEvidence
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.time.*
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AppointmentReminderDeviceTests {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val args = InstrumentationRegistry.getArguments()
    private val manager = context.getSystemService(NotificationManager::class.java)
    private val alarms = context.getSystemService(AlarmManager::class.java)
    private val prefs = context.getSharedPreferences("fictional-s2-device", Context.MODE_PRIVATE)
    private fun <T> ok(result: ApplicationResult<T>): T = when (result) {
        is ApplicationResult.Success -> result.value
        is ApplicationResult.Failure -> throw AssertionError("Test-install operation failed")
    }
    private suspend fun graph() = ok(S1Runtime.open(context))
    private fun requirePermission(g: S1AppGraph, expected: String) {
        assertEquals("Host must explicitly configure appointmentPermissionState", expected, args.getString("appointmentPermissionState"))
        if (Build.VERSION.SDK_INT >= 33) assertEquals(expected == "granted",
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
        assertEquals(expected == "granted", g.reminders.enabled())
    }
    private suspend fun save(g: S1AppGraph, days: Long = 0): Appointment {
        val zone = ZoneId.systemDefault()
        val existingTriggers = ok(g.appointments.all()).mapNotNull { row ->
            row.reminderLeadMinutes?.let { row.startInstant(zone).minusSeconds(it.minutes * 60L).toEpochMilli() }
        }.toSet()
        var start = Instant.now().plusSeconds(16 * 60 + days * 86400).atZone(zone).withNano(0)
        while (start.toInstant().minusSeconds(15 * 60).toEpochMilli() in existingTriggers) start = start.plusSeconds(1)
        val id = UUID.randomUUID()
        val student = ok(g.students.create(StudentDraft("虚构设备提醒", StudentSex.other)))
        try {
            val row = Appointment(id, student.studentID, date = start.toLocalDate(), startTime = start.toLocalTime(),
                reminderLeadMinutes = ReminderLeadMinutes.fifteen, createdAtUTC = Instant.now(), updatedAtUTC = Instant.now())
            ok(g.appointments.createSingle(row, overrideConflict = true))
            assertEquals(row.id, ok(g.appointments.find(row.id))?.id)
            assertNull(g.reminders.lastFailure.value)
            return row
        } catch (failure: Throwable) {
            try { cleanupStudent(g, student.studentID, id) } catch (cleanupFailure: Throwable) { failure.addSuppressed(cleanupFailure) }
            throw failure
        }
    }
    private fun registry(g: S1AppGraph) = JSONObject(g.database.storeMetadataDao().find("appointment-reminders-v1")?.value ?: "{}")
    private fun tag(id: UUID) = "appointment-reminder:$id"
    private fun fireMillis(row: Appointment) = row.startInstant(ZoneId.systemDefault()).minusSeconds(checkNotNull(row.reminderLeadMinutes).minutes * 60L).toEpochMilli()
    private fun assertOsAlarm(fire: Long, fallback: Boolean = false) {
        val latestRecords = java.util.concurrent.atomic.AtomicReference<List<String>>(emptyList())
        try {
            RestNotificationDeviceSupport.awaitSystemState("appointment alarm registered with OS") {
                val dump = instrumentation.uiAutomation.executeShellCommand("dumpsys alarm").use { descriptor ->
                    java.io.FileInputStream(descriptor.fileDescriptor).bufferedReader().use { it.readText() }
                }
                val records = AppointmentAlarmEvidence.packageRecords(dump, context.packageName)
                latestRecords.set(records)
                val matches = AppointmentAlarmEvidence.matching(records, AppointmentReminders.ACTION, fire)
                true.takeIf { matches.size == 1 && (!fallback || AppointmentAlarmEvidence.isWindowFallback(matches.single())) }
            }
        } catch (failure: AssertionError) {
            // Alarm metadata only; do not attach a full system dump or notification contents.
            throw AssertionError("Appointment alarm evidence failed: package=${context.packageName} action=${AppointmentReminders.ACTION} origWhen=$fire fallback=$fallback\nPackage alarm records:\n${latestRecords.get().joinToString("\n").ifEmpty { "<none>" }}", failure)
        }
    }
    private suspend fun trigger(g: S1AppGraph, row: Appointment) {
        val fire = row.startInstant(ZoneId.systemDefault()).minusSeconds(15 * 60)
        // Like RestNotificationDeviceSupport.deliverDue: trigger the real adapter at its due instant;
        // this proves delivery/content, not AlarmManager timing under Doze.
        AppointmentReminders(context, g.database, g.appointmentRepository, AppClock { fire }).receive(
            Intent().setAction(AppointmentReminders.ACTION).putExtra(AppointmentReminders.ID, row.id.toString()))
    }
    private suspend fun cleanupStudent(g: S1AppGraph, student: StudentID, appointment: UUID) = withContext(NonCancellable) {
        try { ok(g.students.delete(student, "虚构设备提醒")) }
        finally { manager.cancel(tag(appointment), 0) }
    }
    private suspend fun cleanup(g: S1AppGraph, row: Appointment) = cleanupStudent(g, row.studentID, row.id)
    @Test fun grantedSaveRegistersAlarmAndDeliversPublicTimeOnlyNotification() = runBlocking {
        val g = graph(); requirePermission(g, "granted")
        val row = save(g)
        try {
            assertTrue(registry(g).has(row.id.toString())); assertOsAlarm(fireMillis(row))
            trigger(g, row)
            val posted = RestNotificationDeviceSupport.awaitSystemState("appointment notification delivered") {
                manager.activeNotifications.singleOrNull { it.tag == tag(row.id) && it.id == 0 }
            }.notification
            assertEquals(AppointmentNotificationContentBuilder.title(), posted.extras.getString(Notification.EXTRA_TITLE))
            assertEquals(AppointmentNotificationContentBuilder.body(row.startInstant(ZoneId.systemDefault()), ZoneId.systemDefault()),
                posted.extras.getString(Notification.EXTRA_TEXT))
            assertEquals(Notification.VISIBILITY_PUBLIC, posted.visibility)
            assertFalse(posted.extras.getString(Notification.EXTRA_TEXT).orEmpty().contains("虚构设备提醒"))
        } finally { cleanup(g, row) }
    }
    @Test fun deniedSavePersistsWithoutDeliveringNotification() = runBlocking {
        val g = graph(); requirePermission(g, "denied")
        val row = save(g)
        try {
            assertFalse(registry(g).has(row.id.toString()))
            trigger(g, row)
            assertNotNull(ok(g.appointments.find(row.id)))
            assertTrue(manager.activeNotifications.none { it.tag == tag(row.id) })
        } finally { cleanup(g, row) }
    }
    @Test fun revokedExactAlarmAccessUsesWindowFallback() = runBlocking {
        val g = graph(); requirePermission(g, "granted")
        assertEquals("revoked", args.getString("appointmentExactAlarmState"))
        assertFalse(alarms.canScheduleExactAlarms())
        val row = save(g)
        try {
            assertTrue(registry(g).getString(row.id.toString()).endsWith("|false"))
            assertOsAlarm(fireMillis(row), fallback = true); assertNull(g.reminders.lastFailure.value)
        } finally { cleanup(g, row) }
    }
    @Test fun prepareBeforeReboot() = runBlocking {
        val g = graph(); requirePermission(g, "granted")
        assertFalse("Finish the previous reboot pair first", prefs.contains("appointment"))
        val row = save(g, days = 1)
        var handedOff = false
        try {
            assertTrue(registry(g).has(row.id.toString())); assertOsAlarm(fireMillis(row))
            assertTrue(prefs.edit().putString("appointment", row.id.toString()).putLong("fire", fireMillis(row))
                .putInt("boot", Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT)).commit())
            handedOff = true
        } finally {
            if (!handedOff) try { cleanup(g, row) } finally { assertTrue(prefs.edit().clear().commit()) }
        }
    }
    @Test fun assertRestoredAfterReboot() = runBlocking {
        val id = UUID.fromString(checkNotNull(prefs.getString("appointment", null)))
        try {
            assertTrue(Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT) > prefs.getInt("boot", -1))
            assertTrue("Missing requested trigger from reboot preparation", prefs.contains("fire"))
            // Open Room directly: launching/reconciling here would mask a broken boot receiver.
            val db = com.ignacioli.finecoach.storage.FineCoachDatabaseFactory.create(context)
            try {
                RestNotificationDeviceSupport.awaitSystemState("boot receiver restored registry") {
                    true.takeIf { JSONObject(db.storeMetadataDao().find("appointment-reminders-v1")?.value ?: "{}").has(id.toString()) }
                }
                assertOsAlarm(prefs.getLong("fire", -1))
                val row = checkNotNull(db.appointmentDao().find(id.toString()))
                val expected = LocalDate.parse(row.date).atTime(LocalTime.parse(row.startTime)).atZone(ZoneId.systemDefault())
                    .toInstant().minusSeconds(checkNotNull(row.reminderLeadMinutes) * 60L).toEpochMilli()
                assertEquals(expected, prefs.getLong("fire", -1))
            } finally { db.close() }
            requirePermission(graph(), "granted")
        } finally {
            withContext(NonCancellable) {
                try {
                    val g = graph()
                    ok(g.appointments.find(id))?.let { cleanup(g, it) }
                } finally { assertTrue(prefs.edit().clear().commit()) }
            }
        }
    }
}
