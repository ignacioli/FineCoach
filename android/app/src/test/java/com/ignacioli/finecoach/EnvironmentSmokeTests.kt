package com.ignacioli.finecoach

import android.os.Build
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertHeightIsEqualTo
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w320dp-h480dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class EnvironmentSmokeTests {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun api36JdkAndLocaleAreAvailable() {
        val resources = RuntimeEnvironment.getApplication().resources
        assertEquals(36, Build.VERSION.SDK_INT)
        assertEquals("21", System.getProperty("java.specification.version"))
        assertEquals(160, resources.displayMetrics.densityDpi)
        assertEquals(1f, resources.configuration.fontScale, 0f)
        assertEquals("zh-CN", resources.configuration.locales[0].toLanguageTag())
        assertEquals("zh-CN", Locale.getDefault().toLanguageTag())
        assertEquals("1,234.5", NumberFormat.getNumberInstance(Locale.CHINA).format(BigDecimal("1234.5")))
        assertEquals("环境 smoke", String("环境 smoke".toByteArray(Charsets.UTF_8), Charsets.UTF_8))
        println("EnvironmentSmoke API=${Build.VERSION.SDK_INT} JDK=${System.getProperty("java.specification.version")} locale=${Locale.getDefault().toLanguageTag()} density=160 fontScale=1")
    }

    @Test
    fun composeComposesAndMeasuresFixedNode() {
        compose.mainClock.autoAdvance = false
        compose.setContent {
            Box(Modifier.requiredSize(width = 96.dp, height = 64.dp).testTag("environment-measurement"))
        }
        compose.mainClock.advanceTimeByFrame()
        compose.onNodeWithTag("environment-measurement")
            .assertWidthIsEqualTo(96.dp)
            .assertHeightIsEqualTo(64.dp)
    }
}
