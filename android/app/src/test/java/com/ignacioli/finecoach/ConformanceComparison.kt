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
    fun run(androidRoot: File, out: File, nodes: JSONArray, bindings: Map<String, String>): JSONObject {
        val assets = File(androidRoot, "design-assets/conformance")
        val layers = JSONObject(File(assets, "P0-a2-training.layers.json").readText()).getJSONArray("layers").objects()
        val map = JSONObject(File(assets, "P0-a2-training.map.json").readText())
        val entries = map.getJSONArray("elements").objects()
        check(entries.map { it.getString("path") }.toSet() == layers.map { it.getString("path") }.toSet() && entries.size == layers.size) { "Map must cover every unique exported layer exactly once" }
        val actual = nodes.objects()
        val contentTop = actual.single { it.getString("tag") == "platform-content" }.getDouble("y")
        val offset = map.getDouble("originOffsetY") + contentTop
        val tolerance = map.getDouble("toleranceDp")
        check(tolerance == 2.0) { "Approved tolerance is ±2dp" }
        val android = ImageIO.read(File(out, "P0-a2-training.android.png"))
        val tokens = parseTokens(File(androidRoot.parentFile, "design/design-system/README.md"))
        fun expand(raw: String): String {
            var value = raw
            bindings.entries.sortedByDescending { it.key.length }.forEach { (key, replacement) -> value = value.replace("$$key", replacement) }
            return value
        }
        fun hexToken(hex: String?): String? = hex?.let { tokens[it.lowercase()] }
        val rows = JSONArray()
        val used = mutableSetOf<Int>()
        for (entry in entries) {
            val layer = layers.single { it.getString("path") == entry.getString("path") }
            val candidates = select(actual, entry, ::expand)
            val n = candidates.singleOrNull()
            val anchor = entry.getString("anchor")
            val expected = expectedBounds(layer, anchor, offset)
            val row = JSONObject().put("path", layer.getString("path")).put("name", layer.getString("name"))
                .put("anchor", anchor).put("toleranceDp", tolerance).put("topOriginApplied", anchor == "top")
                .put("expectedText", layer.optString("text", "")).put("selector", entry)
                .put("expected", expected)
            if (n == null) {
                row.put("status", "MISSING").put("category", "MISSING").put("visibility", JSONObject.NULL).put("reason", if (candidates.size > 1) "ambiguous: ${candidates.size} nodes" else entry.optString("missingReason", "selector has no matching node (含原文 selector 不匹配；不能据此认定 UI 图形不存在)"))
                    .put("textMatches", false).put("tokenMatches", false)
            } else {
                used += n.getInt("id")
                val geometry = geometry(n, layer, anchor, offset, tolerance)
                val deltas = geometry.getJSONObject("delta")
                val textMatches = !layer.has("text") || layer.getString("text") == n.getString("text")
                val expectedHex = layer.optString("fill", "").ifEmpty { layer.optJSONObject("stroke")?.optString("color").orEmpty() }
                val expectedToken = hexToken(expectedHex)
                check(expectedToken == (if (entry.isNull("expectedToken")) null else entry.getString("expectedToken"))) { "Token map drift at ${layer.getString("path")}" }
                val observedHex = if (entry.getString("colorMethod") == "textLayout") n.optString("hex", "").takeUnless { it == "null" || it.isEmpty() }
                    else pixelMode(android, n, entry.getString("colorMethod") == "iconInk")
                val observedToken = hexToken(observedHex)
                val tokenObservable = expectedHex.isEmpty() || observedHex != null
                val tokenMatches = tokenObservable && (expectedHex.isEmpty() || expectedToken != null && expectedToken == observedToken)
                val visibility = visibility(n)
                val visible = visibility.getString("state") == "VISIBLE"
                val geometryMatches = geometry.getBoolean("matches")
                row.put("actual", n).put("delta", deltas).put("geometry", geometry).put("textMatches", textMatches)
                    .put("expectedToken", expectedToken ?: JSONObject.NULL).put("actualToken", observedToken ?: JSONObject.NULL)
                    .put("colorObservation", if (observedHex == null) "UNOBSERVABLE" else "OBSERVED")
                    .put("observedHex", observedHex ?: JSONObject.NULL).put("tokenMatches", if (tokenObservable) tokenMatches else JSONObject.NULL)
                    .put("tokenComparison", if (expectedHex.isEmpty()) "NOT_APPLICABLE" else if (!tokenObservable) "UNOBSERVABLE" else if (tokenMatches) "MATCH" else "MISMATCH")
                    .put("visibility", visibility).put("geometryMatches", geometryMatches)
                    .put("category", if (!visible) "INVISIBLE_OR_CLIPPED" else if (geometryMatches && textMatches && tokenMatches) "PASS" else "UI_DEVIATION")
                    .put("status", if (visible && geometryMatches && textMatches && tokenMatches) "PASS" else "FAIL")
            }
            rows.put(row)
        }
        val rowList = rows.objects()
        for (entry in entries.filter { it.has("unobservable") }) {
            val layer = layers.single { it.getString("path") == entry.getString("path") }
            val parent = layers.singleOrNull { it.getString("path") == entry.optString("parentPath") }
            val parentRow = rowList.singleOrNull { it.getString("path") == entry.optString("parentPath") }
            val row = rowList.single { it.getString("path") == entry.getString("path") }
            val evidence = provenanceValid(androidRoot, entry.optString("asset"))
            val valid = vectorUnobservable(layer, parent, entry, parentRow?.optBoolean("geometryMatches") == true, evidence)
            row.put("parentGeometryPassed", parentRow?.optBoolean("geometryMatches") == true).put("assetProvenanceVerified", evidence)
            if (valid) row.put("status", "UNOBSERVABLE_VECTOR_INTERNAL").put("category", "UNOBSERVABLE_VECTOR_INTERNAL")
                .put("reason", "不可观测（矢量内部）；父图标几何通过，源SVG/drawable与来源记录hash一致；不计PASS或偏差")
            else row.put("status", "FAIL").put("category", "UI_DEVIATION")
                .put("reason", "不可观测标记前提不成立：须批准的内部path、父group/icon几何通过且同名资产来源hash有效")
        }
        val missing = rowList.count { it.getString("status") == "MISSING" }
        val invisible = rowList.count { it.getString("category") == "INVISIBLE_OR_CLIPPED" }
        val uiDeviations = rowList.count { it.getString("category") == "UI_DEVIATION" }
        val passed = rowList.count { it.getString("status") == "PASS" }
        val unobservable = rowList.count { it.getString("status") == "UNOBSERVABLE_VECTOR_INTERNAL" }
        val design = ImageIO.read(File(androidRoot.parentFile, "design/experience-p0/screens/P0-a2-training.png"))
        check(design.width == android.width && design.height == android.height)
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
        ImageIO.write(triptych, "png", File(out, "P0-a2-training.triptych.png"))
        val top = rowList.filter { it.has("delta") && it.getString("category") == "UI_DEVIATION" }.sortedByDescending { row -> listOf("x", "y", "w", "h").maxOf { abs(row.getJSONObject("delta").getDouble(it)) } }.take(10)
        val result = JSONObject().put("artifactStatus", "VALID_FIXTURE").put("invisible", invisible).put("uiDeviations", uiDeviations).put("total", rows.length()).put("passed", passed).put("failed", rows.length() - passed - unobservable).put("missing", missing)
            .put("unobservableVectorInternal", unobservable)
            .put("toleranceDp", tolerance).put("measuredContentTop", contentTop).put("effectiveOriginOffsetY", offset)
            .put("originReason", map.getString("originRule")).put("differentPixelRatio", different.toDouble() / (design.width.toLong() * design.height))
            .put("sha256", sha(File(out, "P0-a2-training.android.png"))).put("elements", rows).put("top10", JSONArray(top))
            .put("humanReadSummary", "本轮未打开新图；上轮仅对无效 fixture 进行过一次图片清单审查，其结论不移植为本轮有效图的人工判断。以下分类与摘要依据节点和几何文字证据；负责人视觉验收仍 PENDING。")
            .put("androidOnlyTextNodes", JSONArray(actual.filter { it.getInt("id") !in used && it.getString("text").isNotEmpty() }))
        return result
    }

    internal fun vectorUnobservable(layer: JSONObject, parent: JSONObject?, entry: JSONObject, parentGeometryPassed: Boolean, provenanceValid: Boolean): Boolean {
        val approved = mapOf("7/1" to ("7" to "barbell"), "33/1" to ("33" to "barbell"),
            "45/1" to ("45" to "edit"), "46/1" to ("46" to "edit"))
        val pair = approved[layer.optString("path")] ?: return false
        return entry.optString("unobservable") == "VECTOR_INTERNAL_PATH" && entry.optString("parentPath") == pair.first &&
            entry.optString("asset") == pair.second && layer.optString("type") == "path" && parent != null &&
            parent.optString("path") == pair.first && parent.optString("type") in setOf("group", "icon") &&
            parent.optString("name").contains(pair.second) && parentGeometryPassed && provenanceValid
    }

    private fun provenanceValid(androidRoot: File, name: String): Boolean {
        if (name !in setOf("barbell", "edit")) return false
        val equipment = name == "barbell"
        val assets = File(androidRoot, "design-assets")
        val file = File(assets, if (equipment) "equipment-provenance.json" else "material-symbols-provenance.json")
        val record = JSONObject(file.readText()).getJSONArray("icons").objects().singleOrNull {
            it.optString(if (equipment) "name" else "symbol") == name
        } ?: return false
        val root = androidRoot.parentFile.canonicalFile
        val source = File(if (equipment) root else assets, record.getString(if (equipment) "source" else "sourceSvg")).canonicalFile
        val drawable = File(androidRoot, record.getString("drawable")).canonicalFile
        return listOf(source, drawable).all { it.toPath().startsWith(root.toPath()) && it.isFile } &&
            sha(source) == record.getString("sourceSha256") && sha(drawable) == record.getString("drawableSha256")
    }

    internal fun select(actual: List<JSONObject>, entry: JSONObject, expand: (String) -> String = { it }): List<JSONObject> {
        if (entry.has("commonLayoutParentOfTags")) return actual.filter {
            it.optJSONArray("commonLayoutParentOfTags")?.toString() == entry.getJSONArray("commonLayoutParentOfTags").toString() &&
                it.optString("containsTag") == entry.getString("containsTag")
        }
        if (!entry.has("tag") && !entry.has("text") && !entry.has("scope")) return emptyList()
        return actual.filter { n ->
            (!entry.has("tag") || n.getString("tag") == expand(entry.getString("tag"))) &&
            (!entry.has("scope") || n.getString("tag") == expand(entry.getString("scope")) || expand(entry.getString("scope")) in n.getJSONArray("ancestors").strings()) &&
            (!entry.has("text") || n.getString("text") == entry.getString("text"))
        }
    }

    private fun expectedBounds(layer: JSONObject, anchor: String, offset: Double): JSONObject {
        require(anchor in setOf("top", "bottom", "viewport")) { "Unknown anchor: $anchor" }
        return if (anchor == "viewport") JSONObject().put("x", 0).put("y", 0).put("w", 390).put("h", 844)
        else JSONObject().put("x", layer.getDouble("x")).put("y", layer.getDouble("y") + if (anchor == "top") offset else 0.0)
            .put("w", layer.getDouble("w")).put("h", layer.getDouble("h"))
    }

    internal fun geometry(actual: JSONObject, layer: JSONObject, anchor: String, offset: Double, tolerance: Double = 2.0): JSONObject {
        require(tolerance == 2.0) { "Approved tolerance is ±2dp" }
        val expected = expectedBounds(layer, anchor, offset)
        val delta = JSONObject()
        val within = JSONObject()
        for (axis in listOf("x", "y", "w", "h")) {
            val value = if (axis == "y" && anchor == "bottom")
                (844.0 - actual.getDouble("y") - actual.getDouble("h")) - (844.0 - layer.getDouble("y") - layer.getDouble("h"))
            else actual.getDouble(axis) - expected.getDouble(axis)
            delta.put(axis, value); within.put(axis, abs(value) <= tolerance)
        }
        val text = layer.optString("type") == "text"
        if (text) {
            val center = actual.getDouble("y") + actual.getDouble("h") / 2 - expected.getDouble("y") - expected.getDouble("h") / 2
            delta.put("centerY", center); within.put("centerY", abs(center) <= tolerance)
        }
        return JSONObject().put("delta", delta).put("withinTolerance", within)
            .put("matches", (if (text) listOf("x", "w", "centerY") else listOf("x", "y", "w", "h")).all { within.getBoolean(it) })
            .put("comparisonAxes", JSONArray(if (text) listOf("x", "w", "centerY") else listOf("x", "y", "w", "h")))
            .put("heightReportOnly", text)
            .put("rawYDelta", actual.getDouble("y") - layer.getDouble("y"))
            .put("yComparison", if (anchor == "bottom") "BOTTOM_GAP" else if (anchor == "viewport") "VIEWPORT_NOT_APPLICABLE_TO_TOP_ORIGIN" else "TOP_POSITION_WITH_ORIGIN")
            .apply { if (anchor == "bottom") {
                put("designBottomGap", 844.0 - layer.getDouble("y") - layer.getDouble("h"))
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
        File(out, "P0-a2-training.report.json").writeText(result.toString(2))
        val rows = result.getJSONArray("elements").objects()
        File(out, "P0-a2-training.report.md").writeText(buildString {
            appendLine("# P0-a2 训练页设计一致性")
            appendLine("\nartifactStatus=${result.getString("artifactStatus")}；总数 ${result.getInt("total")}；通过 ${result.getInt("passed")}；失败 ${result.getInt("failed")}（UI 偏差 ${result.getInt("uiDeviations")}、missing ${result.getInt("missing")}、不可见/裁剪 ${result.getInt("invisible")}）；像素差异比例 ${result.getDouble("differentPixelRatio")}")
            appendLine("\n不可观测（矢量内部）：${result.getInt("unobservableVectorInternal")}，不计入PASS或偏差。仅父图标几何通过且同名资产来源hash验证通过时成立（S1-D37）。")
            appendLine("\noriginOffsetY=${result.getDouble("effectiveOriginOffsetY")}；Android content top=${result.getDouble("measuredContentTop")}；${result.getString("originReason")}")
            result.optJSONObject("stability")?.let { appendLine("\n双次 fresh Room/composition 渲染：$it") }
            appendLine("\nS1-D37：文字仅判定x/w/垂直中心，Δh只报告；其余图形x/y/w/h各自判定。容差均为±2dp含边界。top原点、bottom底距规则不变，文字中心按各anchor的expected矩形计算，无新增偏移。")
            appendLine("\n| path | 元素 | anchor | 容差dp | Δx | Δy | Δw | Δh(文字仅报告) | ΔcenterY | text | token | category | 原因 |")
            appendLine("|---|---|---|---:|---:|---:|---:|---:|---:|---|---|---|---|")
            rows.forEach { r ->
                val d = r.optJSONObject("delta")
                appendLine("| ${r.getString("path")} | ${r.getString("name")} | ${r.getString("anchor")} | ±${r.getDouble("toleranceDp")} | ${d?.optDouble("x")} | ${d?.optDouble("y")} | ${d?.optDouble("w")} | ${d?.optDouble("h")} | ${if (d?.has("centerY") == true) d.getDouble("centerY") else "N/A"} | ${r.getBoolean("textMatches")} | ${r.optString("tokenComparison", "MISSING")} | ${r.getString("category")} | ${r.optString("reason").ifEmpty { r.optJSONObject("visibility")?.optString("reason") ?: "" }} |")
            }
            appendLine("\n## 人读摘要\n\n${result.getString("humanReadSummary")}")
            appendLine("\n颜色读取：文字来自真实 TextLayoutResult；填充来自节点矩形内 exact RGB 众数；iconInk 排除白底/canvas 后取实际众数，无近色匹配。无颜色观测写 UNOBSERVABLE，不能据此声称真实 token 不一致，仍不通过。相同 hex 的 token aliases 归一到 map 使用的语义 token。")
            appendLine("\nmissing 表示无可定位的独立 semantics 节点，不证明屏幕上没有图形。mapped bounds 若是触控容器而非内部图形，只能证明容器与图层几何不同，不能宣称图形轮廓错误。不可见/裁剪节点单列失败，不把零 bounds 的位移混入 UI 偏差 top10。")
        })
    }
    private fun pixelMode(image: BufferedImage, n: JSONObject, inkOnly: Boolean = false): String? {
        val counts = mutableMapOf<Int, Int>()
        val left = (n.getDouble("x") * 2).toInt().coerceIn(0, image.width)
        val top = (n.getDouble("y") * 2).toInt().coerceIn(0, image.height)
        val right = ((n.getDouble("x") + n.getDouble("w")) * 2).toInt().coerceIn(0, image.width)
        val bottom = ((n.getDouble("y") + n.getDouble("h")) * 2).toInt().coerceIn(0, image.height)
        for (y in top until bottom) for (x in left until right) { val rgb = image.getRGB(x,y) and 0xffffff; if (!inkOnly || rgb != 0xffffff && rgb != 0xf7f4ee) counts[rgb] = (counts[rgb] ?: 0) + 1 }
        return counts.maxByOrNull { it.value }?.key?.let { "#%06x".format(it) }
    }
    private fun parseTokens(readme: File): Map<String, String> {
        val names = setOf("surface.page", "text.primary", "text.secondary", "action.primary", "surface.canvas", "surface.divider")
        val result = mutableMapOf<String,String>()
        val pattern = Regex("\\| `color\\.([^`]+)` \\|[^\\n]*?`(#[0-9A-Fa-f]{6})`")
        pattern.findAll(readme.readText()).forEach { m -> if (m.groupValues[1] in names) result[m.groupValues[2].lowercase()] = "color.${m.groupValues[1]}" }
        check(result.size == names.size) { "Cannot resolve required README token names" }; return result
    }
    private fun sha(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
    private fun JSONArray.objects() = (0 until length()).map { getJSONObject(it) }
    private fun JSONArray.strings() = (0 until length()).map { getString(it) }
}
