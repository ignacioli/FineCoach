package com.ignacioli.finecoach

import kotlin.math.hypot
import org.json.JSONArray
import org.json.JSONObject

/**
 * Text uses exact content. Duplicate text uses reading order (top, left), then nearest center;
 * disagreement, ties or insufficient observations are AMBIGUOUS, never an arbitrary first match.
 * Non-text convention: board name `testTag:<runtime tag>` or runtime tag `conformance:<board name>`.
 * Names/tags can contain fixture $bindings. Tags must identify visible geometry, not touch overlays.
 * Vector children inherit the selector of their closest icon/group ancestor; no path allowlist.
 */
internal object ConformanceMapping {
    fun expand(raw: String, bindings: Map<String, String>): String =
        Regex("\\$([A-Za-z][A-Za-z0-9_]*)").replace(raw) { match ->
            bindings[match.groupValues[1]] ?: error("Unresolved fixture binding ${match.value}")
        }

    fun entries(layers: List<JSONObject>, exceptions: List<JSONObject>, actual: List<JSONObject>, bindings: Map<String, String>, originOffsetY: Double = 0.0, viewportHeight: Double = 844.0): List<JSONObject> {
        require(exceptions.map { it.getString("path") }.distinct().size == exceptions.size)
        require(exceptions.all { e -> layers.any { it.getString("path") == e.getString("path") } })
        val visibleLayers = layers.filter { intersectsViewport(it, viewportHeight) }
        val visibleActual = actual.filter { intersectsViewport(it, viewportHeight) && it.getDouble("w") > 0 && it.getDouble("h") > 0 && it.optBoolean("attached", true) && it.optBoolean("placed", true) }
        return visibleEntries(visibleLayers, exceptions.filter { e -> visibleLayers.any { it.getString("path") == e.getString("path") } }, visibleActual, bindings, originOffsetY)
    }

    /** Geometry, including partial nodes, is compared using the complete layout box. */
    internal fun intersectsViewport(box: JSONObject, viewportHeight: Double = 844.0): Boolean {
        val raw = box.optJSONObject("unclipped") ?: box
        return raw.getDouble("w") > 0 && raw.getDouble("h") > 0 &&
            raw.getDouble("x") < 390 && raw.getDouble("y") < viewportHeight &&
            raw.getDouble("x") + raw.getDouble("w") > 0 && raw.getDouble("y") + raw.getDouble("h") > 0
    }

    // AD-01 / S1-D28, canonical mapping table in android/docs/s1/S0-step3-components.md.
    internal val platformIcons = mapOf(
        "filter" to "filter_alt",
        "gearshape" to "settings",
        "calendar" to "calendar_month",
        "line.3.horizontal.decrease.circle" to "filter_alt",
        "line.3.horizontal.decrease.circle.fill" to "filter_alt_filled",
        "plus" to "add",
        "externaldrive" to "hard_drive",
        "info.circle" to "info",
        "chevron.left.forwardslash.chevron.right" to "code",
        "slider.horizontal.3" to "tune",
        "bell" to "notifications",
        "book" to "menu_book",
        "textformat" to "text_fields",
        "list.bullet.rectangle" to "list_alt",
        "figure.stand" to "accessibility_new",
        "chart.line.uptrend.xyaxis" to "trending_up",
        "chart.xyaxis.line" to "show_chart",
        "doc.text" to "description",
        "iphone" to "smartphone",
        "lock" to "lock",
        "person" to "person",
        "arrow.down.doc" to "download",
        "exclamationmark" to "priority_high",
        "info" to "info_i",
        "arrow.triangle.2.circlepath" to "sync",
        "checkmark.circle" to "check_circle",
        "exclamationmark.triangle" to "warning",
        "trash" to "delete",
        "pencil" to "edit",
        "folder" to "folder",
        "checkmark.circle.fill" to "check_circle_filled",
        "star.fill" to "star_filled",
        "bell.slash" to "notifications_off",
        "lock.fill" to "lock_filled",
        "minus" to "remove",
        "chevron.down" to "expand_more"
    )
    internal fun platformIcon(name: String): String? = platformIcons[name.removePrefix("icon / ")]
        // Component groups use the approved Android symbol (e.g. DS-SET-ROW · edit).
        ?: assetName(name).takeIf { it in platformIcons.values }

