package com.ignacioli.finecoach

import com.ignacioli.finecoach.designsystem.FcTypography
import java.io.File
import java.security.MessageDigest
import kotlin.math.abs
import org.json.JSONArray
import org.json.JSONObject

/** Read-only design lint. Findings are design conflicts/review candidates, never changes to comparison rules. */
internal object ConformancePrecheck {
    private fun JSONArray.objects() = (0 until length()).map { getJSONObject(it) }
    fun inspect(board: JSONObject, readme: String, anatomy: String): JSONObject {
        val layers = board.getJSONArray("layers").objects()
        val colors = ConformanceColors.tokens(readme)
        val spaces = Regex("\\| `space\\.(\\d+)` \\| (\\d+)").findAll(readme).associate { "space.${it.groupValues[1]}" to it.groupValues[2].toDouble() }
        require(spaces.isNotEmpty()) { "No README spacing tokens" }
        val findings = JSONArray()
        fun finding(layer: JSONObject, rule: String, actual: Any, expected: Any, source: String, certainty: String = "CONFLICT") {
            findings.put(JSONObject().put("path", layer.getString("path")).put("name", layer.getString("name"))
                .put("rule", rule).put("actual", actual).put("expected", expected).put("source", source).put("certainty", certainty))
        }
        for (layer in layers) {
            val fill = layer.optString("fill", "").ifEmpty { layer.optJSONObject("stroke")?.optString("color").orEmpty() }
            if (fill.isNotEmpty() && colors.none { it.hex == fill.lowercase() }) finding(layer, "NON_TOKEN_COLOR", fill, "README color tokens", "README §2")
            if (layer.optString("type") != "text" || !layer.has("fontSize")) continue
            val size = layer.getDouble("fontSize")
            val weight = layer.optInt("fontWeight", 400)
            val sameSize = FcTypography.styles.filter { it.value.fontSize.value.toDouble() == size }
            val matching = sameSize.filter { weight in FcTypography.allowedWeights.getValue(it.key) }
            if (sameSize.isEmpty()) finding(layer, "NON_TOKEN_FONT_SIZE", size, FcTypography.styles.values.map { it.fontSize.value }.distinct(), "README §3.2–3.3")
            else if (matching.isEmpty()) finding(layer, "NON_TOKEN_FONT_WEIGHT", "$size/$weight", sameSize.keys.associateWith { FcTypography.allowedWeights.getValue(it) }, "README §3.2–3.3")
            val multipliers = matching.keys.map { FcTypography.lineHeightMultipliers.getValue(it).toDouble() }.distinct()
            if (layer.has("lineHeight") && multipliers.isNotEmpty() && multipliers.none { abs(it - layer.getDouble("lineHeight")) < 0.0001 })
                finding(layer, "NON_TOKEN_LINE_HEIGHT", layer.getDouble("lineHeight"), multipliers, "README §3.2–3.3; S1-D40 R2 (comparison normalization remains separate)")
        }
        // An icon + headline + caption between successive dividers is the exercise-row anatomy,
        // independent of board, path, icon name or text content. Parse the source clause before deriving its minimum.
        val clause = anatomy.lineSequence().single { it.startsWith("- **C′ 2b 复用位置与已有动作行变体**") }
        val vertical = Regex("`(space\\.\\d+)` 上下内边距").find(clause)?.groupValues?.get(1) ?: error("Anatomy vertical padding not found")
        val gap = Regex("`(space\\.\\d+)` 文字间距").find(clause)?.groupValues?.get(1) ?: error("Anatomy text gap not found")
        val headline = FcTypography.styles.getValue("headline").fontSize.value * FcTypography.lineHeightMultipliers.getValue("headline")
        val caption = FcTypography.styles.getValue("caption").fontSize.value * FcTypography.lineHeightMultipliers.getValue("caption")
        val dividers = layers.filter { it.optString("type") == "rectangle" && it.getDouble("h") <= 1.01 && it.getDouble("w") > 100 }.sortedBy { it.getDouble("y") }
        for ((start, end) in dividers.zipWithNext()) {
            val inside = layers.filter { it.getDouble("y") > start.getDouble("y") && it.getDouble("y") < end.getDouble("y") }
            val icons = inside.filter { it.optString("type") in setOf("group", "icon") && ConformanceMapping.assetName(it.getString("name")).isNotEmpty() }
            val titles = inside.filter { it.optString("type") == "text" && it.optDouble("fontSize") == FcTypography.styles.getValue("headline").fontSize.value.toDouble() }
            val captions = inside.filter { it.optString("type") == "text" && it.optDouble("fontSize") == FcTypography.styles.getValue("caption").fontSize.value.toDouble() }
            if (icons.size != 1 || titles.size != 1 || captions.size != 1 || abs(titles.single().getDouble("x") - captions.single().getDouble("x")) > 0.01) continue
            val minimum = headline + caption + spaces.getValue(gap) + 2 * spaces.getValue(vertical) + start.getDouble("h")
            val actual = end.getDouble("y") - start.getDouble("y")
            if (actual + 0.01 < minimum) finding(start, "ANATOMY_ROW_PITCH", actual, minimum, "components.md §4.3 C′ 2b; headline + caption + $gap + 2×$vertical + divider")
        }
        // Nearest vertically following text with the same left edge: flag non-token line-box gaps for review.
        // Flat exports lack layout ownership; do not pretend these candidates establish a component relationship.
        val texts = layers.filter { it.optString("type") == "text" && it.has("fontSize") }
        for (a in texts) {
            val b = texts.filter { it.getDouble("y") > a.getDouble("y") + a.getDouble("h") && abs(it.getDouble("x") - a.getDouble("x")) < 0.01 }.minByOrNull { it.getDouble("y") } ?: continue
            val distance = b.getDouble("y") - a.getDouble("y") - a.getDouble("h")
            if (spaces.values.none { abs(it - distance) < 0.01 }) finding(a, "NON_TOKEN_SPACING", distance, spaces, "README §4; next aligned text ${b.getString("path")}", "REVIEW_LAYOUT_OWNERSHIP")
        }
        val known = layers.filter { it.getString("name").startsWith("DS-") }.map { it.getString("name").substringBefore(" ·") }.distinct()
        return JSONObject().put("board", board.optString("boardName")).put("layerCount", layers.size).put("conflictCount", findings.length()).put("findings", findings)
            .put("coverage", JSONObject().put("typography", "all text metadata").put("colors", "all fill/stroke values").put("anatomy", "recognized icon/headline/caption rows between dividers only")
                .put("otherComponentAnatomy", JSONArray(known)).put("otherComponentAnatomyStatus", "UNVERIFIED: prose anatomy is not fully machine-readable; no claim of full anatomy conformance"))
    }

