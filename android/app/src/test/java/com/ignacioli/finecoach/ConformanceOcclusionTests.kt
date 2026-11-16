package com.ignacioli.finecoach

import java.awt.image.BufferedImage
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class ConformanceOcclusionTests {
    private fun box(y: Int, h: Int) = JSONObject().put("x", 0).put("y", y).put("w", 10).put("h", h)
    private fun image(sheetTop: Int) = BufferedImage(20, 20, BufferedImage.TYPE_INT_RGB).apply {
        for (y in 0 until height) for (x in 0 until width) setRGB(x, y, if (y < sheetTop * 2) 0xa6a5a4 else 0xffffff)
    }
    @Test fun mostlyCoveredScrimSamplesOnlyUncoveredStripInEachCoordinateSpace() {
        val scrim = box(0, 10)
        // Android and design have different sheet positions; neither mask may be reused for the other.
        assertEquals("#a6a5a4", ConformanceComparison.pixelMode(image(2), scrim, occluders = listOf(box(2, 8))))
        assertEquals("#a6a5a4", ConformanceComparison.pixelMode(image(3), scrim, occluders = listOf(box(3, 7))))
        assertEquals("#ffffff", ConformanceComparison.pixelMode(image(2), scrim))
    }
    @Test fun fullyCoveredLayerIsUnobservable() {
        val bounds = box(0, 10)
        assertNull(ConformanceComparison.pixelMode(image(0), bounds, occluders = listOf(bounds)))
        assertFalse(ConformanceComparison.hasUncoveredPixels(image(0), bounds, listOf(bounds)))
        val text = JSONObject(bounds.toString()).put("hex", "#ffffff")
        assertNull(ConformanceComparison.observedTextColor(image(0), text, listOf(bounds)))
    }
    @Test fun uncoveredLayerIsUnchanged() {
        val bounds = box(0, 10)
        assertEquals(ConformanceComparison.pixelMode(image(10), bounds),
            ConformanceComparison.pixelMode(image(10), bounds, occluders = listOf(box(10, 5))))
        assertTrue(ConformanceComparison.hasUncoveredPixels(image(10), bounds, emptyList()))
    }
}
