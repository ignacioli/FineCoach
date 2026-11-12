package com.ignacioli.finecoach

import java.awt.Color
import java.awt.Font
import java.awt.image.BufferedImage
import java.io.File
import java.security.MessageDigest
import javax.imageio.ImageIO
import kotlin.math.abs
import org.json.JSONArray
import org.json.JSONObject

/** Test-only comparison. Missing observations are failures, never inferred from expected values. */
internal object ConformanceComparison {
    fun run(androidRoot: File, out: File, nodes: JSONArray, bindings: Map<String, String>, screen: String = "P0-a2-training", designPath: String = "design/experience-p0/screens/P0-a2-training.png", capture: JSONObject? = null): JSONObject {
        val assets = File(androidRoot, "design-assets/conformance")
        val exportedLayers = JSONObject(File(assets, "$screen.layers.json").readText()).getJSONArray("layers").objects()
        val layers = exportedLayers.filter { ConformanceMapping.intersectsViewport(it) }
        val map = JSONObject(File(assets, "$screen.map.json").readText())
        val exceptions = map.getJSONArray("elements").objects()
        val actual = nodes.objects().filter { ConformanceMapping.intersectsViewport(it) && it.getDouble("w") > 0 && it.getDouble("h") > 0 && it.optBoolean("attached", true) && it.optBoolean("placed", true) }
        val contentTop = contentTop(actual)
        val offset = map.getDouble("originOffsetY") + contentTop
        val entries = ConformanceMapping.entries(layers, exceptions, actual, bindings, offset)
        val tolerance = map.getDouble("toleranceDp")
        check(tolerance == 2.0) { "Approved tolerance is ±2dp" }
        val android = ImageIO.read(File(out, "$screen.android.png"))
        val tokens = ConformanceColors.tokens(File(androidRoot.parentFile, "design/design-system/README.md").readText())
        fun expand(raw: String) = ConformanceMapping.expand(raw, bindings)
        fun hexToken(hex: String?): String? = tokens.lastOrNull { it.hex == hex?.lowercase() && it.alpha == 1.0 }?.name
        val rows = JSONArray()
        val used = mutableSetOf<Int>()
        val design = ImageIO.read(File(androidRoot.parentFile, designPath))
        val mapped = entries.associate { e -> e.getString("path") to
            (if (e.has("mappingError")) null else select(actual, e, ::expand).singleOrNull()) }
        fun occluders(layer: JSONObject, node: JSONObject): List<JSONObject> = layers.drop(layers.indexOf(layer) + 1).filter {
            val observed = mapped[it.getString("path")]
            observed != null && observed.getInt("id") != node.getInt("id") &&
                !it.getString("path").startsWith(layer.getString("path") + "/")
        }
        for (entry in entries) {
            val layer = layers.single { it.getString("path") == entry.getString("path") }
            val candidates = if (entry.has("mappingError")) emptyList() else select(actual, entry, ::expand)
            val n = candidates.singleOrNull()
            val anchor = entry.optString("anchor", "top")
            entry.optJSONObject("pendingBoardFix")?.let { fix ->
                check(fix.optString("decision").startsWith("S1-D") && fix.optString("reason").isNotBlank()) { "pendingBoardFix needs a decision and reason at ${layer.getString("path")}" }
            }
            val expected = expectedBounds(layer, anchor, offset, entry)
            val row = JSONObject().put("path", layer.getString("path")).put("name", layer.getString("name"))
                .put("mapping", entry.getString("mapping")).put("anchor", anchor).put("toleranceDp", tolerance).put("topOriginApplied", anchor == "top")
                .put("expectedText", layer.optString("text", "")).put("selector", entry)
                .put("expected", expected)
            if (n == null) {
                row.put("status", "MISSING").put("category", "MISSING").put("visibility", JSONObject.NULL).put("reason", if (entry.has("mappingError")) entry.getString("mappingError") else if (candidates.size > 1) "ambiguous: ${candidates.size} nodes" else entry.optString("missingReason", "selector has no matching node (含原文 selector 不匹配；不能据此认定 UI 图形不存在)"))
                    .put("textMatches", false).put("tokenMatches", false)
            } else if (entry.optString("unobservable") == "AD01_VECTOR_INTERNAL") {
                // AD-01 replaces the entire icon: internal iOS geometry and paint are never compared.
                used += n.getInt("id")
                row.remove("expected")
                row.put("actual", n).put("status", "UNOBSERVABLE_CANDIDATE").put("category", "UNOBSERVABLE_CANDIDATE")
                    .put("textMatches", false).put("tokenMatches", JSONObject.NULL).put("tokenComparison", "NOT_APPLICABLE")
            } else {
                used += n.getInt("id")
                val geometry = geometry(n, layer, anchor, offset, tolerance, entry)
                val deltas = geometry.getJSONObject("delta")
                val textMatches = !layer.has("text") || (entry.optJSONObject("pendingBoardFix")?.optString("text", layer.getString("text")) ?: layer.getString("text")) == n.getString("text")
                val ad01 = ConformanceMapping.platformIcon(layer.optString("name")) != null
                val expectedHex = if (ad01) layers.filter { it.getString("path").startsWith(layer.getString("path") + "/") }
                    .mapNotNull { ConformanceColors.expected(it, layers, tokens) }.distinct().singleOrNull().orEmpty()
                    else ConformanceColors.expected(layer, layers, tokens).orEmpty()
                val expectedToken = hexToken(expectedHex)
                val above = occluders(layer, n)
                val androidMasks = above.map { mapped.getValue(it.getString("path"))!! }
                val designMasks = above
                val designObserved = pixelMode(design, layer, occluders = designMasks)
                val observedHex = if (entry.getString("colorMethod") == "textLayout") observedTextColor(android, n, androidMasks)
                    else pixelMode(android, n, entry.getString("colorMethod") == "iconInk", androidMasks)
                val fullyOccluded = !hasUncoveredPixels(android, n, androidMasks) || !hasUncoveredPixels(design, layer, designMasks)
                val observedToken = hexToken(observedHex)
                val tokenObservable = if (ad01) expectedHex.isNotEmpty() && observedHex != null else expectedHex.isEmpty() || observedHex != null
                val tokenMatches = tokenObservable && (expectedHex.isEmpty() || (if (ad01) tokens.any { it.hex == expectedHex } else tokens.any { it.hex == layer.optString("fill").ifEmpty { layer.optJSONObject("stroke")?.optString("color").orEmpty() }.lowercase() }) && expectedHex == observedHex)
                val visibility = visibility(n)
                val visible = ConformanceMapping.intersectsViewport(n) && n.optBoolean("attached", true) && n.optBoolean("placed", true) && n.getDouble("w") > 0 && n.getDouble("h") > 0
                val geometryMatches = geometry.getBoolean("matches")
                row.put("actual", n).put("delta", deltas).put("geometry", geometry).put("textMatches", textMatches)
                    .put("expectedToken", expectedToken ?: JSONObject.NULL).put("actualToken", observedToken ?: JSONObject.NULL)
                    .put("colorObservation", if (observedHex == null) "UNOBSERVABLE" else "OBSERVED")
                    .put("expectedCompositeHex", expectedHex).put("observedHex", observedHex ?: JSONObject.NULL).put("tokenMatches", if (tokenObservable) tokenMatches else JSONObject.NULL)
                    .put("tokenComparison", if (expectedHex.isEmpty()) "NOT_APPLICABLE" else if (!tokenObservable) "UNOBSERVABLE" else if (tokenMatches) "MATCH" else "MISMATCH")
                    .put("visibility", visibility).put("geometryMatches", geometryMatches)
                    .put("category", if (!visible) "INVISIBLE_OR_CLIPPED" else if (geometryMatches && textMatches && tokenMatches) "PASS" else "UI_DEVIATION")
                    .put("status", if (visible && geometryMatches && textMatches && tokenMatches) "PASS" else "FAIL")
                row.put("designObservedHex", designObserved ?: JSONObject.NULL)
                    .put("occluderPaths", JSONArray(above.map { it.getString("path") }))
                if (fullyOccluded && expectedHex.isNotEmpty()) {
                    row.put("colorFullyOccluded", true).put("colorObservation", "UNOBSERVABLE").put("tokenComparison", "UNOBSERVABLE")
                        .put("tokenMatches", JSONObject.NULL).put("reason", "No uncovered pixels remain in Android or design crop")
                    if (visible && geometryMatches && textMatches)
                        row.put("status", "UNOBSERVABLE_COLOR").put("category", "UNOBSERVABLE_COLOR")
                }
                if (row.getString("status") == "PASS" && entry.has("pendingBoardFix"))
                    row.put("status", "BOARD_FIX_PENDING").put("category", "BOARD_FIX_PENDING").put("pendingBoardFix", entry.getJSONObject("pendingBoardFix"))
            }
            rows.put(row)
        }
        val rowList = rows.objects()
        val relative = ConformanceRelativeGeometry.evaluate(rowList)
        for (entry in entries.filter { it.has("unobservable") }) {
            val layer = layers.single { it.getString("path") == entry.getString("path") }
            val parent = layers.singleOrNull { it.getString("path") == entry.optString("parentPath") }
            val parentRow = rowList.singleOrNull { it.getString("path") == entry.optString("parentPath") }
            val row = rowList.single { it.getString("path") == entry.getString("path") }
            // A wrong selector must stay MISSING: the internal path's own selector has to resolve to the very
            // node its parent icon row observed before the path may be marked unobservable.
            if (row.getString("status") == "MISSING") { row.put("reason", "不可观测标记的前提：本行选择器必须命中父图标节点；${row.optString("reason")}"); continue }
            val ownNodeIsParent = vectorSelectorHitsParent(row, parentRow)
            val evidence = provenanceValid(androidRoot, entry.optString("asset"))
            val valid = ownNodeIsParent && (ad01Unobservable(parent, entry, parentRow?.optString("status") == "PASS", evidence) || vectorUnobservable(layer, parent, entry, parentRow?.optBoolean("geometryMatches") == true, evidence))
            row.put("parentGeometryPassed", parentRow?.optBoolean("geometryMatches") == true).put("assetProvenanceVerified", evidence)
                .put("selectorHitsParentNode", ownNodeIsParent)
            if (valid) row.put("status", "UNOBSERVABLE_VECTOR_INTERNAL").put("category", "UNOBSERVABLE_VECTOR_INTERNAL")
                .put("reason", "不可观测（矢量内部）；父图标几何通过，来源hash有效；${entry.optString("source", "S1-D37")}；不计PASS或偏差")
            else row.put("status", "FAIL").put("category", "UI_DEVIATION")
                .put("reason", "不可观测标记前提不成立：本行选择器须命中父图标节点，且须为真实内部path、父group/icon几何通过、同名资产来源hash有效")
        }
        val iconPixels = ConformanceIconPixels.evaluate(layers, rowList, design, android)
        val missing = rowList.count { it.getString("status") == "MISSING" }
        val invisible = rowList.count { it.getString("category") == "INVISIBLE_OR_CLIPPED" }
        val uiDeviations = rowList.count { it.getString("category") == "UI_DEVIATION" }
        val passed = rowList.count { it.getString("status") == "PASS" }
        val unobservable = rowList.count { it.getString("status") == "UNOBSERVABLE_VECTOR_INTERNAL" }
        val unobservableColor = rowList.count { it.getString("status") == "UNOBSERVABLE_COLOR" }
        val boardFixPending = rowList.count { it.getString("status") == "BOARD_FIX_PENDING" }
        check(design.width == android.width && design.height == android.height)
        val ssim = ConformanceSsim.compare(design, android)
        ImageIO.write(ssim.heatmap(), "png", File(out, "$screen.ssim-heatmap.png"))
        val ssimReport = ssim.json(false).put("heatmap", "$screen.ssim-heatmap.png")
        val pendingRegions = JSONArray()
        rowList.filter { it.has("pendingBoardFix") }.forEach { row ->
            val layer = layers.single { it.getString("path") == row.getString("path") }
            val b = JSONObject().put("x",layer.getDouble("x")).put("y",layer.getDouble("y"))
                .put("w",layer.getDouble("w")).put("h",layer.getDouble("h"))
            val region = ssim.contribution((b.getDouble("x")*2).toInt(), (b.getDouble("y")*2).toInt(),
                ((b.getDouble("x")+b.getDouble("w"))*2).toInt(), ((b.getDouble("y")+b.getDouble("h"))*2).toInt())
            pendingRegions.put(region.put("path",row.getString("path")).put("name",row.getString("name")).put("boundsDp",b))
        }
        ssimReport.put("pendingBoardFixRegions", pendingRegions).put("pendingRegionNote", "按原始画稿 layer bounds 的窗口中心归因；区域可能重叠，不能相加；无屏蔽、无位移补偿。")
        val diff = BufferedImage(design.width, design.height, BufferedImage.TYPE_INT_RGB)
        var different = 0L
        for (y in 0 until design.height) for (x in 0 until design.width) {
            val a = design.getRGB(x, y); val b = android.getRGB(x, y)
            val d = maxOf(abs((a shr 16 and 255) - (b shr 16 and 255)), abs((a shr 8 and 255) - (b shr 8 and 255)), abs((a and 255) - (b and 255)))
            if (d > 0) different++
            diff.setRGB(x, y, if (d == 0) 0xffffff else (255 shl 16) or ((255-d) shl 8) or (255-d))
        }
        val triptych = BufferedImage(design.width * 3, design.height + 40, BufferedImage.TYPE_INT_RGB)
        triptych.createGraphics().apply {
            color = Color.WHITE; fillRect(0, 0, triptych.width, triptych.height)
            color = Color.BLACK; font = Font("SansSerif", Font.PLAIN, 18)
            drawString("Design / 画稿", 16, 27); drawString("Android", design.width + 16, 27); drawString("Diff / 差异", design.width * 2 + 16, 27)
            drawImage(design, 0, 40, null); drawImage(android, design.width, 40, null); drawImage(diff, design.width * 2, 40, null); dispose()
        }
        ImageIO.write(triptych, "png", File(out, "$screen.triptych.png"))
        val top = rowList.filter { it.has("delta") && it.getString("category") == "UI_DEVIATION" }.sortedByDescending { row -> listOf("x", "y", "w", "h").maxOf { abs(row.getJSONObject("delta").getDouble(it)) } }.take(10)
        val invalidCapture = capture?.optString("status") == "INVALID_CAPTURE"
        val manualExceptions = exceptions.count { e -> listOf("tag", "scope", "text", "commonLayoutParentOfTags", "anchor", "geometryRule").any(e::has) }
        val result = JSONObject().put("screen", screen).put("capture", capture ?: JSONObject.NULL).put("captureFailures", if (invalidCapture) 1 else 0)
            .put("outsideBoardLayers", exportedLayers.size - layers.size).put("partialVisibilityRule", "FULL_LAYOUT_GEOMETRY").put("colorTokenCount", tokens.size).put("colorTokenNames", JSONArray(tokens.map { it.name })).put("manualExceptionEntries", manualExceptions).put("manualExceptionRatio", manualExceptions.toDouble() / layers.size)
            .put("pendingBoardFixEntries", exceptions.count { it.has("pendingBoardFix") })
            .put("automaticMapped", rowList.count { it.getString("mapping").startsWith("AUTO") && it.has("actual") })
            .put("automaticMappingRate", rowList.count { it.getString("mapping").startsWith("AUTO") && it.has("actual") }.toDouble() / layers.size)
            .put("unmappedLayers", JSONArray(rowList.filter { !it.has("actual") }.map { JSONObject().put("path", it.getString("path")).put("name", it.getString("name")).put("reason", it.optString("reason")) }))
            .put("artifactStatus", if (invalidCapture) "INVALID_CAPTURE" else "VALID_FIXTURE").put("invisible", invisible).put("uiDeviations", uiDeviations).put("total", rows.length()).put("passed", passed).put("failed", rows.length() - passed - unobservable - unobservableColor - boardFixPending).put("boardFixPending", boardFixPending).put("missing", missing)
            .put("unobservableVectorInternal", unobservable).put("unobservableColor", unobservableColor)
            .put("toleranceDp", tolerance).put("measuredContentTop", contentTop).put("effectiveOriginOffsetY", offset)
            .put("originReason", map.getString("originRule")).put("differentPixelRatio", different.toDouble() / (design.width.toLong() * design.height))
            .put("sha256", sha(File(out, "$screen.android.png"))).put("elements", rows).put("top10", JSONArray(top))
            .put("humanReadSummary", "本轮未进行人工图片审查；以下分类依据节点、几何及像素证据。负责人视觉验收仍 PENDING。")
            .put("androidOnlyTextNodes", JSONArray(actual.filter { it.getInt("id") !in used && it.getString("text").isNotEmpty() }))
        result.put("relativeGeometry", relative)
        result.put("ICON_PIXELS", iconPixels)
        result.put("ssim", ssimReport)
        result.put("designPath", designPath)
        result.put("gatePassed", !invalidCapture && result.getInt("failed") == 0)
        return result
    }

