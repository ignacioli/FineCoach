package com.ignacioli.finecoach

import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.fonts.Font
import android.graphics.fonts.FontFamily as AndroidFontFamily
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.sp
import com.ignacioli.finecoach.designsystem.FcFontFamily
import com.ignacioli.finecoach.designsystem.FcTypography
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
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
class TypographyTests {
    @get:Rule val compose = createComposeRule()

    private data class Expected(val size: Float, val weight: Int, val multiplier: Float)

    // Independently copied from Typography.swift FCTextStyle.spec and
    // TypographyHarnessTests.expectedStyles (DS README §3.2/§3.3).
    private val expected = mapOf(
        "display" to Expected(34f, 700, 1.2f),
        "titleLarge" to Expected(28f, 700, 1.3f),
        "title" to Expected(22f, 600, 1.3f),
        "headline" to Expected(17f, 600, 1.4f),
        "body" to Expected(17f, 400, 1.4f),
        "callout" to Expected(15f, 500, 1.4f),
        "caption" to Expected(13f, 400, 1.3f),
        "numeralHero" to Expected(44f, 700, 1.1f),
        "numeralLarge" to Expected(24f, 600, 1.2f),
        "titleEmphasis" to Expected(22f, 700, 1.3f),
        "exerciseTitle" to Expected(20f, 700, 1.3f),
        "sectionLabel" to Expected(13f, 600, 1.3f),
        "compact" to Expected(14f, 400, 1.2f),
        "chipLabel" to Expected(14f, 500, 1.3f),
    )

    @Test fun allFourteenStylesPreserveSizeWeightNominalLineHeightAndZeroTracking() {
        assertEquals(14, expected.size)
        assertEquals(expected.keys, FcTypography.styles.keys)
        assertEquals(expected.keys, FcTypography.lineHeightMultipliers.keys)
        expected.forEach { (name, spec) ->
            val actual = FcTypography.styles.getValue(name)
            assertEquals("$name size unit", spec.size.sp, actual.fontSize)
            assertEquals("$name weight", spec.weight, actual.fontWeight?.weight)
            assertEquals("$name lineHeight unit", (spec.size * spec.multiplier).sp.type, actual.lineHeight.type)
            assertEquals("$name lineHeight", spec.size * spec.multiplier, actual.lineHeight.value, 0.00001f)
            assertEquals("$name multiplier", spec.multiplier, FcTypography.lineHeightMultipliers.getValue(name), 0f)
            assertEquals("$name letterSpacing", 0.sp, actual.letterSpacing)
        }
    }

    @Test fun onlyDocumentedWeightVariantsAreAvailableAndPreserveOtherMetrics() {
        val weights = expected.mapValues { (name, spec) -> when (name) {
            "title" -> setOf(600, 700)
            "caption" -> setOf(400, 600)
            "callout" -> setOf(400, 500, 600)
            "compact" -> setOf(400, 600)
            else -> setOf(spec.weight)
        } }
        assertEquals(weights, FcTypography.allowedWeights)
        weights.forEach { (name, allowed) -> allowed.forEach { weight ->
            val actual = FcTypography.style(name, weight)
            assertEquals("$name $weight", weight, actual.fontWeight?.weight)
            assertEquals(FcTypography.styles.getValue(name).fontSize, actual.fontSize)
            assertEquals(FcTypography.styles.getValue(name).lineHeight, actual.lineHeight)
            assertEquals(0.sp, actual.letterSpacing)
        } }
        // §3.2 arrows refer to existing named styles rather than adding cases.
        assertEquals(FcTypography.styles.getValue("titleEmphasis"), FcTypography.style("title", 700))
        assertEquals(FcTypography.styles.getValue("sectionLabel"), FcTypography.style("caption", 600))
    }

    @Test fun unsupportedWeightsAndUnknownStylesFailInsteadOfSynthesizing() {
        expected.keys.forEach { name ->
            listOf(100, 300, 800, 900).forEach { weight ->
                assertThrows(IllegalArgumentException::class.java) { FcTypography.style(name, weight) }
            }
        }
        assertThrows(IllegalArgumentException::class.java) { FcTypography.style("unknown", 400) }
    }