    /**
     * DS-STEPPER-FIELD parts, keyed by the board component name after `DS-STEPPER-FIELD · `.
     * Glyphs use the component's own `*-minus-glyph` / `*-plus-glyph` tags. The capsule is the
     * common layout parent of `*-minus` and `*-plus` that also contains `*-input`. Duplicates pair
     * by reading order and nearest center. No path or screen branch.
     */
    internal data class StepperFieldPart(val part: String, val geometryRule: String? = null, val symbolSizeDp: Double? = null, val colorMethod: String? = null, val tagSuffix: String? = null, val capsule: Boolean = false)
    internal val stepperFieldParts = listOf(
        StepperFieldPart("minus", "SYMBOL_CENTER", 20.0, "iconInk", "-minus-glyph"),
        StepperFieldPart("plus", "SYMBOL_CENTER", 20.0, "iconInk", "-plus-glyph"),
        StepperFieldPart("value", "EDITABLE_TEXT_FIELD", colorMethod = "textLayout"),
        StepperFieldPart("capsule", capsule = true),
    )
    internal fun stepperFieldPart(name: String): StepperFieldPart? {
        val marker = "DS-STEPPER-FIELD · "
        val index = name.indexOf(marker)
        if (index < 0) return null
        val part = name.substring(index + marker.length).substringBefore(' ').substringBefore('(')
        return stepperFieldParts.firstOrNull { it.part == part }
    }
    internal fun isStepperCapsuleSelector(entry: JSONObject): Boolean {
        val tags = entry.optJSONArray("commonLayoutParentOfTags") ?: return false
        return tags.length() == 2 && tags.optString(0) == "*-minus" && tags.optString(1) == "*-plus" && entry.optString("containsTag") == "*-input"
    }
    /** A real stepper capsule observation: one prefix's `-minus`, `-plus`, and `-input`. */
    internal fun matchesStepperCapsule(node: JSONObject): Boolean {
        val tags = node.optJSONArray("commonLayoutParentOfTags") ?: return false
        if (tags.length() != 2) return false
        val minus = tags.optString(0)
        val plus = tags.optString(1)
        val prefix = minus.removeSuffix("-minus")
        return prefix.isNotEmpty() && minus == "$prefix-minus" && plus == "$prefix-plus" && node.optString("containsTag") == "$prefix-input"
    }
    private fun applyStepperField(entry: JSONObject, name: String, manualSelector: Boolean) {
        val part = stepperFieldPart(name) ?: return
        part.geometryRule?.let { entry.put("geometryRule", it) }
        part.symbolSizeDp?.let { entry.put("symbolSizeDp", it) }
        part.colorMethod?.let { entry.put("colorMethod", it) }
        if (manualSelector) return
        part.tagSuffix?.let {
            entry.put("tagSuffix", it)
            entry.remove("tag")
            entry.remove("text")
            entry.put("mapping", "AUTO_TAG")
        }
        if (part.capsule) {
            entry.put("commonLayoutParentOfTags", JSONArray(listOf("*-minus", "*-plus")))
            entry.put("containsTag", "*-input")
            entry.remove("tag")
            entry.put("mapping", "AUTO_TAG")
        }
    }
    private fun automaticGroupKey(entry: JSONObject): String = when {
        entry.has("tagSuffix") -> "suffix:" + entry.getString("tagSuffix")
        isStepperCapsuleSelector(entry) -> "stepper-capsule"
        entry.getString("mapping") == "AUTO_TEXT" -> "text:" + normalizeConformanceText(entry.getString("text"))
        else -> "tag:" + entry.optString("tag")
    }
    private fun matchesAutomaticGroup(node: JSONObject, sample: JSONObject): Boolean = when {
        sample.has("tagSuffix") -> node.optString("tag").endsWith(sample.getString("tagSuffix"))
        isStepperCapsuleSelector(sample) -> matchesStepperCapsule(node)
        sample.getString("mapping") == "AUTO_TEXT" -> normalizeConformanceText(node.optString("text")) == normalizeConformanceText(sample.getString("text")) && !node.isNull("hex") && node.optString("hex").isNotEmpty()
        else -> node.optString("tag") == sample.optString("tag")
    }