    /** Both rows must have observed a node, and it must be the same node (same id). */
    internal fun vectorSelectorHitsParent(row: JSONObject, parentRow: JSONObject?): Boolean {
        val own = row.optJSONObject("actual") ?: return false
        val parentNode = parentRow?.optJSONObject("actual") ?: return false
        return row.optString("status") != "MISSING" && parentRow.optString("status") != "MISSING" &&
            own.has("id") && own.getInt("id") == parentNode.optInt("id", -1)
    }

    internal fun ad01Unobservable(parent: JSONObject?, entry: JSONObject, geometryPassed: Boolean, provenance: Boolean): Boolean =
        entry.optString("unobservable") == "AD01_VECTOR_INTERNAL" && parent != null &&
            parent.optString("type") in setOf("group", "icon") && parent.optString("path") == entry.optString("parentPath") &&
            ConformanceMapping.platformIcon(parent.optString("name")) == entry.optString("asset") &&
            entry.optString("source") == "AD-01 / S1-D28" && geometryPassed && provenance

    internal fun vectorUnobservable(layer: JSONObject, parent: JSONObject?, entry: JSONObject, parentGeometryPassed: Boolean, provenanceValid: Boolean): Boolean {
        val parentPath = entry.optString("parentPath")
        val asset = entry.optString("asset")
        return entry.optString("unobservable") == "VECTOR_INTERNAL_PATH" && asset.isNotBlank() &&
            layer.optString("type") == "path" && parent != null &&
            layer.optString("path").startsWith(parentPath + "/") && parent.optString("path") == parentPath &&
            parent.optString("type") in setOf("group", "icon") && ConformanceMapping.assetName(parent.optString("name")) == asset &&
            parentGeometryPassed && provenanceValid
    }

