package com.ignacioli.finecoach

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.sign
import org.json.JSONArray
import org.json.JSONObject

/** S1-D55: relations are selected exclusively from design geometry, never from observed drift. */
internal object ConformanceRelativeGeometry {
    private val names = listOf("SIZE", "GAP", "INSET", "ALIGN", "ABSOLUTE_GROSS", "COLOR", "TEXT_ANCHOR")
    private fun rounded(delta: Double) = sign(delta) * floor(abs(delta) * 4 + 0.5) / 4
    private fun within(delta: Double, tolerance: Double = 2.0) = abs(rounded(delta)) <= tolerance
    private fun measurement(delta: Double, tolerance: Double = 2.0) = JSONObject().put("delta", delta).put("roundedDelta", rounded(delta)).put("toleranceDp", tolerance)
    fun evaluate(rows: List<JSONObject>): JSONObject {
        val counts = JSONObject().apply { names.forEach { put(it, 0) } }
        val checks = JSONArray()
        val gaps = JSONArray()
        rows.forEach { it.put("failedChecks", JSONArray()) }
        val observable = rows.filter { it.has("geometry") && !it.getJSONObject("selector").has("unobservable") }
        fun box(r: JSONObject, actual: Boolean) = r.getJSONObject("geometry").getJSONObject(if (actual) "actualBounds" else "expectedBounds")
        fun v(r: JSONObject, key: String, actual: Boolean = false) = box(r, actual).getDouble(key)
        fun edge(r: JSONObject, axis: String, actual: Boolean = false): Double = when (axis) {
            "right" -> v(r, "x", actual) + v(r, "w", actual)
            "centerX" -> v(r, "x", actual) + v(r, "w", actual) / 2
            else -> v(r, "x", actual)
        }
        fun contains(p: JSONObject, c: JSONObject) = v(c,"x") >= v(p,"x") && v(c,"y") >= v(p,"y") &&
            v(c,"x")+v(c,"w") <= v(p,"x")+v(p,"w") && v(c,"y")+v(c,"h") <= v(p,"y")+v(p,"h") &&
            v(p,"w")*v(p,"h") > v(c,"w")*v(c,"h")
        fun record(kind: String, members: List<JSONObject>, pass: Boolean, detail: JSONObject = JSONObject()) {
            if (!detail.has("toleranceDp")) detail.put("toleranceDp", if (kind == "ABSOLUTE_GROSS") 8.0 else if (kind == "COLOR") JSONObject.NULL else 2.0)
            detail.put("check", kind).put("members", JSONArray(members.map { it.getString("path") })).put("passed", pass)
            checks.put(detail)
            if (!pass) {
                counts.put(kind, counts.getInt(kind) + 1)
                members.forEach { r ->
                    val failed = r.getJSONArray("failedChecks")
                    if ((0 until failed.length()).none { failed.getString(it) == kind }) failed.put(kind)
                }
            }
        }
        for (a in observable) {
            val d = a.getJSONObject("delta")
            val sizeDetail = JSONObject()
            val sizePass = listOf("w","h").map { axis ->
                val delta = d.getDouble(axis)
                val tolerance = if (axis == "w") ConformanceTextTolerance.width(a, v(a,"w")) else 2.0
                sizeDetail.put(axis, measurement(delta, tolerance))
                within(delta, tolerance)
            }.all { it }
            record("SIZE", listOf(a), sizePass, sizeDetail)
            if (ConformanceTextTolerance.isText(a)) {
                val alignment = a.getJSONObject("geometry").optString("textAlignment", "left")
                val axis = when (alignment) { "right" -> "right"; "center" -> "centerX"; else -> "left" }
                val delta = edge(a, axis, true) - edge(a, axis)
                record("TEXT_ANCHOR", listOf(a), within(delta), measurement(delta).put("edge", axis))
            }
            record("ABSOLUTE_GROSS", listOf(a), listOf("x","y").all { abs(d.getDouble(it)) <= 8 })
            if (a.optBoolean("colorFullyOccluded"))
                checks.put(JSONObject().put("check", "COLOR").put("members", JSONArray(listOf(a.getString("path"))))
                    .put("status", "UNOBSERVABLE").put("passed", JSONObject.NULL))
            else record("COLOR", listOf(a), a.optBoolean("tokenMatches"))
            val parent = observable.filter { it !== a && contains(it,a) }.minByOrNull { v(it,"w")*v(it,"h") }
            if (parent != null) {
                val detail = JSONObject()
                val pass = listOf("x","y").map { axis ->
                    val design = v(a,axis)-v(parent,axis)
                    val actual = v(a,axis,true)-v(parent,axis,true)
                    val tolerance = 2.0
                    detail.put(axis, measurement(actual-design, tolerance).put("design",design).put("actual",actual))
                    within(actual-design, tolerance)
                }.all { it }
                record("INSET", listOf(parent,a), pass, detail)
            }
            for ((direction, axis, cross, size) in listOf(listOf("below","y","x","h"), listOf("right","x","y","w"))) {
                val crossSize = if (cross == "x") "w" else "h"
                val b = observable.filter { it !== a && !contains(a,it) && !contains(it,a) &&
                    v(it,axis) >= v(a,axis)+v(a,size) &&
                    minOf(v(a,cross)+v(a,crossSize),v(it,cross)+v(it,crossSize)) > maxOf(v(a,cross),v(it,cross)) }
                    .sortedWith(compareBy<JSONObject> { v(it,axis)-v(a,axis)-v(a,size) }.thenBy { it.getString("path") }).firstOrNull() ?: continue
                val design = v(b,axis)-v(a,axis)-v(a,size)
                val actual = v(b,axis,true)-v(a,axis,true)-v(a,size,true)
                val tolerance = if (axis == "x") maxOf(ConformanceTextTolerance.width(a,v(a,"w")), ConformanceTextTolerance.width(b,v(b,"w"))) else 2.0
                val detail = JSONObject().put("toleranceDp",tolerance).put("a",a.getString("path")).put("b",b.getString("path"))
                    .put("direction",direction).put("design",design).put("actual",actual).put("delta",actual-design).put("roundedDelta",rounded(actual-design))
                record("GAP",listOf(a,b),within(actual-design,tolerance),detail)
                gaps.put(detail)
            }
        }
        for (axis in listOf("left","right","centerX")) {
            val remaining = observable.sortedWith(compareBy<JSONObject> { edge(it,axis) }.thenBy { it.getString("path") }).toMutableList()
            while (remaining.isNotEmpty()) {
                val group = mutableListOf(remaining.first())
                for (next in remaining.drop(1)) {
                    if (edge(next,axis)-edge(group.last(),axis) > 0.5) break
                    group += next
                }
                remaining.removeAll(group.toSet())
                if (group.size < 2) continue
                val spread = group.maxOf { edge(it,axis,true) }-group.minOf { edge(it,axis,true) }
                val tolerances = group.associateWith { ConformanceTextTolerance.edge(it, axis, v(it,"w")) }
                val anchors = group.filter { tolerances.getValue(it) == 2.0 }
                val references = anchors.ifEmpty { group }
                val memberChecks = group.map { member ->
                    val deviation = references.maxOf { abs(edge(member,axis,true)-edge(it,axis,true)) }
                    val tolerance = tolerances.getValue(member)
                    measurement(deviation,tolerance).put("path",member.getString("path")).put("passed",within(deviation,tolerance))
                }
                record("ALIGN",group,memberChecks.all { it.getBoolean("passed") },JSONObject()
                    .put("toleranceDp",JSONObject.NULL).put("memberChecks",JSONArray(memberChecks)).put("edge",axis).put("actualSpread",spread))
            }
        }
        observable.forEach { r ->
            val matches = r.getJSONArray("failedChecks").let { a -> (0 until a.length()).none { a.getString(it) != "COLOR" } }
            r.put("geometryMatches",matches)
            val pass = matches && r.optBoolean("textMatches") && r.optBoolean("tokenMatches")
            if (r.optString("category") != "INVISIBLE_OR_CLIPPED") {
                val unobservableColor = r.optBoolean("colorFullyOccluded") && matches && r.optBoolean("textMatches")
                if (unobservableColor) {
                    r.put("category", "UNOBSERVABLE_COLOR").put("status", "UNOBSERVABLE_COLOR")
                    return@forEach
                }
                r.put("category",if (pass) "PASS" else "UI_DEVIATION").put("status",if (pass) "PASS" else "FAIL")
                if (pass && r.getJSONObject("selector").has("pendingBoardFix")) r.put("category","BOARD_FIX_PENDING").put("status","BOARD_FIX_PENDING")
            }
        }
        return JSONObject().put("counts",counts).put("checks",checks).put("gaps",gaps)
    }
}

/** S2-D18: only real text width-derived edges receive proportional tolerance. */
internal object ConformanceTextTolerance {
    fun isText(row: JSONObject) = row.optString("layerType") == "text" || row.optJSONObject("geometry")?.optString("textLineBox", "") == "TOKEN_LINE_HEIGHT_CENTERED"
    fun width(row: JSONObject, expectedWidth: Double, base: Double = 2.0) = width(isText(row), expectedWidth, base)
    fun width(text: Boolean, expectedWidth: Double, base: Double = 2.0) = if (text) maxOf(base, expectedWidth * 7.0 / 100.0) else base
    fun edge(row: JSONObject, axis: String, expectedWidth: Double): Double {
        if (!isText(row) || axis == "centerX") return 2.0
        val anchor = row.optJSONObject("geometry")?.optString("textAlignment", "left") ?: "left"
        val nonAnchor = anchor == "center" || (anchor == "left" && axis == "right") || (anchor == "right" && axis == "left")
        return if (nonAnchor) width(row,expectedWidth) else 2.0
    }
    fun alignment(value: String) = when (value.lowercase()) { "center", "centre" -> "center"; "right", "end" -> "right"; else -> "left" }
}
