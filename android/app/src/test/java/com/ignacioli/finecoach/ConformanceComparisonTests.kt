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
    @Test fun designTextBoxIsNormalizedToTokenLineHeightAroundItsCenter() {
        // 17pt/400 = body, README multiplier 1.4 → 23.8; Penpot exported 20 tall at y=100 (center 110).
        val design = rect(16.0, 100.0, 86.0, 20.0).put("type", "text").put("fontSize", 17).put("fontWeight", 400)
        val box = ConformanceComparison.designBox(design)
        assertEquals(23.8, box.getDouble("h"), 0.001); assertEquals(110.0, box.getDouble("y") + box.getDouble("h") / 2, 0.001)
        val actual = rect(16.0, 98.1, 86.0, 24.0)
        assertTrue(ConformanceComparison.geometry(actual, design, "top", 0.0).getBoolean("matches"))
    }
    @Test fun textIsJudgedOnAllFourAxesAfterNormalization() {
        val design = rect(16.0, 100.0, 86.0, 20.0).put("type", "text").put("fontSize", 17).put("fontWeight", 400)
        // A natural 24.5→30 box with the same center no longer passes: height is strict now.
        val tall = rect(16.0, 95.0, 86.0, 30.0)
        val g = ConformanceComparison.geometry(tall, design, "top", 0.0)
        assertFalse(g.getBoolean("matches")); assertFalse(g.getJSONObject("withinTolerance").getBoolean("h"))
        assertEquals(0.0, g.getJSONObject("delta").getDouble("centerY"), 0.001)
        for ((axis, value) in listOf("x" to 18.001, "w" to 88.001)) {
            val off = rect(16.0, 98.1, 86.0, 23.8).put(axis, value)
            assertFalse(axis, ConformanceComparison.geometry(off, design, "top", 0.0).getBoolean("matches"))
        }
    }
    @Test fun normalizedTextHonorsTopOriginAndBottomAnchor() {
        // 17pt/600 headline: 23.8 tall around the exported center 785.
        val design = rect(16.0, 775.0, 69.0, 20.0).put("type", "text").put("fontSize", 17).put("fontWeight", 600)
        val bottom = rect(16.0, 773.1, 69.0, 23.8)
        assertTrue(ConformanceComparison.geometry(bottom, design, "bottom", -52.0).getBoolean("matches"))
        assertFalse(ConformanceComparison.geometry(rect(16.0, 775.2, 69.0, 23.8), design, "bottom", -52.0).getBoolean("matches"))
        assertTrue(ConformanceComparison.geometry(rect(16.0, 721.1, 69.0, 23.8), design, "top", -52.0).getBoolean("matches"))
    }
    @Test fun editableTextFieldIsJudgedByCenterAndReportsItsRawHeight() {
        val layer = JSONObject("""{"path":"22","type":"text","fontSize":24,"fontWeight":600,"x":211,"y":215.1,"w":65,"h":28.8}""")
        val rule = JSONObject("""{"geometryRule":"EDITABLE_TEXT_FIELD"}""")
        val centered = ConformanceComparison.geometry(JSONObject("""{"x":211.5,"y":212,"w":63.5,"h":35}"""), layer, "top", 0.0, rule = rule)
        assertTrue(centered.getBoolean("matches"))
        assertEquals(35.0, centered.getJSONObject("editableTextField").getDouble("rawH"), 0.001)
        val shifted = ConformanceComparison.geometry(JSONObject("""{"x":211.5,"y":215,"w":63.5,"h":35}"""), layer, "top", 0.0, rule = rule)
        assertFalse("A 3dp center shift still fails", shifted.getBoolean("matches"))
        assertFalse("Without the rule the height is judged", ConformanceComparison.geometry(
            JSONObject("""{"x":211.5,"y":212,"w":63.5,"h":35}"""), layer, "top", 0.0).getBoolean("matches"))
    }

    @Test fun tokenLineHeightUsesWeightThenSizeAndFailsWhenAmbiguous() {
        assertEquals(22 * 1.3, ConformanceComparison.tokenLineHeight(22.0, 400), 0.001) // ‹: no 22/400 style, all 22pt styles share 1.3
        assertEquals(14 * 1.2, ConformanceComparison.tokenLineHeight(14.0, 400), 0.001) // compact, not chipLabel
        assertEquals(14 * 1.3, ConformanceComparison.tokenLineHeight(14.0, 500), 0.001) // chipLabel
        assertThrows(IllegalStateException::class.java) { ConformanceComparison.tokenLineHeight(19.0, 400) }
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
