package com.ignacioli.finecoach.notifications

import android.app.AlarmManager
import android.content.*
import com.ignacioli.finecoach.S1Runtime
import com.ignacioli.finecoach.core.application.ApplicationResult
import kotlinx.coroutines.*

class ReminderRescheduleReceiver : BroadcastReceiver() {
    companion object {
        val ACTIONS = setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED,
            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)
    }
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in ACTIONS && AppointmentReminders.parse(intent) == null) return
        val pending = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                when (val result = S1Runtime.open(context.applicationContext)) {
                    is ApplicationResult.Success -> if (intent.action == AppointmentReminders.ACTION) result.value.reminders.receive(intent)
                        else result.value.reminders.reconcile(force = true)
                    is ApplicationResult.Failure -> Unit // No state was available; launch reconciliation retries from Room.
                }
            } finally { pending.finish() }
        }
    }
}