    fun generate(root: File, exports: File, out: File): JSONObject {
        val raw = JSONObject(exports.readText())
        val boards = raw.keys().asSequence().map { raw.getJSONObject(it) }.toList()
        val readmeFile = File(root, "design/design-system/README.md")
        val anatomyFile = File(root, "design/design-system/components.md")
        val targets = listOf("01" to "01 今日", "D2b" to "D2b 动作库", "D8c" to "D8c ", "D3a" to "D3a ", "D6" to "D6 ", "D12" to "D12 ")
        out.mkdirs()
        val results = mutableListOf<JSONObject>()
        for ((name, prefix) in targets) {
            val board = boards.single { it.getString("boardName").startsWith(prefix) }
            results += inspect(board, readmeFile.readText(), anatomyFile.readText()).put("id", name).put("input", exports.absolutePath)
        }
        // core-exports.json does not contain P0-a2. Use the committed export without silently substituting D8.
        val training = File(root, "android/design-assets/conformance/P0-a2-training.layers.json")
        results += inspect(JSONObject(training.readText()).put("boardName", "P0-a2 训练"), readmeFile.readText(), anatomyFile.readText())
            .put("id", "P0-a2").put("input", training.absolutePath).put("sourceGap", "P0-a2 absent from core-exports.json; committed P0-a2 export used")
        fun sha(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
        for (r in results) {
            r.put("sourceHashes", JSONObject().put("README", sha(readmeFile)).put("components", sha(anatomyFile)).put("exports", sha(exports)))
            File(out, "${r.getString("id")}.json").writeText(r.toString(2))
        }
        return JSONObject().put("reports", JSONArray(results.map { JSONObject().put("id", it.getString("id")).put("conflicts", it.getInt("conflictCount")) }))
            .put("totalReports", results.size).put("totalFindings", results.sumOf { it.getInt("conflictCount") })
            .also { File(out, "summary.json").writeText(it.toString(2)) }
    }
}
