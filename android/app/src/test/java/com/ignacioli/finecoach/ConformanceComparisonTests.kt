// fictional-data: synthetic geometry only
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
    @Test fun textIdentityOnlyNormalizesNbspAndKeepsDifferentValuesDistinct() {
        val board = rect(y = 100.0).put("path", "value").put("name", "set value")
            .put("type", "text").put("text", "60 kg × 12")
        val node = rect(y = 100.0).put("id", 1).put("text", "60\u00a0kg ×\u00a012").put("hex", "#000000")
        val entries = ConformanceMapping.entries(listOf(board), emptyList(), listOf(node), emptyMap())
        assertEquals(1, entries.single().getInt("nodeID"))
        assertEquals(listOf(node), ConformanceComparison.select(listOf(node), entries.single()))
        val other = JSONObject().put("text", "60 kg × 13")
        assertTrue(ConformanceComparison.select(listOf(node), other).isEmpty())
        assertEquals(" A  B\t\n", normalizeConformanceText(" A\u00a0 B\t\n"))
    }
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
            boundary.put(axis, base.getDouble(axis) + if (axis in listOf("x", "y")) 8.001 else 2.001)
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
    @Test fun multiLineDesignTextMatchesATwoLineBoxAndOneLineLayersStayOneTokenLine() {
        val line = ConformanceComparison.tokenLineHeight(13.0, 400)
        val design = rect(16.0, 700.0, 220.0, 34.0).put("type", "text").put("fontSize", 13).put("fontWeight", 400)
        val box = ConformanceComparison.designBox(design)
        assertEquals(2 * line, box.getDouble("h"), 0.001)
        assertEquals(717.0, box.getDouble("y") + box.getDouble("h") / 2, 0.001)
        assertEquals(16.0, box.getDouble("x"), 0.001)
        assertEquals(220.0, box.getDouble("w"), 0.001)
        val twoLines = rect(16.0, box.getDouble("y"), 220.0, box.getDouble("h"))
        assertTrue(ConformanceComparison.geometry(twoLines, design, "top", 0.0).getBoolean("matches"))
        val oneLineTall = rect(16.0, 717.0 - line / 2, 220.0, line)
        assertFalse(ConformanceComparison.geometry(oneLineTall, design, "top", 0.0).getBoolean("matches"))

        val single = rect(16.0, 100.0, 86.0, 20.0).put("type", "text").put("fontSize", 17).put("fontWeight", 400)
        val singleBox = ConformanceComparison.designBox(single)
        assertEquals(ConformanceComparison.tokenLineHeight(17.0, 400), singleBox.getDouble("h"), 0.001)
        assertEquals(110.0, singleBox.getDouble("y") + singleBox.getDouble("h") / 2, 0.001)
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
        for ((axis, value) in listOf("x" to 24.001, "w" to 93.741)) {
            val off = rect(16.0, 98.1, 86.0, 23.8).put(axis, value)
            assertFalse(axis, ConformanceComparison.geometry(off, design, "top", 0.0).getBoolean("matches"))
        }
    }
    @Test fun normalizedTextHonorsTopOriginAndBottomAnchor() {
        // 17pt/600 headline: 23.8 tall around the exported center 785.
        val design = rect(16.0, 775.0, 69.0, 20.0).put("type", "text").put("fontSize", 17).put("fontWeight", 600)
        val bottom = rect(16.0, 773.1, 69.0, 23.8)
        assertTrue(ConformanceComparison.geometry(bottom, design, "bottom", -52.0).getBoolean("matches"))
        assertFalse(ConformanceComparison.geometry(rect(16.0, 781.2, 69.0, 23.8), design, "bottom", -52.0).getBoolean("matches"))
        assertTrue(ConformanceComparison.geometry(rect(16.0, 721.1, 69.0, 23.8), design, "top", -52.0).getBoolean("matches"))
    }
    @Test fun editableTextFieldIsJudgedByCenterAndReportsItsRawHeight() {
        val layer = JSONObject("""{"path":"22","type":"text","fontSize":24,"fontWeight":600,"x":211,"y":215.1,"w":65,"h":28.8}""")
        val rule = JSONObject("""{"geometryRule":"EDITABLE_TEXT_FIELD"}""")
        val centered = ConformanceComparison.geometry(JSONObject("""{"x":211.5,"y":212,"w":63.5,"h":35}"""), layer, "top", 0.0, rule = rule)
        assertTrue(centered.getBoolean("matches"))
        assertEquals(35.0, centered.getJSONObject("editableTextField").getDouble("rawH"), 0.001)
        val shifted = ConformanceComparison.geometry(JSONObject("""{"x":211.5,"y":221,"w":63.5,"h":35}"""), layer, "top", 0.0, rule = rule)
        assertFalse("A gross center shift still fails", shifted.getBoolean("matches"))
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
    @Test fun stepperFieldRulesComeFromTheComponentTable() {
        fun layer(path: String, name: String, type: String, y: Int) = JSONObject()
            .put("path", path).put("name", name).put("type", type).put("x", 16).put("y", y).put("w", 20).put("h", 20)
            .put("text", if (type == "text") "−" else "")
        val minus = layer("m", "DS-STEPPER-FIELD · minus", "text", 10).put("fontSize", 22).put("fontWeight", 600).put("w", 14).put("h", 26)
        val plus = layer("p", "DS-STEPPER-FIELD · plus", "text", 40).put("text", "+")
        val value = layer("v", "DS-STEPPER-FIELD · value (可点击输入)", "text", 10).put("text", "122.5").put("fontSize", 24).put("fontWeight", 600)
        val capsule = layer("c", "DS-STEPPER-FIELD · capsule (重量)", "rectangle", 0)
        val hint = layer("h", "DS-STEPPER-FIELD · hint", "text", 80).put("text", "hint")
        val entries = ConformanceMapping.entries(listOf(minus, plus, value, capsule, hint), emptyList(), emptyList(), emptyMap())
            .associateBy { it.getString("path") }
        val glyph = entries.getValue("m")
        assertEquals("SYMBOL_CENTER", glyph.getString("geometryRule"))
        assertEquals(20.0, glyph.getDouble("symbolSizeDp"), 0.0)
        assertEquals("iconInk", glyph.getString("colorMethod"))
        assertEquals("-minus-glyph", glyph.getString("tagSuffix"))
        assertEquals("AUTO_TAG", glyph.getString("mapping"))
        assertFalse(glyph.has("tag"))
        assertFalse(glyph.has("text"))
        assertEquals("SYMBOL_CENTER", entries.getValue("p").getString("geometryRule"))
        assertEquals("-plus-glyph", entries.getValue("p").getString("tagSuffix"))
        val field = entries.getValue("v")
        assertEquals("EDITABLE_TEXT_FIELD", field.getString("geometryRule"))
        assertEquals("textLayout", field.getString("colorMethod"))
        assertEquals("AUTO_TEXT", field.getString("mapping"))
        assertEquals("122.5", field.getString("text"))
        val capsuleEntry = entries.getValue("c")
        assertTrue(ConformanceMapping.isStepperCapsuleSelector(capsuleEntry))
        assertFalse(capsuleEntry.has("tag"))
        assertEquals("AUTO_TAG", capsuleEntry.getString("mapping"))
        assertFalse(entries.getValue("h").has("geometryRule"))
        val explicit = JSONObject().put("geometryRule", "SYMBOL_CENTER").put("symbolSizeDp", 20)
        assertEquals(ConformanceComparison.designBox(minus, explicit).toString(), ConformanceComparison.designBox(minus, glyph).toString())
        val centered = ConformanceComparison.geometry(JSONObject("""{"x":211.5,"y":212,"w":63.5,"h":35}"""),
            JSONObject("""{"path":"22","type":"text","fontSize":24,"fontWeight":600,"x":211,"y":215.1,"w":65,"h":28.8}"""),
            "top", 0.0, rule = field)
        assertTrue(centered.getBoolean("matches"))
        fun observed(id: Int, tag: String, y: Double) = JSONObject().put("id", id).put("tag", tag).put("text", "").put("hex", JSONObject.NULL)
            .put("x", 130.0).put("y", y).put("w", 20.0).put("h", 20.0).put("attached", true).put("placed", true)
        val low = layer("low", "DS-STEPPER-FIELD · minus", "text", 10)
        val high = layer("high", "DS-STEPPER-FIELD · minus", "text", 80)
        val paired = ConformanceMapping.entries(listOf(low, high), emptyList(),
            listOf(observed(1, "set-reps-minus-glyph", 80.0), observed(2, "set-weight-minus-glyph", 10.0)), emptyMap())
        assertEquals(2, paired.single { it.getString("path") == "low" }.getInt("nodeID"))
        assertEquals(1, paired.single { it.getString("path") == "high" }.getInt("nodeID"))
        val weight = JSONObject().put("commonLayoutParentOfTags", JSONArray(listOf("set-weight-minus", "set-weight-plus"))).put("containsTag", "set-weight-input").put("y", 258.0).put("x", 112.0).put("w", 262.0).put("h", 48.0).put("id", 7)
        val reps = JSONObject(weight.toString()).put("commonLayoutParentOfTags", JSONArray(listOf("set-reps-minus", "set-reps-plus"))).put("containsTag", "set-reps-input").put("y", 318.0).put("id", 8)
        assertEquals(2, ConformanceComparison.select(listOf(weight, reps), capsuleEntry).size)
        assertFalse(ConformanceMapping.matchesStepperCapsule(JSONObject().put("commonLayoutParentOfTags", JSONArray(listOf("rest-minus", "rest-plus"))).put("containsTag", "rest-skip")))
    }

    @Test fun proportionalTextGeometryAndAlignmentKeepAnchorStrict() {
        val design = rect(0.0,0.0,100.0,20.0).put("type", "text")
        for ((alignment, x) in listOf("left" to 0.0, "center" to 3.0, "right" to 6.0)) {
            val rule = JSONObject(design.toString()).put("textAlign", alignment)
            assertTrue(ConformanceComparison.geometry(rect(x,0.0,94.0,20.0), rule, "top", 0.0).getBoolean("matches"))
            assertFalse(ConformanceComparison.geometry(rect(x+2.5,0.0,94.0,20.0), rule, "top", 0.0).getBoolean("matches"))
        }
        assertFalse(ConformanceComparison.geometry(rect(0.0,0.0,91.0,20.0), design,"top",0.0).getBoolean("matches"))
        assertFalse(ConformanceComparison.geometry(rect(0.0,0.0,102.5,20.0), rect(0.0,0.0,100.0,20.0),"top",0.0).getBoolean("matches"))
    }

    private fun placed(path: String, x: Double, y: Double, w: Double, h: Double, dx: Double = 0.0, dy: Double = 0.0, dw: Double = 0.0): JSONObject {
        fun box(x: Double, y: Double, w: Double, h: Double) = JSONObject().put("x", x).put("y", y).put("w", w).put("h", h)
        return JSONObject().put("path", path).put("selector", JSONObject()).put("category", "PASS").put("textMatches", true).put("tokenMatches", true)
            .put("delta", box(dx, dy, dw, 0.0)).put("geometry", JSONObject().put("expectedBounds", box(x, y, w, h)).put("actualBounds", box(x + dx, y + dy, w + dw, h)))
    }

    private fun grant(row: JSONObject, checks: List<String>, maxDeltaDp: Double) {
        row.getJSONObject("selector").put("ownerException", JSONObject()
            .put("decision", "S3-D12").put("reason", "fictional raster width")
            .put("checks", JSONArray(checks)).put("maxDeltaDp", maxDeltaDp))
    }

    private fun apply(rows: List<JSONObject>) {
        val checks = ConformanceRelativeGeometry.evaluate(rows).getJSONArray("checks")
        ConformanceComparison.applyOwnerExceptions(rows, checks)
    }

    @Test fun ownerExceptionCoversAListedCheckInsideTheDeltaCap() {
        val row = placed("12", 0.0, 0.0, 40.0, 10.0, dw = 3.0)
        grant(row, listOf("SIZE"), 4.0)
        apply(listOf(row))
        assertEquals("OWNER_EXCEPTION", row.getString("status"))
        assertEquals("S3-D12", row.getJSONObject("ownerException").getString("decision"))
        assertFalse(row.optBoolean("ownerExceptionUnused"))
    }

    @Test fun ownerExceptionStaysFailWhenAnotherCheckFails() {
        val left = placed("12", 0.0, 0.0, 40.0, 10.0, dw = -2.0)
        val right = placed("13", 50.0, 0.0, 10.0, 10.0, dx = 2.0)
        grant(left, listOf("GAP"), 4.0)
        grant(right, listOf("GAP"), 4.0)
        val checks = ConformanceRelativeGeometry.evaluate(listOf(left, right)).getJSONArray("checks")
        left.getJSONArray("failedChecks").put("ICON_PIXELS")
        ConformanceComparison.applyOwnerExceptions(listOf(left, right), checks)
        assertEquals("FAIL", left.getString("status"))
        assertEquals("OWNER_EXCEPTION", right.getString("status"))
    }

    @Test fun ownerExceptionStaysFailWhenTheDeltaExceedsTheCap() {
        val left = placed("12", 0.0, 0.0, 40.0, 10.0, dw = -2.0)
        val right = placed("13", 50.0, 0.0, 10.0, 10.0, dx = 2.0)
        grant(left, listOf("GAP"), 3.0)
        grant(right, listOf("GAP"), 3.0)
        apply(listOf(left, right))
        assertEquals("FAIL", left.getString("status"))
        assertEquals("FAIL", right.getString("status"))
    }

    @Test fun ownerExceptionNotesAnUnusedRegistrationWhenTheRowPasses() {
        val row = placed("12", 0.0, 0.0, 40.0, 10.0)
        grant(row, listOf("GAP"), 4.0)
        apply(listOf(row))
        assertEquals("PASS", row.getString("status"))
        assertTrue(row.getBoolean("ownerExceptionUnused"))
        assertTrue(row.getString("reason").contains("例外登记未被使用"))
    }

    @Test fun ownerExceptionRejectsAnIncompleteRegistration() {
        val row = placed("12", 0.0, 0.0, 40.0, 10.0, dw = 3.0)
        val cases = listOf(
            JSONObject().put("decision", "board").put("reason", "because").put("checks", JSONArray(listOf("SIZE"))).put("maxDeltaDp", 4),
            JSONObject().put("decision", "S3-D12").put("reason", " ").put("checks", JSONArray(listOf("SIZE"))).put("maxDeltaDp", 4),
            JSONObject().put("decision", "S3-D12").put("reason", "because").put("checks", JSONArray()).put("maxDeltaDp", 4),
            JSONObject().put("decision", "S3-D12").put("reason", "because").put("checks", JSONArray(listOf("SIZE"))),
            JSONObject().put("decision", "S3-D12").put("reason", "because").put("checks", JSONArray(listOf("SIZE"))).put("maxDeltaDp", 0),
        )
        for (spec in cases) {
            row.getJSONObject("selector").put("ownerException", spec)
            val error = runCatching { ConformanceComparison.applyOwnerExceptions(listOf(row), JSONArray()) }.exceptionOrNull()
            assertTrue(spec.toString(), error is IllegalStateException)
            assertTrue(error?.message, error?.message?.contains("12") == true)
        }
    }

    @Test fun ownerExceptionNeedsBothSidesOfAGap() {
        val left = placed("12", 0.0, 0.0, 40.0, 10.0, dw = -2.0)
        val right = placed("13", 50.0, 0.0, 10.0, 10.0, dx = 2.0)
        grant(left, listOf("GAP"), 4.0)
        apply(listOf(left, right))
        assertEquals("FAIL", left.getString("status"))
        assertEquals("FAIL", right.getString("status"))
        grant(right, listOf("GAP"), 4.0)
        apply(listOf(left, right))
        assertEquals("OWNER_EXCEPTION", left.getString("status"))
        assertEquals("OWNER_EXCEPTION", right.getString("status"))
    }
}