    internal fun provenanceValid(androidRoot: File, name: String): Boolean {
        if (name.isBlank()) return false
        val assets = File(androidRoot, "design-assets")
        for ((fileName, equipment) in listOf("equipment-provenance.json" to true, "material-symbols-provenance.json" to false)) {
            val file = File(assets, fileName)
            val record = JSONObject(file.readText()).getJSONArray("icons").objects().singleOrNull {
                it.optString(if (equipment) "name" else "symbol") == name
            } ?: continue
            val root = androidRoot.parentFile.canonicalFile
            val source = File(if (equipment) root else assets, record.getString(if (equipment) "source" else "sourceSvg")).canonicalFile
            val drawable = File(androidRoot, record.getString("drawable")).canonicalFile
            return listOf(source, drawable).all { it.toPath().startsWith(root.toPath()) && it.isFile } &&
                sha(source) == record.getString("sourceSha256") && sha(drawable) == record.getString("drawableSha256")
        }
        return false
    }

    internal fun select(actual: List<JSONObject>, entry: JSONObject, expand: (String) -> String = { it }): List<JSONObject> {
        if (entry.has("nodeID")) return actual.filter { it.optInt("id", -1) == entry.getInt("nodeID") }
        if (entry.has("commonLayoutParentOfTags")) return actual.filter {
            it.optJSONArray("commonLayoutParentOfTags")?.toString() == JSONArray(entry.getJSONArray("commonLayoutParentOfTags").strings().map(expand)).toString() &&
                it.optString("containsTag") == expand(entry.getString("containsTag"))
        }
        if (!entry.has("tag") && !entry.has("text") && !entry.has("scope")) return emptyList()
        return actual.filter { n ->
            (!entry.has("tag") || n.getString("tag") == expand(entry.getString("tag"))) &&
            (!entry.has("scope") || n.getString("tag") == expand(entry.getString("scope")) || expand(entry.getString("scope")) in n.getJSONArray("ancestors").strings()) &&
            (!entry.has("text") || n.getString("text") == expand(entry.getString("text")))
        }
    }

