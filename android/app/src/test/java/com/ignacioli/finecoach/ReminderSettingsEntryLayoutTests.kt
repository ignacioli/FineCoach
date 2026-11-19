// fictional-data: isolated Room and synthetic appointments; no real notification payloads.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.unit.width
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.settings.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import android.provider.Settings

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[36],qualifiers="zh-rCN-w390dp-h844dp-notnight-xhdpi")
class ReminderSettingsEntryLayoutTests {
    @get:Rule val compose=createAndroidComposeRule<ComponentActivity>()
    private lateinit var f: S2ScreenFixture
    private fun node(tag:String)=compose.onNodeWithTag(tag)
    private fun await(test:()->Boolean)=compose.waitUntil(15_000) { compose.waitForIdle(); test() }
    @Before fun setup() { f=S2ScreenFixture(todayHero=false) }
    @After fun close() { compose.runOnUiThread { compose.activity.setContent {} }; compose.waitForIdle(); f.close() }
    @Test fun deniedRowUsesStatusAndVisibleSystemSettingsActionWithoutRoomMutation() {
        val state=ReminderSettingsState { ReminderSettingsState.Status.denied }
        var back=0
        compose.setContent { FineCoachTheme { ReminderSettingsScreen(state,{back++}) { openNotificationSettings(compose.activity) } } }
        await { state.status!=null }
        node("settings-notifications").assertIsDisplayed().assertTextContains("前往设置")
        assertEquals(node("settings-content").getUnclippedBoundsInRoot().width,node("settings-notifications").getUnclippedBoundsInRoot().width)
        node("settings-notifications").performClick()
        val intent=shadowOf(compose.activity).nextStartedActivity
        assertEquals(Settings.ACTION_APP_NOTIFICATION_SETTINGS,intent.action)
        assertEquals(compose.activity.packageName,intent.getStringExtra(Settings.EXTRA_APP_PACKAGE))
        node("settings-back").assertIsDisplayed().performClick(); assertEquals(1,back)
        f.room.test { assertEquals(9L,f.room.count("appointments")); assertEquals(0L,f.room.count("credit_adjustments")) }
    }
    @Test fun enabledRowStillOpensSystemSettingsAndNeverRequestsRuntimePermission() {
        val state=ReminderSettingsState { ReminderSettingsState.Status.enabled }; var opens=0
        compose.setContent { FineCoachTheme { ReminderSettingsScreen(state,{}) { opens++; true } } }; await { state.status!=null }
        node("settings-notifications").assertIsDisplayed().assertTextContains("提醒已开启").performClick(); assertEquals(1,opens)
        f.room.test { assertNull(f.room.db.storeMetadataDao().find("appointment-permission-requested")) }
    }
    @Test fun failureRetryAndOpenFailureAreVisibleAndDoNotChangeRoom() {
        var reads=0; val state=ReminderSettingsState { reads++; if(reads==1) error("synthetic failure") else ReminderSettingsState.Status.notRequested }
        compose.setContent { FineCoachTheme { ReminderSettingsScreen(state,{}) { false } } }; await { state.error!=null }
        node("settings-retry").assertIsDisplayed().performClick(); await { state.status!=null }
        node("settings-notifications").assertTextContains("尚未请求").performClick(); await { state.error!=null }
        node("settings-error").assertIsDisplayed().assertTextEquals("无法打开系统设置，请稍后重试。")
        f.room.test { assertEquals(9L,f.room.count("appointments")); assertEquals(0L,f.room.count("credit_adjustments")) }
    }
}
