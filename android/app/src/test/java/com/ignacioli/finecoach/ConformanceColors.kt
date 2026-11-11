package com.ignacioli.finecoach

import org.json.JSONObject
import kotlin.math.roundToInt

internal object ConformanceColors {
    data class Token(val name: String, val hex: String, val alpha: Double)
    /** Parse every primitive/semantic color row, retaining aliases and declared opacity. */
    fun tokens(readme: String): List<Token> = Regex("(?m)^\\| `(?<name>color\\.[^`]+)` \\|(?<cells>[^\\n]+)").findAll(readme).map { m ->
        val cells = m.groups["cells"]!!.value
        val hex = Regex("`(#[0-9a-fA-F]{6})`").find(cells)?.groupValues?.get(1) ?: error("Missing color value ${m.value}")
        val alpha = Regex("@ (\\d+(?:\\.\\d+)?)%").find(cells)?.groupValues?.get(1)?.toDouble()?.div(100) ?: 1.0
        Token(m.groups["name"]!!.value, hex.lowercase(), alpha)
    }.toList().also { require(it.isNotEmpty()); require(it.map(Token::name).distinct().size == it.size) }

    /** Exact sRGB source-over, quantized once to the screenshot's 8-bit channels; no near-color tolerance. */
    fun composite(hex: String, alpha: Double, background: String): String {
        require(alpha in 0.0..1.0)
        val foreground = hex.removePrefix("#").toInt(16)
        val back = background.removePrefix("#").toInt(16)
        return "#%06x".format(listOf(16, 8, 0).fold(0) { rgb, shift ->
            rgb or ((((foreground shr shift and 255) * alpha + (back shr shift and 255) * (1 - alpha)).roundToInt()) shl shift)
        })
    }

    /** Previous painted, covering fills are the background stack; missing background fails closed. */
    fun expected(layer: JSONObject, layers: List<JSONObject>, tokens: List<Token> = emptyList()): String? {
        val hex = layer.optString("fill", "").ifEmpty { layer.optJSONObject("stroke")?.optString("color").orEmpty() }
        if (hex.isEmpty()) return null
        // An exported token name (or its unique terminal name, e.g. Scrim) preserves README opacity
        // even when the flat export omitted it. Ambiguous names never select an arbitrary token.
        val named = tokens.filter { token -> layer.optString("name").equals(token.name, true) ||
            layer.optString("name").equals(token.name.substringAfterLast('.'), true) }.singleOrNull()
        val alpha = layer.optDouble("opacity", 1.0) * layer.optDouble("fillOpacity", if (layer.has("opacity")) 1.0 else named?.alpha ?: 1.0)
        if (alpha == 1.0) return hex.lowercase()
        val prior = layers.takeWhile { it !== layer }.filter { b -> b.has("fill") && b.optString("type") in setOf("rectangle", "board") &&
            b.getDouble("x") <= layer.getDouble("x") && b.getDouble("y") <= layer.getDouble("y") &&
            b.getDouble("x") + b.getDouble("w") >= layer.getDouble("x") + layer.getDouble("w") &&
            b.getDouble("y") + b.getDouble("h") >= layer.getDouble("y") + layer.getDouble("h") }
        val background = prior.lastOrNull() ?: error("No observed design background for translucent ${layer.optString("path")}")
        return composite(hex, alpha, expected(background, layers, tokens) ?: error("Missing background fill"))
    }
}
