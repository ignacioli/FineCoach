package com.ignacioli.finecoach

import java.awt.image.BufferedImage
import org.json.JSONArray
import org.json.JSONObject

/** Test-only capture pipeline: alpha-composite each real window bitmap in z order at its measured origin. */
internal object ConformanceCapture {
    data class Window(val bitmap: BufferedImage, val x: Int, val y: Int)
    fun composite(base: BufferedImage, windows: List<Window>): BufferedImage {
        val result = BufferedImage(base.width, base.height, BufferedImage.TYPE_INT_ARGB)
        result.createGraphics().apply {
            drawImage(base, 0, 0, null)
            windows.forEach { drawImage(it.bitmap, it.x, it.y, null) }
            dispose()
        }
        return result
    }
    /** A panel's semantics alone and a stable hash are not pixel evidence. Check the actual panel region. */
    fun validate(before: BufferedImage, after: BufferedImage, panels: List<JSONObject>, windowCount: Int, activity: BufferedImage = before, textProbes: List<JSONObject> = emptyList()): JSONObject {
        if (before.width != after.width || before.height != after.height)
            return JSONObject().put("status", "INVALID_CAPTURE").put("reason", "viewport mismatch")
        val evidence = panels.map { panel ->
            val l = (panel.getDouble("x") * 2).toInt().coerceIn(0, after.width)
            val t = (panel.getDouble("y") * 2).toInt().coerceIn(0, after.height)
            val r = ((panel.getDouble("x") + panel.getDouble("w")) * 2).toInt().coerceIn(0, after.width)
            val b = ((panel.getDouble("y") + panel.getDouble("h")) * 2).toInt().coerceIn(0, after.height)
            var changed = 0
            var windowContribution = 0
            val colors = mutableSetOf<Int>()
            for (y in t until b) for (x in l until r) {
                if (before.getRGB(x, y) != after.getRGB(x, y)) changed++
                if (activity.getRGB(x, y) != after.getRGB(x, y)) windowContribution++
                colors += after.getRGB(x, y)
            }
            val inkProven = textProbes.filter { probe -> probe.getDouble("x") >= panel.getDouble("x") && probe.getDouble("y") >= panel.getDouble("y") &&
                probe.getDouble("x") + probe.getDouble("w") <= panel.getDouble("x") + panel.getDouble("w") &&
                probe.getDouble("y") + probe.getDouble("h") <= panel.getDouble("y") + panel.getDouble("h") }.any { probe ->
                val ink = probe.getString("hex").removePrefix("#").toInt(16)
                val pl = (probe.getDouble("x") * 2).toInt().coerceIn(l, r)
                val pt = (probe.getDouble("y") * 2).toInt().coerceIn(t, b)
                val pr = ((probe.getDouble("x") + probe.getDouble("w")) * 2).toInt().coerceIn(pl, r)
                val pb = ((probe.getDouble("y") + probe.getDouble("h")) * 2).toInt().coerceIn(pt, b)
                (pt until pb).any { y -> (pl until pr).any { x ->
                    after.getRGB(x, y) and 0xffffff == ink && activity.getRGB(x, y) != after.getRGB(x, y) && before.getRGB(x, y) != after.getRGB(x, y)
                } }
            }
            JSONObject().put("bounds", panel).put("windowContributionPixels", windowContribution).put("panelInkProven", inkProven).put("changedPixels", changed).put("distinctColors", colors.size)
                .put("valid", changed > 0 && windowContribution > 0 && inkProven && colors.size > 1 && r > l && b > t)
        }
        val valid = panels.isNotEmpty() && windowCount > 0 && evidence.all { it.getBoolean("valid") }
        return JSONObject().put("status", if (valid) "VALID_CAPTURE" else "INVALID_CAPTURE")
            .put("windowCount", windowCount).put("panels", JSONArray(evidence))
            .put("reason", if (valid) "Panel region contains changed, non-uniform pixels and new text ink contributed by captured windows" else "Panel bitmap absent, uniform, empty or identical to the no-panel capture")
    }
}
