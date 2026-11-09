// fictional-data: stable invented Session identifiers; fixed clock only.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.application.AppClock
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.features.session.*
import java.time.Instant
import org.junit.Test
import org.junit.Assert.*

class RestTimerTests {
    private val a = SessionID.parse("abcdef00-0000-4000-8000-000000000001")
    private val b = SessionID.parse("abcdef00-0000-4000-8000-000000000002")
    @Test fun independentSessionsAdjustmentClampSkipAndCloseUseFixedClock() {
        var now = Instant.parse("2026-11-08T00:00:00Z")
        val store = RestTimerStore(AppClock { now })
        store.start(a); store.start(b); assertEquals(120L, store.remaining(a))
        store.adjust(a, 15); assertEquals(135L, store.remaining(a)); assertEquals(120L, store.remaining(b))
        now = now.plusSeconds(134); store.adjust(a, -15); assertEquals(now, store.end(a)); assertEquals(0L, store.remaining(a))
        assertNotNull(store.end(b)); store.clear(a); assertNull(store.end(a)); assertNotNull(store.end(b))
        store.clear(b); assertNull(store.end(b))
    }
    @Test fun fractionalRemainingRoundsUpAndReplacementDoesNotAccumulate() {
        var now = Instant.parse("2026-11-08T00:00:00Z")
        val store = RestTimerStore(AppClock { now }); store.start(a)
        now = now.plusNanos(500_000_000); assertEquals(120L, store.remaining(a))
        store.start(a); assertEquals(now.plusSeconds(120), store.end(a))
        assertNull(RestTimerStore(AppClock { now }).end(a))
    }
}
