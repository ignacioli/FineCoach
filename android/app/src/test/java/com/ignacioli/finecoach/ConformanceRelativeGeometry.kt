package com.ignacioli.finecoach

import kotlin.math.abs
import kotlin.math.round
import org.json.JSONArray
import org.json.JSONObject

/** S1-D55: relations are selected exclusively from design geometry, never from observed drift. */
internal object ConformanceRelativeGeometry {
    private val names = listOf("SIZE", "GAP", "INSET", "ALIGN", "ABSOLUTE_GROSS", "COLOR")
    private fun rounded(delta: Double) = round(delta * 4) / 4
    private fun within(delta: Double) = abs(rounded(delta)) <= 2
    private fun measurement(delta: Double) = JSONObject().put("delta", delta).put("roundedDelta", rounded(delta))
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
                sizeDetail.put(axis, measurement(delta))
                within(delta)
            }.all { it }
            record("SIZE", listOf(a), sizePass, sizeDetail)
            record("ABSOLUTE_GROSS", listOf(a), listOf("x","y").all { abs(d.getDouble(it)) <= 8 })
            record("COLOR", listOf(a), a.optBoolean("tokenMatches"))
            val parent = observable.filter { it !== a && contains(it,a) }.minByOrNull { v(it,"w")*v(it,"h") }
            if (parent != null) {
                val detail = JSONObject()
                val pass = listOf("x","y").map { axis ->
                    val design = v(a,axis)-v(parent,axis)
                    val actual = v(a,axis,true)-v(parent,axis,true)
                    detail.put(axis, measurement(actual-design).put("design",design).put("actual",actual))
                    within(actual-design)
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
                val detail = JSONObject().put("a",a.getString("path")).put("b",b.getString("path"))
                    .put("direction",direction).put("design",design).put("actual",actual).put("delta",actual-design).put("roundedDelta",rounded(actual-design))
                record("GAP",listOf(a,b),within(actual-design),detail)
                gaps.put(detail)
            }
        }
        for (axis in listOf("left","right","centerX")) {
            val remaining = observable.sortedWith(compareBy<JSONObject> { edge(it,axis) }.thenBy { it.getString("path") }).toMutableList()
            while (remaining.isNotEmpty()) {
                val first = remaining.first()
                val group = remaining.takeWhile { edge(it,axis)-edge(first,axis) <= 0.5 }
                remaining.removeAll(group.toSet())
                if (group.size < 2) continue
                val spread = group.maxOf { edge(it,axis,true) }-group.minOf { edge(it,axis,true) }
                record("ALIGN",group,within(spread),measurement(spread).put("edge",axis).put("actualSpread",spread))
            }
        }
        observable.forEach { r ->
            val matches = r.getJSONArray("failedChecks").let { a -> (0 until a.length()).none { a.getString(it) != "COLOR" } }
            r.put("geometryMatches",matches)
            val pass = matches && r.optBoolean("textMatches") && r.optBoolean("tokenMatches")
            if (r.optString("category") != "INVISIBLE_OR_CLIPPED") {
                r.put("category",if (pass) "PASS" else "UI_DEVIATION").put("status",if (pass) "PASS" else "FAIL")
                if (pass && r.getJSONObject("selector").has("pendingBoardFix")) r.put("category","BOARD_FIX_PENDING").put("status","BOARD_FIX_PENDING")
            }
        }
        return JSONObject().put("counts",counts).put("checks",checks).put("gaps",gaps)
    }
}
