package com.ignacioli.finecoach

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class ConformanceComparisonTests {
    private fun rect(x: Double = 16.0, y: Double = 760.0, w: Double = 358.0, h: Double = 52.0) =
        JSONObject().put("x", x).put("y", y).put("w", w).put("h", h)
    @Test fun topRetainsRegisteredOriginOffset() {
        val g = ConformanceComparison.geometry(rect(y = 708.0), rect(), "top", -52.0)
        assertTrue(g.getBoolean("matches")); assertEquals(-52.0, g.getDouble("rawYDelta"), 0.0)
    }
    @Test fun viewportBackgroundNeverInheritsTopOffset() {
        val g = ConformanceComparison.geometry(rect(0.0, 0.0, 390.0, 844.0), rect(0.0, 0.0, 390.0, 844.0), "viewport", -52.0)
        assertTrue(g.getBoolean("matches")); assertEquals(0.0, g.getJSONObject("delta").getDouble("y"), 0.0)
    }
    @Test fun bottomUsesGapAndDoesNotInheritTopOffset() {
        val g = ConformanceComparison.geometry(rect(), rect(), "bottom", -52.0)
        assertTrue(g.getBoolean("matches")); assertEquals(32.0, g.getDouble("actualBottomGap"), 0.0)
        assertEquals(32.0, g.getDouble("designBottomGap"), 0.0)
    }
    @Test fun bottomDoesNotAbsorbRealPlacementDrift() {
        val g = ConformanceComparison.geometry(rect(y = 792.0), rect(), "bottom", -52.0)
        assertFalse(g.getBoolean("matches")); assertEquals(-32.0, g.getJSONObject("delta").getDouble("y"), 0.0)
    }
    @Test fun bottomStillChecksHeightIndependently() {
        val g = ConformanceComparison.geometry(rect(y = 757.0, h = 55.0), rect(), "bottom", -52.0)
        assertEquals(0.0, g.getJSONObject("delta").getDouble("y"), 0.0)
        assertFalse(g.getBoolean("matches")); assertFalse(g.getJSONObject("withinTolerance").getBoolean("h"))
    }
    @Test fun allFourAxesUseInclusiveTwoDpAndRejectAnIndividualExcess() {
        val base = rect()
        for (axis in listOf("x", "y", "w", "h")) {
            val boundary = JSONObject(base.toString()).put(axis, base.getDouble(axis) + 2.0)
            assertTrue("$axis boundary", ConformanceComparison.geometry(boundary, base, "top", 0.0).getBoolean("matches"))
            boundary.put(axis, base.getDouble(axis) + 2.001)
            val g = ConformanceComparison.geometry(boundary, base, "top", 0.0)
            assertFalse("$axis excess", g.getBoolean("matches")); assertFalse(g.getJSONObject("withinTolerance").getBoolean(axis))
        }
    }
    @Test fun subpixelDifferencesPassWithoutChangingTolerance() {
        assertTrue(ConformanceComparison.geometry(rect(16.5, 760.5, 357.5, 52.5), rect(), "bottom", -52.0).getBoolean("matches"))
    }
    @Test(expected = IllegalArgumentException::class) fun unknownAnchorFailsClosed() {
        ConformanceComparison.geometry(rect(), rect(), "automatic", -52.0)
    }
    @Test fun commonParentSelectorRequiresBothChildTagsAndInputEvidence() {
        val selector = JSONObject().put("commonLayoutParentOfTags", JSONArray(listOf("set-weight-minus", "set-weight-plus")))
            .put("containsTag", "set-weight-input")
        val observed = JSONObject(selector.toString()).put("geometrySource", "real Row")
        assertEquals(listOf(observed), ConformanceComparison.select(listOf(observed), selector))
        val wrong = JSONObject(observed.toString()).put("containsTag", "set-reps-input")
        assertTrue(ConformanceComparison.select(listOf(wrong), selector).isEmpty())
    }
    @Test fun duplicateParentObservationsStayAmbiguousRatherThanPickingOne() {
        val selector = JSONObject().put("commonLayoutParentOfTags", JSONArray(listOf("minus", "plus"))).put("containsTag", "input")
        assertEquals(2, ConformanceComparison.select(listOf(JSONObject(selector.toString()), JSONObject(selector.toString())), selector).size)
    }
}
