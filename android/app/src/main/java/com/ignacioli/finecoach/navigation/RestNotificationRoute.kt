package com.ignacioli.finecoach.navigation

import android.content.Intent
import com.ignacioli.finecoach.core.domain.common.SessionID

object RestNotificationRoute {
    const val ACTION = "com.ignacioli.finecoach.REST_ENDED"
    const val SESSION = "restSessionID"
    fun parse(intent: Intent?): SessionID? {
        if (intent?.action != ACTION) return null
        return intent.getStringExtra(SESSION)?.let { runCatching { SessionID.parse(it) }.getOrNull() }
    }
    fun deliver(intent: Intent?, onSession: (SessionID) -> Unit): Boolean {
        val id = parse(intent) ?: return false
        onSession(id); return true
    }
}
