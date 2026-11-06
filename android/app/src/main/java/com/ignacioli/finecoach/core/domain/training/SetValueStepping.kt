package com.ignacioli.finecoach.core.domain.training

import java.math.BigDecimal

object SetValueStepping {
    enum class Field(
        val step: BigDecimal,
        val minimum: BigDecimal,
    ) {
        weight(step = BigDecimal("2.5"), minimum = BigDecimal.ZERO),
        reps(step = BigDecimal.ONE, minimum = BigDecimal.ONE),
    }

    fun stepped(text: String, field: Field, up: Boolean): String {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) {
            return if (up) {
                formatDecimal(maxOf(field.step, field.minimum))
            } else {
                text
            }
        }
        val value = runCatching { DecimalValue.parse(trimmed).decimal }.getOrElse { return text }
        val moved = if (up) value + field.step else value - field.step
        return formatDecimal(if (moved >= field.minimum) moved else field.minimum)
    }

    fun canStepDown(text: String, field: Field): Boolean {
        val value = runCatching { DecimalValue.parse(text.trim()).decimal }.getOrElse { return false }
        return value > field.minimum
    }

    private fun formatDecimal(value: BigDecimal): String {
        var canonical = value.stripTrailingZeros().toPlainString()
        if (canonical == "-0") {
            canonical = "0"
        }
        return canonical
    }
}
