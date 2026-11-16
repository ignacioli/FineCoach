package com.ignacioli.finecoach

import java.awt.image.BufferedImage
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.roundToInt
import org.json.JSONArray
import org.json.JSONObject

/** S1-D59: centre-aligned parent crops; no ink-centroid fitting or shape rescaling. */
internal object ConformanceIconPixels {
    const val inkThreshold = 32
    const val minimumIou = 0.70
    data class Mask(val width: Int, val height: Int, val ink: BooleanArray)

    fun mask(image: BufferedImage, box: JSONObject, width: Int, height: Int): Mask {
        fun sample(x: Int, y: Int): Int {
            val px = floor((box.getDouble("x") + (x + 0.5) * box.getDouble("w") / width) * 2).toInt()
            val py = floor((box.getDouble("y") + (y + 0.5) * box.getDouble("h") / height) * 2).toInt()
            require(px in 0 until image.width && py in 0 until image.height) { "Icon crop outside capture" }
            return image.getRGB(px, py) and 0xffffff
        }
        val boundary = mutableMapOf<Int, Int>()
        for (y in 0 until height) for (x in 0 until width) {
            if (x == 0 || y == 0 || x == width - 1 || y == height - 1) {
                val rgb = sample(x,y); boundary[rgb] = (boundary[rgb] ?: 0) + 1
            }
        }
        val background = boundary.entries.sortedWith(compareByDescending<Map.Entry<Int,Int>> { it.value }.thenBy { it.key }).first().key
        return Mask(width,height,BooleanArray(width * height) { i ->
            val rgb = sample(i % width,i / width)
            listOf(0,8,16).maxOf { abs((rgb shr it and 255) - (background shr it and 255)) } > inkThreshold
        })
    }
    fun iou(a: Mask, b: Mask): Double {
        require(a.width == b.width && a.height == b.height)
        val union = a.ink.indices.count { a.ink[it] || b.ink[it] }
        return if (union == 0) 0.0 else a.ink.indices.count { a.ink[it] && b.ink[it] }.toDouble() / union
    }
    fun scaled(mask: Mask, factor: Double): Mask = Mask(mask.width,mask.height,BooleanArray(mask.ink.size) { i ->
        val x = floor((i % mask.width + 0.5 - mask.width / 2.0) / factor + mask.width / 2.0).toInt()
        val y = floor((i / mask.width + 0.5 - mask.height / 2.0) / factor + mask.height / 2.0).toInt()
        x in 0 until mask.width && y in 0 until mask.height && mask.ink[y * mask.width + x]
    })
    fun evaluate(layers: List<JSONObject>, rows: List<JSONObject>, design: BufferedImage, android: BufferedImage): JSONObject {
        val checks = JSONArray()
        for (layer in layers.filter { it.optString("type") in setOf("icon","group") &&
            (it.optString("type") == "icon" || it.optString("name").startsWith("icon / ") || rows.any { child -> child.getJSONObject("selector").optString("parentPath") == it.getString("path") }) }) {
            val row = rows.single { it.getString("path") == layer.getString("path") }
            if (ConformanceMapping.platformIcon(layer.optString("name")) != null) continue
            val check = JSONObject().put("check","ICON_PIXELS").put("path",layer.getString("path"))
                .put("name",layer.getString("name")).put("threshold",minimumIou).put("inkThreshold",inkThreshold)
            if (!row.optBoolean("geometryMatches")) {
                check.put("status","BLOCKED_PARENT_GEOMETRY").put("passed",false).put("iou",JSONObject.NULL)
            } else {
                val width = (layer.getDouble("w") * 2).roundToInt().coerceAtLeast(1)
                val height = (layer.getDouble("h") * 2).roundToInt().coerceAtLeast(1)
                val a = mask(design,layer,width,height)
                val b = mask(android,row.getJSONObject("geometry").getJSONObject("actualBounds"),width,height)
                val metric = iou(a,b)
                check.put("iou",metric).put("passed",metric >= minimumIou).put("status",if (metric >= minimumIou) "PASS" else "FAIL")
                    .put("scale1_4Iou",iou(a,scaled(b,1.4)))
                if (metric < minimumIou) {
                    row.put("status","FAIL").put("category","UI_DEVIATION")
                    row.getJSONArray("failedChecks").put("ICON_PIXELS")
                }
            }
            row.put("ICON_PIXELS",check)
            checks.put(check)
        }
        return JSONObject().put("checks",checks).put("failed",(0 until checks.length()).count { !checks.getJSONObject(it).getBoolean("passed") })
    }
}