    /**
     * S1-D40 R2: a design text box is re-expressed in the token line-box model, keeping its center
     * (glyph position does not move): h = fontSize × the README line-height multiplier of the style
     * with that size and weight. Layers without font metadata keep their exported box.
     */
    internal fun tokenLineHeight(fontSize: Double, fontWeight: Int): Double {
        val styles = com.ignacioli.finecoach.designsystem.FcTypography.styles
        val sameSize = styles.filter { (_, s) -> s.fontSize.value.toDouble() == fontSize }
        val byWeight = sameSize.filter { (name, _) -> fontWeight in com.ignacioli.finecoach.designsystem.FcTypography.allowedWeights.getValue(name) }
        val multipliers = (byWeight.ifEmpty { sameSize }).keys.map { com.ignacioli.finecoach.designsystem.FcTypography.lineHeightMultipliers.getValue(it).toDouble() }.toSet()
        check(multipliers.size == 1) { "No unique README line-height token for ${fontSize}pt/$fontWeight: $multipliers" }
        return fontSize * multipliers.single()
    }

    /**
     * Map rules (both explicit per entry, never inferred):
     * - `geometryRule=SYMBOL_CENTER` (S1-D40 R4): a design text glyph that AD-01 maps to a Material
     *   symbol is compared as a `symbolSizeDp` square centered on the glyph box center.
     * - `geometryRule=EDITABLE_TEXT_FIELD` (S1-D42): the platform text field keeps its natural single-line
     *   minimum height outside the caller's modifiers, so the actual editor box is normalized to the design
     *   token line box around its own center; x, w and the center are judged, the raw height is reported.
     * - `pendingBoardFix` (S1-D42): a registered board drift awaiting a Penpot fix shifts the expected
     *   box by `dx`/`dy`; such a row is reported as BOARD_FIX_PENDING, never as PASS.
     */
    internal fun designBox(layer: JSONObject, rule: JSONObject? = null): JSONObject {
        val box = JSONObject().put("x", layer.getDouble("x")).put("y", layer.getDouble("y")).put("w", layer.getDouble("w")).put("h", layer.getDouble("h"))
        if (rule?.optString("geometryRule") == "SYMBOL_CENTER") {
            val size = rule.getDouble("symbolSizeDp")
            box.put("x", layer.getDouble("x") + layer.getDouble("w") / 2 - size / 2).put("y", layer.getDouble("y") + layer.getDouble("h") / 2 - size / 2)
                .put("w", size).put("h", size)
        } else if (layer.optString("type") == "text" && layer.has("fontSize")) {
            val h = tokenLineHeight(layer.getDouble("fontSize"), layer.optInt("fontWeight", 400))
            box.put("y", layer.getDouble("y") + layer.getDouble("h") / 2 - h / 2).put("h", h)
        }
        rule?.optJSONObject("pendingBoardFix")?.let { fix ->
            box.put("x", box.getDouble("x") + fix.optDouble("dx", 0.0)).put("y", box.getDouble("y") + fix.optDouble("dy", 0.0))
        }
        return box
    }