    private fun visibleEntries(layers: List<JSONObject>, exceptions: List<JSONObject>, actual: List<JSONObject>, bindings: Map<String, String>, originOffsetY: Double): List<JSONObject> {
        val byPath = exceptions.associateBy { it.getString("path") }
        val result = layers.map { layer ->
            val exception = byPath[layer.getString("path")]
            val entry = JSONObject(exception?.toString() ?: "{}").put("path", layer.getString("path"))
            val manualSelector = listOf("tag", "scope", "text", "commonLayoutParentOfTags").any { entry.has(it) }
            if (!manualSelector) {
                if (layer.optString("type") == "text") entry.put("text", entry.optJSONObject("pendingBoardFix")?.optString("text", layer.getString("text")) ?: layer.getString("text"))
                else {
                    val name = expand(layer.getString("name"), bindings)
                    entry.put("tag", if (name.startsWith("testTag:")) name.removePrefix("testTag:") else "conformance:$name")
                }
            }
            entry.put("mapping", if (manualSelector) "MANUAL" else if (layer.optString("type") == "text") "AUTO_TEXT" else "AUTO_TAG")
            if (platformIcon(layer.optString("name")) != null) entry.put("colorMethod", "iconInk")
            if (!entry.has("anchor")) entry.put("anchor", "top")
            if (!entry.has("colorMethod")) entry.put("colorMethod", if (layer.optString("type") == "text") "textLayout" else "exactPixelMode")
            applyStepperField(entry, layer.getString("name"), manualSelector)
            entry
        }
        // Only non-manual text selectors participate. All must have unique real text observations.
        val reserved = result.filter { it.getString("mapping") == "MANUAL" }.flatMap { entry ->
            ConformanceComparison.select(actual, entry) { expand(it, bindings) }.singleOrNull()?.let { listOf(it.getInt("id")) }.orEmpty()
        }.toSet()
        val automatic = result.filter { it.getString("mapping") in setOf("AUTO_TEXT", "AUTO_TAG") && layers.single { l -> l.getString("path") == it.getString("path") }.optString("type") != "path" }
        for (group in automatic.groupBy { automaticGroupKey(it) }.values) {
            val ordered = group.sortedWith(compareBy({ e -> layers.single { it.getString("path") == e.getString("path") }.getDouble("y") },
                { e -> layers.single { it.getString("path") == e.getString("path") }.getDouble("x") }))
            val candidates = actual.filter { n -> n.getInt("id") !in reserved && matchesAutomaticGroup(n, group.first()) }
                .sortedWith(compareBy({ it.getDouble("y") }, { it.getDouble("x") }))
            for ((index, entry) in ordered.withIndex()) {
                if (candidates.size == 1 && ordered.size == 1) entry.put("nodeID", candidates.single().getInt("id"))
                else if (candidates.isNotEmpty()) {
                    val layer = layers.single { it.getString("path") == entry.getString("path") }
                    val target = ConformanceComparison.designBox(layer, entry).let { box -> box.put("y", box.getDouble("y") + (if (entry.getString("anchor") == "top") originOffsetY else 0.0)) }
                    val ranked = candidates.sortedBy { distance(target, it) }
                    val uniqueNearest = ranked.size == 1 || kotlin.math.abs(distance(target, ranked[0]) - distance(target, ranked[1])) > 0.0001
                    val reading = candidates.getOrNull(index)
                    if (ordered.size == candidates.size && uniqueNearest && reading === ranked[0]) entry.put("nodeID", reading.getInt("id"))
                    else entry.put("mappingError", "AMBIGUOUS: reading order and unique nearest center cannot establish a one-to-one match (${ordered.size} layers/${candidates.size} nodes)")
                }
            }
        }
        for (layer in layers.filter { it.optString("type") == "path" || layers.any { p -> platformIcon(p.optString("name")) != null && it.getString("path").startsWith(p.getString("path") + "/") } }) {
            val parent = layers.filter { it.optString("type") in setOf("icon", "group") && layer.getString("path").startsWith(it.getString("path") + "/") }
                .maxByOrNull { it.getString("path").length } ?: continue
            val entry = result.single { it.getString("path") == layer.getString("path") }
            if (byPath[layer.getString("path")]?.let { listOf("tag", "scope", "text").any(it::has) } == true) continue
            val parentEntry = result.single { it.getString("path") == parent.getString("path") }
            for (key in listOf("tag", "scope", "nodeID", "mappingError")) if (parentEntry.has(key)) entry.put(key, parentEntry.get(key))
            entry.remove("tag")
            for (key in listOf("tag", "scope", "nodeID")) if (parentEntry.has(key)) entry.put(key, parentEntry.get(key))
            entry.put("anchor", parentEntry.getString("anchor"))
            platformIcon(parent.getString("name"))?.let { symbol ->
                entry.put("parentPath", parent.getString("path")).put("unobservable", "AD01_VECTOR_INTERNAL")
                    .put("asset", symbol).put("source", "AD-01 / S1-D28").put("mapping", "AUTO_VECTOR_PARENT")
                return@let
            }
            if (entry.optString("unobservable") == "AD01_VECTOR_INTERNAL") continue
            entry.put("parentPath", parent.getString("path")).put("unobservable", "VECTOR_INTERNAL_PATH")
                .put("asset", assetName(parent.getString("name"))).put("mapping", "AUTO_VECTOR_PARENT")
        }
        return result
    }
    fun assetName(name: String): String = Regex("(?:icon / |· )([a-z_-]+)(?:\\s|$)").find(name)?.groupValues?.get(1) ?: ""

    private fun distance(a: JSONObject, b: JSONObject) = hypot(a.getDouble("x") + a.getDouble("w") / 2 - b.getDouble("x") - b.getDouble("w") / 2,
        a.getDouble("y") + a.getDouble("h") / 2 - b.getDouble("y") - b.getDouble("h") / 2)
}
