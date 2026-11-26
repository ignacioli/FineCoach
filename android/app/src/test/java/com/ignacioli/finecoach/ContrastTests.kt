// fictional-data: design contrast constants only; no business content.
package com.ignacioli.finecoach

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import com.ignacioli.finecoach.designsystem.FcColors
import kotlin.math.pow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// One test per DS README §11 row; literals and thresholds are independently
// transcribed from iOS ContrastHarnessTests. Both exemptions execute assertions.
class ContrastTests {
    private fun color(name: String) = FcColors.semantic.getValue("color.$name")

    private fun luminance(color: Color): Double {
        val argb = color.toArgb()
        fun linear(channel: Int): Double {
            val c = channel / 255.0
            return if (c <= 0.03928) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * linear((argb ushr 16) and 255) +
            0.7152 * linear((argb ushr 8) and 255) + 0.0722 * linear(argb and 255)
    }

    private fun verify(foreground: String, background: String, recorded: Double, threshold: Double? = null) {
        val first = luminance(color(foreground))
        val second = luminance(color(background))
        val ratio = (maxOf(first, second) + 0.05) / (minOf(first, second) + 0.05)
        // Same 0.005 absolute tolerance as iOS; do not relax rounded table values.
        assertEquals("$foreground on $background", recorded, ratio, 0.005)
        if (threshold != null) assertTrue("$foreground on $background: $ratio < $threshold", ratio >= threshold)
    }

    @Test fun chartLineOnPage() = verify("chart.line", "surface.page", 4.93, 3.0)
    @Test fun textPrimaryOnPage() = verify("text.primary", "surface.page", 16.45, 4.5)
    @Test fun textSecondaryOnPage() = verify("text.secondary", "surface.page", 6.91, 4.5)
    @Test fun actionPrimaryOnPage() = verify("action.primary", "surface.page", 14.74, 4.5)
    @Test fun actionOnOnPrimary() = verify("action.on", "action.primary", 14.74, 4.5)
    @Test fun actionOnOnPressed() = verify("action.on", "action.pressed", 16.67, 4.5)
    @Test fun secondaryOnPrimary() = verify("text.onActionSecondary", "action.primary", 6.45, 4.5)
    @Test fun primaryOnCanvas() = verify("action.primary", "surface.canvas", 13.42, 4.5)
    @Test fun secondaryOnCanvas() = verify("text.secondary", "surface.canvas", 6.29, 4.5)
    @Test fun primaryOnSelected() = verify("action.primary", "surface.selected", 12.18, 4.5)
    @Test fun secondaryOnSelected() = verify("text.secondary", "surface.selected", 5.71, 4.5)
    @Test fun actionOnOnWarning() = verify("action.on", "status.warning", 5.02, 4.5)
    @Test fun destructiveOnPage() = verify("status.destructive", "surface.page", 4.51, 4.5)
    @Test fun pendingCircleBoundaryOnPage() = verify("border.control", "surface.page", 3.48, 3.0)
    @Test fun offSwitchBoundaryOnPage() = verify("border.control", "surface.page", 3.48, 3.0)
    @Test fun onSwitchTrackOnPage() = verify("action.primary", "surface.page", 14.74, 3.0)
    @Test fun decorativeDividerRecordsRatioWithoutThreshold() = verify("surface.divider", "surface.page", 1.21)
    @Test fun disabledTextRecordsExemptRatioWithoutThresholdOrSkip() = verify("text.disabled", "surface.page", 2.51)
}