    private fun expectedBounds(layer: JSONObject, anchor: String, offset: Double, rule: JSONObject? = null): JSONObject {
        require(anchor in setOf("top", "bottom", "viewport")) { "Unknown anchor: $anchor" }
        if (anchor == "viewport") return JSONObject().put("x", 0).put("y", 0).put("w", 390).put("h", 844)
        val box = designBox(layer, rule)
        return box.put("y", box.getDouble("y") + if (anchor == "top") offset else 0.0)
    }

    internal fun geometry(actual: JSONObject, layer: JSONObject, anchor: String, offset: Double, tolerance: Double = 2.0, rule: JSONObject? = null): JSONObject {
        require(tolerance == 2.0) { "Approved tolerance is ±2dp" }
        val expected = expectedBounds(layer, anchor, offset, rule)
        val design = designBox(layer, rule)
        val rawActual = actual
        val layoutActual = actual.optJSONObject("unclipped") ?: actual
        @Suppress("NAME_SHADOWING") val actual = if (rule?.optString("geometryRule") == "EDITABLE_TEXT_FIELD") JSONObject(layoutActual.toString())
            .put("y", actual.getDouble("y") + actual.getDouble("h") / 2 - expected.getDouble("h") / 2).put("h", expected.getDouble("h")) else layoutActual
        val delta = JSONObject()
        val within = JSONObject()
        for (axis in listOf("x", "y", "w", "h")) {
            val value = if (axis == "y" && anchor == "bottom")
                (844.0 - actual.getDouble("y") - actual.getDouble("h")) - (844.0 - design.getDouble("y") - design.getDouble("h"))
            else actual.getDouble(axis) - expected.getDouble(axis)
            delta.put(axis, value); within.put(axis, abs(value) <= if (axis in listOf("x", "y")) 8.0 else tolerance)
        }
        val text = layer.optString("type") == "text"
        if (text) {
            val center = actual.getDouble("y") + actual.getDouble("h") / 2 - expected.getDouble("y") - expected.getDouble("h") / 2
            delta.put("centerY", center); within.put("centerY", abs(center) <= tolerance)
        }
        return JSONObject().put("delta", delta).put("withinTolerance", within)
            .put("actualBounds", actual).put("expectedBounds", expected)
            .put("matches", listOf("x", "y", "w", "h").all { within.getBoolean(it) })
            .put("comparisonAxes", JSONArray(listOf("x", "y", "w", "h")))
            .put("textLineBox", if (text) "TOKEN_LINE_HEIGHT_CENTERED" else JSONObject.NULL)
            .put("rawYDelta", actual.getDouble("y") - layer.getDouble("y"))
            .apply { if (rawActual !== actual) put("editableTextField", JSONObject().put("rawH", rawActual.getDouble("h")).put("rawY", rawActual.getDouble("y"))) }
            .put("yComparison", if (anchor == "bottom") "BOTTOM_GAP" else if (anchor == "viewport") "VIEWPORT_NOT_APPLICABLE_TO_TOP_ORIGIN" else "TOP_POSITION_WITH_ORIGIN")
            .apply { if (anchor == "bottom") {
                put("designBottomGap", 844.0 - design.getDouble("y") - design.getDouble("h"))
                put("actualBottomGap", 844.0 - actual.getDouble("y") - actual.getDouble("h"))
            } }
    }

