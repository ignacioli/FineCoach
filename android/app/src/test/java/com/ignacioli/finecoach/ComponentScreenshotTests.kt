package com.ignacioli.finecoach

import androidx.compose.foundation.layout.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import com.github.takahirom.roborazzi.captureRoboImage
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import java.io.File
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ComponentScreenshotTests {
    @get:Rule val compose = createComposeRule()
    @Test fun catalogPrimaryButtonMatchesOwnerBaseline() {
        val baseline = File(System.getProperty("finecoach.storageProjectDirectory"), "../screenshot-baselines/components/DS-BUTTON-default.png").canonicalFile
        val record = System.getProperty("roborazzi.test.record", "false").toBoolean()
        val verify = System.getProperty("roborazzi.test.verify", "false").toBoolean()
        check(record.xor(verify)) { "Require exactly one of owner record or verify" }
        if (verify) check(baseline.isFile) { "Missing owner-approved component baseline: $baseline; never auto-record" }
        compose.mainClock.autoAdvance = false
        compose.setContent { FineCoachTheme {
            Box(Modifier.requiredSize(390.dp, 160.dp).testTag("component-capture")) { S0ComponentState("DS-BUTTON", "default") }
        } }
        compose.mainClock.advanceTimeByFrame()
        compose.onNodeWithTag("component-capture").captureRoboImage(file = baseline)
    }
}
