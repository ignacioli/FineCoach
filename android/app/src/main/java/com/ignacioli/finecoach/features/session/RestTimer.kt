package com.ignacioli.finecoach.features.session

import androidx.compose.runtime.*
import com.ignacioli.finecoach.core.application.AppClock
import com.ignacioli.finecoach.core.domain.common.SessionID
import java.time.Duration
import java.time.Instant

/** No business content is passed to the system adapter. */
interface RestNotificationScheduler {
    fun replace(sessionID: SessionID, endsAt: Instant)
    fun cancel(sessionID: SessionID)
}

class RestTimerStore(private val clock: AppClock, var notifications: RestNotificationScheduler? = null) {
    private val entries = mutableStateMapOf<SessionID, Instant>()
    fun end(id: SessionID): Instant? = entries[id]
    fun rescheduleAll() { entries.keys.toList().forEach(::sync) }
    fun start(id: SessionID) { entries[id] = clock.now().plusSeconds(120); sync(id) }
    fun adjust(id: SessionID, seconds: Long) {
        require(seconds == 15L || seconds == -15L)
        val end = entries[id] ?: return
        entries[id] = maxOf(clock.now(), end.plusSeconds(seconds)); sync(id)
    }
    fun clear(id: SessionID) { entries.remove(id); notifications?.cancel(id) }
    fun remaining(id: SessionID): Long = entries[id]?.let {
        val delta = Duration.between(clock.now(), it)
        if (delta.isNegative || delta.isZero) 0L else delta.seconds + if (delta.nano > 0) 1 else 0
    } ?: 0L
    private fun sync(id: SessionID) {
        val end = entries[id]
        if (end != null && end > clock.now()) notifications?.replace(id, end) else notifications?.cancel(id)
    }
}
