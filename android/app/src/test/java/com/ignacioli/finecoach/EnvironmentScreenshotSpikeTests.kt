package com.ignacioli.finecoach

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertHeightIsEqualTo
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w320dp-h480dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class EnvironmentScreenshotSpikeTests {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun fixedGeometryMatchesOwnerBaseline() {
        val record = System.getProperty("roborazzi.test.record", "false").toBoolean()
        val verify = System.getProperty("roborazzi.test.verify", "false").toBoolean()
        check(record.xor(verify)) { "Environment screenshot requires exactly one of verify or owner-only record" }
        val baseline = File(checkNotNull(System.getProperty("finecoach.environmentBaseline")))
        if (verify) {
            check(baseline.isFile) { "Missing owner-approved environment baseline: $baseline; never auto-record" }
        }
        compose.mainClock.autoAdvance = false
        compose.setContent {
            // Literal fixture colors and dimensions, not DS tokens; environment smoke only.
            // No text, icons, fonts, transitions or product components participate.
            Box(
                Modifier.requiredSize(width = 96.dp, height = 64.dp)
                    .background(Color(0xFFF0F0F0))
                    .border(2.dp, Color(0xFF202020))
                    .testTag("environment-geometry"),
            ) {
                Box(Modifier.offset(8.dp, 8.dp).requiredSize(32.dp, 48.dp).background(Color(0xFF336699)))
                Box(Modifier.offset(48.dp, 16.dp).requiredSize(40.dp, 32.dp)
                    .background(Color(0xFFCC6633)).border(2.dp, Color(0xFF202020)))
            }
        }
        compose.mainClock.advanceTimeByFrame()
        compose.onNodeWithTag("environment-geometry")
            .assertWidthIsEqualTo(96.dp)
            .assertHeightIsEqualTo(64.dp)
            .captureRoboImage(file = baseline)
    }
}
