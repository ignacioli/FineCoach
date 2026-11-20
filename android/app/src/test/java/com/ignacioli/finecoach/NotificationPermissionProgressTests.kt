// fictional-data: synthetic process identities and permission results only.
package com.ignacioli.finecoach

import android.os.Bundle
import com.ignacioli.finecoach.features.settings.ReminderSettingsState
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class NotificationPermissionProgressTests {
    @Test fun rotationKeepsRequestAndLateResultInSameRevisionDomain() {
        val original = NotificationPermissionProgress("fictional-process")
        original.complete(); original.begin()
        val saved = Bundle().also(original::save)
        val recreated = NotificationPermissionProgress("fictional-process").also { it.restore(saved) }
        assertTrue(recreated.inFlight); assertEquals(original.revision, recreated.revision)
        recreated.complete()
        assertFalse(recreated.inFlight); assertEquals(original.revision + 1, recreated.revision)
    }
    @Test fun processDeathDropsLostRequestButPreservesRevisionForCurrentStateRead() {
        val original = NotificationPermissionProgress("fictional-old-process")
        original.complete(); original.begin()
        val recreated = NotificationPermissionProgress("fictional-new-process").also { it.restore(Bundle().also(original::save)) }
        assertFalse(recreated.inFlight); assertEquals(1, recreated.revision)
    }
    @Test fun failedPostSaveReadUsesSettingsFailureAndRetry() = runBlocking {
        var fail = true
        val state = ReminderSettingsState { if (fail) throw IllegalStateException("fictional read failure") else ReminderSettingsState.Status.denied }
        state.refresh()
        assertEquals("读取通知设置失败，请重试。", state.error); assertNull(state.status)
        fail = false; state.refresh()
        assertNull(state.error); assertEquals(ReminderSettingsState.Status.denied, state.status)
    }
}