    /** Visibility is geometric only. Sibling overlay occlusion cannot be inferred. */
    internal fun visibility(node: JSONObject): JSONObject {
        val raw = node.getJSONObject("unclipped")
        fun positive(rect: JSONObject) = rect.getDouble("w") > 0 && rect.getDouble("h") > 0
        fun outside(a: JSONObject, b: JSONObject) = a.getDouble("x") + a.getDouble("w") <= b.getDouble("x") ||
            a.getDouble("y") + a.getDouble("h") <= b.getDouble("y") || a.getDouble("x") >= b.getDouble("x") + b.getDouble("w") ||
            a.getDouble("y") >= b.getDouble("y") + b.getDouble("h")
        fun contained(a: JSONObject, b: JSONObject) = a.getDouble("x") >= b.getDouble("x") && a.getDouble("y") >= b.getDouble("y") &&
            a.getDouble("x") + a.getDouble("w") <= b.getDouble("x") + b.getDouble("w") && a.getDouble("y") + a.getDouble("h") <= b.getDouble("y") + b.getDouble("h")
        val viewport = JSONObject().put("x", 0).put("y", 0).put("w", 390).put("h", 844)
        val scroll = node.getJSONArray("scrollAncestors").objects().firstOrNull { !contained(raw, it) }
        val state: String
        val reason: String
        when {
            !node.optBoolean("attached", true) || !node.optBoolean("placed", true) -> { state = "NOT_PLACED"; reason = "节点未 attached/placed，不能作为可见元素通过。" }
            !positive(raw) -> { state = "ZERO_LAYOUT"; reason = "节点自身布局为零；不是缺失节点，是否被条件隐藏未确认。" }
            scroll != null -> { state = if (outside(raw, scroll)) "OUTSIDE_SCROLL_VIEWPORT" else "PARTIALLY_CLIPPED_BY_SCROLL"; reason = "超出滚动容器 ${scroll.getString("tag")} 可视区；需要滚动才能完整呈现，本 fixture 未滚动。页面 rest/finish 为滚动容器之后的同级布局，不能据此声称被浮层遮挡。" }
            outside(raw, viewport) -> { state = "OUTSIDE_VIEWPORT"; reason = "布局位于390×844视口外；是否可滚动到达未确认。" }
            !positive(node) -> { state = "ZERO_CLIPPED_BOUNDS"; reason = "自身布局非零但 clipped bounds 为零；祖先裁剪，具体遮挡未确认。" }
            !contained(raw, viewport) || node.getDouble("w") < raw.getDouble("w") - 0.01 || node.getDouble("h") < raw.getDouble("h") - 0.01 -> { state = "PARTIALLY_CLIPPED"; reason = "节点仅部分可见；视口或祖先裁剪。" }
            else -> { state = "VISIBLE"; reason = "布局及 clipped bounds 完整位于视口内；不证明不存在同级绘制遮挡。" }
        }
        return JSONObject().put("state", state).put("reason", reason).put("needsScroll", scroll != null).put("occlusion", "UNVERIFIED")
    }

