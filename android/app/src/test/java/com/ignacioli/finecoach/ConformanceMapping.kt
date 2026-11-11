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

    fun entries(layers: List<JSONObject>, exceptions: List<JSONObject>, actual: List<JSONObject>, bindings: Map<String, String>, originOffsetY: Double = 0.0): List<JSONObject> {
        require(exceptions.map { it.getString("path") }.distinct().size == exceptions.size)
        require(exceptions.all { e -> layers.any { it.getString("path") == e.getString("path") } })
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
            if (!entry.has("anchor")) entry.put("anchor", "top")
            if (!entry.has("colorMethod")) entry.put("colorMethod", if (layer.optString("type") == "text") "textLayout" else "exactPixelMode")
            entry
        }
        // Only non-manual text selectors participate. All must have unique real text observations.
        val reserved = result.filter { it.getString("mapping") == "MANUAL" }.flatMap { entry ->
            ConformanceComparison.select(actual, entry) { expand(it, bindings) }.singleOrNull()?.let { listOf(it.getInt("id")) }.orEmpty()
        }.toSet()
        val automatic = result.filter { it.getString("mapping") in setOf("AUTO_TEXT", "AUTO_TAG") && layers.single { l -> l.getString("path") == it.getString("path") }.optString("type") != "path" }
        for (group in automatic.groupBy { it.getString("mapping") + ":" + it.optString("text", it.optString("tag")) }.values) {
            val ordered = group.sortedWith(compareBy({ e -> layers.single { it.getString("path") == e.getString("path") }.getDouble("y") },
                { e -> layers.single { it.getString("path") == e.getString("path") }.getDouble("x") }))
            val candidates = actual.filter { n -> n.getInt("id") !in reserved && (if (group.first().getString("mapping") == "AUTO_TEXT") n.optString("text") == group.first().getString("text") && !n.isNull("hex") && n.optString("hex").isNotEmpty() else n.optString("tag") == group.first().getString("tag")) }
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
        for (layer in layers.filter { it.optString("type") == "path" }) {
            val parent = layers.filter { it.optString("type") in setOf("icon", "group") && layer.getString("path").startsWith(it.getString("path") + "/") }
                .maxByOrNull { it.getString("path").length } ?: continue
            val entry = result.single { it.getString("path") == layer.getString("path") }
            if (byPath[layer.getString("path")]?.let { listOf("tag", "scope", "text").any(it::has) } == true) continue
            val parentEntry = result.single { it.getString("path") == parent.getString("path") }
            for (key in listOf("tag", "scope", "nodeID", "mappingError")) if (parentEntry.has(key)) entry.put(key, parentEntry.get(key))
            entry.remove("tag")
            for (key in listOf("tag", "scope", "nodeID")) if (parentEntry.has(key)) entry.put(key, parentEntry.get(key))
            entry.put("anchor", parentEntry.getString("anchor"))
            entry.put("parentPath", parent.getString("path")).put("unobservable", "VECTOR_INTERNAL_PATH")
                .put("asset", assetName(parent.getString("name"))).put("mapping", "AUTO_VECTOR_PARENT")
        }
        return result
    }
    fun assetName(name: String): String = Regex("(?:icon / |· )([a-z_-]+)(?:\\s|$)").find(name)?.groupValues?.get(1) ?: ""

    private fun distance(a: JSONObject, b: JSONObject) = hypot(a.getDouble("x") + a.getDouble("w") / 2 - b.getDouble("x") - b.getDouble("w") / 2,
        a.getDouble("y") + a.getDouble("h") / 2 - b.getDouble("y") - b.getDouble("h") / 2)
}
