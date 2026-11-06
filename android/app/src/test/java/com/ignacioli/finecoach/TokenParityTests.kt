package com.ignacioli.finecoach

import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import com.ignacioli.finecoach.designsystem.FcColors
import com.ignacioli.finecoach.designsystem.FcShapes
import com.ignacioli.finecoach.designsystem.FcSpacing
import org.junit.Assert.assertEquals
import org.junit.Test

// Independent literals transcribed from iOS Tokens.swift and VisionHarnessTests;
// DS README §2/§4/§5 is authoritative. Never parse generator input for expectations.
class TokenParityTests {
    @Test fun primitiveColorsMatchIosVisionHarness() {
        val expected = mapOf(
            "color.brand.primary" to 0xFF2A2822, "color.brand.pressed" to 0xFF1F1E1B,
            "color.brand.subtle" to 0xFFEDE9E2, "color.brand.on" to 0xFFFFFFFF,
            "color.neutral.0" to 0xFFFFFFFF, "color.neutral.50" to 0xFFF7F4EE,
            "color.neutral.100" to 0xFFF0EEE9, "color.neutral.200" to 0xFFECE9E2,
            "color.neutral.400" to 0xFFA8A39A, "color.neutral.500" to 0xFF8E897F,
            "color.neutral.600" to 0xFF5C5A52, "color.neutral.900" to 0xFF211F1B,
            "color.green.600" to 0xFF2A2822, "color.amber.700" to 0xFFB45309,
            "color.red.700" to 0xFFD4442A,
        )
        assertEquals(expected.keys, FcColors.primitives.keys)
        expected.forEach { (name, argb) -> assertEquals(name, argb.toInt(), FcColors.primitives.getValue(name).toArgb()) }
    }

    @Test fun semanticColorsMatchIosVisionHarnessInBothSystemModes() {
        val expected = mapOf(
            "color.action.primary" to 0xFF2A2822, "color.action.pressed" to 0xFF1F1E1B,
            "color.action.on" to 0xFFFFFFFF, "color.surface.page" to 0xFFFFFFFF,
            "color.surface.elevated" to 0xFFFFFFFF, "color.surface.canvas" to 0xFFF7F4EE,
            "color.surface.subtle" to 0xFFF0EEE9, "color.surface.divider" to 0xFFECE9E2,
            "color.surface.selected" to 0xFFEDE9E2, "color.border.control" to 0xFF8E897F,
            "color.text.primary" to 0xFF211F1B, "color.text.secondary" to 0xFF5C5A52,
            "color.text.disabled" to 0xFFA8A39A, "color.text.onActionSecondary" to 0xFFB0ABA2,
            "color.surface.dividerOnAction" to 0xFF4C4A45,
            "color.status.success" to 0xFF2A2822, "color.status.warning" to 0xFFB45309,
            "color.status.destructive" to 0xFFD4442A, "color.overlay.scrim" to 0x66211F1B,
        )
        // No independent dark palette has been approved; both modes preserve §2.
        listOf(FcColors.semantic, FcColors.light, FcColors.dark).forEach { palette ->
            assertEquals(expected.keys, palette.keys)
            expected.forEach { (name, argb) -> assertEquals(name, argb.toInt(), palette.getValue(name).toArgb()) }
        }
    }

    @Test fun overlayPreservesRgbAndFortyPercentOpacity() {
        // iOS VisionHarnessTests.testOverlayScrimValue, DS §2.2.
        val overlay = FcColors.semantic.getValue("color.overlay.scrim")
        assertEquals(0.4f, overlay.alpha, 1f / 255f)
        assertEquals(0xFF211F1B.toInt(), overlay.copy(alpha = 1f).toArgb())
    }

    @Test fun sixSpacingValuesRemainUnscaledDp() {
        val expected = mapOf("space.1" to 4f, "space.2" to 8f, "space.3" to 12f,
            "space.4" to 16f, "space.6" to 24f, "space.8" to 32f)
        assertEquals(expected.keys, FcSpacing.values.keys)
        expected.forEach { (name, value) ->
            val actual = FcSpacing.values.getValue(name)
            assertEquals(name, value, actual.value, 0f)
            listOf(1f, 1.5f, 2f).forEach { scale ->
                assertEquals(name, value * 2f, with(Density(2f, scale)) { actual.toPx() }, 0f)
            }
        }
    }

    @Test fun fiveFixedRadiiMatchIosVisionHarness() {
        val expected = mapOf("radius.sm" to 8f, "radius.md" to 12f, "radius.lg" to 16f,
            "radius.xl" to 20f, "radius.dialogAction" to 10f)
        assertEquals(expected.keys, FcShapes.radii.keys)
        expected.forEach { (name, value) -> assertEquals(name, value, FcShapes.radii.getValue(name).value, 0f) }
    }

    @Test fun capsuleTracksHalfTheShorterDimensionInsteadOfAFixedRadius() {
        // Android-specific proof of DS §15.4; iOS harness only checks fixed radii.
        listOf(Size(120f, 32f), Size(120f, 64f), Size(32f, 120f)).forEach { size ->
            val corner = minOf(size.width, size.height) / 2f
            listOf(FcShapes.capsule.topStart, FcShapes.capsule.topEnd,
                FcShapes.capsule.bottomStart, FcShapes.capsule.bottomEnd).forEach {
                assertEquals(corner, it.toPx(size, Density(1f)), 0f)
            }
            // Also exercise the shape's runtime outline path, independent of layout direction.
            FcShapes.capsule.createOutline(size, LayoutDirection.Ltr, Density(1f))
        }
    }
}