    fun writeReports(out: File, result: JSONObject) {
        val screen = result.optString("screen", "P0-a2-training")
        File(out, "$screen.report.json").writeText(result.toString(2))
        val rows = result.getJSONArray("elements").objects()
        File(out, "$screen.report.md").writeText(buildString {
            appendLine("# $screen 设计一致性")
            appendLine("自动映射率=${result.optDouble("automaticMappingRate")}；例外=${result.optInt("manualExceptionEntries")}/${result.getInt("total")}；未映射=${result.optJSONArray("unmappedLayers")}")
            appendLine("\nartifactStatus=${result.getString("artifactStatus")}；总数 ${result.getInt("total")}；通过 ${result.getInt("passed")}；失败 ${result.getInt("failed")}（UI 偏差 ${result.getInt("uiDeviations")}、missing ${result.getInt("missing")}、不可见/裁剪 ${result.getInt("invisible")}）；像素差异比例 ${result.getDouble("differentPixelRatio")}")
            result.optJSONObject("ssim")?.let { metric ->
                appendLine("\n## 整屏 SSIM\n\n全局=${metric.getDouble("global")}；最低48dp横条=${metric.getDouble("minimumStrip")}；阈值=${metric.getDouble("globalThreshold")}/${metric.getDouble("minimumStripThreshold")}；门禁=${metric.getBoolean("gated")}；达标=${metric.getBoolean("thresholdPassed")}；热力图=${metric.getString("heatmap")}（绿=1，红=0或负值，灰=无完整窗口的5px边缘）。")
                appendLine("最低5块（y范围半开，px/dp）：${metric.getJSONArray("lowest5")}")
                appendLine("pendingBoardFix 区域贡献（未屏蔽）：${metric.getJSONArray("pendingBoardFixRegions")}")
            }
            result.optJSONObject("ssimCalibration")?.let { calibration ->
                appendLine("\nSSIM 校准：${calibration.getString("mutations")}")
                appendLine("| 样本 | 全局SSIM | 最低横条SSIM | 通过 |")
                appendLine("|---|---:|---:|---|")
                calibration.getJSONArray("samples").objects().forEach { sample ->
                    appendLine("| ${sample.getString("sample")} | ${sample.getDouble("global")} | ${sample.getDouble("minimumStrip")} | ${sample.getBoolean("thresholdPassed")} |")
                }
            }
            appendLine("\n画板待改（已登记，S1-D42）：${result.optInt("boardFixPending")}，不计入PASS或偏差；画板修正并重新导出后撤掉登记。")
            appendLine("\n不可观测（矢量内部）：${result.getInt("unobservableVectorInternal")}，不计入PASS或偏差。仅父图标几何通过且同名资产来源hash验证通过时成立（S1-D37）。")
            appendLine("\noriginOffsetY=${result.getDouble("effectiveOriginOffsetY")}；Android content top=${result.getDouble("measuredContentTop")}；${result.getString("originReason")}")
            result.optJSONObject("stability")?.let { appendLine("\n双次 fresh Room/composition 渲染：$it") }
            appendLine("\nS1-D40 R2：画稿文字框以中心为准换算为 token 行盒（高 = 字号 × README 行高倍率），尺寸、间距、内边距与对齐的Δ先按S1-D56取最近0.25dp，再采用±2dp含边界；绝对坐标±8dp粗界限，界内仅诊断。ΔcenterY 仅报告。top原点、bottom底距规则不变，无新增偏移。")
            appendLine("\n| path | 元素 | anchor | 容差dp | Δx | Δy | Δw | Δh | ΔcenterY(报告) | text | token | category | 原因 |")
            appendLine("|---|---|---|---:|---:|---:|---:|---:|---:|---|---|---|---|")
            rows.forEach { r ->
                val d = r.optJSONObject("delta")
                appendLine("| ${r.getString("path")} | ${r.getString("name")} | ${r.getString("anchor")} | ±${r.getDouble("toleranceDp")} | ${d?.optDouble("x")} | ${d?.optDouble("y")} | ${d?.optDouble("w")} | ${d?.optDouble("h")} | ${if (d?.has("centerY") == true) d.getDouble("centerY") else "N/A"} | ${r.getBoolean("textMatches")} | ${r.optString("tokenComparison", "MISSING")} | ${r.getString("category")} ${r.optJSONArray("failedChecks")} | ${r.optString("reason").ifEmpty { r.optJSONObject("visibility")?.optString("reason") ?: "" }} |")
            }
            appendLine("\n## ICON_PIXELS\n\n每个父图标中心对齐，ink IoU ≥ ${ConformanceIconPixels.minimumIou}，背景 RGB 最大通道差 > ${ConformanceIconPixels.inkThreshold}。AD-01 不适用。")
            result.getJSONObject("ICON_PIXELS").getJSONArray("checks").objects().forEach { appendLine("- ${it.getString("path")} ${it.getString("name")}: ${it.getString("status")}; IoU=${it.opt("iou")}; scale1.4=${it.opt("scale1_4Iou")}") }
            appendLine("\n## relative-spacing diagnostics\n\n${result.optJSONObject("relativeGeometry")?.optJSONObject("counts")}")
            appendLine("| A→B | direction | design | actual | raw Δ | rounded Δ | ")
            appendLine("|---|---|---:|---:|---:|---:|")
            result.getJSONObject("relativeGeometry").getJSONArray("gaps").objects()
                .sortedByDescending { abs(it.getDouble("delta")) }.take(10).forEach {
                    appendLine("| ${it.getString("a")}→${it.getString("b")} | ${it.getString("direction")} | ${it.getDouble("design")} | ${it.getDouble("actual")} | ${it.getDouble("delta")} | ${it.getDouble("roundedDelta")} |")
                }
            appendLine("\n## 人读摘要\n\n${result.getString("humanReadSummary")}")
            appendLine("\n颜色读取：文字来自真实 TextLayoutResult；填充来自节点矩形内未被后序 mapped layer 遮挡的 exact RGB 众数（Android 用实测 bounds，design 用导出 bounds）；完全遮挡记 UNOBSERVABLE_COLOR，不计 PASS；iconInk 排除节点边界采样的背景众数后取实际众数，无近色匹配。无颜色观测写 UNOBSERVABLE，不能据此声称真实 token 不一致，仍不通过。README 所有 primitive/semantic token 均自动读取，保留同色 aliases；按精确 RGB 比较。带 opacity 的填色按前序覆盖背景逐层 source-over，不使用近色容差。")
            appendLine("\nmissing 表示无可定位的独立 semantics 节点，不证明屏幕上没有图形。mapped bounds 若是触控容器而非内部图形，只能证明容器与图层几何不同，不能宣称图形轮廓错误。不可见/裁剪节点单列失败，不把零 bounds 的位移混入 UI 偏差 top10。")
        })
    }
    internal fun contentTop(nodes: List<JSONObject>): Double =
        nodes.filter { it.optString("tag") == "platform-content" }.single().getDouble("y")

