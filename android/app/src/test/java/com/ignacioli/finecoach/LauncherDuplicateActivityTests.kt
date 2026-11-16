package com.ignacioli.finecoach

import android.content.Intent
import com.ignacioli.finecoach.navigation.RestNotificationRoute
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadow.api.Shadow

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31])
class LauncherDuplicateActivityTests {
    @Test fun nonRootMainLauncherIsIntercepted() {
        assertTrue(shouldFinishDuplicateLauncher(false, Intent.ACTION_MAIN, setOf(Intent.CATEGORY_LAUNCHER)))
    }

    @Test fun taskRootMainLauncherIsNotIntercepted() {
        assertFalse(shouldFinishDuplicateLauncher(true, Intent.ACTION_MAIN, setOf(Intent.CATEGORY_LAUNCHER)))
    }

    @Test fun notificationIntentIsNotIntercepted() {
        val intent = Intent(RestNotificationRoute.ACTION).putExtra(RestNotificationRoute.SESSION,
            "abcdef00-0000-4000-8000-000000000001")
        assertFalse(shouldFinishDuplicateLauncher(false, intent.action, intent.categories))
    }

    @Test fun s0ShellIntentIsNotIntercepted() {
        val intent = Intent().putExtra(MainActivity.EXTRA_S0_SHELL, true)
        assertFalse(shouldFinishDuplicateLauncher(false, intent.action, intent.categories))
    }

    @Test fun mainWithoutLauncherCategoryIsNotIntercepted() {
        for (categories in listOf(null, emptySet(), setOf(Intent.CATEGORY_DEFAULT))) {
            assertFalse(shouldFinishDuplicateLauncher(false, Intent.ACTION_MAIN, categories))
        }
    }

    @Test fun launcherCategoryWithoutMainActionIsNotIntercepted() {
        for (action in listOf(null, Intent.ACTION_VIEW, RestNotificationRoute.ACTION)) {
            assertFalse(shouldFinishDuplicateLauncher(false, action, setOf(Intent.CATEGORY_LAUNCHER)))
        }
    }

    @Test @Config(sdk = [31, 32, 33], shadows = [RecentsActivityShadow::class])
    fun interceptedActivityDestroysWithoutCreatingOrTouchingPrivacyCover() {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val controller = Robolectric.buildActivity(MainActivity::class.java, intent)
        val activity = controller.get()
        shadowOf(activity).setIsTaskRoot(false)
        assertFalse(activity.isTaskRoot)
        val privacyCoverField = MainActivity::class.java.getDeclaredField("privacyCover").apply { isAccessible = true }

        controller.create()
        assertTrue(activity.isFinishing)
        assertNull(privacyCoverField.get(activity))
        assertTrue(Shadow.extract<RecentsActivityShadow>(activity).recentsCalls.isEmpty())
        controller.destroy()
        assertTrue(activity.isDestroyed)
        assertNull(privacyCoverField.get(activity))
        assertTrue(Shadow.extract<RecentsActivityShadow>(activity).recentsCalls.isEmpty())
    }
}
