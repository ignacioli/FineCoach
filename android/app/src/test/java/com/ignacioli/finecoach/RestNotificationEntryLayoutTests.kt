// fictional-data: no personal data; permission controls and fixed-clock Session IDs only.
package com.ignacioli.finecoach

import android.Manifest
import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.width
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.notifications.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], qualifiers = "zh-rCN-w320dp-h640dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class RestNotificationEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @Test fun visibleRequestAndCancelDoNotPretendPermissionGranted() {
        val app = ApplicationProvider.getApplicationContext<Application>()
        shadowOf(app).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        var requests = 0
        compose.setContent { FineCoachTheme { CompositionLocalProvider(LocalRestPermissionRequest provides { requests++ }) { RestPermissionEntry() } } }
        val request = compose.onNodeWithTag("rest-permission-request")
        request.assertIsDisplayed().assertHasClickAction()
        assertEquals(compose.onNodeWithTag("rest-permission-content").getUnclippedBoundsInRoot().width, request.getUnclippedBoundsInRoot().width)
        request.performClick(); assertEquals(1, requests); assertTrue(RestNotifications(app).needsRuntimePermission())
        compose.onNodeWithTag("rest-permission-cancel").assertIsDisplayed().performClick()
        compose.onNodeWithTag("rest-permission-content").assertDoesNotExist()
    }
}
