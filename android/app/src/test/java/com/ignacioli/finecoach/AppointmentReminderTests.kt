// fictional-data: invented appointments and students; fixed DST clock and no real identities.
package com.ignacioli.finecoach

import android.app.*
import android.content.*
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.notifications.*
import java.io.File
import java.time.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [32])
class AppointmentReminderTests {
    @Test fun reconcileSchedulesReplacesDisablesAndDeletes() = s2Run {
        val alarms = shadowOf(context.getSystemService(AlarmManager::class.java))
        val reminders = AppointmentReminders(context, db, repository, clock) { zone }
        val use = AppointmentUseCases(repository, reminders)
        val a = row(student())
        use.createSingle(a).requireSuccess()
        assertEquals(a.startInstant(zone).minusSeconds(3600).toEpochMilli(), alarms.scheduledAlarms.single().triggerAtTime)
        use.editSingle(a.id, AppointmentEdit(startTime = LocalTime.of(11, 0))).requireSuccess()
        assertEquals(1, alarms.scheduledAlarms.size)
        assertEquals(a.copy(startTime = LocalTime.of(11, 0)).startInstant(zone).minusSeconds(3600).toEpochMilli(), alarms.scheduledAlarms.single().triggerAtTime)
        use.editSingle(a.id, AppointmentEdit(reminderEnabled = false)).requireSuccess()
        assertTrue(alarms.scheduledAlarms.isEmpty())
        use.editSingle(a.id, AppointmentEdit(reminderEnabled = true)).requireSuccess()
        use.deleteFuture(a.id, true).requireSuccess()
        assertTrue(alarms.scheduledAlarms.isEmpty())
    }
    @Test fun studentDeletionReconcilesAllRegisteredAlarms() = s2Run {
        val student = student()
        graph.appointments.createSingle(row(student)).requireSuccess()
        assertEquals(1, shadowOf(context.getSystemService(AlarmManager::class.java)).scheduledAlarms.size)
        graph.students.delete(student, "虚构排课").requireSuccess()
        assertTrue(shadowOf(context.getSystemService(AlarmManager::class.java)).scheduledAlarms.isEmpty())
    }
    @Test fun forcedReconcileRestoresLostAlarmsAndUsesNewTimeZone() = s2Run {
        val reminders = AppointmentReminders(context, db, repository, clock) { zone }
        val a = row(student())
        cases.createSingle(a).requireSuccess(); reminders.reconcile()
        val alarms = shadowOf(context.getSystemService(AlarmManager::class.java))
        val pending = alarms.scheduledAlarms.single().operation
        context.getSystemService(AlarmManager::class.java).cancel(requireNotNull(pending))
        reminders.reconcile(force = true)
        assertEquals(1, alarms.scheduledAlarms.size)
        AppointmentReminders(context, db, repository, clock) { ZoneId.of("Asia/Shanghai") }.reconcile(force = true)
        assertEquals(a.startInstant(ZoneId.of("Asia/Shanghai")).minusSeconds(3600).toEpochMilli(), alarms.scheduledAlarms.single().triggerAtTime)
    }
    @Test fun dstAndElapsedReminderNeverCatchUp() = s2Run {
        val a = row(student(), "2026-03-08", "04:00")
        assertEquals(Instant.parse("2026-03-08T10:00:00Z"), a.startInstant(zone).minusSeconds(3600))
        cases.createSingle(a).requireSuccess()
        AppointmentReminders(context, db, repository, clock) { zone }.reconcile(force = true)
        assertTrue(shadowOf(context.getSystemService(AlarmManager::class.java)).scheduledAlarms.isEmpty())
    }
    @Test fun contentAndTiersReadSharedVectors() = s2Run {
        fun vector(name: String): JSONObject {
            val root = File(MergedPrivacyInputs.property("sourceRoot"), "../../../shared/test-vectors/s2")
            return JSONObject(File(root, name).readText()).getJSONObject("then").getJSONObject("state")
        }
        val tiers = vector("m1b-fr-010__s2-reminder-tiers.json")
        assertEquals((0 until tiers.getJSONArray("minutes").length()).map { tiers.getJSONArray("minutes").getInt(it) }, ReminderLeadMinutes.entries.map { it.minutes })
        val a = row(student())
        assertEquals(tiers.getInt("default"), a.reminderLeadMinutes!!.minutes)
        assertTrue(tiers.isNull("disabledLead"))
        val content = vector("m1b-fr-011__s2-notification-content.json")
        assertEquals(content.getString("title"), AppointmentNotificationContentBuilder.title())
        assertEquals(content.getString("body"), AppointmentNotificationContentBuilder.body(Instant.parse("2026-03-08T09:00:00Z"), zone))
    }
    @Test fun clickAndAlarmHaveOnlyOpaqueIdAndSeparateChannel() = s2Run {
        val id = row(student()).id
        val reminders = AppointmentReminders(context, db, repository, clock) { zone }
        val click = reminders.clickIntent(id)
        assertEquals(id, AppointmentReminders.parse(click))
        assertEquals(setOf(AppointmentReminders.ID), click.extras!!.keySet())
        assertTrue(click.flags and Intent.FLAG_ACTIVITY_SINGLE_TOP != 0)
        assertTrue(click.flags and Intent.FLAG_ACTIVITY_CLEAR_TOP != 0)
        assertNotEquals(RestNotifications.CHANNEL, AppointmentReminders.CHANNEL)
        assertEquals(4, ReminderRescheduleReceiver.ACTIONS.size)
        assertNull(AppointmentReminders.parse(Intent().setAction(AppointmentReminders.ACTION).putExtra(AppointmentReminders.ID, "invalid")))
    }
    @Test @Config(sdk = [33]) fun denialPersistsAndOnlyFirstEnabledSaveRequestsPermission() = s2Run {
        shadowOf(context as Application).denyPermissions(android.Manifest.permission.POST_NOTIFICATIONS)
        val reminders = AppointmentReminders(context, db, repository, clock) { zone }
        val use = AppointmentUseCases(repository, reminders)
        val a = row(student())
        use.createSingle(a.copy(reminderEnabled = false)).requireSuccess()
        assertFalse(reminders.permissionRequest.value)
        use.editSingle(a.id, AppointmentEdit(reminderEnabled = true)).requireSuccess()
        assertTrue(reminders.permissionRequest.value)
        reminders.permissionRequest.value = false
        use.editSingle(a.id, AppointmentEdit(startTime = LocalTime.NOON)).requireSuccess()
        assertFalse(reminders.permissionRequest.value)
        assertTrue(shadowOf(context.getSystemService(AlarmManager::class.java)).scheduledAlarms.isEmpty())
        assertNotNull(use.find(a.id).requireSuccess())
    }
    @Test fun exactAccessChangeReplacesWindowWithIdleExactAlarm() = s2Run {
        val alarms = shadowOf(context.getSystemService(AlarmManager::class.java))
        org.robolectric.shadows.ShadowAlarmManager.setCanScheduleExactAlarms(false)
        cases.createSingle(row(student())).requireSuccess()
        val reminders = AppointmentReminders(context, db, repository, clock) { zone }
        reminders.reconcile()
        assertEquals(600_000L, alarms.scheduledAlarms.single().windowLengthMs)
        assertFalse(alarms.scheduledAlarms.single().isAllowWhileIdle)
        org.robolectric.shadows.ShadowAlarmManager.setCanScheduleExactAlarms(true)
        reminders.reconcile(force = true)
        assertEquals(0L, alarms.scheduledAlarms.single().windowLengthMs)
        assertTrue(alarms.scheduledAlarms.single().isAllowWhileIdle)
    }
    @Test fun futureEditsCancellationAbsenceAndStartRemoveAffectedAlarms() = s2Run {
        val student = student()
        val rows = series(student).filter { it.startInstant(zone) > now }
        val reminders = AppointmentReminders(context, db, repository, clock) { zone }
        val use = AppointmentUseCases(repository, reminders)
        reminders.reconcile()
        val alarms = shadowOf(context.getSystemService(AlarmManager::class.java))
        assertEquals(rows.size, alarms.scheduledAlarms.size)
        val edited = use.editFuture(rows.first().seriesID!!, rows.first().date, FutureAppointmentEdit(startTime = LocalTime.of(12, 0))).requireSuccess()
        assertTrue(alarms.scheduledAlarms.all { Instant.ofEpochMilli(it.triggerAtTime).atZone(zone).hour == 11 })
        use.cancel(edited[0].id).requireSuccess()
        use.markAbsent(edited[1].id, AbsentCreditChoice.notCharged, true).requireSuccess()
        use.startTraining(edited[2].id).requireSuccess()
        assertEquals(edited.size - 3, alarms.scheduledAlarms.size)
        edited.drop(3).forEach { use.cancel(it.id).requireSuccess() }
        assertTrue(alarms.scheduledAlarms.isEmpty())
    }
    @Test fun receivePublishesOnlyCurrentGenericContentAndIgnoresCancelledAlarm() = s2Run {
        val a = row(student())
        val reminders = AppointmentReminders(context, db, repository, clock) { zone }
        val use = AppointmentUseCases(repository, reminders)
        use.createSingle(a).requireSuccess()
        val intent = Intent().setAction(AppointmentReminders.ACTION).putExtra(AppointmentReminders.ID, a.id.toString())
        reminders.receive(intent)
        val manager = shadowOf(context.getSystemService(NotificationManager::class.java))
        assertTrue(manager.allNotifications.isEmpty())
        clock.advanceSeconds(Duration.between(now, a.startInstant(zone).minusSeconds(3600)).seconds)
        reminders.receive(intent)
        val notification = manager.allNotifications.single()
        assertEquals(Notification.VISIBILITY_PUBLIC, notification.visibility)
        assertEquals(AppointmentNotificationContentBuilder.title(), notification.extras.getString(Notification.EXTRA_TITLE))
        assertEquals(AppointmentNotificationContentBuilder.body(a.startInstant(zone), zone), notification.extras.getString(Notification.EXTRA_TEXT))
        use.cancel(a.id).requireSuccess()
        context.getSystemService(NotificationManager::class.java).cancelAll()
        reminders.receive(intent)
        assertTrue(manager.allNotifications.isEmpty())
    }
    @Test fun failedSetLeavesRegistryRetryableWithoutForce() = s2Run {
        val row = row(student())
        cases.createSingle(row).requireSuccess()
        val manager = context.getSystemService(AlarmManager::class.java)
        val alarms = shadowOf(manager)
        var attempts = 0
        val reminders = AppointmentReminders(context, db, repository, clock, registerAlarm = { fire, pending ->
            attempts++
            if (attempts == 1) throw IllegalStateException("fictional registration failure")
            manager.setWindow(AlarmManager.RTC_WAKEUP, fire, 600_000, pending)
        }) { zone }
        reminders.reconcile()
        assertNotNull(reminders.lastFailure.value)
        assertTrue(alarms.scheduledAlarms.isEmpty())
        assertFalse(JSONObject(db.storeMetadataDao().find("appointment-reminders-v1")!!.value).has(row.id.toString()))
        reminders.reconcile()
        assertNull(reminders.lastFailure.value)
        assertEquals(2, attempts)
        assertEquals(1, alarms.scheduledAlarms.size)
        assertTrue(JSONObject(db.storeMetadataDao().find("appointment-reminders-v1")!!.value).has(row.id.toString()))
    }
    @Test fun timeChangedBroadcastReallyDrivesReceiverAndRestoresAlarm() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val executor = java.util.concurrent.Executors.newSingleThreadExecutor()
        fun <T> worker(action: suspend () -> T): T = executor.submit(java.util.concurrent.Callable {
            kotlinx.coroutines.runBlocking { action() }
        }).get()
        S1Runtime.resetForTest()
        val env = worker { context.deleteDatabase(com.ignacioli.finecoach.storage.FineCoachDatabaseFactory.DATABASE_NAME); S2Environment(context) }
        val runtime = worker { S1Runtime.open(context).requireSuccess() }
        val receiver = ReminderRescheduleReceiver()
        // MIME isolates this registered receiver from the manifest's parallel delivery.
        val filter = IntentFilter(Intent.ACTION_TIME_CHANGED).apply { addDataType("application/x-finecoach-test") }
        context.registerReceiver(receiver, filter)
        try {
            worker {
                val future = LocalDate.now(ZoneId.systemDefault()).plusDays(2).toString()
                env.cases.createSingle(env.row(env.student(), future)).requireSuccess()
                runtime.reminders.reconcile(force = true)
            }
            val manager = context.getSystemService(AlarmManager::class.java)
            val alarms = shadowOf(manager)
            manager.cancel(requireNotNull(alarms.scheduledAlarms.single().operation))
            assertTrue(alarms.scheduledAlarms.isEmpty())
            context.sendBroadcast(Intent(Intent.ACTION_TIME_CHANGED).setType("application/x-finecoach-test").setPackage(context.packageName))
            shadowOf(android.os.Looper.getMainLooper()).idle()
            assertTrue(shadowOf(receiver).wentAsync())
            val pending = requireNotNull(shadowOf(receiver).originalPendingResult)
            org.robolectric.shadow.api.Shadow.extract<org.robolectric.shadows.ShadowBroadcastPendingResult>(pending)
                .future.get(10, java.util.concurrent.TimeUnit.SECONDS)
            assertNull(runtime.reminders.lastFailure.value)
            assertEquals(1, alarms.scheduledAlarms.size)
        } finally {
            context.unregisterReceiver(receiver)
            worker { runtime.database.close(); env.db.close(); context.deleteDatabase(com.ignacioli.finecoach.storage.FineCoachDatabaseFactory.DATABASE_NAME) }
            S1Runtime.resetForTest()
            executor.shutdownNow()
        }
    }
}
