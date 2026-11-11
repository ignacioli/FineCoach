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
    @Test fun textHeightIsReportOnlyWhileItsCenterAndWidthRemainStrict() {
        val design = rect(16.0, 100.0, 86.0, 20.0).put("type", "text")
        val actual = rect(16.0, 95.0, 86.0, 30.0)
        val result = ConformanceComparison.geometry(actual, design, "top", 0.0)
        assertTrue(result.getBoolean("matches")); assertEquals(10.0, result.getJSONObject("delta").getDouble("h"), 0.0)
        assertEquals(0.0, result.getJSONObject("delta").getDouble("centerY"), 0.0)
        actual.put("w", 88.001)
        assertFalse(ConformanceComparison.geometry(actual, design, "top", 0.0).getBoolean("matches"))
        actual.put("w", 86.0).put("x", 18.001)
        assertFalse(ConformanceComparison.geometry(actual, design, "top", 0.0).getBoolean("matches"))
    }
    @Test fun textCentersHonorTopOriginBottomAnchorAndInclusiveTolerance() {
        val design = rect(16.0, 775.0, 69.0, 20.0).put("type", "text")
        val actual = rect(16.0, 770.0, 69.0, 30.0)
        assertTrue(ConformanceComparison.geometry(actual, design, "bottom", -52.0).getBoolean("matches"))
        actual.put("y", 772.0)
        assertTrue(ConformanceComparison.geometry(actual, design, "bottom", -52.0).getBoolean("matches"))
        actual.put("y", 772.001)
        assertFalse(ConformanceComparison.geometry(actual, design, "bottom", -52.0).getBoolean("matches"))
        actual.put("y", 718.0)
        assertTrue(ConformanceComparison.geometry(actual, design, "top", -52.0).getBoolean("matches"))
    }
    @Test fun vectorInternalIsUnobservableOnlyWithMatchingParentAndProvenance() {
        val layer = JSONObject("""{"path":"7/1","type":"path"}""")
        val parent = JSONObject("""{"path":"7","type":"group","name":"icon / barbell"}""")
        val entry = JSONObject("""{"unobservable":"VECTOR_INTERNAL_PATH","parentPath":"7","asset":"barbell"}""")
        assertTrue(ConformanceComparison.vectorUnobservable(layer, parent, entry, true, true))
        assertFalse(ConformanceComparison.vectorUnobservable(layer, parent, entry, false, true))
        assertFalse(ConformanceComparison.vectorUnobservable(layer, parent, entry, true, false))
        assertFalse(ConformanceComparison.vectorUnobservable(layer, null, entry, true, true))
        parent.put("type", "rectangle")
        assertFalse(ConformanceComparison.vectorUnobservable(layer, parent, entry, true, true))
        parent.put("type", "group").put("name", "icon / dumbbell")
        assertFalse(ConformanceComparison.vectorUnobservable(layer, parent, entry, true, true))
    }
    @Test fun vectorInternalRequiresItsOwnSelectorToHitTheParentNode() {
        val parentRow = JSONObject().put("status", "PASS").put("actual", JSONObject().put("id", 7))
        val hit = JSONObject().put("status", "PASS").put("actual", JSONObject().put("id", 7))
        assertTrue(ConformanceComparison.vectorSelectorHitsParent(hit, parentRow))
        // Selector found nothing: the row stays MISSING and cannot be marked unobservable.
        assertFalse(ConformanceComparison.vectorSelectorHitsParent(JSONObject().put("status", "MISSING"), parentRow))
        // Selector found a different node than the parent icon.
        assertFalse(ConformanceComparison.vectorSelectorHitsParent(JSONObject().put("status", "FAIL").put("actual", JSONObject().put("id", 8)), parentRow))
        // Parent row itself missing.
        assertFalse(ConformanceComparison.vectorSelectorHitsParent(hit, JSONObject().put("status", "MISSING")))
        assertFalse(ConformanceComparison.vectorSelectorHitsParent(hit, null))
    }
    @Test fun vectorMarkCannotHideTextOrAnUnapprovedLayer() {
        val parent = JSONObject("""{"path":"45","type":"group","name":"edit"}""")
        val entry = JSONObject("""{"unobservable":"VECTOR_INTERNAL_PATH","parentPath":"45","asset":"edit"}""")
        assertFalse(ConformanceComparison.vectorUnobservable(JSONObject("""{"path":"45/1","type":"text"}"""), parent, entry, true, true))
        assertFalse(ConformanceComparison.vectorUnobservable(JSONObject("""{"path":"45/2","type":"path"}"""), parent, entry, true, true))
    }
}
