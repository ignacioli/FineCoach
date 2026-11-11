package com.ignacioli.finecoach

import java.awt.image.BufferedImage
import java.io.File
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class ConformanceGenericTests {
    private fun layer(path: String, text: String = "应用", y: Int = 0) = JSONObject()
        .put("path", path).put("name", "Text").put("type", "text").put("text", text).put("x", 0).put("y", y).put("w", 10).put("h", 10)
    private fun node(id: Int, text: String = "应用", y: Int = 0) = layer("unused", text, y).put("id", id).put("tag", "").put("hex", "#211f1b")
    @Test fun exactTextAndDuplicateReadingOrderMatchWithoutSelectors() {
        val entries = ConformanceMapping.entries(listOf(layer("a"), layer("b", y = 50)), emptyList(), listOf(node(2, y = 50), node(1)), emptyMap())
        assertEquals(listOf(1, 2), entries.map { it.getInt("nodeID") })
    }
    @Test fun tiesExtraNodesAndContentDifferencesDoNotPickArbitraryMatches() {
        val ties = ConformanceMapping.entries(listOf(layer("a")), emptyList(), listOf(node(1), node(2)), emptyMap()).single()
        assertTrue(ties.has("mappingError")); assertFalse(ties.has("nodeID"))
        val wrong = ConformanceMapping.entries(listOf(layer("a")), emptyList(), listOf(node(1, "应用 ")), emptyMap()).single()
        assertTrue(ConformanceComparison.select(listOf(node(1, "应用 ")), wrong).isEmpty())
        val reversed = ConformanceMapping.entries(listOf(layer("a"), layer("b", y = 50)), emptyList(), listOf(node(1, y = 100), node(2, y = 150)), emptyMap())
        assertTrue(reversed.any { it.has("mappingError") })
    }
    @Test fun containerConventionUsesExactTagAndDynamicBindings() {
        val l = layer("a").put("type", "rectangle").put("name", "testTag:template-apply-\$template1ID")
        val entry = ConformanceMapping.entries(listOf(l), emptyList(), emptyList(), mapOf("template1ID" to "fresh-id")).single()
        assertEquals("template-apply-fresh-id", entry.getString("tag"))
        assertEquals(1, ConformanceComparison.select(listOf(node(1).put("tag", "template-apply-fresh-id")), entry).size)
        assertTrue(ConformanceComparison.select(listOf(node(1).put("tag", "template-apply-stale-id")), entry).isEmpty())
        assertThrows(IllegalStateException::class.java) { ConformanceMapping.expand("\$unknown", emptyMap()) }
    }
    @Test fun alternativeContainerConventionDoesNotUseGeometryAsSelector() {
        val l = layer("a").put("type", "rectangle").put("name", "DS-SECTION · content")
        val entry = ConformanceMapping.entries(listOf(l), emptyList(), emptyList(), emptyMap()).single()
        assertEquals("conformance:DS-SECTION · content", entry.getString("tag"))
        assertTrue(ConformanceComparison.select(listOf(node(1)), entry).isEmpty())
    }
    @Test fun allReadmeColorTokensIncludingAliasesAndScrimAreParsed() {
        val app = File(System.getProperty("finecoach.storageProjectDirectory"))
        val text = File(app, "../../design/design-system/README.md").readText()
        val tokens = ConformanceColors.tokens(text)
        assertEquals(Regex("(?m)^\\| `color\\.[^`]+` \\|").findAll(text).count(), tokens.size)
        assertEquals("#ede9e2", tokens.single { it.name == "color.surface.selected" }.hex)
        assertEquals(0.4, tokens.single { it.name == "color.overlay.scrim" }.alpha, 0.0)
        assertTrue(tokens.count { it.hex == "#ffffff" } > 1)
        assertThrows(IllegalArgumentException::class.java) { ConformanceColors.tokens("no tokens") }
    }
    @Test fun alphaSourceOverIsExactAndBackgroundDependent() {
        assertEquals("#a6a5a4", ConformanceColors.composite("#211f1b", 0.4, "#ffffff"))
        assertEquals("#211f1b", ConformanceColors.composite("#211f1b", 1.0, "#ffffff"))
        assertEquals("#ffffff", ConformanceColors.composite("#211f1b", 0.0, "#ffffff"))
        assertNotEquals("#a6a5a4", ConformanceColors.composite("#211f1b", 0.4, "#f7f4ee"))
        val background = layer("bg").put("type", "rectangle").put("fill", "#ffffff")
        val overlay = layer("mask").put("fill", "#211f1b").put("opacity", 0.4)
        assertEquals("#a6a5a4", ConformanceColors.expected(overlay, listOf(background, overlay)))
        assertThrows(IllegalStateException::class.java) { ConformanceColors.expected(overlay, listOf(overlay)) }
    }
    @Test fun arbitraryVectorChildrenRequireParentGeometryAndProvenance() {
        val parent = layer("arbitrary/group").put("type", "group").put("name", "icon / dumbbell")
        val child = layer("arbitrary/group/99").put("type", "path")
        val entries = ConformanceMapping.entries(listOf(parent, child), emptyList(), emptyList(), emptyMap())
        val e = entries.last()
        assertTrue(ConformanceComparison.vectorUnobservable(child, parent, e, true, true))
        assertFalse(ConformanceComparison.vectorUnobservable(child, parent, e, false, true))
        assertFalse(ConformanceComparison.vectorUnobservable(child, parent, e, true, false))
        assertFalse(ConformanceComparison.vectorUnobservable(child.put("path", "other/99"), parent, e, true, true))
    }
    @Test fun multipleWindowPixelsAreCompositedAndAbsentOrUnchangedPanelsFailClosed() {
        val before = BufferedImage(20, 20, BufferedImage.TYPE_INT_ARGB)
        val panel = BufferedImage(10, 10, BufferedImage.TYPE_INT_ARGB).apply {
            for (y in 0 until 10) for (x in 0 until 10) setRGB(x, y, if (x < 5) -1 else 0xff211f1b.toInt())
        }
        val after = ConformanceCapture.composite(before, listOf(ConformanceCapture.Window(panel, 5, 10)))
        assertEquals(-1, after.getRGB(5, 10)); assertEquals(0, after.getRGB(0, 0))
        val bounds = JSONObject().put("x", 2.5).put("y", 5).put("w", 5).put("h", 5)
        val ink = JSONObject(bounds.toString()).put("hex", "#211f1b")
        assertEquals("VALID_CAPTURE", ConformanceCapture.validate(before, after, listOf(bounds), 1, before, listOf(ink)).getString("status"))
        assertEquals("INVALID_CAPTURE", ConformanceCapture.validate(before, after, listOf(bounds), 1, after, listOf(ink)).getString("status"))
        assertEquals("INVALID_CAPTURE", ConformanceCapture.validate(before, after, listOf(bounds), 1, before, emptyList()).getString("status"))
        assertEquals("INVALID_CAPTURE", ConformanceCapture.validate(before, before, listOf(bounds), 1).getString("status"))
        assertEquals("INVALID_CAPTURE", ConformanceCapture.validate(before, after, listOf(bounds), 0).getString("status"))
        assertEquals("INVALID_CAPTURE", ConformanceCapture.validate(before, after, emptyList(), 1).getString("status"))
    }
    @Test fun duplicateMatchingUsesRegisteredOriginAndReservesManualSelectors() {
        val first = layer("first", y = 100)
        val second = layer("second", y = 150)
        val nodes = listOf(node(1, y = 0), node(2, y = 50))
        val entries = ConformanceMapping.entries(listOf(first, second), emptyList(), nodes, emptyMap(), -100.0)
        assertEquals(listOf(1, 2), entries.map { it.getInt("nodeID") })
        val exception = JSONObject().put("path", "first").put("tag", "manual")
        nodes.first().put("tag", "manual")
        val reserved = ConformanceMapping.entries(listOf(first, second), listOf(exception), nodes, emptyMap(), -100.0)
        assertEquals(2, reserved.last().getInt("nodeID"))
    }
    @Test fun namedOpacityTokenIsDerivedFromReadmeWithoutColorApproximation() {
        val tokens = listOf(ConformanceColors.Token("color.overlay.scrim", "#211f1b", 0.4))
        val background = layer("bg").put("type", "rectangle").put("fill", "#ffffff")
        val overlay = layer("mask").put("name", "Scrim").put("fill", "#211f1b")
        assertEquals("#a6a5a4", ConformanceColors.expected(overlay, listOf(background, overlay), tokens))
        overlay.put("name", "opaque primary")
        assertEquals("#211f1b", ConformanceColors.expected(overlay, listOf(background, overlay), tokens))
    }

    @Test fun iconInkUsesMeasuredBackgroundRatherThanTwoHardCodedSurfaceColors() {
        val image = BufferedImage(20, 20, BufferedImage.TYPE_INT_RGB)
        for (y in 0 until 20) for (x in 0 until 20) image.setRGB(x, y, 0xede9e2)
        val bounds = JSONObject().put("x", 0).put("y", 0).put("w", 10).put("h", 10)
        assertNull(ConformanceComparison.pixelMode(image, bounds, true))
        for (y in 5 until 15) for (x in 5 until 15) image.setRGB(x, y, 0x211f1b)
        assertEquals("#211f1b", ConformanceComparison.pixelMode(image, bounds, true))
        assertEquals("#ede9e2", ConformanceComparison.pixelMode(image, bounds))
    }

}
