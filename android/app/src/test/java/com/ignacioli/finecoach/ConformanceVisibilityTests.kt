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
class ConformanceVisibilityTests {
    private fun rect(x: Double, y: Double, w: Double, h: Double) = JSONObject()
        .put("x", x).put("y", y).put("w", w).put("h", h)
    private fun node(raw: JSONObject, clipped: JSONObject, scroll: JSONObject? = null): JSONObject {
        val result = JSONObject(clipped.toString()).put("unclipped", raw).put("placed", true).put("attached", true)
        return result.put("scrollAncestors", JSONArray().apply { if (scroll != null) put(scroll.put("tag", "active-session-content")) })
    }
    @Test fun zeroClippedBoundsOutsideScrollRequiresScrollRatherThanMissing() {
        val r = ConformanceComparison.visibility(node(rect(16.0, 780.0, 80.0, 22.0), rect(0.0, 0.0, 0.0, 0.0), rect(16.0, 0.0, 358.0, 700.0)))
        assertEquals("OUTSIDE_SCROLL_VIEWPORT", r.getString("state")); assertTrue(r.getBoolean("needsScroll"))
    }
    @Test fun partiallyClippedNodeDoesNotPassAsVisible() {
        val r = ConformanceComparison.visibility(node(rect(16.0, 690.0, 80.0, 22.0), rect(16.0, 690.0, 80.0, 10.0), rect(16.0, 0.0, 358.0, 700.0)))
        assertEquals("PARTIALLY_CLIPPED_BY_SCROLL", r.getString("state"))
    }
    @Test fun zeroLayoutIsDistinctFromOffscreenLayout() {
        val r = ConformanceComparison.visibility(node(rect(0.0, 0.0, 0.0, 0.0), rect(0.0, 0.0, 0.0, 0.0)))
        assertEquals("ZERO_LAYOUT", r.getString("state")); assertFalse(r.getBoolean("needsScroll"))
    }
    @Test fun visibleGeometryNeverClaimsSiblingOcclusionIsVerified() {
        val r = ConformanceComparison.visibility(node(rect(16.0, 20.0, 80.0, 22.0), rect(16.0, 20.0, 80.0, 22.0)))
        assertEquals("VISIBLE", r.getString("state")); assertEquals("UNVERIFIED", r.getString("occlusion"))
    }
}