    /** Layout color is a source, not proof that text ink reached the screenshot. */
    internal fun observedTextColor(image: BufferedImage, n: JSONObject, occluders: List<JSONObject> = emptyList()): String? {
        val source = n.optString("hex", "").takeUnless { it == "null" || it.isEmpty() } ?: return null
        val alpha = n.optDouble("alpha", 1.0)
        val color = if (alpha == 1.0) source else {
            val background = pixelMode(image, n, occluders = occluders) ?: return null
            ConformanceColors.composite(source, alpha, background)
        }
        val rgb = color.removePrefix("#").toInt(16)
        val left = (n.getDouble("x") * 2).toInt().coerceIn(0, image.width)
        val top = (n.getDouble("y") * 2).toInt().coerceIn(0, image.height)
        val right = ((n.getDouble("x") + n.getDouble("w")) * 2).toInt().coerceIn(0, image.width)
        val bottom = ((n.getDouble("y") + n.getDouble("h")) * 2).toInt().coerceIn(0, image.height)
        val uncovered = uncoveredPredicate(occluders)
        return color.takeIf { (top until bottom).any { y -> (left until right).any { x -> uncovered(x, y) && image.getRGB(x, y) and 0xffffff == rgb } } }
    }

    private fun uniqueMode(counts: Map<Int, Int>): Int? {
        val max = counts.values.maxOrNull() ?: return null
        return counts.filterValues { it == max }.keys.singleOrNull()
    }

    internal fun pixelMode(image: BufferedImage, n: JSONObject, inkOnly: Boolean = false, occluders: List<JSONObject> = emptyList()): String? {
        val uncovered = uncoveredPredicate(occluders)
        val counts = mutableMapOf<Int, Int>()
        val left = (n.getDouble("x") * 2).toInt().coerceIn(0, image.width)
        val top = (n.getDouble("y") * 2).toInt().coerceIn(0, image.height)
        val right = ((n.getDouble("x") + n.getDouble("w")) * 2).toInt().coerceIn(0, image.width)
        val bottom = ((n.getDouble("y") + n.getDouble("h")) * 2).toInt().coerceIn(0, image.height)
        val boundary = mutableMapOf<Int, Int>()
        if (inkOnly && left < right && top < bottom) {
            for (x in left until right) for (y in listOf(top, bottom - 1)) {
                if (!uncovered(x, y)) continue
                val rgb = image.getRGB(x, y) and 0xffffff; boundary[rgb] = (boundary[rgb] ?: 0) + 1
            }
            for (y in top until bottom) for (x in listOf(left, right - 1)) {
                if (!uncovered(x, y)) continue
                val rgb = image.getRGB(x, y) and 0xffffff; boundary[rgb] = (boundary[rgb] ?: 0) + 1
            }
        }
        val background = uniqueMode(boundary)
        if (inkOnly && background == null) return null
        for (y in top until bottom) for (x in left until right) {
            if (!uncovered(x, y)) continue
            val rgb = image.getRGB(x,y) and 0xffffff
            if (!inkOnly || rgb != background) counts[rgb] = (counts[rgb] ?: 0) + 1
        }
        return uniqueMode(counts)?.let { "#%06x".format(it) }
    }
    /** Same half-open raster bounds as the existing crop; stacking order is supplied by the export. */
    private fun uncoveredPredicate(occluders: List<JSONObject>): (Int, Int) -> Boolean {
        val boxes = occluders.map { intArrayOf((it.getDouble("x") * 2).toInt(), (it.getDouble("y") * 2).toInt(),
            ((it.getDouble("x") + it.getDouble("w")) * 2).toInt(), ((it.getDouble("y") + it.getDouble("h")) * 2).toInt()) }
        return { x, y -> boxes.none { x >= it[0] && x < it[2] && y >= it[1] && y < it[3] } }
    }
    internal fun hasUncoveredPixels(image: BufferedImage, n: JSONObject, occluders: List<JSONObject>): Boolean {
        val uncovered = uncoveredPredicate(occluders)
        val left = (n.getDouble("x") * 2).toInt().coerceIn(0, image.width)
        val top = (n.getDouble("y") * 2).toInt().coerceIn(0, image.height)
        val right = ((n.getDouble("x") + n.getDouble("w")) * 2).toInt().coerceIn(0, image.width)
        val bottom = ((n.getDouble("y") + n.getDouble("h")) * 2).toInt().coerceIn(0, image.height)
        return (top until bottom).any { y -> (left until right).any { x -> uncovered(x, y) } }
    }
    private fun sha(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
    private fun JSONArray.objects() = (0 until length()).map { getJSONObject(it) }
    private fun JSONArray.strings() = (0 until length()).map { getString(it) }
}
