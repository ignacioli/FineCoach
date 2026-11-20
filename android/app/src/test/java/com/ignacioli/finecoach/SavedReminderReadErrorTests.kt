// fictional-data: injected notification-settings read failure, no identity or training data.
package com.ignacioli.finecoach

import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.activity.ComponentActivity
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.settings.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class SavedReminderReadErrorTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @Test fun failedReadShowsSettingsFailureAndVisibleRetryRecoversWithoutCrash() {
        var fail = true
        val state = ReminderSettingsState {
            if (fail) throw IllegalStateException("fictional read failure")
            ReminderSettingsState.Status.denied
        }
        runBlocking { state.refresh() }
        compose.setContent { FineCoachTheme {
            val scope = rememberCoroutineScope()
            SavedReminderReadError(state) { scope.launch { state.refresh() } }
        } }
        compose.onNodeWithText("读取通知设置失败，请重试。", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithTag("saved-reminder-error-accept", useUnmergedTree = true).assertIsDisplayed().assertHasClickAction()
        compose.runOnIdle { fail = false }
        compose.onNodeWithTag("saved-reminder-error-accept", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("saved-reminder-error-card", useUnmergedTree = true).assertDoesNotExist()
        assertNull(state.error); assertEquals(ReminderSettingsState.Status.denied, state.status)
    }
}
