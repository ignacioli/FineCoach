package com.ignacioli.finecoach.features.body

import java.math.BigDecimal
import java.math.RoundingMode

/** Display only. Custom measurements retain their recorded canonical precision. */
object BodyDataDisplay {
    fun format(value: BigDecimal, unit: String, custom: Boolean = false): String {
        val shown = if (custom) value else value.setScale(if (unit == "lb" || unit == "in") 2 else 1, RoundingMode.HALF_UP)
        return shown.stripTrailingZeros().toPlainString()
    }
}