    @Test fun everyStyleUsesTheBundledFontFamily() {
        FcTypography.styles.forEach { (name, style) ->
            assertNotNull(name, style.fontFamily)
            assertSame(name, FcFontFamily, style.fontFamily)
        }
    }

    @Test fun bundledFontLoadsAllFourWeightAxesAndContainsRequiredGlyphs() {
        val resources = RuntimeEnvironment.getApplication().resources
        listOf(400, 500, 600, 700).forEach { weight ->
            val font = Font.Builder(resources, R.font.noto_sans_sc_variable)
                .setFontVariationSettings("'wght' $weight").build()
            val axis = font.axes.orEmpty().single { it.tag == "wght" }
            assertEquals(weight.toFloat(), axis.styleValue, 0f)
            val family = AndroidFontFamily.Builder(font).build()
            val typeface = Typeface.CustomFallbackBuilder(family).build()
            val paint = Paint().apply { this.typeface = typeface; textSize = 17f }
            listOf("‹", "›", "✓", "教", "练").forEach { glyph ->
                assertTrue("wght=$weight missing $glyph", paint.hasGlyph(glyph))
            }
        }
        // This proves resource loading and Android font-axis support, not that
        // Compose's resolver has been independently inspected at runtime.
    }

    @Test fun spTextRespondsToFontScaleWithoutGlobalClamp() {
        val results = mutableMapOf<Float, TextLayoutResult>()
        compose.setContent {
            Column {
                listOf(1f, 1.5f, 2f).forEach { scale ->
                    CompositionLocalProvider(LocalDensity provides Density(1f, scale)) {
                        BasicText("教练‹›✓", style = FcTypography.styles.getValue("body"),
                            onTextLayout = { results[scale] = it })
                    }
                }
            }
        }
        compose.runOnIdle {
            assertEquals(setOf(1f, 1.5f, 2f), results.keys)
            val base = results.getValue(1f)
            listOf(1.5f, 2f).forEach { scale ->
                val scaled = results.getValue(scale)
                assertEquals(scale, scaled.layoutInput.density.fontScale, 0f)
                assertTrue("fontScale=$scale must enlarge text", scaled.size.height > base.size.height)
                assertTrue("fontScale=$scale must enlarge glyph advances", scaled.size.width > base.size.width)
            }
        }
    }

    @Test fun singleAndMultilineMetricsAreMeasuredAndReportedWithoutClaimingIosLineboxParity() {
        val results = mutableMapOf<String, TextLayoutResult>()
        compose.setContent {
            Column {
                listOf(1f, 1.5f, 2f).forEach { scale ->
                    CompositionLocalProvider(LocalDensity provides Density(1f, scale)) {
                        listOf("single" to "教练‹›✓", "multi" to "教练‹›✓\n训练记录").forEach { (kind, text) ->
                            val key = "$kind-$scale"
                            BasicText(text, style = FcTypography.styles.getValue("body"),
                                onTextLayout = { results[key] = it })
                        }
                    }
                }
            }
        }
        compose.runOnIdle {
            assertEquals(6, results.size)
            results.forEach { (name, result) ->
                assertEquals(name, if (name.startsWith("single")) 1 else 2, result.lineCount)
                assertTrue(name, result.size.height > 0)
                assertTrue(name, result.firstBaseline > 0f)
                if (result.lineCount == 2) assertTrue(name, result.lastBaseline > result.firstBaseline)
                println("T013 linebox $name height=${result.size.height} first=${result.firstBaseline} " +
                    "last=${result.lastBaseline} nominal=${result.layoutInput.style.lineHeight}")
            }
            // Exact iOS natural-line-height floor, first/last padding and nonlinear
            // platform font scaling remain owner/runtime verification items (§15.5).
        }
    }
}
