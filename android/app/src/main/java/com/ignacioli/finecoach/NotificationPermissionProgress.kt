package com.ignacioli.finecoach

import android.os.Bundle
import androidx.compose.runtime.*
import java.util.UUID

/** Keep rotation and late ActivityResult delivery in one revision domain. A dead process cannot keep a request alive. */
internal class NotificationPermissionProgress(private val process: String = PROCESS) {
    companion object { private val PROCESS = UUID.randomUUID().toString() }
    var revision by mutableIntStateOf(0); private set
    var inFlight by mutableStateOf(false); private set
    fun begin() { inFlight = true }
    fun complete() { revision++; inFlight = false }
    fun save(out: Bundle) {
        out.putInt("notificationRevision", revision)
        out.putBoolean("notificationInFlight", inFlight)
        out.putString("notificationProcess", process)
    }
    fun restore(saved: Bundle?) {
        revision = saved?.getInt("notificationRevision") ?: 0
        inFlight = saved?.getString("notificationProcess") == process && saved.getBoolean("notificationInFlight")
    }
}
